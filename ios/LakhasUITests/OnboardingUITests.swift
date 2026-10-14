import XCTest

/// UI tests (PROJECT_PROMPT.md §10): onboarding, then logging a meal on Today.
/// `-uiTesting` gives an in-memory store and default AI settings (no key).
final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(language: String, stubAI: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "ar" ? "ar_EG" : "en_US"]
        if stubAI { app.launchArguments.append("-uiTestingStubAI") }
        app.launch()
        return app
    }

    @MainActor
    private func openLogSheetAfterOnboarding(_ app: XCUIApplication) {
        completeOnboarding(app)
        finishAfterSummary(app)
        app.buttons["ax.tab.plus"].tap()
    }

    @MainActor
    func testTextAnalysisReviewAndSave() throws {
        let app = launch(language: "en", stubAI: true)
        openLogSheetAfterOnboarding(app)
        element(app, "ax.log.text").tap()
        let input = app.textFields["ax.text.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("a plate of koshary")
        app.buttons["ax.text.analyze"].tap()

        XCTAssertTrue(element(app, "ax.review.item").waitForExistence(timeout: 10))
        // 450 g × 156 kcal/100 g from the bundled DB (confident match)
        XCTAssertTrue(element(app, "ax.review.total").label.contains("702"), element(app, "ax.review.total").label)
        app.buttons["ax.review.save"].tap()
        let meal = element(app, "ax.today.meal")
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        XCTAssertTrue(meal.label.contains("Koshary"))
    }

    @MainActor
    func testPhotoAnalysisWithCorrection() throws {
        let app = launch(language: "en", stubAI: true)
        openLogSheetAfterOnboarding(app)
        element(app, "ax.log.photo").tap()
        let sample = element(app, "ax.photo.sample")
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        sample.tap()
        app.buttons["ax.photo.analyze"].tap()
        XCTAssertTrue(element(app, "ax.review.item").waitForExistence(timeout: 10))

        // A vertical-axis TextField is exposed as a text view, so match by identifier only.
        let correction = element(app, "ax.review.correction")
        XCTAssertTrue(correction.waitForExistence(timeout: 5))
        correction.tap()
        correction.typeText("it was a smaller plate")
        let correct = app.buttons["ax.review.correct"]
        if !correct.isHittable { app.swipeUp() }        // keyboard and totals bar can cover it
        correct.tap()
        // corrected to 300 g → 468 kcal
        let total = element(app, "ax.review.total")
        let predicate = NSPredicate(format: "label CONTAINS %@", "468")
        expectation(for: predicate, evaluatedWith: total)
        waitForExpectations(timeout: 10)
        app.buttons["ax.review.save"].tap()
        XCTAssertTrue(element(app, "ax.today.meal").waitForExistence(timeout: 5))
    }

    @MainActor
    func testPlateBuilderWithoutAKey() throws {
        let app = launch(language: "ar")
        openLogSheetAfterOnboarding(app)
        element(app, "ax.log.plate").tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("كشري")
        let result = element(app, "ax.search.result")
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        let add = app.buttons["ax.portion.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(element(app, "ax.review.item").waitForExistence(timeout: 5))
        app.buttons["ax.review.save"].tap()
        XCTAssertTrue(element(app, "ax.today.meal").waitForExistence(timeout: 5))
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
