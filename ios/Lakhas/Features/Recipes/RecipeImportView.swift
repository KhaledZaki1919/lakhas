import LakhasKit
import PhotosUI
import SwiftData
import SwiftUI

/// Opens the import sheet, optionally with a link (share extension hand-off, clipboard).
struct RecipeImportRequest: Identifiable {
    let id = UUID()
    var link: String?
}

/// Recipe import (PROJECT_PROMPT.md §4.4): a TikTok / Instagram / YouTube link (public page text
/// fetched on the device), a pasted caption, or screenshots. When a page gives no usable text,
/// the screen says so and offers the other two. The recipe is saved locally as soon as it's read.
struct RecipeImportView: View {
    let request: RecipeImportRequest

    enum Mode: Hashable { case link, text, screenshots }

    /// Why the last attempt gave no recipe.
    enum Problem: Equatable {
        case invalidLink
        case fetch(RecipeFetchError)
        /// The page answered, but with no caption or description we can use.
        case noText(RecipePlatform)
        case noRecipe(String?)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var mode: Mode = .link
    @State private var link: String
    @State private var caption = ""
    @State private var shots: [Data] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isFetching = false
    @State private var isExtracting = false
    @State private var problem: Problem?
    @State private var aiError: AIError?
    /// The link the user tried; kept as the source when they fall back to text or screenshots.
    @State private var linkPage: RecipePageText?
    @State private var imported: Recipe?
    @State private var hasKey = LogSheet.keyAvailable()

    private let format = AppFormat.current

    init(request: RecipeImportRequest) {
        self.request = request
        _link = State(initialValue: request.link ?? "")
    }

    private var busy: Bool { isFetching || isExtracting }

    var body: some View {
        NavigationStack {
            Group {
                if hasKey {
                    form
                } else {
                    NoKeyView()
                }
            }
            .navigationTitle("recipes.import.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                        .accessibilityIdentifier("ax.recipe.cancel")
                }
            }
            .navigationDestination(item: $imported) { RecipeDetailView(recipe: $0) }
        }
        .tint(Theme.Palette.primary)
        .onAppear { hasKey = LogSheet.keyAvailable() }
        .task {
            // A link handed over by the share extension or the clipboard starts right away.
            if hasKey, request.link != nil, RecipeLink.parse(link) != nil { await importLink() }
        }
    }

    private var form: some View {
        Form {
            Section {
                Picker("recipes.import.mode", selection: $mode) {
                    Text("recipes.import.link").tag(Mode.link)
                    Text("recipes.import.text").tag(Mode.text)
                    Text("recipes.import.screenshots").tag(Mode.screenshots)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ax.recipe.mode")
            }
            switch mode {
            case .link: linkSection
            case .text: textSection
            case .screenshots: screenshotSection
            }
            if let problem {
                problemSection(problem)
            }
            if let aiError {
                Section { AIErrorView(error: aiError) }
            }
            Section {
                Button {
                    Task { await start() }
                } label: {
                    HStack {
                        Text(mode == .link ? LocalizedStringKey("recipes.import.fetch") : LocalizedStringKey("recipes.import.extract"))
                            .font(.headline)
                        Spacer()
                        if busy { ProgressView() }
                    }
                }
                .disabled(!canStart)
                .accessibilityIdentifier("ax.recipe.start")
            } footer: {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(verbatim: costEstimate)
                    Text("recipes.import.privacy")
                }
            }
        }
        .overlay {
            if busy {
                ImportProgress(fetching: isFetching)
            }
        }
        .onChange(of: pickerItems) { _, items in
            Task { await loadScreenshots(items) }
        }
    }

    // MARK: Sections

    private var linkSection: some View {
        Section {
            HStack {
                TextField("recipes.import.link.placeholder", text: $link)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityIdentifier("ax.recipe.link")
                PasteButton(payloadType: String.self) { strings in
                    if let first = strings.first { link = first }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
            }
        } footer: {
            Text("recipes.import.link.footer")
        }
    }

    private var textSection: some View {
        Section {
            TextField("recipes.import.text.placeholder", text: $caption, axis: .vertical)
                .lineLimit(5...14)
                .accessibilityIdentifier("ax.recipe.caption")
        } footer: {
            Text("recipes.import.text.footer")
        }
    }

    private var screenshotSection: some View {
        Section {
            if !shots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.sm) {
                        ForEach(Array(shots.enumerated()), id: \.offset) { index, data in
                            ScreenshotThumb(data: data) { shots.remove(at: index) }
                        }
                    }
                }
            }
            PhotosPicker(selection: $pickerItems, maxSelectionCount: RecipeImporter.maxScreenshots, matching: .images) {
                Label("recipes.import.screenshots.pick", systemImage: "photo.on.rectangle.angled")
            }
            .accessibilityIdentifier("ax.recipe.pick")
        } footer: {
            Text("recipes.import.screenshots.footer \(format.number(RecipeImporter.maxScreenshots))")
        }
    }

    private func problemSection(_ problem: Problem) -> some View {
        Section {
            Label {
                Text(message(for: problem))
            } icon: {
                Image(systemName: "exclamationmark.bubble").foregroundStyle(Theme.Palette.warning)
            }
            .accessibilityIdentifier("ax.recipe.problem")
            if case .noRecipe(let notes) = problem, let notes, !notes.isEmpty {
                Text(verbatim: notes).font(.footnote).foregroundStyle(Theme.Palette.muted)
            }
            if mode != .text {
                Button {
                    switchMode(.text)
                } label: {
                    Label("recipes.fallback.text", systemImage: "text.quote")
                }
                .accessibilityIdentifier("ax.recipe.fallback.text")
            }
            if mode != .screenshots {
                Button {
                    switchMode(.screenshots)
                } label: {
                    Label("recipes.fallback.screenshot", systemImage: "camera.viewfinder")
                }
                .accessibilityIdentifier("ax.recipe.fallback.screenshot")
            }
        }
    }

    private func message(for problem: Problem) -> LocalizedStringKey {
        switch problem {
        case .invalidLink: "recipes.problem.invalidLink"
        case .noText(let platform): "recipes.problem.noText \(platform.displayName)"
        case .noRecipe: "recipes.problem.noRecipe"
        case .fetch(let error):
            switch error {
            case .unsupportedLink: "recipes.problem.invalidLink"
            case .blocked: "recipes.problem.blocked"
            case .notFound: "recipes.problem.notFound"
            case .timedOut: "recipes.problem.timedOut"
            case .network: "recipes.problem.network"
            case .blockedRedirect, .tooManyRedirects, .unavailable, .notAPage, .cancelled: "recipes.problem.unavailable"
            }
        }
    }

    // MARK: State

    private var canStart: Bool {
        guard !busy else { return false }
        switch mode {
        case .link: return !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .text: return caption.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
        case .screenshots: return !shots.isEmpty
        }
    }

    /// Before importing: a rough estimate for the selected input and model.
    private var costEstimate: String {
        let model = AISettings.load().model(for: .recipe)
        let cost = RecipeImporter.estimatedCost(
            textCharacters: mode == .text ? caption.count : RecipeImporter.typicalCaptionCharacters,
            images: mode == .screenshots ? max(shots.count, 1) : 0,
            model: model
        )
        guard let cost else { return String(localized: "recipes.import.cost.unknown \(model)") }
        return String(localized: "recipes.import.cost \(format.cost(cost)) \(model)")
    }

    private func switchMode(_ newMode: Mode) {
        if newMode == .text, caption.isEmpty, let page = linkPage, page.isUsable {
            caption = [page.title, page.caption].compactMap { $0 }.joined(separator: "\n")
        }
        mode = newMode
        problem = nil
        aiError = nil
    }

    private func loadScreenshots(_ items: [PhotosPickerItem]) async {
        var loaded: [Data] = []
        for item in items.prefix(RecipeImporter.maxScreenshots) {
            if let data = try? await item.loadTransferable(type: Data.self) { loaded.append(data) }
        }
        shots = loaded
    }

    // MARK: Import

    private func start() async {
        switch mode {
        case .link: await importLink()
        case .text:
            if let page = linkPage {
                // The caption pasted for a link that hid it: the link stays the source.
                var withCaption = page
                withCaption.caption = caption
                withCaption.title = nil
                await extract(.page(withCaption), photo: nil)
            } else {
                await extract(.text(caption), photo: nil)
            }
        case .screenshots:
            let prepared = shots.compactMap { ImageProcessor.prepare($0) }
            guard !prepared.isEmpty else { return }
            await extract(.screenshots(prepared), photo: shots.first)
        }
    }

    private func importLink() async {
        problem = nil
        aiError = nil
        guard let url = RecipeLink.parse(link) else {
            problem = .invalidLink
            return
        }
        isFetching = true
        let page: RecipePageText
        do {
            page = try await RecipePageFetcher(language: format.language).fetch(url)
        } catch {
            isFetching = false
            problem = .fetch(error as? RecipeFetchError ?? .network)
            linkPage = RecipePageText(platform: RecipeLink.platform(of: url) ?? .tiktok, url: RecipeLink.canonical(url),
                                      creatorHandle: RecipeLink.handle(in: url))
            return
        }
        isFetching = false
        linkPage = page
        guard page.isUsable else {
            problem = .noText(page.platform)
            return
        }
        await extract(.page(page), photo: nil)
    }

    private func extract(_ input: RecipeImporter.Input, photo: Data?) async {
        problem = nil
        aiError = nil
        isExtracting = true
        defer { isExtracting = false }
        do {
            let outcome = try await RecipeImporter(service: AIService(context: context)).extract(input, language: format.language)
            guard var draft = outcome.draft else {
                problem = .noRecipe(outcome.notes)
                return
            }
            if draft.sourceURL == nil, let page = linkPage {
                draft.sourceURL = page.url
                draft.platform = page.platform
            }
            if draft.creatorHandle == nil { draft.creatorHandle = linkPage?.creatorHandle ?? linkPage?.author }
            let recipe = Recipe.insert(draft, in: context)
            recipe.importModel = outcome.model
            recipe.importCost = outcome.fromCache ? 0 : outcome.estimatedCost
            if let photo { recipe.photoFileName = try? MealPhotoStore().save(photo) }
            try? context.save()
            imported = recipe
        } catch let error as AIError {
            aiError = error
        } catch {
            aiError = .network
        }
    }
}

/// What's happening while the page is read or the model works (docs/design.md §4).
private struct ImportProgress: View {
    let fetching: Bool

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            ProgressView().controlSize(.large).tint(Theme.Palette.primary)
            Text(fetching ? LocalizedStringKey("recipes.import.fetching") : LocalizedStringKey("recipes.import.extracting"))
                .font(.headline)
                .foregroundStyle(Theme.Palette.ink)
        }
        .padding(Theme.Space.xl)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
    }
}

private struct ScreenshotThumb: View {
    let data: Data
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Theme.Palette.onPrimary, Theme.Palette.ink.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(Theme.Space.xxs)
            .accessibilityLabel(Text("common.delete"))
        }
    }
}
