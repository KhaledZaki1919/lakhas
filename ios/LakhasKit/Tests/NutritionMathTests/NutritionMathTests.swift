import Foundation
import Testing
@testable import NutritionMath

/// shared/test-vectors/nutrition.json — the same cases the backend mirror is tested against.
private struct Vectors: Decodable {
    struct Profile: Decodable {
        let sex: Sex
        let age: Int
        let heightCm: Double
        let weightKg: Double
        let activity: ActivityLevel
        let goal: Goal
        let paceKgPerWeek: Double
        let goalWeightKg: Double?
    }

    struct Expected: Decodable {
        let bmr: Double
        let tdee: Double
        let calories: Int
        let proteinG: Int
        let carbsG: Int
        let fatG: Int
        let waterMl: Int
        let floorApplied: Bool
        let fatReduced: Bool
        let bmiCategory: BMICategory
        let healthyMinKg: Double
        let healthyMaxKg: Double
    }

    struct Case: Decodable {
        let name: String
        let profile: Profile
        let expected: Expected
    }

    let cases: [Case]

    static func load() throws -> [Case] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/test-vectors/nutrition.json")
        return try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url)).cases
    }
}

private func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
private func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }

struct NutritionMathTests {
    @Test func bmrMale() {
        #expect(NutritionMath.bmr(sex: .male, weightKg: 80, heightCm: 180, age: 30) == 1780)
    }

    @Test func bmrFemale() {
        #expect(NutritionMath.bmr(sex: .female, weightKg: 60, heightCm: 165, age: 28) == 1330.25)
    }

    @Test(arguments: [
        (ActivityLevel.sedentary, 1.2),
        (.light, 1.375),
        (.active, 1.55),
        (.veryActive, 1.725),
    ])
    func activityFactors(level: ActivityLevel, factor: Double) {
        #expect(level.factor == factor)
    }

    @Test func goalAdjustmentIs250PerQuarterKilo() {
        #expect(NutritionMath.goalAdjustment(goal: .lose, paceKgPerWeek: 0.75) == -750)
        #expect(NutritionMath.goalAdjustment(goal: .gain, paceKgPerWeek: 0.5) == 500)
        #expect(NutritionMath.goalAdjustment(goal: .maintain, paceKgPerWeek: 1) == 0)
    }

    @Test func pacesFollowADR011() {
        #expect(Goal.lose.paces == [0.25, 0.5, 0.75, 1.0])
        #expect(Goal.gain.paces == [0.25, 0.5])
        #expect(Goal.maintain.paces == [0])
    }

    @Test func matchesSharedVectors() throws {
        for vector in try Vectors.load() {
            let input = vector.profile
            let targets = NutritionMath.targets(for: BodyProfile(
                sex: input.sex, age: input.age, heightCm: input.heightCm, weightKg: input.weightKg,
                activity: input.activity, goal: input.goal, paceKgPerWeek: input.paceKgPerWeek,
                goalWeightKg: input.goalWeightKg
            ))
            let expected = vector.expected
            #expect(round2(targets.bmr) == expected.bmr, "\(vector.name)")
            #expect(round2(targets.tdee) == expected.tdee, "\(vector.name)")
            #expect(targets.calories == expected.calories, "\(vector.name)")
            #expect(targets.proteinG == expected.proteinG, "\(vector.name)")
            #expect(targets.carbsG == expected.carbsG, "\(vector.name)")
            #expect(targets.fatG == expected.fatG, "\(vector.name)")
            #expect(targets.waterMl == expected.waterMl, "\(vector.name)")
            #expect(targets.floorApplied == expected.floorApplied, "\(vector.name)")
            #expect(targets.fatReduced == expected.fatReduced, "\(vector.name)")

            let summary = NutritionMath.bodySummary(weightKg: input.weightKg, heightCm: input.heightCm)
            #expect(summary.category == expected.bmiCategory, "\(vector.name)")
            #expect(round1(summary.healthyMinKg) == expected.healthyMinKg, "\(vector.name)")
            #expect(round1(summary.healthyMaxKg) == expected.healthyMaxKg, "\(vector.name)")
        }
    }

    @Test func carbsNeverNegative() {
        let targets = NutritionMath.targets(for: BodyProfile(
            sex: .female, age: 60, heightCm: 150, weightKg: 120,
            activity: .sedentary, goal: .lose, paceKgPerWeek: 1, goalWeightKg: 200
        ))
        #expect(targets.carbsG == 0)
        #expect(targets.fatReduced)
    }
}
