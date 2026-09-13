import XCTest

/// Tab navigation. This exists because a debug affordance once bound the
/// TabView's selection to a constant, which left the tab bar inert — every tab
/// rendered, none responded. Nothing in the unit suite could see it.
final class NavigationUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitesting"]
        app.launch()
        return app
    }

    func testBothTabsExist() {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Activity"].exists)
    }

    /// The regression test: tapping Trends must actually move there.
    func testCanSwitchToActivity() {
        let app = launchApp()
        let activity = app.tabBars.buttons["Activity"]
        XCTAssertTrue(activity.waitForExistence(timeout: 10))

        activity.tap()
        XCTAssertTrue(
            app.staticTexts["Activity"].waitForExistence(timeout: 5),
            "Tapping the Activity tab should show the Activity screen"
        )
        XCTAssertTrue(activity.isSelected, "The Activity tab should be selected after tapping it")
    }

    /// And back again — a binding that only moves one way is still broken.
    func testCanSwitchBackToToday() {
        let app = launchApp()
        let today = app.tabBars.buttons["Today"]
        let activity = app.tabBars.buttons["Activity"]
        XCTAssertTrue(activity.waitForExistence(timeout: 10))

        activity.tap()
        XCTAssertTrue(activity.isSelected)

        today.tap()
        XCTAssertTrue(today.isSelected, "The Today tab should be selected after tapping back")
        XCTAssertTrue(app.staticTexts["day.label"].waitForExistence(timeout: 5),
                      "The Today screen's day header should be back")
    }

    /// Repeated switching must keep working, not stick after the first move.
    func testSwitchingRepeatedlyKeepsWorking() {
        let app = launchApp()
        let today = app.tabBars.buttons["Today"]
        let activity = app.tabBars.buttons["Activity"]
        XCTAssertTrue(activity.waitForExistence(timeout: 10))

        for pass in 1...3 {
            activity.tap()
            XCTAssertTrue(activity.isSelected, "Activity should be selected on pass \(pass)")
            today.tap()
            XCTAssertTrue(today.isSelected, "Today should be selected on pass \(pass)")
        }
    }
}
