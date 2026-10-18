import Foundation
import SwiftData

/// How a recipe got into the app.
public enum RecipeSource: String, Codable, Sendable {
    /// The public text of a TikTok / Instagram / YouTube page, fetched on the device.
    case link
    /// A caption or recipe text the user pasted.
    case text
    /// One or more screenshots read by the user's AI provider.
    case screenshot
}

/// An imported recipe (PROJECT_PROMPT.md §4.4). Personal use, stays on this device (ADR-020).
@Model
public final class Recipe {
    @Attribute(.unique) public var id: UUID
    public var titleAr: String
    public var titleEn: String
    public var servings: Int
    /// In the language that was active at import.
    public var steps: [String]
    public var notes: String?
    /// The model filled in a dish's ingredients or amounts the source didn't give.
    public var estimated: Bool
    public var sourceRaw: String
    public var sourceURL: String?
    public var platformRaw: String?
    public var creatorHandle: String?
    public var language: String
    /// First screenshot as a thumbnail in `MealPhotoStore` (device only).
    public var photoFileName: String?
    public var importModel: String?
    /// USD estimate of the import request; 0 when it came from the same-day cache.
    public var importCost: Double?
    public var createdAt: Date
    public var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.recipe) public var ingredients: [RecipeIngredient] = []

    public init(id: UUID = UUID(), draft: RecipeDraft, now: Date = .now) {
        self.id = id
        titleAr = draft.titleAr
        titleEn = draft.titleEn
        servings = draft.servings
        steps = draft.steps
        notes = draft.notes
        estimated = draft.estimated
        sourceRaw = draft.source.rawValue
        sourceURL = draft.sourceURL?.absoluteString
        platformRaw = draft.platform?.rawValue
        creatorHandle = draft.creatorHandle
        language = draft.language
        createdAt = now
        updatedAt = now
    }

    public var source: RecipeSource { RecipeSource(rawValue: sourceRaw) ?? .text }
    public var platform: RecipePlatform? { platformRaw.flatMap(RecipePlatform.init(rawValue:)) }

    /// SwiftData doesn't keep to-many order, so ingredients carry an explicit `sortIndex`.
    public var orderedIngredients: [RecipeIngredient] { ingredients.sorted { $0.sortIndex < $1.sortIndex } }

    public func title(language: String) -> String {
        language == "ar" ? (titleAr.isEmpty ? titleEn : titleAr) : (titleEn.isEmpty ? titleAr : titleEn)
    }

    /// The editable copy shown on the recipe screen.
    public var draft: RecipeDraft {
        RecipeDraft(
            titleAr: titleAr, titleEn: titleEn, servings: servings,
            ingredients: orderedIngredients.map(\.draftItem),
            steps: steps, notes: notes, estimated: estimated, source: source,
            sourceURL: sourceURL.flatMap(URL.init(string:)), platform: platform,
            creatorHandle: creatorHandle, language: language
        )
    }

    /// Inserts a new recipe with the draft's ingredients.
    @discardableResult
    public static func insert(_ draft: RecipeDraft, in context: ModelContext, now: Date = .now) -> Recipe {
        let recipe = Recipe(draft: draft, now: now)
        context.insert(recipe)
        recipe.replaceIngredients(with: draft.ingredients, in: context)
        return recipe
    }

    /// Saves an edited draft (title, servings, ingredients, steps). The import facts stay.
    public func apply(_ draft: RecipeDraft, in context: ModelContext, now: Date = .now) {
        titleAr = draft.titleAr
        titleEn = draft.titleEn
        servings = draft.servings
        steps = draft.steps
        replaceIngredients(with: draft.ingredients, in: context)
        updatedAt = now
    }

    private func replaceIngredients(with items: [DraftItem], in context: ModelContext) {
        for old in ingredients { context.delete(old) }
        ingredients = []
        for (index, item) in items.enumerated() {
            ingredients.append(RecipeIngredient(item: item, sortIndex: index))
        }
    }
}

@Model
public final class RecipeIngredient {
    public var id: UUID
    public var nameAr: String
    public var nameEn: String
    /// Amount as written in the source ("2 cups"), if any.
    public var measure: String?
    /// For the whole recipe (all servings).
    public var grams: Double
    public var kcalPer100: Double
    public var proteinPer100: Double
    public var carbsPer100: Double
    public var fatPer100: Double
    public var valueSourceRaw: String
    public var foodDbId: String?
    public var confidence: Double?
    public var sortIndex: Int
    public var recipe: Recipe?

    public init(item: DraftItem, sortIndex: Int) {
        id = item.id
        nameAr = item.nameAr
        nameEn = item.nameEn
        measure = item.measure
        grams = item.grams
        kcalPer100 = item.per100.kcal
        proteinPer100 = item.per100.protein
        carbsPer100 = item.per100.carbs
        fatPer100 = item.per100.fat
        valueSourceRaw = item.valueSource.rawValue
        foodDbId = item.foodDbId
        confidence = item.confidence
        self.sortIndex = sortIndex
    }

    public var draftItem: DraftItem {
        DraftItem(id: id, nameAr: nameAr, nameEn: nameEn, grams: grams,
                  per100: Macros(kcal: kcalPer100, protein: proteinPer100, carbs: carbsPer100, fat: fatPer100),
                  valueSource: ValueSource(rawValue: valueSourceRaw) ?? .ai, foodDbId: foodDbId,
                  confidence: confidence, measure: measure)
    }
}

/// A logged meal kept as a reusable "ready meal" (PROJECT_PROMPT.md §4.3 D), logged in one tap.
@Model
public final class SavedMeal {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var mealTypeRaw: String
    public var photoFileName: String?
    public var createdAt: Date
    public var lastUsedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \SavedMealItem.savedMeal) public var items: [SavedMealItem] = []

    public init(id: UUID = UUID(), title: String, mealType: MealType, now: Date = .now) {
        self.id = id
        self.title = title
        mealTypeRaw = mealType.rawValue
        createdAt = now
        lastUsedAt = now
    }

    public var mealType: MealType { MealType(rawValue: mealTypeRaw) ?? .snack }
    public var orderedItems: [SavedMealItem] { items.sorted { $0.sortIndex < $1.sortIndex } }
    public var totals: Macros { items.reduce(.zero) { $0 + $1.totals } }

    /// Inserts a copy of the meal's items in order; the title is the meal's name in `language`.
    @discardableResult
    public static func save(_ meal: Meal, language: String, in context: ModelContext, now: Date = .now) -> SavedMeal {
        let saved = SavedMeal(title: meal.displayName(language: language), mealType: meal.mealType, now: now)
        context.insert(saved)
        for (index, item) in meal.orderedItems.enumerated() {
            saved.items.append(SavedMealItem(item: item, sortIndex: index))
        }
        return saved
    }

    /// Inserts a new meal with copies of the items and marks this one as used.
    @discardableResult
    public func log(at date: Date, mealType: MealType, in context: ModelContext, now: Date = .now) -> Meal {
        let meal = Meal(loggedAt: date, mealType: mealType, source: .saved, title: title)
        context.insert(meal)
        meal.append(orderedItems.map { $0.makeMealItem() })
        lastUsedAt = now
        return meal
    }
}

@Model
public final class SavedMealItem {
    public var id: UUID
    public var nameAr: String
    public var nameEn: String
    public var grams: Double
    public var kcalPer100: Double
    public var proteinPer100: Double
    public var carbsPer100: Double
    public var fatPer100: Double
    public var valueSourceRaw: String
    public var foodDbId: String?
    public var barcode: String?
    public var sortIndex: Int
    public var savedMeal: SavedMeal?

    public init(item: MealItem, sortIndex: Int) {
        id = UUID()
        nameAr = item.nameAr
        nameEn = item.nameEn
        grams = item.grams
        kcalPer100 = item.kcalPer100
        proteinPer100 = item.proteinPer100
        carbsPer100 = item.carbsPer100
        fatPer100 = item.fatPer100
        valueSourceRaw = item.valueSourceRaw
        foodDbId = item.foodDbId
        barcode = item.barcode
        self.sortIndex = sortIndex
    }

    public var per100: Macros {
        Macros(kcal: kcalPer100, protein: proteinPer100, carbs: carbsPer100, fat: fatPer100)
    }

    public var totals: Macros {
        let factor = grams / 100
        return Macros(kcal: kcalPer100 * factor, protein: proteinPer100 * factor,
                      carbs: carbsPer100 * factor, fat: fatPer100 * factor)
    }

    public func name(language: String) -> String {
        language == "ar" ? (nameAr.isEmpty ? nameEn : nameAr) : (nameEn.isEmpty ? nameAr : nameEn)
    }

    public func makeMealItem() -> MealItem {
        MealItem(nameAr: nameAr, nameEn: nameEn, grams: grams, per100: per100,
                 valueSource: ValueSource(rawValue: valueSourceRaw) ?? .user, foodDbId: foodDbId, barcode: barcode)
    }
}
