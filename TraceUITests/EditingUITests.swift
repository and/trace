import XCTest

/// Editing and deleting a logged activity, including the paths that also have
/// to keep Apple Health in step.
final class EditingUITests: UITestCase {

    /// Logs one activity and returns the app sitting on the Today screen.
    private func appWithOneActivity(label: String = "Study") -> XCUIApplication {
        let app = launchApp()
        XCTAssertTrue(app.buttons["chip.\(label)"].waitForExistence(timeout: 10))
        app.buttons["chip.\(label)"].tap()
        let stop = app.buttons["running.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "recent.row").firstMatch.waitForExistence(timeout: 5))
        return app
    }

    func testTappingARowOpensTheEditor() {
        let app = appWithOneActivity()
        app.buttons.matching(identifier: "recent.row").firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Edit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["editor.name"].exists)
        XCTAssertTrue(app.buttons["editor.delete"].exists)
    }

    func testRenamingAnActivityUpdatesTheList() {
        let app = appWithOneActivity()
        app.buttons.matching(identifier: "recent.row").firstMatch.tap()

        let field = app.textFields["editor.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let existing = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        field.typeText("Revision")
        app.buttons["editor.done"].tap()

        XCTAssertTrue(app.staticTexts["Revision"].waitForExistence(timeout: 5),
                      "The renamed activity should show its new name")
        XCTAssertFalse(app.staticTexts["Study"].exists)
    }

    func testDeletingFromTheEditorRemovesTheRow() {
        let app = appWithOneActivity()
        XCTAssertEqual(app.buttons.matching(identifier: "recent.row").count, 1)

        app.buttons.matching(identifier: "recent.row").firstMatch.tap()
        XCTAssertTrue(app.buttons["editor.delete"].waitForExistence(timeout: 5))
        app.buttons["editor.delete"].tap()

        // Confirmation dialog.
        let confirm = app.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        XCTAssertTrue(app.buttons["chip.Study"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "recent.row").count, 0,
                       "The deleted activity should be gone from Recent")
    }

    func testSwipingARowDeletesIt() {
        let app = appWithOneActivity()
        let row = app.buttons.matching(identifier: "recent.row").firstMatch
        row.swipeLeft()

        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()

        XCTAssertEqual(app.buttons.matching(identifier: "recent.row").count, 0)
    }

    /// A running activity has no end, so the editor must not offer one —
    /// binding an end through a non-optional proxy would silently stop it.
    func testEditorHidesTheEndPickerForARunningActivity() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["chip.Study"].waitForExistence(timeout: 10))
        app.buttons["chip.Study"].tap()
        XCTAssertTrue(app.staticTexts["running.label"].waitForExistence(timeout: 5))

        // A running activity is not in Recent, so there is no row to open.
        XCTAssertEqual(app.buttons.matching(identifier: "recent.row").count, 0)
        XCTAssertTrue(app.buttons["running.stop"].exists)
    }
}
