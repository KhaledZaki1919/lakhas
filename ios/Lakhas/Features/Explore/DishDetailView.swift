import LakhasKit
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// One Explore dish (PROJECT_PROMPT.md §4.5, ADR-026): per-serving values, servings that scale
/// every amount, editable grams, "Log to Today" with a meal type and "Save to My Recipes".
/// Everything is computed from the bundled food DB; nothing here uses AI or the user's key.
struct DishDetailView: View {
    let dish: ExploreDish

    @Environment(\.modelContext) private var context
    @Query private var preferences: [DishPreference]
    @Query private var savedRecipes: [Recipe]
    @State private var draft: RecipeDraft
    @State private var mealType: MealType
    @State private var portions = 1.0
    @State private var showSearch = false
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var loggedMeal: Meal?
    @State private var logged = 0

    private let format = AppFormat.current
    /// Grams per serving as shipped, to know when a household measure still applies.
    private let baseGramsPerServing: [UUID: Double]

    init(dish: ExploreDish) {
        self.dish = dish
        let dishId = dish.id
        let optionalId: String? = dish.id
        _preferences = Query(filter: #Predicate<DishPreference> { $0.dishId == dishId })
        _savedRecipes = Query(filter: #Predicate<Recipe> { $0.exploreDishId == optionalId })
        let draft = dish.draft(language: AppFormat.current.language)
        _draft = State(initialValue: draft)
        _mealType = State(initialValue: dish.suggestedMealType())
        let servings = Double(max(draft.servings, 1))
        baseGramsPerServing = Dictionary(draft.ingredients.map { ($0.id, $0.grams / servings) },
                                         uniquingKeysWith: { first, _ in first })
    }

    private var preference: DishPreference? { preferences.first }

    var body: some View {
        List {
            header
            servingSection
            ingredientSection
            logSection
            saveSection
        }
        .navigationTitle(dish.name(language: format.language))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSearch) {
            NavigationStack {
                FoodSearchView { food, grams in
                    draft.ingredients.append(DraftItem(food: food, grams: grams))
                    showSearch = false
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraView { captured in
                if let captured { setPhoto(captured) }
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { setPhoto(data) }
                pickerItem = nil
            }
        }
        .sensoryFeedback(.success, trigger: logged)
    }

    // MARK: Sections

    private var header: some View {
        Section {
            DishHero(category: dish.dishCategory, photoFileName: preference?.photoFileName)
                .listRowInsets(EdgeInsets())
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(verbatim: dish.name(language: format.language))
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: tagLine)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.muted)
            }
            HStack(spacing: Theme.Space.md) {
                let isFavorite = preference?.isFavorite ?? false
                let rating = preference?.rating ?? .none
                Button {
                    updatePreference { $0.toggleFavorite() }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? Theme.Palette.accent : Theme.Palette.muted)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(Text(isFavorite ? "explore.favorite.remove" : "explore.favorite.add"))
                .accessibilityAddTraits(isFavorite ? .isSelected : [])
                .accessibilityIdentifier("ax.explore.favorite")
                Button {
                    updatePreference { $0.rate(.liked) }
                } label: {
                    Image(systemName: rating == .liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .foregroundStyle(rating == .liked ? Theme.Palette.primary : Theme.Palette.muted)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(Text("explore.like"))
                .accessibilityAddTraits(rating == .liked ? .isSelected : [])
                .accessibilityIdentifier("ax.explore.like")
                Button {
                    updatePreference { $0.rate(.disliked) }
                } label: {
                    Image(systemName: rating == .disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .foregroundStyle(rating == .disliked ? Theme.Palette.ink : Theme.Palette.muted)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(Text("explore.dislike"))
                .accessibilityAddTraits(rating == .disliked ? .isSelected : [])
                .accessibilityIdentifier("ax.explore.dislike")
                Spacer()
                photoMenu
            }
            .font(.title3)
            .buttonStyle(.borderless)
            Label("explore.estimate", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.muted)
        }
    }

    private var tagLine: String {
        let separator = format.language == "ar" ? "، " : ", "
        let meals = dish.meals.map { String(localized: $0.resource) }.joined(separator: separator)
        let goals = dish.goalTags.map { String(localized: $0.exploreResource) }.joined(separator: separator)
        return "\(meals) · \(goals)"
    }

    private var photoMenu: some View {
        Menu {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("photo.library", systemImage: "photo.on.rectangle")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCamera = true
                } label: {
                    Label("photo.camera", systemImage: "camera")
                }
            }
            if preference?.photoFileName != nil {
                Button(role: .destructive, action: removePhoto) {
                    Label("explore.photo.remove", systemImage: "trash")
                }
            }
        } label: {
            Label("explore.photo.set", systemImage: "camera")
                .labelStyle(.iconOnly)
                .foregroundStyle(Theme.Palette.primary)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(Text("explore.photo.set"))
        .accessibilityIdentifier("ax.explore.photo")
    }

    private var servingSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text("explore.perServing").font(.headline)
                Spacer()
                Text(verbatim: "\(format.number(Int(draft.perServing.kcal.rounded()))) \(String(localized: "unit.kcal"))")
                    .font(.title3.bold().monospacedDigit())
                    .accessibilityIdentifier("ax.explore.perServing")
            }
            HStack(spacing: Theme.Space.md) {
                macro(.protein, draft.perServing.protein)
                macro(.carbs, draft.perServing.carbs)
                macro(.fat, draft.perServing.fat)
                Spacer()
            }
            Stepper(value: Binding(get: { draft.servings }, set: { draft.setServings($0, scaleIngredients: true) }),
                    in: RecipeDraft.servingsRange) {
                Text("explore.servings \(format.number(draft.servings))")
            }
            .accessibilityIdentifier("ax.explore.servings")
        } footer: {
            Text("explore.servings.footer")
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
                DishIngredientRow(item: $item, showsMeasure: measureApplies(item), format: format)
            }
            .onDelete { draft.ingredients.remove(atOffsets: $0) }
            Button {
                showSearch = true
            } label: {
                Label("review.addItem", systemImage: "plus.circle")
            }
        } header: {
            HStack {
                Text("explore.ingredients")
                Spacer()
                Text(verbatim: "\(format.number(Int(draft.totals.kcal.rounded()))) \(String(localized: "unit.kcal"))")
                    .monospacedDigit()
            }
        } footer: {
            Text("explore.ingredients.footer")
        }
    }

    /// The shipped household measure ("plate", "loaf") only describes the shipped amount.
    private func measureApplies(_ item: DraftItem) -> Bool {
        guard item.measure != nil, draft.servings == dish.servings, let base = baseGramsPerServing[item.id] else { return false }
        return abs(item.grams - base * Double(draft.servings)) < 0.15
    }

    private var logSection: some View {
        Section {
            Picker("quickadd.mealType", selection: $mealType) {
                ForEach(MealType.allCases) { Text($0.titleKey).tag($0) }
            }
            .accessibilityIdentifier("ax.explore.mealType")
            Stepper(value: $portions, in: ExploreLog.portionsRange, step: 0.5) {
                Text("explore.portions \(format.number(portions, fractionDigits: 1))")
            }
            .accessibilityIdentifier("ax.explore.portions")
            HStack {
                Text("explore.logTotal")
                Spacer()
                Text(verbatim: "\(format.number(Int((draft.perServing.kcal * portions).rounded()))) \(String(localized: "unit.kcal"))")
                    .font(.headline.monospacedDigit())
                    .accessibilityIdentifier("ax.explore.logTotal")
            }
            PrimaryButton(titleKey: "explore.log", isEnabled: !draft.ingredients.isEmpty, action: log)
                .accessibilityIdentifier("ax.explore.log")
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            if loggedMeal != nil {
                Label("explore.logged", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Palette.primary)
                    .accessibilityIdentifier("ax.explore.logged")
                if preference?.photoFileName == nil {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text("explore.photo.prompt").font(.footnote)
                        HStack {
                            PhotosPicker(selection: $pickerItem, matching: .images) {
                                Label("photo.library", systemImage: "photo.on.rectangle")
                            }
                            Spacer()
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button {
                                    showCamera = true
                                } label: {
                                    Label("photo.camera", systemImage: "camera")
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.Palette.primary)
                    }
                }
            }
        } footer: {
            Text("explore.noKey")
        }
    }

    private var saveSection: some View {
        Section {
            if savedRecipes.isEmpty {
                Button(action: saveToRecipes) {
                    Label("explore.save", systemImage: "book")
                }
                .disabled(draft.ingredients.isEmpty)
                .accessibilityIdentifier("ax.explore.save")
            } else {
                Label("explore.saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Palette.primary)
                    .accessibilityIdentifier("ax.explore.saved")
            }
        }
    }

    // MARK: Actions

    private func updatePreference(_ change: (DishPreference) -> Void) {
        change(DishPreference.findOrInsert(dish.id, in: context))
        try? context.save()
    }

    private func log() {
        let meal = ExploreLog.log(draft, portions: portions, mealType: mealType, language: format.language, in: context)
        if let photo = preference?.photoFileName { meal.photoFileName = copyPhoto(photo) }
        try? context.save()
        loggedMeal = meal
        logged += 1
    }

    private func saveToRecipes() {
        let recipe = ExploreLog.saveToRecipes(draft, dishId: dish.id, in: context)
        if let photo = preference?.photoFileName { recipe.photoFileName = copyPhoto(photo) }
        try? context.save()
    }

    /// The photo becomes the dish's picture; the meal just logged gets its own copy.
    private func setPhoto(_ data: Data) {
        let store = MealPhotoStore()
        guard let name = try? store.save(data) else { return }
        updatePreference { preference in
            if let old = preference.photoFileName { store.delete(old) }
            preference.photoFileName = name
        }
        if let meal = loggedMeal, meal.photoFileName == nil {
            meal.photoFileName = try? store.save(data)
            try? context.save()
        }
    }

    private func removePhoto() {
        updatePreference { preference in
            if let old = preference.photoFileName { MealPhotoStore().delete(old) }
            preference.photoFileName = nil
        }
    }

    /// Meals and recipes own their files (deleting one never removes another's photo).
    private func copyPhoto(_ name: String) -> String? {
        let store = MealPhotoStore()
        guard let data = try? Data(contentsOf: store.url(for: name)) else { return nil }
        return try? store.save(data)
    }
}

private struct DishIngredientRow: View {
    @Binding var item: DraftItem
    let showsMeasure: Bool
    let format: AppFormat

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.name(language: format.language)).font(.callout.weight(.semibold))
                if showsMeasure, let measure = item.measure {
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
                .accessibilityIdentifier("ax.explore.grams")
            Text("unit.g").font(.caption).foregroundStyle(Theme.Palette.muted)
            Text(verbatim: format.number(Int(item.totals.kcal.rounded())))
                .font(.callout.monospacedDigit())
                .frame(minWidth: 44, alignment: .trailing)
        }
    }
}
