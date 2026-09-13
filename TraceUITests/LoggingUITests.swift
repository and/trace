import XCTest

/// Logging an activity: the app's core loop. Start it, stop it, see it listed.
final class LoggingUITests: UITestCase {

    func testStartingAnActivityShowsItAsRunning() {
        let app = launchApp()
        let chip = app.buttons["chip.Study"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))

        chip.tap()

        XCTAssertTrue(app.staticTexts["running.label"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["running.label"].label, "Study")
        XCTAssertTrue(app.buttons["running.stop"].exists, "A running activity offers Stop")
        XCTAssertFalse(chip.exists, "The picker is replaced while an activity runs")
    }

    func testStoppingAnActivityMovesItToRecent() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["chip.Study"].waitForExistence(timeout: 10))
        app.buttons["chip.Study"].tap()

        let stop = app.buttons["running.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()

        XCTAssertTrue(app.staticTexts["Recent"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "recent.row").count, 1)
        XCTAssertFalse(app.buttons["running.stop"].exists, "Nothing is running once stopped")
        XCTAssertTrue(app.buttons["chip.Study"].exists, "The picker returns")
    }

    func testOnlyOneActivityRunsAtATime() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["chip.Study"].waitForExistence(timeout: 10))
        app.buttons["chip.Study"].tap()
        XCTAssertTrue(app.staticTexts["running.label"].waitForExistence(timeout: 5))

        // With one running, no other chip is reachable to start a second.
        XCTAssertFalse(app.buttons["chip.Meeting"].exists)
    }

    func testSeveralActivitiesAccumulateInRecent() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["chip.Study"].waitForExistence(timeout: 10))

        for label in ["Study", "Meeting"] {
            app.buttons["chip.\(label)"].tap()
            let stop = app.buttons["running.stop"]
            XCTAssertTrue(stop.waitForExistence(timeout: 5))
            stop.tap()
            XCTAssertTrue(app.buttons["chip.Study"].waitForExistence(timeout: 5))
        }

        XCTAssertEqual(app.buttons.matching(identifier: "recent.row").count, 2)
    }

    /// A typed label must be remembered as a chip afterwards — the feature that
    /// makes the picker yours rather than a fixed list.
    func testACustomLabelBecomesAQuickPick() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["chip.new"].waitForExistence(timeout: 10))
        app.buttons["chip.new"].tap()

        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Piano")
        app.alerts.buttons["Start"].tap()

        XCTAssertTrue(app.staticTexts["running.label"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["running.label"].label, "Piano")

        app.buttons["running.stop"].tap()
        XCTAssertTrue(app.buttons["chip.Piano"].waitForExistence(timeout: 5),
                      "A typed label should be offered as a chip next time")
    }
}
