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
    /// No callback runs at the base length of an open session, so its stale card counts up instead of asking for a confirmation
    /// (2026-11-18 single-interval amendment, decision 14).
    func testStaleOpenSessionPreviewCountsUp() {
        for (name, extra) in [("activity-open-stale", [String]()),
                              ("activity-open-stale-dark", ["-UIUserInterfaceStyle", "dark"]),
                              ("activity-open-stale-largest-text", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "approved", "--selected", "--activity-preview", "open-stale"] + extra
            app.launch()
            XCTAssertTrue(app.staticTexts["activityPreviewReady"].waitForExistence(timeout: 10), name)
            XCTAssertTrue(app.staticTexts.matching(identifier: "activityCountUp").firstMatch.exists, name)
            XCTAssertFalse(app.staticTexts.matching(identifier: "activityStale").firstMatch.exists, name)
            XCTAssertTrue(app.staticTexts["집중 중"].exists, name)
            capture(app, name: name)
            app.terminate()
        }
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
            // The small and the medium widget say the same.
            for identifier in ["todayWidget", "todayWidgetMedium"] {
                let widget = app.descendants(matching: .any)[identifier]
                XCTAssertTrue(widget.exists, "\(mode) \(identifier)")
                XCTAssertEqual(widget.label, label, identifier)
            }
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
    /// The production everyday plan widget view for fixed plans; the preview reads no file and makes no WidgetKit request.
    func testPlanWidgetPreviewShowsEachState() {
        let expected = [
            ("restricted", "오늘의 제한 계획, 지금 14:20 제한, 13:00부터 16:00까지, 다음 해제 16:00부터 30분, 그다음 제한 16:30부터 18:00까지"),
            ("unblocked", "오늘의 제한 계획, 지금 12:30 해제, 12:00부터 13:00까지, 다음 제한 13:00부터 16:00까지"),
            ("after", "오늘의 제한 계획, 지금 19:00 제한 끝, 18:00에 끝났어요, 다음 제한 내일 08:00"),
            ("none", "오늘의 제한 계획, 앱에서 매일 제한을 정해 보세요"),
            ("check", "오늘의 제한 계획, 앱에서 확인해 주세요"),
            ("day-off", "오늘의 제한 계획, 오늘은 제한하지 않는 요일이에요"),
        ]
        let app = XCUIApplication()
        for (mode, label) in expected {
            app.launchArguments = ["--ui-testing", "approved", "--selected", "--plan-widget-preview", mode, "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
            app.launch()
            XCTAssertTrue(app.staticTexts["planWidgetPreviewReady"].waitForExistence(timeout: 10), mode)
            let widget = app.descendants(matching: .any)["everydayPlanWidget"].firstMatch
            XCTAssertTrue(widget.exists, mode)
            XCTAssertEqual(widget.label, label, mode)
            capture(app, name: "plan-widget-\(mode)")
            app.terminate()
        }
    }
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
