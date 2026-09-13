import XCTest

/// Shared launch handling. Every UI test starts from a wiped store so a run
/// never inherits the previous one's activities.
class UITestCase: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// - Parameters:
    ///   - sampleData: serve synthetic health readings instead of HealthKit.
    ///   - tab: which tab to open on.
    func launchApp(sampleData: Bool = false, tab: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitesting", "-reset-data"]
        if sampleData { app.launchArguments += ["-sample-data"] }
        if let tab { app.launchArguments += ["-start-tab", tab] }
        app.launch()
        return app
    }
}
