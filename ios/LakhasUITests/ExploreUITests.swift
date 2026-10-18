import XCTest

/// Explore (Phase 8). Runs without `-uiTestingStubAI` and with no key: logging and saving from
/// Explore never touch AI. A medium koshary is 450 g × 156 kcal / 100 g = 702 kcal.
extension OnboardingUITests {
    @MainActor
    private func openExplore(_ app: XCUIApplication) {
        completeOnboarding(app)
        finishAfterSummary(app)
        // Let onboarding's closing transition finish, or the tab's frame is read mid-animation.
        XCTAssertTrue(element(app, "ax.today.ring").waitForExistence(timeout: 10), app.debugDescription)
        let tab = app.buttons["ax.tab.explore"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5) && tab.isHittable, app.debugDescription)
        tab.tap()
        XCTAssertTrue(element(app, "ax.explore.dish").waitForExistence(timeout: 5),
                      "explore tab selected: \(tab.isSelected)\n\(app.debugDescription)")
    }

    @MainActor
    private func searchAndOpen(_ query: String, in app: XCUIApplication) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        field.typeText(query)
        let first = element(app, "ax.explore.dish")
        XCTAssertTrue(first.waitForExistence(timeout: 5), app.debugDescription)
        first.tap()
    }

    @MainActor
    func testExploreDishLogsToTodayWithoutAKey() throws {
        let app = launch(language: "en")
        openExplore(app)
        searchAndOpen("koshari", in: app)

        let perServing = element(app, "ax.explore.perServing")
        XCTAssertTrue(perServing.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(perServing.label.contains("702"), perServing.label)
        let like = element(app, "ax.explore.like")
        like.tap()
        XCTAssertTrue(like.isSelected, app.debugDescription)
        element(app, "ax.explore.favorite").tap()

        let log = element(app, "ax.explore.log")
        scrollUntilHittable(log, in: app)
        log.tap()
        XCTAssertTrue(element(app, "ax.explore.logged").waitForExistence(timeout: 5), app.debugDescription)

        app.buttons["ax.tab.today"].tap()
        let meal = element(app, "ax.today.meal")
        XCTAssertTrue(meal.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(meal.label.contains("Koshary"), meal.label)
        XCTAssertTrue(meal.label.contains("702"), meal.label)
    }

    @MainActor
    func testExploreArabicSearchAndSaveToMyRecipes() throws {
        let app = launch(language: "ar")
        openExplore(app)
        element(app, "ax.explore.meal.breakfast").tap()
        searchAndOpen("طعميه", in: app)

        let save = element(app, "ax.explore.save")
        scrollUntilHittable(save, in: app)
        save.tap()
        XCTAssertTrue(element(app, "ax.explore.saved").waitForExistence(timeout: 5), app.debugDescription)

        app.buttons["ax.tab.recipes"].tap()
        let fromExplore = app.buttons["من استكشف"]
        XCTAssertTrue(fromExplore.waitForExistence(timeout: 5), app.debugDescription)
        fromExplore.tap()
        let row = element(app, "ax.recipes.explore")
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(row.label.contains("طعمية"), row.label)
    }
}
