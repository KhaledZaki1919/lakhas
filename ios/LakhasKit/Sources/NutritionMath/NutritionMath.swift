import Foundation

// Daily targets exactly as specified in PROJECT_PROMPT.md §6 (ADR-011 for pace and the
// BMI ≥ 30 reference weight). The backend mirrors these formulas in
// backend/src/lib/nutrition.ts; both are tested against shared/test-vectors/nutrition.json.

public enum Sex: String, Codable, Sendable, CaseIterable {
    case male, female
}

public enum ActivityLevel: String, Codable, Sendable, CaseIterable {
    case sedentary, light, active, veryActive

    /// TDEE multiplier.
    public var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .active: 1.55
        case .veryActive: 1.725
        }
    }

    /// "Active" and above get the +10% water bonus.
    public var isActiveOrMore: Bool { self == .active || self == .veryActive }
}

public enum Goal: String, Codable, Sendable, CaseIterable {
    case lose, maintain, gain

    /// Protein in g per kg of (reference) body weight.
    public var proteinPerKg: Double {
        switch self {
        case .lose: 2.0
        case .maintain: 1.6
        case .gain: 1.8
        }
    }

    /// Allowed paces in kg/week (ADR-011).
    public var paces: [Double] {
        switch self {
        case .lose: [0.25, 0.5, 0.75, 1.0]
        case .maintain: [0]
        case .gain: [0.25, 0.5]
        }
    }
}

public enum BMICategory: String, Codable, Sendable {
    case underweight, normal, overweight, obese

    public init(bmi: Double) {
        switch bmi {
        case ..<18.5: self = .underweight
        case ..<25: self = .normal
        case ..<30: self = .overweight
        default: self = .obese
        }
    }
}

public struct BodyProfile: Sendable, Equatable {
    public var sex: Sex
    public var age: Int
    public var heightCm: Double
    public var weightKg: Double
    public var activity: ActivityLevel
    public var goal: Goal
    /// kg/week; ignored for `.maintain`.
    public var paceKgPerWeek: Double
    /// Optional goal weight (My Goals); replaces the BMI-25 reference weight for protein.
    public var goalWeightKg: Double?

    public init(
        sex: Sex, age: Int, heightCm: Double, weightKg: Double,
        activity: ActivityLevel, goal: Goal, paceKgPerWeek: Double, goalWeightKg: Double? = nil
    ) {
        self.sex = sex
        self.age = age
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activity = activity
        self.goal = goal
        self.paceKgPerWeek = paceKgPerWeek
        self.goalWeightKg = goalWeightKg
    }
}

public struct DailyTargets: Sendable, Equatable {
    public let bmr: Double
    public let tdee: Double
    /// Rounded kcal/day after goal adjustment and floor.
    public let calories: Int
    public let proteinG: Int
    public let carbsG: Int
    public let fatG: Int
    public let waterMl: Int
    /// True when the safety floor raised the calorie target (show a gentle note).
    public let floorApplied: Bool
    /// True when fat had to drop below 27% (to as low as 20%) to keep carbs non-negative.
    public let fatReduced: Bool
}

public struct BodySummary: Sendable, Equatable {
    public let bmi: Double
    public let category: BMICategory
    public let healthyMinKg: Double
    public let healthyMaxKg: Double
}

public enum NutritionMath {
    public static let fatShare = 0.27
    public static let minimumFatShare = 0.20

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

    public static func bmi(weightKg: Double, heightCm: Double) -> Double {
        let meters = heightCm / 100
        return weightKg / (meters * meters)
    }

    /// BMI category and the healthy weight range (BMI 18.5–24.9) for this height.
    public static func bodySummary(weightKg: Double, heightCm: Double) -> BodySummary {
        let value = bmi(weightKg: weightKg, heightCm: heightCm)
        let squared = (heightCm / 100) * (heightCm / 100)
        return BodySummary(
            bmi: value,
            category: BMICategory(bmi: value),
            healthyMinKg: 18.5 * squared,
            healthyMaxKg: 24.9 * squared
        )
    }

    /// ±250 kcal/day per 0.25 kg/week (lose subtracts, gain adds).
    public static func goalAdjustment(goal: Goal, paceKgPerWeek: Double) -> Double {
        let magnitude = paceKgPerWeek / 0.25 * 250
        switch goal {
        case .lose: return -magnitude
        case .maintain: return 0
        case .gain: return magnitude
        }
    }

    /// Never below max(BMR, 1200 kcal for women / 1500 kcal for men).
    public static func calorieFloor(sex: Sex, bmr: Double) -> Double {
        max(bmr, sex == .female ? 1200 : 1500)
    }

    /// Weight used for protein: actual weight, or when BMI ≥ 30 the goal weight if set,
    /// otherwise the weight at BMI 25 for this height (ADR-011).
    public static func proteinReferenceWeight(_ profile: BodyProfile) -> Double {
        guard bmi(weightKg: profile.weightKg, heightCm: profile.heightCm) >= 30 else { return profile.weightKg }
        if let goal = profile.goalWeightKg { return goal }
        let meters = profile.heightCm / 100
        return 25 * meters * meters
    }

    /// 35 ml × kg, +10% if active or more, rounded to the nearest 250 ml.
    public static func waterMl(weightKg: Double, activity: ActivityLevel) -> Int {
        var ml = 35 * weightKg
        if activity.isActiveOrMore { ml *= 1.1 }
        return Int((ml / 250).rounded()) * 250
    }

    public static func targets(for profile: BodyProfile) -> DailyTargets {
        let bmr = bmr(sex: profile.sex, weightKg: profile.weightKg, heightCm: profile.heightCm, age: profile.age)
        let tdee = tdee(bmr: bmr, activity: profile.activity)
        let pace = profile.goal == .maintain ? 0 : profile.paceKgPerWeek
        let adjusted = tdee + goalAdjustment(goal: profile.goal, paceKgPerWeek: pace)
        let floor = calorieFloor(sex: profile.sex, bmr: bmr)
        let calories = max(adjusted, floor)

        let macros = macroSplit(
            calories: calories,
            proteinG: profile.goal.proteinPerKg * proteinReferenceWeight(profile)
        )
        return DailyTargets(
            bmr: bmr,
            tdee: tdee,
            calories: Int(calories.rounded()),
            proteinG: Int(macros.protein.rounded()),
            carbsG: Int(macros.carbs.rounded()),
            fatG: Int(macros.fat.rounded()),
            waterMl: waterMl(weightKg: profile.weightKg, activity: profile.activity),
            floorApplied: adjusted < floor,
            fatReduced: macros.fatReduced
        )
    }

    /// Fat 27% of calories; carbs get the rest. If carbs would go negative, fat drops toward
    /// 20% first; carbs never go below zero.
    struct MacroSplit: Equatable {
        let protein: Double
        let carbs: Double
        let fat: Double
        let fatReduced: Bool
    }

    static func macroSplit(calories: Double, proteinG: Double) -> MacroSplit {
        let proteinKcal = proteinG * 4
        var fatKcal = fatShare * calories
        var fatReduced = false
        if calories - proteinKcal - fatKcal < 0 {
            fatKcal = max(minimumFatShare * calories, calories - proteinKcal)
            fatReduced = true
        }
        let carbsKcal = max(0, calories - proteinKcal - fatKcal)
        return MacroSplit(protein: proteinG, carbs: carbsKcal / 4, fat: fatKcal / 9, fatReduced: fatReduced)
    }
}
