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
        XCTAssertTrue(app.staticTexts["휴식 끝"].exists)
        capture(app, name: "activity-break-compact")
    }
    /// The compact break label at the largest text size, for the visual review of the 2026-11-11 label change.
    func testCompactBreakLabelAtLargestTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "approved", "--selected", "--activity-preview", "break",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["activityPreviewReady"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["휴식 끝"].exists)
        capture(app, name: "activity-break-compact-largest-text")
    }
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
