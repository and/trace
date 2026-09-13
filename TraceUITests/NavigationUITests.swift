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
        XCTAssertTrue(app.tabBars.buttons["Trends"].exists)
    }

    /// The regression test: tapping Trends must actually move there.
    func testCanSwitchToTrends() {
        let app = launchApp()
        let trends = app.tabBars.buttons["Trends"]
        XCTAssertTrue(trends.waitForExistence(timeout: 10))

        trends.tap()
        XCTAssertTrue(
            app.staticTexts["Trends"].waitForExistence(timeout: 5),
            "Tapping the Trends tab should show the Trends screen"
        )
        XCTAssertTrue(trends.isSelected, "The Trends tab should be selected after tapping it")
    }

    /// And back again — a binding that only moves one way is still broken.
    func testCanSwitchBackToToday() {
        let app = launchApp()
        let today = app.tabBars.buttons["Today"]
        let trends = app.tabBars.buttons["Trends"]
        XCTAssertTrue(trends.waitForExistence(timeout: 10))

        trends.tap()
        XCTAssertTrue(trends.isSelected)

        today.tap()
        XCTAssertTrue(today.isSelected, "The Today tab should be selected after tapping back")
        XCTAssertTrue(app.staticTexts["day.label"].waitForExistence(timeout: 5),
                      "The Today screen's day header should be back")
    }

    /// Repeated switching must keep working, not stick after the first move.
    func testSwitchingRepeatedlyKeepsWorking() {
        let app = launchApp()
        let today = app.tabBars.buttons["Today"]
        let trends = app.tabBars.buttons["Trends"]
        XCTAssertTrue(trends.waitForExistence(timeout: 10))

        for pass in 1...3 {
            trends.tap()
            XCTAssertTrue(trends.isSelected, "Trends should be selected on pass \(pass)")
            today.tap()
            XCTAssertTrue(today.isSelected, "Today should be selected on pass \(pass)")
        }
    }
}
