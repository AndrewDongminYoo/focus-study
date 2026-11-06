import XCTest

final class FocusActivityTests: XCTestCase {
    func testPreviewShowsPlannedTimesAndConfirmationContext() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "approved", "--selected", "--activity-preview", "focus"]
        app.launch()
        XCTAssertTrue(app.staticTexts["activityPreviewReady"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(identifier: "activityPlanTitle").firstMatch.label.contains("예정"))
        XCTAssertTrue(app.staticTexts.matching(identifier: "activityConfirmation").firstMatch.exists)
    }
    func testStalePreviewUsesAppConfirmationInsteadOfRunningCountdown() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "approved", "--selected", "--activity-preview", "stale"]
        app.launch()
        XCTAssertTrue(app.staticTexts["activityPreviewReady"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(identifier: "activityStale").firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(identifier: "activityCountdown").firstMatch.exists)
    }
    func testCompactPreviewDistinguishesFocusAndBreakPlans() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "approved", "--selected", "--activity-preview", "focus"]
        app.launch()
        XCTAssertTrue(app.staticTexts["activityPreviewReady"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["집중 예정"].exists)
        app.terminate()
        app.launchArguments = ["--ui-testing", "approved", "--selected", "--activity-preview", "break"]
        app.launch()
        XCTAssertTrue(app.staticTexts["activityPreviewReady"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["휴식 예정"].exists)
    }
}
