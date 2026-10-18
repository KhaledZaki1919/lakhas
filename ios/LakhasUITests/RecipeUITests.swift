import XCTest

/// Recipe import (Phase 7). `-uiTesting` answers recipe pages from `UITestingAIProvider.recipePages`
/// (any other link reads like a login wall) and `-uiTestingStubAI` returns a 2-serving recipe of
/// 1,246.8 kcal, so one serving is 623 kcal.
extension OnboardingUITests {
    @MainActor
    private func openRecipeImport(_ app: XCUIApplication) {
        completeOnboarding(app)
        finishAfterSummary(app)
        app.buttons["ax.tab.recipes"].tap()
        let importButton = app.buttons["ax.recipes.import"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5), app.debugDescription)
        importButton.tap()
    }

    @MainActor
    private func importLink(_ link: String, in app: XCUIApplication) {
        let field = app.textFields["ax.recipe.link"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        field.typeText(link)
        app.buttons["ax.recipe.start"].tap()
    }

    @MainActor
    private func waitForPerServing(_ kcal: String, in app: XCUIApplication) {
        let perServing = element(app, "ax.recipe.perServing")
        XCTAssertTrue(perServing.waitForExistence(timeout: 10), app.debugDescription)
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", kcal), object: perServing)
        XCTAssertEqual(XCTWaiter().wait(for: [matches], timeout: 5), .completed, perServing.label)
    }

    @MainActor
    func testRecipeLinkWithoutACaptionFallsBackToPastedTextAndLogsAServing() throws {
        let app = launch(language: "en", stubAI: true)
        openRecipeImport(app)
        importLink("https://www.instagram.com/reel/Cabc123/", in: app)

        let paste = element(app, "ax.recipe.fallback.text")
        XCTAssertTrue(paste.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element(app, "ax.recipe.fallback.screenshot").exists)
        paste.tap()
        let caption = element(app, "ax.recipe.caption")
        XCTAssertTrue(caption.waitForExistence(timeout: 5))
        caption.tap()
        caption.typeText("Lentil rice: 1 cup rice, half a cup lentils, 2 tbsp oil")
        app.buttons["ax.recipe.start"].tap()
        waitForPerServing("623", in: app)

        let log = element(app, "ax.recipe.log")
        scrollUntilHittable(log, in: app)
        log.tap()
        XCTAssertTrue(element(app, "ax.recipe.logged").waitForExistence(timeout: 5))

        // Close the sheet: the recipe is in My Recipes and the serving is on Today.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let cancel = app.buttons["ax.recipe.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), app.debugDescription)
        cancel.tap()
        XCTAssertTrue(element(app, "ax.recipes.row").waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["ax.tab.today"].tap()
        let meal = element(app, "ax.today.meal")
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        XCTAssertTrue(meal.label.contains("Lentil rice"), meal.label)
        XCTAssertTrue(meal.label.contains("623"), meal.label)
    }

    @MainActor
    func testRecipeImportFromALinkScalesServings() throws {
        let app = launch(language: "en", stubAI: true)
        openRecipeImport(app)
        importLink("https://www.tiktok.com/@lakhas/video/7000000000000000001?_r=1", in: app)
        waitForPerServing("623", in: app)

        // SwiftUI exposes the stepper's buttons as "<identifier>-Increment" / "-Decrement".
        let increment = app.buttons["ax.recipe.servings-Increment"]
        XCTAssertTrue(increment.waitForExistence(timeout: 5), app.debugDescription)
        increment.tap()   // 2 → 3 servings, amounts × 1.5
        let rice = app.textFields.matching(identifier: "ax.recipe.grams").firstMatch
        let scaled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "300"), object: rice)
        XCTAssertEqual(XCTWaiter().wait(for: [scaled], timeout: 5), .completed, String(describing: rice.value))
        waitForPerServing("623", in: app)   // one serving stays the same

        let save = app.buttons["ax.recipe.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"), object: save)
        XCTAssertEqual(XCTWaiter().wait(for: [saved], timeout: 5), .completed)
    }
}
