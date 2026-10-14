import LakhasKit
import SwiftData
import SwiftUI

/// Review before saving (PROJECT_PROMPT.md §4.3): edit grams (type or slider), add or remove
/// items, pick the meal, correct with AI. Totals are always grams × per-100 g.
struct ReviewView: View {
    let request: LogRequest
    let source: LogSource
    let photoData: Data?
    let onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @State private var items: [DraftItem]
    @State private var notes: String?
    @State private var costNote: String?
    @State private var mealType: MealType
    @State private var correction = ""
    @State private var isCorrecting = false
    @State private var error: AIError?
    @State private var showSearch = false
    @State private var saved = 0

    private let format = AppFormat.current

    init(request: LogRequest, source: LogSource, outcome: MealAnalyzer.Outcome?, items: [DraftItem] = [],
         photoData: Data? = nil, onSaved: @escaping () -> Void) {
        self.request = request
        self.source = source
        self.photoData = photoData
        self.onSaved = onSaved
        _items = State(initialValue: outcome?.items ?? items)
        _notes = State(initialValue: outcome?.notes)
        _costNote = State(initialValue: outcome.map(ReviewView.costText))
        _mealType = State(initialValue: request.mealType ?? MealType.suggested(for: request.date))
    }

    private var totals: Macros { items.reduce(.zero) { $0 + $1.totals } }
    private var canCorrect: Bool { source == .photo || source == .text }
    private var canSubmitCorrection: Bool { !correction.trimmingCharacters(in: .whitespaces).isEmpty && !isCorrecting }

    var body: some View {
        List {
            if let photoData, let image = UIImage(data: photoData) {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
                        .accessibilityHidden(true)
                }
            }
            if let notes, !notes.isEmpty {
                Section { Label(notes, systemImage: "info.circle").font(.callout) }
            }
            Section {
                if items.isEmpty {
                    Text("review.empty").foregroundStyle(Theme.Palette.muted)
                }
                ForEach($items) { $item in
                    ReviewItemRow(item: $item, format: format)
                }
                .onDelete { items.remove(atOffsets: $0) }
                Button {
                    showSearch = true
                } label: {
                    Label("review.addItem", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("ax.review.add")
            } header: {
                Text("review.items")
            }
            if canCorrect {
                correctionSection
            }
            Section {
                Picker("quickadd.mealType", selection: $mealType) {
                    ForEach(MealType.allCases) { Text($0.titleKey).tag($0) }
                }
                if let costNote {
                    Text(verbatim: costNote).font(.footnote).foregroundStyle(Theme.Palette.muted)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { totalsBar }
        .navigationTitle("review.title")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSearch) {
            NavigationStack {
                FoodSearchView { food, grams in
                    items.append(DraftItem(food: food, grams: grams))
                    showSearch = false
                }
            }
        }
        .sensoryFeedback(.success, trigger: saved)
    }

    private var correctionSection: some View {
        Section {
            TextField("review.correct.placeholder", text: $correction)
                .submitLabel(.go)
                .onSubmit { if canSubmitCorrection { Task { await runCorrection() } } }
                .accessibilityIdentifier("ax.review.correction")
            Button {
                Task { await runCorrection() }
            } label: {
                HStack {
                    Label("review.correct.button", systemImage: "wand.and.stars")
                    Spacer()
                    if isCorrecting { ProgressView() }
                }
            }
            .disabled(!canSubmitCorrection)
            .accessibilityIdentifier("ax.review.correct")
            if let error {
                Text(error.messageKey).font(.footnote).foregroundStyle(Theme.Palette.accent)
            }
        } header: {
            Text("review.correct.title")
        }
    }

    private var totalsBar: some View {
        VStack(spacing: Theme.Space.xs) {
            HStack {
                Text("review.total").font(.headline)
                Spacer()
                Text(verbatim: "\(format.number(Int(totals.kcal.rounded()))) \(String(localized: "unit.kcal"))")
                    .font(.headline.monospacedDigit())
                    .accessibilityIdentifier("ax.review.total")
            }
            HStack(spacing: Theme.Space.md) {
                macro("macro.protein.short", totals.protein)
                macro("macro.carbs.short", totals.carbs)
                macro("macro.fat.short", totals.fat)
                Spacer()
            }
            PrimaryButton(titleKey: "common.save", isEnabled: !items.isEmpty, action: save)
                .accessibilityIdentifier("ax.review.save")
        }
        .padding(Theme.Space.md)
        .background(Theme.Palette.surface)
    }

    private func macro(_ key: LocalizedStringKey, _ grams: Double) -> some View {
        HStack(spacing: 2) {
            Text(key)
            Text(verbatim: "\(format.number(Int(grams.rounded())))\(String(localized: "unit.g"))")
        }
        .font(.footnote.monospacedDigit())
        .foregroundStyle(Theme.Palette.muted)
    }

    private func runCorrection() async {
        isCorrecting = true
        error = nil
        defer { isCorrecting = false }
        do {
            let outcome = try await MealAnalyzer(service: AIService(context: context))
                .correct(items, correction: correction, language: format.language)
            items = outcome.items
            notes = outcome.notes
            costNote = Self.costText(outcome)
            correction = ""
        } catch let aiError as AIError {
            error = aiError
        } catch {
            self.error = .network
        }
    }

    private func save() {
        let meal = Meal(loggedAt: request.date, mealType: mealType, source: source)
        if let photoData {
            meal.photoFileName = try? MealPhotoStore().save(photoData)
        }
        context.insert(meal)
        meal.append(items.map { $0.makeMealItem() })
        try? context.save()
        saved += 1
        onSaved()
    }

    static func costText(_ outcome: MealAnalyzer.Outcome) -> String {
        costText(fromCache: outcome.fromCache, cost: outcome.estimatedCost, model: outcome.model)
    }

    static func costText(fromCache: Bool, cost: Double?, model: String) -> String {
        if fromCache { return String(localized: "review.cost.cached") }
        guard let cost else { return String(localized: "review.cost.unknown \(model)") }
        return String(localized: "review.cost \(AppFormat.current.cost(cost)) \(model)")
    }
}

private struct ReviewItemRow: View {
    @Binding var item: DraftItem
    let format: AppFormat

    private var sliderMax: Double { max(500, (item.servedGrams ?? item.grams) * 2) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: item.name(language: format.language)).font(.headline)
                Text(item.valueSource == .db ? LocalizedStringKey("review.source.db") : LocalizedStringKey("review.source.ai"))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.Palette.halo, in: Capsule())
                Spacer()
                Text(verbatim: "\(format.number(Int(item.totals.kcal.rounded()))) \(String(localized: "unit.kcal"))")
                    .font(.callout.monospacedDigit())
            }
            HStack {
                TextField("unit.g", value: $item.grams, format: .number.precision(.fractionLength(0)).locale(format.locale))
                    .keyboardType(.numberPad)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(Text("review.grams"))
                Text("unit.g").foregroundStyle(Theme.Palette.muted)
                Slider(value: $item.grams, in: 0...sliderMax, step: 5)
                    .tint(Theme.Palette.primary)
                    .accessibilityLabel(Text("review.grams"))
            }
            if let served = item.servedGrams, let left = item.leftoverGrams {
                Text(verbatim: String(localized: "review.leftover \(format.number(Int(served))) \(format.number(Int(left)))"))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.muted)
            }
            if item.needsCheck {
                Label("review.checkAmount", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.warning)
            }
        }
        .padding(.vertical, Theme.Space.xxs)
        .accessibilityIdentifier("ax.review.item")
    }
}
