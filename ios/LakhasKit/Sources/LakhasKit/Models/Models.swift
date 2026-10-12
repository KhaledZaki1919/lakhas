import Foundation
import NutritionMath
import SwiftData

// SwiftData models (docs/architecture.md §3). Enums are stored as raw strings so future
// cases and migrations stay simple. Logs keep snapshots of names and per-100g values
// (ADR-010): editing a food never changes history.

public enum MealType: String, Codable, Sendable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    public var id: String { rawValue }

    /// Default meal type by local time of day.
    public static func suggested(for date: Date, calendar: Calendar = .current) -> MealType {
        switch calendar.component(.hour, from: date) {
        case 5..<11: .breakfast
        case 11..<16: .lunch
        case 18..<23: .dinner
        default: .snack
        }
    }
}

public enum LogSource: String, Codable, Sendable {
    case photo, text, barcode, plate, saved, explore, recipe, manual
}

public enum ValueSource: String, Codable, Sendable {
    case db, ai, product, user
}

/// kcal and macro grams.
public struct Macros: Sendable, Equatable {
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double

    public static let zero = Macros(kcal: 0, protein: 0, carbs: 0, fat: 0)

    public init(kcal: Double, protein: Double, carbs: Double, fat: Double) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    public static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(kcal: lhs.kcal + rhs.kcal, protein: lhs.protein + rhs.protein,
               carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat)
    }
}

@Model
public final class UserProfile {
    public var sexRaw: String
    public var birthYear: Int
    public var heightCm: Double
    public var weightKg: Double
    public var activityRaw: String
    public var goalRaw: String
    public var paceKgPerWeek: Double
    public var onboardedAt: Date

    public init(sex: Sex, birthYear: Int, heightCm: Double, weightKg: Double,
                activity: ActivityLevel, goal: Goal, paceKgPerWeek: Double, onboardedAt: Date = .now) {
        sexRaw = sex.rawValue
        self.birthYear = birthYear
        self.heightCm = heightCm
        self.weightKg = weightKg
        activityRaw = activity.rawValue
        goalRaw = goal.rawValue
        self.paceKgPerWeek = paceKgPerWeek
        self.onboardedAt = onboardedAt
    }

    public var sex: Sex { Sex(rawValue: sexRaw) ?? .male }
    public var activity: ActivityLevel { ActivityLevel(rawValue: activityRaw) ?? .sedentary }
    public var goal: Goal { Goal(rawValue: goalRaw) ?? .maintain }

    public func age(on date: Date = .now, calendar: Calendar = .current) -> Int {
        max(0, calendar.component(.year, from: date) - birthYear)
    }

    public func bodyProfile(goalWeightKg: Double? = nil, on date: Date = .now) -> BodyProfile {
        BodyProfile(sex: sex, age: age(on: date), heightCm: heightCm, weightKg: weightKg,
                    activity: activity, goal: goal, paceKgPerWeek: paceKgPerWeek, goalWeightKg: goalWeightKg)
    }
}

/// "My Goals": any non-nil field overrides the computed target.
@Model
public final class GoalOverride {
    public var calories: Int?
    public var proteinG: Int?
    public var carbsG: Int?
    public var fatG: Int?
    public var waterMl: Int?
    public var goalWeightKg: Double?

    public init() {}
}

@Model
public final class Meal {
    @Attribute(.unique) public var id: UUID
    /// Local calendar day "yyyy-MM-dd" at log time.
    public var dayKey: String
    public var loggedAt: Date
    public var mealTypeRaw: String
    public var sourceRaw: String
    public var sortIndex: Int
    public var title: String?
    @Relationship(deleteRule: .cascade, inverse: \MealItem.meal) public var items: [MealItem] = []

    public init(id: UUID = UUID(), loggedAt: Date = .now, mealType: MealType, source: LogSource,
                sortIndex: Int = 0, title: String? = nil, calendar: Calendar = .current) {
        self.id = id
        self.loggedAt = loggedAt
        dayKey = DayKey.make(loggedAt, calendar: calendar)
        mealTypeRaw = mealType.rawValue
        sourceRaw = source.rawValue
        self.sortIndex = sortIndex
        self.title = title
    }

    public var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    public var source: LogSource { LogSource(rawValue: sourceRaw) ?? .manual }

    public var totals: Macros { items.reduce(.zero) { $0 + $1.totals } }

    /// Display name in the given language: the title, else the item names joined.
    public func displayName(language: String) -> String {
        if let title, !title.isEmpty { return title }
        let separator = language == "ar" ? "، " : ", "
        return items.map { $0.name(language: language) }.joined(separator: separator)
    }
}

@Model
public final class MealItem {
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
    public var confidence: Double?
    public var meal: Meal?

    public init(id: UUID = UUID(), nameAr: String, nameEn: String, grams: Double, per100: Macros,
                valueSource: ValueSource, foodDbId: String? = nil, barcode: String? = nil, confidence: Double? = nil) {
        self.id = id
        self.nameAr = nameAr
        self.nameEn = nameEn
        self.grams = grams
        kcalPer100 = per100.kcal
        proteinPer100 = per100.protein
        carbsPer100 = per100.carbs
        fatPer100 = per100.fat
        valueSourceRaw = valueSource.rawValue
        self.foodDbId = foodDbId
        self.barcode = barcode
        self.confidence = confidence
    }

    public var per100: Macros {
        Macros(kcal: kcalPer100, protein: proteinPer100, carbs: carbsPer100, fat: fatPer100)
    }

    /// Totals are always computed from grams × per-100g (PROJECT_PROMPT.md §7.3).
    public var totals: Macros {
        let factor = grams / 100
        return Macros(kcal: kcalPer100 * factor, protein: proteinPer100 * factor,
                      carbs: carbsPer100 * factor, fat: fatPer100 * factor)
    }

    public func name(language: String) -> String {
        language == "ar" ? (nameAr.isEmpty ? nameEn : nameAr) : (nameEn.isEmpty ? nameAr : nameEn)
    }

    public func copy() -> MealItem {
        MealItem(nameAr: nameAr, nameEn: nameEn, grams: grams, per100: per100,
                 valueSource: ValueSource(rawValue: valueSourceRaw) ?? .user,
                 foodDbId: foodDbId, barcode: barcode, confidence: confidence)
    }
}

public enum DayKey {
    public static func make(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
