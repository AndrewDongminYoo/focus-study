import XCTest
final class FocusFlowTests: XCTestCase {
    func app(_ mode: String = "approved", selected: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", mode] + (selected ? ["--selected"] : []) + extra; app.launch(); return app
    }
    /// Today's history and the usage report open from the one-line summary at the bottom of the timer screen.
    private func openToday(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["todaySummary"].waitForExistence(timeout: 8)); app.buttons["todaySummary"].tap()
    }
    private func openReport(_ app: XCUIApplication) {
        openToday(app); XCTAssertTrue(app.buttons["report"].waitForExistence(timeout: 5)); app.buttons["report"].tap()
    }
    func testStartupStorageFailureAllowsSafeEndAndRetry() {
        let app = app("startup-failure")
        XCTAssertTrue(app.buttons["startupEnd"].waitForExistence(timeout: 8))
        app.buttons["startupEnd"].tap(); app.buttons["startupRetry"].tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 8)); XCTAssertTrue(app.buttons["start"].isEnabled)
        openToday(app)
        XCTAssertTrue(app.staticTexts["중도 종료"].waitForExistence(timeout: 8))
    }
    func testTodaySummaryCountsOnlyCompletedSessions() {
        let app = app("expiring")
        XCTAssertTrue(app.descendants(matching: .any)["completion"].waitForExistence(timeout: 15))
        app.buttons["completionDismiss"].tap()
        XCTAssertTrue(app.buttons["todaySummary"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["todaySummary"].label, "오늘 집중 25분 · 1회")
        app.buttons["start"].tap(); app.buttons["end"].tap(); app.buttons["종료하기"].tap()
        XCTAssertTrue(app.buttons["todaySummary"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["todaySummary"].label, "오늘 집중 25분 · 1회")
        captureReport(app, name: "timer-screen-after-sessions")
    }
    func testLengthSettingAppliesToNextSession() {
        let app = app()
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 8)); app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.segmentedControls["lengthPicker"].waitForExistence(timeout: 5))
        app.segmentedControls["lengthPicker"].buttons["45분"].tap()
        captureReport(app, name: "settings")
        app.buttons["settingsDone"].tap()
        XCTAssertTrue(app.staticTexts["countdown"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["countdown"].label, "남은 시간 45분 0초")
    }
    func testCompletionCopyUsesSessionLength() {
        let app = app("expiring", extra: ["--length", "40"])
        // The Label exposes its icon and text under the same identifier, in a runtime-dependent order (iOS 26.5 lists the icon, labelled "Selected", first).
        let completion = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'completion' AND label CONTAINS '집중을 마쳤어요'")).firstMatch
        XCTAssertTrue(completion.waitForExistence(timeout: 15))
        XCTAssertTrue(completion.label.contains("40분"), completion.label); XCTAssertFalse(completion.label.contains("25분"), completion.label)
    }
    func testReloadRecreatesReportContentWithinSameDay() {
        let app = app()
        openReport(app)
        let generation = app.staticTexts["reportGeneration"]
        XCTAssertTrue(generation.waitForExistence(timeout: 8))
        let firstInstance = generation.label
        app.buttons["reportReload"].tap()
        let changed = NSPredicate(format: "label != %@", firstInstance)
        expectation(for: changed, evaluatedWith: generation)
        waitForExpectations(timeout: 5)
    }
    func testReportWaitingDoesNotClaimZeroUsage() {
        let app = app("report-waiting")
        openReport(app)
        XCTAssertTrue(app.staticTexts["reportWaiting"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["reportTotal"].exists)
        XCTAssertFalse(app.staticTexts["reportUnavailable"].exists)
        XCTAssertFalse(app.staticTexts["reportGeneration"].exists)
        captureReport(app, name: "report-waiting")
    }
    func testEmptyReportShowsUnavailableInsteadOfZero() {
        let app = app("report-empty")
        openReport(app)
        let unavailable = app.staticTexts["reportUnavailable"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 5))
        XCTAssertEqual(unavailable.label, "사용량을 불러오지 못했어요. 잠시 후 다시 확인해 주세요.")
        XCTAssertFalse(app.staticTexts["reportTotal"].exists)
        captureReport(app, name: "report-empty")
    }
    func testActualZeroReportShowsDurationInsteadOfUnavailable() {
        let app = app("report-zero")
        openReport(app)
        let total = app.staticTexts["reportTotal"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.contains("0"))
        XCTAssertFalse(app.staticTexts["reportUnavailable"].exists)
        captureReport(app, name: "report-zero")
    }
    private func captureReport(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testNewUserCompletesOnboardingInOrder() {
        let app = app("onboarding", selected: false)
        XCTAssertTrue(app.descendants(matching: .any)["purpose"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["countdown"].exists)
        captureReport(app, name: "onboarding-intro")
        app.buttons["onboardingNext"].tap()
        XCTAssertTrue(app.buttons["authorize"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["onboardingNext"].isEnabled)
        app.buttons["authorize"].tap()
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: app.buttons["onboardingNext"]); waitForExpectations(timeout: 5)
        app.buttons["onboardingNext"].tap()
        XCTAssertTrue(app.buttons["chooseSelection"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["onboardingNext"].isEnabled)
        app.buttons["chooseSelection"].tap(); app.buttons["fixtureSelect"].tap(); app.buttons["pickerSave"].tap()
        expectation(for: enabled, evaluatedWith: app.buttons["onboardingNext"]); waitForExpectations(timeout: 5)
        app.buttons["onboardingNext"].tap()
        XCTAssertTrue(app.segmentedControls["lengthPicker"].waitForExistence(timeout: 5))
        app.segmentedControls["lengthPicker"].buttons["40분"].tap()
        captureReport(app, name: "onboarding-length")
        app.buttons["onboardingFinish"].tap()
        XCTAssertTrue(app.staticTexts["countdown"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["countdown"].label, "남은 시간 40분 0초")
    }
    func testOnboardingBackReturnsToPreviousStep() {
        let app = app("onboarding", selected: false)
        XCTAssertTrue(app.buttons["onboardingNext"].waitForExistence(timeout: 8)); XCTAssertFalse(app.buttons["onboardingBack"].exists)
        app.buttons["onboardingNext"].tap()
        XCTAssertTrue(app.buttons["authorize"].waitForExistence(timeout: 5))
        app.buttons["onboardingBack"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["purpose"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["authorize"].exists)
    }
    func testDeniedPermissionShowsSettingsGuide() {
        let app = app("denied")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "settings").firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["authorize"].exists); XCTAssertFalse(app.buttons["start"].exists)
        captureReport(app, name: "permission-settings-guide")
    }
    func testActiveSessionLocksSelectionAndEarlyExitCreatesHistory() {
        let app = app(); app.buttons["start"].tap()
        XCTAssertTrue(app.buttons["end"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["selection"].exists); XCTAssertFalse(app.buttons["todaySummary"].exists)
        app.buttons["end"].tap()
        XCTAssertTrue(app.buttons["종료하기"].waitForExistence(timeout: 5)); app.buttons["종료하기"].tap()
        XCTAssertTrue(app.buttons["selection"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["selection"].isEnabled)
        openToday(app)
        XCTAssertTrue(app.staticTexts["중도 종료"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["completion"].exists)
    }
    func testCountdownSpeaksRemainingTimeAndScalesWithTextSize() {
        let regular = app()
        let countdown = regular.staticTexts["countdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 8))
        XCTAssertEqual(countdown.label, "남은 시간 25분 0초")
        let regularHeight = countdown.frame.height
        regular.terminate()
        let large = XCUIApplication()
        large.launchArguments = ["--ui-testing", "approved", "--selected", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        large.launch()
        let scaled = large.staticTexts["countdown"]
        XCTAssertTrue(scaled.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(scaled.frame.height, regularHeight)
        XCTAssertLessThanOrEqual(scaled.frame.maxX, large.windows.firstMatch.frame.maxX)
        captureReport(large, name: "countdown-accessibility-xxxl")
    }
    func testCancellingEarlyExitKeepsTheSessionRunning() {
        let app = app(); app.buttons["start"].tap()
        XCTAssertTrue(app.buttons["end"].waitForExistence(timeout: 5))
        app.buttons["end"].tap()
        XCTAssertTrue(app.buttons["종료하기"].waitForExistence(timeout: 5))
        captureReport(app, name: "early-exit-confirmation")
        // Newer iOS shows the dialog as a popover without its cancel button; tapping outside dismisses it.
        let cancel = app.buttons["계속 집중하기"]
        if cancel.exists { cancel.tap() } else { app.otherElements["PopoverDismissRegion"].tap() }
        XCTAssertTrue(app.buttons["end"].waitForExistence(timeout: 5)); XCTAssertFalse(app.staticTexts["중도 종료"].exists)
    }
    func testExpiredSessionShowsCompletionUntilDismissed() {
        let app = app("expiring")
        let completion = app.descendants(matching: .any)["completion"]
        XCTAssertTrue(completion.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["start"].exists)
        captureReport(app, name: "session-completed")
        app.buttons["completionDismiss"].tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 5)); XCTAssertFalse(completion.exists)
    }
    func testPickerCancelKeepsExistingSelection() {
        let app = app(); app.buttons["selection"].tap(); app.buttons["fixtureClear"].tap(); app.buttons["pickerCancel"].tap()
        XCTAssertTrue(app.buttons["start"].isEnabled)
    }
    func testPickerCountsFollowDraftAndCancelRestoresSavedSelection() {
        let app = app(); app.buttons["selection"].tap()
        let counts = app.staticTexts["selectionCounts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 5))
        XCTAssertEqual(counts.label, "앱 1개 · 웹사이트 0개 선택")
        app.buttons["fixtureClear"].tap()
        XCTAssertEqual(counts.label, "앱 0개 · 웹사이트 0개 선택")
        app.buttons["pickerCancel"].tap(); app.buttons["selection"].tap()
        XCTAssertEqual(counts.label, "앱 1개 · 웹사이트 0개 선택")
        captureReport(app, name: "selection-counts")
    }
    func testEmptySelectionReturnsToSelectionStepThenTimer() {
        let app = app(selected: false)
        XCTAssertTrue(app.buttons["chooseSelection"].waitForExistence(timeout: 8)); XCTAssertFalse(app.buttons["start"].exists)
        app.buttons["chooseSelection"].tap(); app.buttons["fixtureSelect"].tap(); app.buttons["pickerSave"].tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["start"].isEnabled)
    }
    func testEmptyDraftDisablesSaveWithInlineReason() {
        let app = app(); app.buttons["selection"].tap()
        let issue = app.descendants(matching: .any)["selectionIssue"]
        XCTAssertTrue(app.buttons["pickerSave"].waitForExistence(timeout: 5)); XCTAssertFalse(issue.exists)
        app.buttons["fixtureClear"].tap()
        XCTAssertTrue(issue.waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["pickerSave"].isEnabled)
        captureReport(app, name: "selection-empty-draft")
        app.buttons["fixtureSelect"].tap()
        XCTAssertTrue(app.buttons["pickerSave"].isEnabled); XCTAssertFalse(issue.exists)
    }
    func testRegistrationFailureNeverShowsActiveAndCanRetry() {
        let app = app("registration-failure"); app.buttons["start"].tap()
        XCTAssertTrue(app.staticTexts["startError"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["end"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["completion"].exists)
        XCTAssertEqual(app.staticTexts["startBlocker"].label, "오류를 다시 확인한 뒤에 시작할 수 있어요.")
        XCTAssertFalse(app.buttons["selection"].isEnabled)
        app.buttons["retry"].tap()
        XCTAssertTrue(app.buttons["start"].isEnabled)
    }
}
