import Testing
@testable import NutritionMath

struct NutritionMathTests {
    @Test func bmrMale() {
        // 10·80 + 6.25·180 − 5·30 + 5 = 1780
        #expect(NutritionMath.bmr(sex: .male, weightKg: 80, heightCm: 180, age: 30) == 1780)
    }

    @Test func bmrFemale() {
        // 10·60 + 6.25·165 − 5·28 − 161 = 1330.25
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
        #expect(NutritionMath.tdee(bmr: 1000, activity: level) == 1000 * factor)
    }
}
