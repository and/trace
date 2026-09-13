import XCTest

/// The Trends screen. With sample data it must render both charts; with none
/// it must say so rather than showing an empty frame.
final class TrendsUITests: UITestCase {

    func testTrendsRendersBothChartsWithData() {
        let app = launchApp(sampleData: true, tab: "trends")

        XCTAssertTrue(app.staticTexts["Daily strain"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Strain by activity"].waitForExistence(timeout: 5))
    }

    func testTrendsExplainsItselfWithoutData() {
        let app = launchApp(tab: "trends")

        XCTAssertTrue(app.staticTexts["No health data yet"].waitForExistence(timeout: 10),
                      "Without readings, Trends should explain why rather than render nothing")
    }

    /// The overlay picker should come up already showing an activity, so the
    /// highlight is visible without hunting for it.
    func testStrainChartOffersTheActivityHighlight() {
        let app = launchApp(sampleData: true, tab: "trends")
        XCTAssertTrue(app.staticTexts["Daily strain"].waitForExistence(timeout: 10))

        let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Deep work'")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5),
                      "A label should be preselected in the highlight picker")
    }

    func testTrendsIsReachableFromToday() {
        let app = launchApp(sampleData: true)
        XCTAssertTrue(app.staticTexts["day.label"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Trends"].tap()
        XCTAssertTrue(app.staticTexts["Daily strain"].waitForExistence(timeout: 5))
    }
}
