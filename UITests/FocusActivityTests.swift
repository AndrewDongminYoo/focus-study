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
    /// The production home screen widget view for each state; the preview reads no file and makes no WidgetKit request.
    func testWidgetPreviewShowsEachState() {
        let expected = [("numbers", "오늘 집중 1시간 15분, 3회"), ("empty", "오늘 집중, 앱에서 시작해 보세요"), ("check", "오늘 집중, 앱에서 확인해 주세요")]
        let app = XCUIApplication()
        for (mode, label) in expected {
            app.launchArguments = ["--ui-testing", "approved", "--selected", "--widget-preview", mode, "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
            app.launch()
            XCTAssertTrue(app.staticTexts["widgetPreviewReady"].waitForExistence(timeout: 10), mode)
            let widget = app.descendants(matching: .any)["todayWidget"]
            XCTAssertTrue(widget.exists, mode)
            XCTAssertEqual(widget.label, label)
            capture(app, name: "widget-\(mode)")
            app.terminate()
        }
    }
    /// The same states at the largest text size, for the visual approval of the widget.
    func testWidgetPreviewAtLargestTextSize() {
        let app = XCUIApplication()
        for mode in ["numbers", "empty", "check"] {
            app.launchArguments = ["--ui-testing", "approved", "--selected", "--widget-preview", mode, "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR",
                                   "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch()
            XCTAssertTrue(app.staticTexts["widgetPreviewReady"].waitForExistence(timeout: 10), mode)
            XCTAssertTrue(app.descendants(matching: .any)["todayWidget"].exists, mode)
            capture(app, name: "widget-\(mode)-largest-text")
            app.terminate()
        }
    }
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
