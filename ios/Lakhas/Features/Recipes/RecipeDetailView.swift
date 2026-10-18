import LakhasKit
import SwiftData
import SwiftUI

/// One recipe (PROJECT_PROMPT.md §4.4): per-serving calories and macros, servings, ingredients
/// with grams, steps. Every edit recalculates live; Save keeps the changes, and logging one
/// serving saves them too.
struct RecipeDetailView: View {
    let recipe: Recipe

    @Environment(\.modelContext) private var context
    @State private var draft: RecipeDraft
    @State private var scaleIngredients = true
    @State private var mealType = MealType.suggested(for: .now)
    @State private var showSearch = false
    @State private var logged = 0
    @State private var showLogged = false

    private let format = AppFormat.current

    init(recipe: Recipe) {
        self.recipe = recipe
        _draft = State(initialValue: recipe.draft)
    }

    private var isDirty: Bool { draft != recipe.draft }

    var body: some View {
        List {
            header
            servingSection
            ingredientSection
            if !draft.steps.isEmpty {
                Section {
                    ForEach(Array(draft.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                            Text(verbatim: format.number(index + 1))
                                .font(.callout.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Theme.Palette.primary)
                            Text(verbatim: step).font(.callout)
                        }
                    }
                } header: {
                    Text("recipes.detail.steps")
                }
            }
            logSection
        }
        .navigationTitle(draft.title(language: format.language))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("common.save", action: save)
                    .disabled(!isDirty)
                    .accessibilityIdentifier("ax.recipe.save")
            }
        }
        .sheet(isPresented: $showSearch) {
            NavigationStack {
                FoodSearchView { food, grams in
                    draft.ingredients.append(DraftItem(food: food, grams: grams))
                    showSearch = false
                }
            }
        }
        .sensoryFeedback(.success, trigger: logged)
    }

    // MARK: Sections

    private var titleBinding: Binding<String> {
        format.language == "ar" ? $draft.titleAr : $draft.titleEn
    }

    private var header: some View {
        Section {
            if let photo = recipe.photoFileName,
               let image = UIImage(contentsOfFile: MealPhotoStore().url(for: photo).path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
                    .accessibilityHidden(true)
            }
            TextField("recipes.detail.title", text: titleBinding, axis: .vertical)
                .font(.title3.bold())
                .accessibilityIdentifier("ax.recipe.title")
            if let source = sourceLine {
                if let url = draft.sourceURL {
                    Link(destination: url) {
                        Label(source, systemImage: "link").font(.footnote)
                    }
                } else {
                    Label(source, systemImage: "photo").font(.footnote).foregroundStyle(Theme.Palette.muted)
                }
            }
            if draft.estimated {
                Label("recipes.detail.estimated", systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.warning)
            }
            if let notes = draft.notes, !notes.isEmpty {
                Label(notes, systemImage: "info.circle").font(.footnote)
            }
        }
    }

    private var sourceLine: String? {
        var parts: [String] = []
        if let platform = draft.platform { parts.append(platform.displayName) }
        if let handle = draft.creatorHandle { parts.append(handle) }
        if parts.isEmpty, draft.source == .screenshot { parts.append(String(localized: "recipes.detail.fromScreenshots")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var servingSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text("recipes.detail.perServing").font(.headline)
                Spacer()
                Text(verbatim: "\(format.number(Int(draft.perServing.kcal.rounded()))) \(String(localized: "unit.kcal"))")
                    .font(.title3.bold().monospacedDigit())
                    .accessibilityIdentifier("ax.recipe.perServing")
            }
            HStack(spacing: Theme.Space.md) {
                macro(.protein, draft.perServing.protein)
                macro(.carbs, draft.perServing.carbs)
                macro(.fat, draft.perServing.fat)
                Spacer()
            }
            Stepper(value: Binding(get: { draft.servings }, set: { draft.setServings($0, scaleIngredients: scaleIngredients) }),
                    in: RecipeDraft.servingsRange) {
                Text("recipes.detail.servings \(format.number(draft.servings))")
            }
            .accessibilityIdentifier("ax.recipe.servings")
            Toggle("recipes.detail.scale", isOn: $scaleIngredients)
        } footer: {
            Text(scaleIngredients ? LocalizedStringKey("recipes.detail.scale.on") : LocalizedStringKey("recipes.detail.scale.off"))
        }
    }

    private func macro(_ kind: MacroKind, _ grams: Double) -> some View {
        Label {
            Text(verbatim: "\(format.number(Int(grams.rounded())))\(String(localized: "unit.g"))")
                .font(.footnote.monospacedDigit())
        } icon: {
            Image(systemName: kind.symbol).foregroundStyle(kind.color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(kind.nameKey))
        .accessibilityValue(Text(verbatim: "\(format.number(Int(grams.rounded()))) \(String(localized: "unit.g"))"))
    }

    private var ingredientSection: some View {
        Section {
            ForEach($draft.ingredients) { $item in
                RecipeIngredientRow(item: $item, format: format)
            }
            .onDelete { draft.ingredients.remove(atOffsets: $0) }
            Button {
                showSearch = true
            } label: {
                Label("review.addItem", systemImage: "plus.circle")
            }
        } header: {
            HStack {
                Text("recipes.detail.ingredients")
                Spacer()
                Text(verbatim: "\(format.number(Int(draft.totals.kcal.rounded()))) \(String(localized: "unit.kcal"))")
                    .monospacedDigit()
            }
        } footer: {
            Text("recipes.detail.ingredients.footer")
        }
    }

    private var logSection: some View {
        Section {
            Picker("quickadd.mealType", selection: $mealType) {
                ForEach(MealType.allCases) { Text($0.titleKey).tag($0) }
            }
            PrimaryButton(titleKey: "recipes.detail.log", isEnabled: !draft.ingredients.isEmpty, action: logOneServing)
                .accessibilityIdentifier("ax.recipe.log")
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            if showLogged {
                Label("recipes.detail.logged", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Palette.primary)
                    .accessibilityIdentifier("ax.recipe.logged")
            }
        } footer: {
            if let cost = importCostText { Text(verbatim: cost) }
        }
    }

    private var importCostText: String? {
        guard let model = recipe.importModel else { return nil }
        if recipe.importCost == 0 { return String(localized: "review.cost.cached") }
        guard let cost = recipe.importCost else { return String(localized: "recipes.detail.importCost.unknown \(model)") }
        return String(localized: "recipes.detail.importCost \(format.cost(cost)) \(model)")
    }

    // MARK: Actions

    private func save() {
        recipe.apply(draft, in: context)
        try? context.save()
        // Fresh ids from the saved ingredients keep `isDirty` honest.
        draft = recipe.draft
    }

    /// Each ingredient's share of one serving, as one meal titled with the recipe.
    private func logOneServing() {
        if isDirty { save() }
        let meal = Meal(mealType: mealType, source: .recipe, title: draft.title(language: format.language))
        context.insert(meal)
        meal.append(draft.servingItems().map { $0.makeMealItem() })
        try? context.save()
        logged += 1
        showLogged = true
    }
}

private struct RecipeIngredientRow: View {
    @Binding var item: DraftItem
    let format: AppFormat

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.name(language: format.language)).font(.callout.weight(.semibold))
                if let measure = item.measure {
                    Text(verbatim: measure).font(.caption).foregroundStyle(Theme.Palette.muted)
                }
            }
            Spacer(minLength: Theme.Space.xs)
            TextField("unit.g", value: $item.grams, format: .number.precision(.fractionLength(0...1)).locale(format.locale))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(Text(verbatim: item.name(language: format.language)))
                .accessibilityIdentifier("ax.recipe.grams")
            Text("unit.g").font(.caption).foregroundStyle(Theme.Palette.muted)
            Text(verbatim: format.number(Int(item.totals.kcal.rounded())))
                .font(.callout.monospacedDigit())
                .frame(minWidth: 44, alignment: .trailing)
        }
    }
}
