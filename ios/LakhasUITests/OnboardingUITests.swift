import XCTest

/// UI tests (PROJECT_PROMPT.md §10): onboarding, then logging a meal on Today.
/// `-uiTesting` gives an in-memory store and default AI settings (no key).
final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "ar" ? "ar_EG" : "en_US"]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @MainActor
    private func completeOnboarding(_ app: XCUIApplication) {
        let next = app.buttons["ax.onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()                                        // welcome
        app.buttons["ax.onboarding.option.male"].tap()
        next.tap()                                        // sex
        next.tap()                                        // age (default 30)
        next.tap()                                        // height (default 170 cm)
        next.tap()                                        // weight (default 70 kg)
        app.buttons["ax.onboarding.option.active"].tap()
        next.tap()                                        // activity
        app.buttons["ax.onboarding.option.lose"].tap()    // pace defaults to 0.5 kg/week
        next.tap()                                        // goal
    }

    /// Summary → optional AI step (skipped) → Today.
    @MainActor
    private func finishAfterSummary(_ app: XCUIApplication) {
        app.buttons["ax.onboarding.next"].tap()
        XCTAssertTrue(app.buttons["ax.onboarding.aiSetup"].waitForExistence(timeout: 5))
        app.buttons["ax.onboarding.finish"].tap()
    }

    @MainActor
    func testPhotoLoggingWithoutAKeyShowsTheNoKeyScreen() throws {
        let app = launch(language: "en")
        completeOnboarding(app)
        finishAfterSummary(app)

        app.buttons["ax.tab.plus"].tap()
        let photo = element(app, "ax.log.photo")
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.tap()
        XCTAssertTrue(element(app, "ax.nokey.title").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "ax.nokey.open").exists)
    }

    @MainActor
    func testOnboardingShowsComputedTargetsAndOpensToday() throws {
        let app = launch(language: "en")
        completeOnboarding(app)

        // Male, 30 y, 170 cm, 70 kg, active, lose 0.5 kg/week:
        // BMR 1617.5 × 1.55 = 2507.1 − 500 = 2007 kcal.
        let calories = element(app, "ax.onboarding.summary.calories")
        XCTAssertTrue(calories.waitForExistence(timeout: 5))
        XCTAssertTrue(calories.label.contains("2,007"), "summary showed \(calories.label)")

        finishAfterSummary(app)
        XCTAssertTrue(element(app, "ax.today.ring").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ax.tab.plus"].exists)
    }

    @MainActor
    func testOnboardingWorksInArabic() throws {
        let app = launch(language: "ar")
        completeOnboarding(app)
        let calories = element(app, "ax.onboarding.summary.calories")
        XCTAssertTrue(calories.waitForExistence(timeout: 5))
        // Western digits by default in Arabic.
        XCTAssertTrue(calories.label.contains("2,007") || calories.label.contains("2٬007"), "summary showed \(calories.label)")
        finishAfterSummary(app)
        XCTAssertTrue(element(app, "ax.today.ring").waitForExistence(timeout: 5))
    }

    @MainActor
    func testQuickAddLogsAMealOnToday() throws {
        let app = launch(language: "en")
        completeOnboarding(app)
        finishAfterSummary(app)

        app.buttons["ax.tab.plus"].tap()
        let quickAdd = element(app, "ax.log.quickAdd")
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 5))
        quickAdd.tap()

        let name = app.textFields["ax.quickadd.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Koshary")
        let kcal = app.textFields["ax.quickadd.kcal"]
        kcal.tap()
        kcal.typeText("650")
        app.buttons["ax.quickadd.save"].tap()

        let meal = element(app, "ax.today.meal")
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        XCTAssertTrue(meal.label.contains("Koshary"))
    }
}
