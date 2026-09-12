import XCTest

/// The day stepper, driven through the real UI. This exists because the
/// stepper once froze for reasons no unit test could reach: a scrollable chart
/// held a scroll offset pointing into the previous day's domain, and two
/// buttons in one List row let the row swallow their taps. Both only show up
/// when something actually taps the screen.
final class DayStepperUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitesting"]
        app.launch()
        return app
    }

    /// Matches the format used by the header, so the assertions compare what a
    /// person would actually read.
    private func headerText(for date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year())
    }

    private func day(offsetFromToday days: Int) -> Date {
        let today = Calendar.current.startOfDay(for: .now)
        return Calendar.current.date(byAdding: .day, value: days, to: today)!
    }

    func testOpensOnToday() {
        let app = launchApp()
        let label = app.staticTexts["day.label"]
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        XCTAssertEqual(label.label, headerText(for: day(offsetFromToday: 0)))
    }

    func testNextIsDisabledOnToday() {
        let app = launchApp()
        let next = app.buttons["day.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertFalse(next.isEnabled, "Cannot navigate into the future")
    }

    /// The regression test for the freeze: every tap must advance the date.
    /// When the stepper was stuck, the label stopped changing after the first.
    func testSteppingBackRepeatedlyKeepsMoving() {
        let app = launchApp()
        let label = app.staticTexts["day.label"]
        let previous = app.buttons["day.previous"]
        XCTAssertTrue(label.waitForExistence(timeout: 10))

        for step in 1...5 {
            previous.tap()
            let expected = headerText(for: day(offsetFromToday: -step))
            XCTAssertTrue(
                app.staticTexts[expected].waitForExistence(timeout: 3),
                "After \(step) back-taps the header should read \(expected), not \(label.label)"
            )
        }
    }

    /// Back then forward must return to today, which fails if either
    /// direction silently stops responding.
    func testSteppingBackAndForwardReturnsToToday() {
        let app = launchApp()
        let label = app.staticTexts["day.label"]
        XCTAssertTrue(label.waitForExistence(timeout: 10))

        for _ in 1...3 { app.buttons["day.previous"].tap() }
        let threeBack = headerText(for: day(offsetFromToday: -3))
        XCTAssertTrue(app.staticTexts[threeBack].waitForExistence(timeout: 3))

        for _ in 1...3 { app.buttons["day.next"].tap() }
        let today = headerText(for: day(offsetFromToday: 0))
        XCTAssertTrue(app.staticTexts[today].waitForExistence(timeout: 3))
    }

    /// Once off today, forward must become available again.
    func testNextBecomesEnabledAfterSteppingBack() {
        let app = launchApp()
        let previous = app.buttons["day.previous"]
        XCTAssertTrue(previous.waitForExistence(timeout: 10))

        previous.tap()
        let next = app.buttons["day.next"]
        XCTAssertTrue(next.isEnabled, "Forward should be available on a past day")

        next.tap()
        XCTAssertFalse(next.isEnabled, "Back on today, forward is disabled again")
    }
}
