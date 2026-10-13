import Foundation
import SwiftData
import Testing
@testable import LakhasKit

struct ModelTests {
    private let gregorian: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Africa/Cairo") ?? .gmt
        return cal
    }()

    @Test func itemTotalsComeFromGramsTimesPer100() {
        let rice = MealItem(nameAr: "رز", nameEn: "Rice", grams: 150,
                            per100: Macros(kcal: 130, protein: 2.7, carbs: 28, fat: 0.3), valueSource: .db)
        #expect(rice.totals.kcal == 195)
        #expect(abs(rice.totals.carbs - 42) < 0.0001)
    }

    @Test func mealTotalsSumItemsInAStore() throws {
        let context = ModelContext(try LakhasStore.makeContainer(inMemory: true))
        let meal = Meal(mealType: .lunch, source: .manual)
        context.insert(meal)
        meal.append([
            MealItem(nameAr: "كشري", nameEn: "Koshary", grams: 450,
                     per100: Macros(kcal: 155, protein: 4.9, carbs: 24.9, fat: 4), valueSource: .ai),
            MealItem(nameAr: "سلطة", nameEn: "Salad", grams: 100,
                     per100: Macros(kcal: 20, protein: 1, carbs: 4, fat: 0), valueSource: .ai),
        ])
        try context.save()
        #expect(abs(meal.totals.kcal - 717.5) < 0.0001)
        #expect(meal.displayName(language: "en") == "Koshary, Salad")
        #expect(meal.displayName(language: "ar") == "كشري، سلطة")
    }

    @Test func dayKeyUsesTheLocalCalendar() {
        // 22:30 UTC on Oct 11 is Oct 12 01:30 in Cairo.
        let date = Date(timeIntervalSince1970: 1_760_221_800)
        #expect(DayKey.make(date, calendar: gregorian) == "2025-10-12")
    }

    @Test(arguments: [(7, MealType.breakfast), (13, .lunch), (17, .snack), (20, .dinner), (2, .snack)])
    func suggestsMealTypeByHour(hour: Int, expected: MealType) throws {
        let date = try #require(gregorian.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: hour)))
        #expect(MealType.suggested(for: date, calendar: gregorian) == expected)
    }

    @Test func overridesReplaceComputedTargets() {
        let profile = UserProfile(sex: .male, birthYear: 1996, heightCm: 180, weightKg: 80,
                                  activity: .active, goal: .lose, paceKgPerWeek: 0.5)
        let date = Date(timeIntervalSince1970: 1_791_763_200)   // 2026-10-12
        let computed = TargetsResolver.targets(profile: profile, override: nil, on: date)
        #expect(computed.calories == 2259)

        let override = GoalOverride()
        override.calories = 2000
        override.waterMl = 2500
        let resolved = TargetsResolver.targets(profile: profile, override: override, on: date)
        #expect(resolved.calories == 2000)
        #expect(resolved.waterMl == 2500)
        #expect(resolved.proteinG == computed.proteinG)
    }
}

struct AppFormatTests {
    @Test func arabicUsesWesternDigitsByDefault() {
        let text = AppFormat(language: "ar", digits: .western).number(1234)
        #expect(text.filter(\.isNumber) == "1234")
    }

    @Test func arabicCanUseEasternDigits() {
        let text = AppFormat(language: "ar", digits: .eastern).number(1234)
        #expect(text.filter(\.isNumber) == "١٢٣٤")
    }

    @Test func englishGroupsThousands() {
        #expect(AppFormat(language: "en", digits: .western).number(2259) == "2,259")
    }
}
