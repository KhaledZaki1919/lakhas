import Foundation

/// What the model returns for a recipe import (link text, pasted text or screenshots).
/// Validated after decoding; amounts are for the whole recipe.
public struct RecipeExtraction: Codable, Equatable, Sendable, AIValidatable {
    public struct Ingredient: Codable, Equatable, Sendable {
        public let nameAr: String
        public let nameEn: String
        /// As written in the source ("2 cups"), or null.
        public let quantity: String?
        public let grams: Double
        public let per100: MealAnalysis.Per100
        public let foodDbId: String?
        public let confidence: Double
    }

    /// false when the input has no recipe and no identifiable dish.
    public let found: Bool
    public let titleAr: String
    public let titleEn: String
    public let servings: Double
    public let ingredients: [Ingredient]
    /// In the app language at import.
    public let steps: [String]
    /// The model filled in ingredients or amounts the source didn't give.
    public let estimated: Bool
    public let notes: String?

    public static let schema: JSONValue = JSONSchema.object([
        "found": JSONSchema.boolean,
        "titleAr": JSONSchema.string,
        "titleEn": JSONSchema.string,
        "servings": JSONSchema.number,
        "ingredients": JSONSchema.array(JSONSchema.object([
            "nameAr": JSONSchema.string,
            "nameEn": JSONSchema.string,
            "quantity": JSONSchema.nullable("string"),
            "grams": JSONSchema.number,
            "per100": JSONSchema.object([
                "kcal": JSONSchema.number,
                "protein": JSONSchema.number,
                "carbs": JSONSchema.number,
                "fat": JSONSchema.number,
            ]),
            "foodDbId": JSONSchema.nullable("string"),
            "confidence": JSONSchema.number,
        ])),
        "steps": JSONSchema.array(JSONSchema.string),
        "estimated": JSONSchema.boolean,
        "notes": JSONSchema.nullable("string"),
    ])

    public func validate() throws {
        guard found else { return }
        guard !titleAr.trimmingCharacters(in: .whitespaces).isEmpty || !titleEn.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AIValidationError("a recipe needs a title")
        }
        guard (1...50).contains(servings) else { throw AIValidationError("servings must be 1–50") }
        guard (1...60).contains(ingredients.count) else { throw AIValidationError("a recipe needs 1–60 ingredients") }
        guard steps.count <= 80 else { throw AIValidationError("too many steps (max 80)") }
        for (index, item) in ingredients.enumerated() {
            let label = "ingredient \(index + 1)"
            guard !item.nameAr.trimmingCharacters(in: .whitespaces).isEmpty,
                  !item.nameEn.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw AIValidationError("\(label): names must not be empty")
            }
            guard item.grams > 0, item.grams <= 10000 else { throw AIValidationError("\(label): grams must be above 0 and at most 10000") }
            guard (0...1).contains(item.confidence) else { throw AIValidationError("\(label): confidence must be 0–1") }
            let per100 = item.per100
            guard (0...900).contains(per100.kcal) else { throw AIValidationError("\(label): kcal per 100 g must be 0–900") }
            for value in [per100.protein, per100.carbs, per100.fat] where !(0...100).contains(value) {
                throw AIValidationError("\(label): macros per 100 g must be 0–100")
            }
            guard per100.protein + per100.carbs + per100.fat <= 101 else {
                throw AIValidationError("\(label): protein + carbs + fat can't exceed 100 g per 100 g")
            }
        }
    }

    /// Editable lines. Confident matches take the bundled DB's per-100 g values (as for meals).
    func draftItems(database: FoodDatabase) -> [DraftItem] {
        ingredients.map { item in
            let match = item.foodDbId.flatMap(database.food(id:))
            let useDB = match != nil && item.confidence >= MealAnalyzer.dbOverrideConfidence
            let per100 = useDB
                ? (match?.macros ?? .zero)
                : Macros(kcal: item.per100.kcal, protein: item.per100.protein, carbs: item.per100.carbs, fat: item.per100.fat)
            let quantity = item.quantity?.trimmingCharacters(in: .whitespaces)
            return DraftItem(nameAr: item.nameAr.trimmingCharacters(in: .whitespaces),
                             nameEn: item.nameEn.trimmingCharacters(in: .whitespaces),
                             grams: (item.grams * 10).rounded() / 10, per100: per100, valueSource: useDB ? .db : .ai,
                             foodDbId: match?.id, confidence: item.confidence,
                             measure: quantity?.isEmpty == false ? quantity : nil)
        }
    }
}
