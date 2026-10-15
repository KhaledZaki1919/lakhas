import LakhasKit
import SwiftData
import SwiftUI

/// Settings → AI (ADR-020): provider, API key (Keychain), Test connection, models,
/// High accuracy, usage and estimated cost, optional daily limit.
struct AISettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var settings = AISettings.load()
    @State private var keyDraft = ""
    @State private var storedKey: String?
    @State private var liveModels: [String] = []
    @State private var testState: TestState = .idle
    @State private var testTask: Task<Void, Never>?
    @State private var testID: UUID?
    @State private var usageToday = UsageSummary([])
    @State private var usageMonth = UsageSummary([])

    private let keyStore = AIKeyStore()
    private let format = AppFormat.current

    enum TestState: Equatable {
        case idle, running
        case passed(model: String, cost: Double?)
        case failed(AIError)
    }

    private var provider: AIProviderKind { settings.provider }
    private var availableModels: [String] { liveModels.isEmpty ? provider.builtInModels : liveModels }

    var body: some View {
        Form {
            providerSection
            keySection
            if storedKey != nil { testSection }
            modelSection
            diagnosticsSection
            usageSection
            limitSection
        }
        .navigationTitle("ai.title")
        .onAppear(perform: reload)
        .onChange(of: settings) { _, new in new.save() }
        .onChange(of: settings.provider) { _, _ in reload() }
    }

    // MARK: Sections

    private var providerSection: some View {
        Section {
            Picker("ai.provider", selection: $settings.provider) {
                ForEach(AIProviderKind.allCases) { kind in
                    Text(verbatim: kind.displayName).tag(kind)
                }
            }
            .accessibilityIdentifier("ax.ai.provider")
        } footer: {
            Text(verbatim: String(localized: "ai.privacy \(provider.displayName)"))
        }
    }

    private var keySection: some View {
        Section {
            if let storedKey {
                LabeledContent("ai.key.saved") {
                    Text(verbatim: AIKeyStore.masked(storedKey))
                        .font(.callout.monospaced())
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityIdentifier("ax.ai.key.masked")
                }
                keyWarnings(storedKey)
                Button("ai.key.delete", role: .destructive) {
                    keyStore.delete(for: provider)
                    reload()
                }
            } else {
                SecureField("ai.key.placeholder", text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .font(.callout.monospaced())
                    // Keys are Latin text: typed and shown left to right, even in Arabic.
                    .environment(\.layoutDirection, .leftToRight)
                    .multilineTextAlignment(.leading)
                    .accessibilityIdentifier("ax.ai.key")
                let clean = AIKeyStore.sanitize(keyDraft)
                if !clean.isEmpty {
                    Text(verbatim: AIKeyStore.masked(clean))
                        .font(.footnote.monospaced())
                        .foregroundStyle(Theme.Palette.muted)
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityIdentifier("ax.ai.key.preview")
                    keyWarnings(clean)
                }
                Button("ai.key.save") {
                    try? keyStore.save(keyDraft, for: provider)
                    keyDraft = ""
                    reload()
                    startTest()
                }
                .disabled(clean.isEmpty)
                .accessibilityIdentifier("ax.ai.saveKey")
            }
            if let url = provider.keyPageURL {
                Link(destination: url) {
                    Label("ai.key.get", systemImage: "arrow.up.right.square")
                }
            }
        } header: {
            Text("ai.key.title")
        } footer: {
            Text("ai.key.footer")
        }
    }

    private var testSection: some View {
        Section {
            Button {
                startTest()
            } label: {
                HStack {
                    Text("ai.test")
                    Spacer()
                    if testState == .running { ProgressView() }
                }
            }
            .disabled(testState == .running)
            .accessibilityIdentifier("ax.ai.test")
            if testState == .running {
                Button("ai.test.cancel", role: .cancel) { testTask?.cancel() }
                    .accessibilityIdentifier("ax.ai.test.cancel")
            }
            switch testState {
            case .idle, .running:
                EmptyView()
            case .passed(let model, let cost):
                Label {
                    Text(verbatim: passedText(model: model, cost: cost))
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.success)
                }
                .font(.callout)
            case .failed(let error):
                AIErrorView(error: error)
            }
        }
    }

    private var diagnosticsSection: some View {
        Section {
            NavigationLink {
                AIDiagnosticsView()
            } label: {
                LabeledContent {
                    if let diagnostic = AIDiagnosticsStore.load() {
                        Text(diagnostic.succeeded ? LocalizedStringKey("ai.diag.success") : diagnostic.failedStep?.titleKey ?? "")
                    }
                } label: {
                    Label("ai.diag.title", systemImage: "stethoscope")
                }
            }
            .accessibilityIdentifier("ax.ai.diagnostics")
        } footer: {
            Text("ai.diag.footer")
        }
    }

    /// Format hints for a key (never block saving).
    @ViewBuilder private func keyWarnings(_ key: String) -> some View {
        ForEach(Array(AIKeyStore.warnings(for: key, provider: provider).enumerated()), id: \.offset) { _, warning in
            Label {
                Text(verbatim: warningText(warning))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.Palette.warning)
            }
            .font(.footnote)
            .accessibilityIdentifier("ax.ai.key.warning")
        }
    }

    private func warningText(_ warning: AIKeyWarning) -> String {
        switch warning {
        case .looksLike(let owner):
            return String(localized: "ai.key.warn.looksLike \(owner.displayName) \(provider.displayName)")
        case .unexpectedFormat:
            let prefixes = provider.keyPrefixes.map { "\($0)…" }.joined(separator: " / ")
            return String(localized: "ai.key.warn.format \(provider.displayName) \(prefixes)")
        case .unexpectedCharacters:
            return String(localized: "ai.key.warn.characters")
        case .tooShort:
            return String(localized: "ai.key.warn.short")
        }
    }

    /// The live list is what this key can actually call; an ID outside it (a typo, a retired
    /// model, or one the key's tier can't use) is the usual cause of "model not found".
    @ViewBuilder private func notInListWarning(_ model: String) -> some View {
        if !liveModels.isEmpty && !liveModels.contains(model) {
            Label {
                Text(verbatim: String(localized: "ai.model.notInList \(model)"))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.Palette.warning)
            }
            .font(.footnote)
            .accessibilityIdentifier("ax.ai.model.notInList")
        }
    }

    private var modelSection: some View {
        Section {
            NavigationLink {
                ModelPickerView(
                    titleKey: "ai.model.standard",
                    selection: Binding(
                        get: { settings.standardModel(for: provider) },
                        set: { settings.standardModels[provider.rawValue] = $0 }
                    ),
                    models: availableModels,
                    recommended: provider.recommendedStandardModel,
                    isLiveList: !liveModels.isEmpty
                )
            } label: {
                LabeledContent("ai.model.standard", value: settings.standardModel(for: provider))
            }
            notInListWarning(settings.standardModel(for: provider))
            Toggle("ai.highAccuracy", isOn: $settings.highAccuracy)
                .accessibilityIdentifier("ax.ai.highAccuracy")
            if settings.highAccuracy {
                NavigationLink {
                    ModelPickerView(
                        titleKey: "ai.model.accurate",
                        selection: Binding(
                            get: { settings.accurateModel(for: provider) },
                            set: { settings.accurateModels[provider.rawValue] = $0 }
                        ),
                        models: availableModels,
                        recommended: provider.recommendedAccurateModel,
                        isLiveList: !liveModels.isEmpty
                    )
                } label: {
                    LabeledContent("ai.model.accurate", value: settings.accurateModel(for: provider))
                }
                notInListWarning(settings.accurateModel(for: provider))
            }
        } header: {
            Text("ai.model.title")
        } footer: {
            Text("ai.highAccuracy.footer")
        }
    }

    private var usageSection: some View {
        Section {
            usageRow("ai.usage.today", usageToday)
            usageRow("ai.usage.month", usageMonth)
        } header: {
            Text("ai.usage.title")
        } footer: {
            Text("ai.usage.footer")
        }
    }

    private var limitSection: some View {
        Section {
            Toggle("ai.limit.toggle", isOn: Binding(
                get: { settings.dailyLimit != nil },
                set: { settings.dailyLimit = $0 ? (settings.dailyLimit ?? 20) : nil }
            ))
            if let limit = settings.dailyLimit {
                Stepper(value: Binding(get: { limit }, set: { settings.dailyLimit = $0 }), in: 1...200) {
                    Text(verbatim: String(localized: "ai.limit.value \(format.number(limit))"))
                }
            }
        } footer: {
            Text("ai.limit.footer")
        }
    }

    private func usageRow(_ key: LocalizedStringKey, _ summary: UsageSummary) -> some View {
        LabeledContent(key) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: String(localized: "ai.usage.requests \(format.number(summary.requests))"))
                Text(verbatim: summary.requests == 0 || summary.estimatedCost > 0
                     ? "≈ \(format.cost(summary.estimatedCost))"
                     : String(localized: "ai.usage.noPrice"))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.muted)
            }
        }
    }

    // MARK: Actions

    private func reload() {
        storedKey = keyStore.key(for: provider)
        testTask?.cancel()
        testTask = nil
        testID = nil
        testState = .idle
        liveModels = []
        let service = AIService(context: context)
        let calendar = Calendar.current
        usageToday = service.summary(since: calendar.startOfDay(for: .now))
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now
        usageMonth = service.summary(since: monthStart)
        if let key = storedKey {
            let kind = provider
            Task {
                let models = await service.listModels(provider: kind, key: key)
                if kind == provider { liveModels = models }
            }
        }
    }

    /// Runs the test in a task the Cancel button can stop. `testConnection` always returns
    /// (answer, error, 30 s timeout or cancellation), so the spinner always stops.
    private func startTest() {
        testTask?.cancel()
        guard let key = storedKey ?? keyStore.key(for: provider) else {
            testState = .idle
            return
        }
        testState = .running
        let kind = provider
        let model = settings.standardModel(for: kind)
        let service = AIService(context: context)
        let id = UUID()
        testID = id
        testTask = Task {
            let result = await service.testConnection(provider: kind, key: key, model: model)
            guard testID == id else { return }   // a newer test (or a provider change) replaced this one
            switch result {
            case .success(let reply):
                let cost = PriceTable.estimatedCost(of: reply.usage, model: reply.model, overrides: PriceTable.overrides())
                testState = .passed(model: reply.model, cost: cost)
            case .failure(.cancelled):
                testState = .idle
            case .failure(let error):
                testState = .failed(error)
            }
            testTask = nil
        }
    }

    private func passedText(model: String, cost: Double?) -> String {
        guard let cost else { return String(localized: "ai.test.passed \(model)") }
        return String(localized: "ai.test.passedCost \(model) \(format.cost(cost))")
    }
}

/// Model list (live from the provider when a key is set) plus a custom model ID.
struct ModelPickerView: View {
    let titleKey: LocalizedStringKey
    @Binding var selection: String
    let models: [String]
    let recommended: String
    let isLiveList: Bool

    @State private var custom = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("ai.model.custom", text: $custom)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                    Button("common.use") {
                        selection = custom.trimmingCharacters(in: .whitespaces)
                        dismiss()
                    }
                    .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("ai.model.customFooter")
            }
            Section {
                ForEach(models, id: \.self) { model in
                    Button {
                        selection = model
                        dismiss()
                    } label: {
                        HStack {
                            Text(verbatim: model).font(.callout.monospaced()).foregroundStyle(Theme.Palette.ink)
                            if model == recommended {
                                Text("ai.model.recommended")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.Palette.halo, in: Capsule())
                            }
                            Spacer()
                            if model == selection { Image(systemName: "checkmark").foregroundStyle(Theme.Palette.primary) }
                        }
                    }
                }
            } footer: {
                if isLiveList && !models.contains(recommended) {
                    Text("ai.model.recommendedMissing")
                } else if !isLiveList {
                    Text("ai.model.builtInFooter")
                }
            }
        }
        .navigationTitle(titleKey)
        .environment(\.layoutDirection, .leftToRight)   // model IDs are Latin text
    }
}
