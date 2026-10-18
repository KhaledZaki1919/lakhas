import Foundation

/// An editable recipe: what an import returns and what the recipe screen edits. Totals are
/// always grams × per-100 g, summed over the ingredients of the whole recipe.
public struct RecipeDraft: Equatable, Sendable {
    public static let servingsRange = 1...50

    public var titleAr: String
    public var titleEn: String
    public var servings: Int
    /// For the whole recipe (all servings).
    public var ingredients: [DraftItem]
    public var steps: [String]
    public var notes: String?
    public var estimated: Bool
    public var source: RecipeSource
    public var sourceURL: URL?
    public var platform: RecipePlatform?
    public var creatorHandle: String?
    /// Language of the steps (the app language at import).
    public var language: String

    public init(titleAr: String, titleEn: String, servings: Int, ingredients: [DraftItem], steps: [String] = [],
                notes: String? = nil, estimated: Bool = false, source: RecipeSource, sourceURL: URL? = nil,
                platform: RecipePlatform? = nil, creatorHandle: String? = nil, language: String) {
        self.titleAr = titleAr
        self.titleEn = titleEn
        self.servings = min(max(servings, Self.servingsRange.lowerBound), Self.servingsRange.upperBound)
        self.ingredients = ingredients
        self.steps = steps
        self.notes = notes
        self.estimated = estimated
        self.source = source
        self.sourceURL = sourceURL
        self.platform = platform
        self.creatorHandle = creatorHandle
        self.language = language
    }

    public func title(language: String) -> String {
        language == "ar" ? (titleAr.isEmpty ? titleEn : titleAr) : (titleEn.isEmpty ? titleAr : titleEn)
    }

    public var totals: Macros { ingredients.reduce(.zero) { $0 + $1.totals } }
    public var totalGrams: Double { ingredients.reduce(0) { $0 + $1.grams } }

    public var perServing: Macros {
        let count = Double(max(servings, 1))
        let total = totals
        return Macros(kcal: total.kcal / count, protein: total.protein / count,
                      carbs: total.carbs / count, fat: total.fat / count)
    }

    /// Changes the number of servings. With `scaleIngredients` every amount changes in
    /// proportion, so one serving stays the same; without it the same pot is shared by more
    /// (or fewer) people, so one serving gets smaller (or larger).
    public mutating func setServings(_ newValue: Int, scaleIngredients: Bool) {
        let clamped = min(max(newValue, Self.servingsRange.lowerBound), Self.servingsRange.upperBound)
        guard clamped != servings else { return }
        if scaleIngredients {
            let factor = Double(clamped) / Double(servings)
            for index in ingredients.indices {
                ingredients[index].grams = (ingredients[index].grams * factor * 10).rounded() / 10
            }
        }
        servings = clamped
    }

    /// The lines logged for `portions` servings: each ingredient's share, in recipe order.
    public func servingItems(portions: Double = 1) -> [DraftItem] {
        let share = portions / Double(max(servings, 1))
        return ingredients.compactMap { ingredient in
            let grams = (ingredient.grams * share * 10).rounded() / 10
            guard grams > 0 else { return nil }
            var item = ingredient
            item.grams = grams
            item.servedGrams = nil
            item.leftoverGrams = nil
            return item
        }
    }
}
