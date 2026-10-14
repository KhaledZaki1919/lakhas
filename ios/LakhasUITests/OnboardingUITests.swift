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

        let correction = element(app, "ax.review.correction")
        scrollTo(correction, in: app)
        correction.tap()
        correction.typeText("it was a smaller plate\n")   // Go submits the correction
        // corrected to 300 g → 468 kcal
        let total = element(app, "ax.review.total")
        let corrected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "468"), object: total)
        XCTAssertEqual(XCTWaiter().wait(for: [corrected], timeout: 10), .completed,
                       "total \(total.label)\n\(app.debugDescription)")
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
    private func lookUpBarcode(_ code: String, in app: XCUIApplication) {
        element(app, "ax.log.barcode").tap()
        let field = app.textFields["ax.barcode.code"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(code)
        app.buttons["ax.barcode.lookup"].tap()
    }

    /// Product card → add the default amount → review total → save to Today.
    @MainActor
    private func addProductAndSave(_ app: XCUIApplication, expectedKcal: String, name: String) {
        XCTAssertTrue(element(app, "ax.barcode.product").waitForExistence(timeout: 10), app.debugDescription)
        let add = element(app, "ax.barcode.add")
        scrollUntilHittable(add, in: app)
        add.tap()
        XCTAssertTrue(element(app, "ax.review.item").waitForExistence(timeout: 5))
        let total = element(app, "ax.review.total")
        XCTAssertTrue(total.label.contains(expectedKcal), "total \(total.label)")
        app.buttons["ax.review.save"].tap()
        let meal = element(app, "ax.today.meal")
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        XCTAssertTrue(meal.label.contains(name), meal.label)
    }

    @MainActor
    func testBarcodeLookupLogsAProductWithoutAKey() throws {
        let app = launch(language: "en")
        openLogSheetAfterOnboarding(app)
        lookUpBarcode("6221000000010", in: app)   // stubbed Open Food Facts product
        // 30 g serving × 480 kcal/100 g
        addProductAndSave(app, expectedKcal: "144", name: "Test Crackers")
    }

    @MainActor
    func testUnknownBarcodeIsAddedFromLabelPhotos() throws {
        let app = launch(language: "en", stubAI: true)
        openLogSheetAfterOnboarding(app)
        lookUpBarcode("6221000000027", in: app)
        let addProduct = element(app, "ax.barcode.addProduct")
        XCTAssertTrue(addProduct.waitForExistence(timeout: 10), app.debugDescription)
        scrollUntilHittable(addProduct, in: app)
        addProduct.tap()

        let sample = element(app, "ax.product.sample")
        scrollUntilHittable(sample, in: app)
        sample.tap()
        let read = element(app, "ax.product.read")
        scrollUntilHittable(read, in: app)
        read.tap()
        // The stub's label fills the form, which enables Save.
        let save = app.buttons["ax.product.save"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: save)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 10), .completed, app.debugDescription)
        save.tap()
        // 25 g serving × 400 kcal/100 g
        addProductAndSave(app, expectedKcal: "100", name: "Label Biscuits")
    }

    /// Drags from low on the screen (inside the sheet, even at medium height) until the target can be tapped.
    @MainActor
    private func scrollUntilHittable(_ target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !(target.exists && target.isHittable) {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        }
        XCTAssertTrue(target.exists && target.isHittable, app.debugDescription)
    }

    /// Lists load rows lazily, so rows below the fold only exist after scrolling.
    @MainActor
    private func scrollTo(_ target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !target.exists { app.swipeUp() }
        XCTAssertTrue(target.waitForExistence(timeout: 5))
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
