import XCTest

/// The Activity tab, which replaced Trends. It shows what heart rate did during
/// each logged session rather than a daily strain score.
final class ActivityTabUITests: UITestCase {

    func testShowsPerActivityHeartRateWithData() {
        let app = launchApp(sampleData: true, tab: "trends")

        XCTAssertTrue(app.staticTexts["Heart rate by activity"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Sessions"].waitForExistence(timeout: 5))
    }

    func testExplainsItselfWithNothingLogged() {
        let app = launchApp(tab: "trends")

        XCTAssertTrue(app.staticTexts["Nothing to compare yet"].waitForExistence(timeout: 15),
                      "With no activities logged, the tab should say so rather than render nothing")
    }

    func testIsReachableFromToday() {
        let app = launchApp(sampleData: true)
        XCTAssertTrue(app.staticTexts["day.label"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["Heart rate by activity"].waitForExistence(timeout: 15))
    }

    /// The daily strain score is gone; nothing should still be advertising it.
    func testNoLongerShowsDailyStrain() {
        let app = launchApp(sampleData: true, tab: "trends")
        XCTAssertTrue(app.staticTexts["Heart rate by activity"].waitForExistence(timeout: 15))

        XCTAssertFalse(app.staticTexts["Daily strain"].exists)
        XCTAssertFalse(app.staticTexts["Strain by activity"].exists)
    }
}
