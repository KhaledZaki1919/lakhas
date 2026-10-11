import Foundation

// Phase 1 holds only the input types and BMR/TDEE. The full target calculation
// (goal adjustment, floor, macros, water) is implemented in Phase 3 per PROJECT_PROMPT.md §6.

public enum Sex: String, Codable, Sendable, CaseIterable {
    case male, female
}

public enum ActivityLevel: String, Codable, Sendable, CaseIterable {
    case sedentary, light, active, veryActive

    /// TDEE multiplier (PROJECT_PROMPT.md §6).
    public var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .active: 1.55
        case .veryActive: 1.725
        }
    }
}

public enum Goal: String, Codable, Sendable, CaseIterable {
    case lose, maintain, gain
}

public enum NutritionMath {
    /// Mifflin-St Jeor basal metabolic rate in kcal/day.
    public static func bmr(sex: Sex, weightKg: Double, heightCm: Double, age: Int) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        switch sex {
        case .male: return base + 5
        case .female: return base - 161
        }
    }

    /// Total daily energy expenditure in kcal/day.
    public static func tdee(bmr: Double, activity: ActivityLevel) -> Double {
        bmr * activity.factor
    }
}
