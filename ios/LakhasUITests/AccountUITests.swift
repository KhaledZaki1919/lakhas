import XCTest

/// Settings → Account (Phase 9, ADR-027). `-uiTesting` answers the server from `UITestingServer`
/// (in memory, invite code TEST-INVITE) and keeps secrets in memory. Password stretching is the
/// real 600,000-round PBKDF2, so the waits are generous.
extension OnboardingUITests {
    @MainActor
    private func openAccount(_ app: XCUIApplication) {
        completeOnboarding(app)
        finishAfterSummary(app)
        let settings = app.buttons["ax.today.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), app.debugDescription)
        settings.tap()
        let account = element(app, "ax.settings.account")
        XCTAssertTrue(account.waitForExistence(timeout: 5), app.debugDescription)
        account.tap()
    }

    @MainActor
    private func type(_ text: String, into id: String, in app: XCUIApplication) {
        let field = element(app, id)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "missing \(id)\n\(app.debugDescription)")
        scrollUntilHittable(field, in: app)
        field.tap()
        if field.elementType == .secureTextField {
            // Secure fields drop keystrokes when typed in one burst on the Simulator.
            for character in text { field.typeText(String(character)) }
            let typed = (field.value as? String)?.count ?? 0
            XCTAssertEqual(typed, text.count, "secure field \(id) has \(typed) characters\n\(app.debugDescription)")
        } else {
            field.typeText(text)
        }
    }

    @MainActor
    private func turnOn(_ id: String, in app: XCUIApplication) {
        let toggle = app.switches[id]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "missing \(id)\n\(app.debugDescription)")
        scrollUntilHittable(toggle, in: app)
        if (toggle.value as? String) != "1" { toggle.tap() }
        if (toggle.value as? String) != "1" { toggle.switches.firstMatch.tap() }
        XCTAssertEqual(toggle.value as? String, "1", app.debugDescription)
    }

    @MainActor
    private func signUp(_ app: XCUIApplication, email: String) {
        element(app, "ax.account.signUp").tap()
        type("test-invite", into: "ax.account.invite", in: app)
        type(email, into: "ax.account.emailField", in: app)
        type("a long passphrase", into: "ax.account.password", in: app)
        type("a long passphrase", into: "ax.account.confirm", in: app)
        let submit = element(app, "ax.account.submit")
        scrollUntilHittable(submit, in: app)
        submit.tap()

        // The recovery code is shown once; Done stays off until "I saved it" is on.
        let code = element(app, "ax.account.recoveryCode")
        XCTAssertTrue(code.waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertEqual(code.label.count, 32, code.label)
        let done = element(app, "ax.account.done")
        scrollUntilHittable(done, in: app)
        XCTAssertFalse(done.isEnabled)
        turnOn("ax.account.savedToggle", in: app)
        XCTAssertTrue(done.isEnabled)
        done.tap()

        let shown = element(app, "ax.account.email")
        XCTAssertTrue(shown.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(shown.label, email)
    }

    @MainActor
    func testAccountSignUpShowsTheRecoveryCodeOnceThenSignsOut() throws {
        let app = launch(language: "en")
        openAccount(app)
        XCTAssertTrue(element(app, "ax.account.privacy").waitForExistence(timeout: 5))
        signUp(app, email: "me@example.com")

        let signOut = element(app, "ax.account.signOut")
        scrollUntilHittable(signOut, in: app)
        signOut.tap()
        let confirm = app.buttons["ax.account.signOutConfirm"].exists
            ? app.buttons["ax.account.signOutConfirm"]
            : app.sheets.buttons.element(boundBy: 0)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()
        XCTAssertTrue(element(app, "ax.account.signUp").waitForExistence(timeout: 10), app.debugDescription)

        // Signing in again works with the same password.
        element(app, "ax.account.signIn").tap()
        type("me@example.com", into: "ax.account.emailField", in: app)
        type("a long passphrase", into: "ax.account.password", in: app)
        let submit = element(app, "ax.account.submit")
        scrollUntilHittable(submit, in: app)
        submit.tap()
        XCTAssertTrue(element(app, "ax.account.email").waitForExistence(timeout: 60), app.debugDescription)
    }

    @MainActor
    func testAccountDeletionInArabic() throws {
        let app = launch(language: "ar")
        openAccount(app)
        signUp(app, email: "delete@example.com")

        let delete = element(app, "ax.account.delete")
        scrollUntilHittable(delete, in: app)
        delete.tap()
        let confirm = element(app, "ax.account.deleteConfirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(confirm.isEnabled)
        type("a long passphrase", into: "ax.account.password", in: app)
        turnOn("ax.account.understood", in: app)
        scrollUntilHittable(confirm, in: app)
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        XCTAssertTrue(element(app, "ax.account.signUp").waitForExistence(timeout: 60), app.debugDescription)
    }
}
