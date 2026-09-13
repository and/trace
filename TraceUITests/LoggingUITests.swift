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

/// Refreshing. The chart previously loaded on appear and never again, so a
/// reading that synced from the watch while the app sat open never showed.
final class RefreshUITests: UITestCase {

    func testPullToRefreshKeepsTheScreenIntact() {
        let app = launchApp(sampleData: true)
        let label = app.staticTexts["day.label"]
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        let before = label.label

        // Pull down from the chart area.
        let top = app.collectionViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let bottom = app.collectionViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        top.press(forDuration: 0.1, thenDragTo: bottom)

        XCTAssertTrue(label.waitForExistence(timeout: 10))
        XCTAssertEqual(label.label, before, "A refresh should not change which day is shown")
        XCTAssertTrue(app.buttons["chip.Study"].exists, "The screen should still be usable after a refresh")
    }

    /// Stopping an activity refreshes the chart, and must not throw away the
    /// day being viewed while doing so.
    func testStoppingRefreshesWithoutLosingTheDay() {
        // No sample data here: it seeds activities of its own, and this asserts
        // on the exact contents of Recent.
        let app = launchApp()
        XCTAssertTrue(app.buttons["chip.Study"].waitForExistence(timeout: 10))
        let today = app.staticTexts["day.label"].label

        app.buttons["chip.Study"].tap()
        let stop = app.buttons["running.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()

        XCTAssertTrue(app.staticTexts["day.label"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["day.label"].label, today)
        XCTAssertEqual(app.buttons.matching(identifier: "recent.row").count, 1)
    }

    /// A refresh must not silently drag you back to today.
    func testRefreshKeepsThePastDayBeingViewed() {
        let app = launchApp(sampleData: true)
        XCTAssertTrue(app.buttons["day.previous"].waitForExistence(timeout: 10))
        app.buttons["day.previous"].tap()
        let yesterday = app.staticTexts["day.label"].label

        let list = app.collectionViews.firstMatch
        list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.1,
                   thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))

        XCTAssertTrue(app.staticTexts["day.label"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["day.label"].label, yesterday,
                       "Refreshing should keep the day you navigated to")
    }
}
