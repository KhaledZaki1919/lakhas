import Foundation

/// The JSON every analysis returns (photo, text, correction). Validated after decoding.
public struct MealAnalysis: Codable, Equatable, Sendable, AIValidatable {
    public struct Per100: Codable, Equatable, Sendable {
        public let kcal: Double
        public let protein: Double
        public let carbs: Double
        public let fat: Double
    }

    public struct Item: Codable, Equatable, Sendable {
        public let nameAr: String
        public let nameEn: String
        public let grams: Double
        public let confidence: Double
        public let per100: Per100
        public let foodDbId: String?
        public let leftoverGrams: Double?
    }

    public let items: [Item]
    public let notes: String?

    public static let schema: JSONValue = JSONSchema.object([
        "items": JSONSchema.array(JSONSchema.object([
            "nameAr": JSONSchema.string,
            "nameEn": JSONSchema.string,
            "grams": JSONSchema.number,
            "confidence": JSONSchema.number,
            "per100": JSONSchema.object([
                "kcal": JSONSchema.number,
                "protein": JSONSchema.number,
                "carbs": JSONSchema.number,
                "fat": JSONSchema.number,
            ]),
            "foodDbId": JSONSchema.nullable("string"),
            "leftoverGrams": JSONSchema.nullable("number"),
        ])),
        "notes": JSONSchema.nullable("string"),
    ])

    public func validate() throws {
        guard items.count <= 30 else { throw AIValidationError("too many items (max 30)") }
        for (index, item) in items.enumerated() {
            let label = "item \(index + 1)"
            guard !item.nameAr.trimmingCharacters(in: .whitespaces).isEmpty,
                  !item.nameEn.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw AIValidationError("\(label): names must not be empty")
            }
            guard item.grams > 0, item.grams <= 5000 else { throw AIValidationError("\(label): grams must be 1–5000") }
            guard (0...1).contains(item.confidence) else { throw AIValidationError("\(label): confidence must be 0–1") }
            let per100 = item.per100
            guard (0...900).contains(per100.kcal) else { throw AIValidationError("\(label): kcal per 100 g must be 0–900") }
            for value in [per100.protein, per100.carbs, per100.fat] where !(0...100).contains(value) {
                throw AIValidationError("\(label): macros per 100 g must be 0–100")
            }
            guard per100.protein + per100.carbs + per100.fat <= 101 else {
                throw AIValidationError("\(label): protein + carbs + fat can't exceed 100 g per 100 g")
            }
            if let leftover = item.leftoverGrams, !(0...(item.grams * 1.05)).contains(leftover) {
                throw AIValidationError("\(label): leftoverGrams must be between 0 and grams")
            }
        }
    }
}

/// An editable line on the review screen. Totals are always grams × per-100 g (§7.3).
public struct DraftItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var nameAr: String
    public var nameEn: String
    /// Grams eaten (served minus leftovers).
    public var grams: Double
    public var per100: Macros
    public var valueSource: ValueSource
    public var foodDbId: String?
    public var confidence: Double?
    /// Set when a leftover photo was analyzed.
    public var servedGrams: Double?
    public var leftoverGrams: Double?

    public init(id: UUID = UUID(), nameAr: String, nameEn: String, grams: Double, per100: Macros,
                valueSource: ValueSource, foodDbId: String? = nil, confidence: Double? = nil,
                servedGrams: Double? = nil, leftoverGrams: Double? = nil) {
        self.id = id
        self.nameAr = nameAr
        self.nameEn = nameEn
        self.grams = grams
        self.per100 = per100
        self.valueSource = valueSource
        self.foodDbId = foodDbId
        self.confidence = confidence
        self.servedGrams = servedGrams
        self.leftoverGrams = leftoverGrams
    }

    public init(food: FoodEntry, grams: Double) {
        self.init(nameAr: food.nameAr, nameEn: food.nameEn, grams: grams, per100: food.macros,
                  valueSource: .db, foodDbId: food.id)
    }

    public var totals: Macros {
        let factor = grams / 100
        return Macros(kcal: per100.kcal * factor, protein: per100.protein * factor,
                      carbs: per100.carbs * factor, fat: per100.fat * factor)
    }

    /// Low confidence gets a "check the amount" hint on the review screen.
    public var needsCheck: Bool { (confidence ?? 1) < 0.5 }

    public func name(language: String) -> String { language == "ar" ? nameAr : nameEn }

    public func makeMealItem() -> MealItem {
        MealItem(nameAr: nameAr, nameEn: nameEn, grams: grams, per100: per100,
                 valueSource: valueSource, foodDbId: foodDbId, confidence: confidence)
    }

    /// For the correction prompt: the analysis shape of this line.
    var analysisItem: MealAnalysis.Item {
        MealAnalysis.Item(
            nameAr: nameAr, nameEn: nameEn, grams: grams, confidence: confidence ?? 1,
            per100: .init(kcal: per100.kcal, protein: per100.protein, carbs: per100.carbs, fat: per100.fat),
            foodDbId: foodDbId, leftoverGrams: nil
        )
    }
}
