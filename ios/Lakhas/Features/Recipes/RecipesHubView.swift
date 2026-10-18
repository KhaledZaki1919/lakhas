import LakhasKit
import SwiftData
import SwiftUI

/// "My Recipes" (PROJECT_PROMPT.md §4.4): imported recipes, saved meals and the user's products,
/// with search and delete. Everything here lives on this device only.
struct RecipesHubView: View {
    let onImport: () -> Void

    enum HubTab: String, CaseIterable, Identifiable {
        case recipes, meals, products

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .recipes: "recipes.hub.recipes"
            case .meals: "recipes.hub.meals"
            case .products: "recipes.hub.products"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @Query(sort: \SavedMeal.lastUsedAt, order: .reverse) private var meals: [SavedMeal]
    @Query(sort: \Product.lastUsedAt, order: .reverse) private var products: [Product]
    @State private var section: HubTab = .recipes
    @State private var search = ""

    private let format = AppFormat.current

    var body: some View {
        List {
            Picker("recipes.hub.section", selection: $section) {
                ForEach(HubTab.allCases) { Text($0.titleKey).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .accessibilityIdentifier("ax.recipes.section")

            switch section {
            case .recipes: recipeRows
            case .meals: mealRows
            case .products: productRows
            }
        }
        .searchable(text: $search, prompt: Text("recipes.hub.search"))
        .navigationTitle("tab.recipes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onImport) {
                    Label("recipes.import.title", systemImage: "plus")
                }
                .accessibilityIdentifier("ax.recipes.import")
            }
        }
        .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
        .navigationDestination(for: SavedMeal.self) { SavedMealDetailView(meal: $0) }
        .navigationDestination(for: Product.self) { ProductDetailView(product: $0) }
    }

    // MARK: Rows

    @ViewBuilder private var recipeRows: some View {
        let shown = recipes.filter { matches($0.titleAr, $0.titleEn, $0.creatorHandle ?? "") }
        if shown.isEmpty {
            emptyState(search.isEmpty ? "recipes.empty.recipes" : "recipes.empty.search", symbol: "book") {
                if search.isEmpty {
                    Button("recipes.import.title", action: onImport).buttonStyle(.borderedProminent).tint(Theme.Palette.primary)
                }
            }
        }
        ForEach(shown) { recipe in
            NavigationLink(value: recipe) {
                HubRow(photo: recipe.photoFileName, symbol: "book", title: recipe.title(language: format.language),
                       detail: recipeDetail(recipe), kcal: recipe.draft.perServing.kcal, format: format)
            }
            .accessibilityIdentifier("ax.recipes.row")
        }
        .onDelete { offsets in delete(offsets.map { shown[$0] }) }
    }

    @ViewBuilder private var mealRows: some View {
        let shown = meals.filter { meal in
            matches(meal.title, meal.items.map(\.nameAr).joined(separator: " "), meal.items.map(\.nameEn).joined(separator: " "))
        }
        if shown.isEmpty {
            emptyState(search.isEmpty ? "recipes.empty.meals" : "recipes.empty.search", symbol: "bookmark") { EmptyView() }
        }
        ForEach(shown) { meal in
            NavigationLink(value: meal) {
                HubRow(photo: meal.photoFileName, symbol: "bookmark", title: meal.title,
                       detail: String(localized: "recipes.hub.items \(format.number(meal.items.count))"),
                       kcal: meal.totals.kcal, format: format)
            }
            .accessibilityIdentifier("ax.recipes.meal")
        }
        .onDelete { offsets in delete(offsets.map { shown[$0] }) }
    }

    @ViewBuilder private var productRows: some View {
        let shown = products.filter { matches($0.nameAr, $0.nameEn, $0.brand ?? "", $0.barcode) }
        if shown.isEmpty {
            emptyState(search.isEmpty ? "recipes.empty.products" : "recipes.empty.search", symbol: "barcode") { EmptyView() }
        }
        ForEach(shown) { product in
            NavigationLink(value: product) {
                HubRow(photo: product.photoFileName, symbol: "barcode", title: product.info.name(language: format.language),
                       detail: [product.brand, String(localized: "recipes.hub.per100")].compactMap { $0 }.joined(separator: " · "),
                       kcal: product.kcalPer100, format: format)
            }
            .accessibilityIdentifier("ax.recipes.product")
        }
        .onDelete { offsets in delete(offsets.map { shown[$0] }) }
    }

    private func recipeDetail(_ recipe: Recipe) -> String {
        var parts = [String(localized: "recipes.hub.servings \(format.number(recipe.servings))")]
        if let platform = recipe.platform { parts.append(platform.displayName) }
        if let handle = recipe.creatorHandle { parts.append(handle) }
        return parts.joined(separator: " · ")
    }

    private func emptyState<Actions: View>(_ key: LocalizedStringKey, symbol: String,
                                          @ViewBuilder actions: () -> Actions) -> some View {
        ContentUnavailableView {
            Label(section.titleKey, systemImage: symbol)
        } description: {
            Text(key)
        } actions: {
            actions()
        }
        .listRowBackground(Color.clear)
    }

    // MARK: Search and delete

    private func matches(_ fields: String...) -> Bool {
        let needle = TextNormalizer.normalize(search.trimmingCharacters(in: .whitespaces))
        guard !needle.isEmpty else { return true }
        return fields.contains { TextNormalizer.normalize($0).contains(needle) }
    }

    private func delete(_ recipes: [Recipe]) {
        for recipe in recipes {
            if let photo = recipe.photoFileName { MealPhotoStore().delete(photo) }
            context.delete(recipe)
        }
        try? context.save()
    }

    private func delete(_ meals: [SavedMeal]) {
        for meal in meals { context.delete(meal) }
        try? context.save()
    }

    private func delete(_ products: [Product]) {
        for product in products {
            if let photo = product.photoFileName { MealPhotoStore().delete(photo) }
            context.delete(product)
        }
        try? context.save()
    }
}

/// Thumbnail, title, one detail line and kcal.
struct HubRow: View {
    let photo: String?
    let symbol: String
    let title: String
    let detail: String
    let kcal: Double
    let format: AppFormat

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            MealThumbnail(fileName: photo, symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.headline).foregroundStyle(Theme.Palette.ink).lineLimit(2)
                Text(verbatim: detail).font(.caption).foregroundStyle(Theme.Palette.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: format.number(Int(kcal.rounded()))).font(.headline.monospacedDigit())
                Text("unit.kcal").font(.caption2).foregroundStyle(Theme.Palette.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
