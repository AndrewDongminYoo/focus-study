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
        XCTAssertTrue(app.staticTexts["집중 종료"].waitForExistence(timeout: 8))
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
    /// The everyday layer opens from its row in the settings sheet.
    private func openEveryday(_ app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 8)); app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.buttons["everydayRow"].waitForExistence(timeout: 5)); app.buttons["everydayRow"].tap()
        let status = app.staticTexts["everydayStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        return status
    }
    /// A `Toggle` in a `Form` can take the tap on its label without flipping; the inner switch is the fallback.
    private func flip(_ toggle: XCUIElement) {
        let before = toggle.value as? String
        toggle.tap()
        if toggle.value as? String == before { toggle.switches.firstMatch.tap() }
        XCTAssertNotEqual(toggle.value as? String, before)
    }
    func testEverydayLayerTurnsOnFromSettings() {
        let app = app()
        let status = openEveryday(app)
        XCTAssertEqual(status.label, "꺼져 있어요")
        let selection = app.buttons["everydaySelection"], fixtureSelect = app.buttons["fixtureSelect"]
        // A tap while the everyday screen still slides in can miss; tap again only when the sheet did not open and the row still takes a tap.
        expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: selection); waitForExpectations(timeout: 5)
        selection.tap()
        if !fixtureSelect.waitForExistence(timeout: 3), selection.isHittable { selection.tap() }
        XCTAssertTrue(fixtureSelect.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: fixtureSelect); waitForExpectations(timeout: 5)
        fixtureSelect.tap(); app.buttons["pickerSave"].tap()
        // An empty draft makes the save below refuse, so a missed fixture tap fails here instead.
        expectation(for: NSPredicate(format: "label CONTAINS '앱 1개'"), evaluatedWith: app.buttons["everydaySelection"]); waitForExpectations(timeout: 5)
        // The count follows the draft while the sheet is still up, so wait for the sheet to go and the switch to take a tap.
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: fixtureSelect); waitForExpectations(timeout: 5)
        let toggle = app.switches["everydayToggle"]
        expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: toggle); waitForExpectations(timeout: 5)
        flip(toggle)
        app.buttons["everydaySave"].tap()
        expectation(for: NSPredicate(format: "label BEGINSWITH '켜져 있어요' OR label BEGINSWITH '지금 제한하고 있어요'"), evaluatedWith: status)
        waitForExpectations(timeout: 5)
        let refusal = app.staticTexts["everydayRefusal"]
        XCTAssertFalse(refusal.exists, refusal.exists ? refusal.label : "")
        captureReport(app, name: "everyday-settings")
    }
    func testLooserEditInsideTheRangeIsRefused() {
        let app = app(extra: ["--everyday-fixture", "blocking"])
        let status = openEveryday(app)
        XCTAssertTrue(status.label.hasPrefix("지금 제한하고 있어요"), status.label)
        flip(app.switches["everydayToggle"])
        app.buttons["everydaySave"].tap()
        let refusal = app.staticTexts["everydayRefusal"]
        XCTAssertTrue(refusal.waitForExistence(timeout: 5))
        XCTAssertTrue(refusal.label.hasPrefix("제한 시간에는 더 엄격하게만 바꿀 수 있어요."), refusal.label)
        XCTAssertTrue(status.label.hasPrefix("지금 제한하고 있어요"), status.label)
    }
    func testThreeWindowsAreTheLimit() {
        let app = app()
        _ = openEveryday(app)
        let add = app.buttons["everydayAddWindow"]
        for template in ["점심", "등교", "하교"] {
            XCTAssertTrue(add.isEnabled, template); add.tap()
            XCTAssertTrue(app.buttons[template].waitForExistence(timeout: 5), template); app.buttons[template].tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["everydayWindow.3"].waitForExistence(timeout: 5))
        // Three window rows push the button below the fold, and the Form renders only visible rows.
        for _ in 0..<4 where !add.exists { app.swipeUp() }
        XCTAssertTrue(add.exists)
        XCTAssertFalse(add.isEnabled)
    }
    func testTimerScreenIsUnchangedWithTheLayerOn() {
        let app = app(extra: ["--everyday-fixture", "blocking"])
        XCTAssertTrue(app.staticTexts["countdown"].waitForExistence(timeout: 8))
        for identifier in ["start", "settingsButton", "todaySummary"] { XCTAssertTrue(app.buttons[identifier].exists, identifier) }
        for identifier in ["everydayRow", "everydayStatus", "everydayToggle", "everydaySave"] {
            XCTAssertFalse(app.descendants(matching: .any)[identifier].exists, identifier)
        }
    }
    private func openFocusGuide(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 8)); app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.buttons["focusGuideRow"].waitForExistence(timeout: 5)); app.buttons["focusGuideRow"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["focusGuide"].waitForExistence(timeout: 5))
    }
    func testFocusGuideOpensFromSettings() {
        let app = app()
        openFocusGuide(app)
        XCTAssertFalse(app.staticTexts["focusFilterRefusal"].exists)
    }
    func testStoredRefusalShowsInTheGuide() {
        let app = app(extra: ["--focus-filter-refusal", "busy"])
        openFocusGuide(app)
        XCTAssertTrue(app.staticTexts["focusFilterRefusal"].waitForExistence(timeout: 5))
    }
    func testTimerScreenIsUnchangedWithTheGuide() {
        let app = app(extra: ["--focus-filter-refusal", "busy"])
        XCTAssertTrue(app.staticTexts["countdown"].waitForExistence(timeout: 8))
        for identifier in ["start", "settingsButton", "todaySummary"] { XCTAssertTrue(app.buttons[identifier].exists, identifier) }
        for identifier in ["focusGuideRow", "focusGuide", "focusFilterRefusal"] { XCTAssertFalse(app.descendants(matching: .any)[identifier].exists, identifier) }
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
        XCTAssertTrue(app.staticTexts["집중 종료"].waitForExistence(timeout: 5))
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
        // The `end` button itself reads "집중 종료", so the check is that the session is still counting down.
        XCTAssertTrue(app.buttons["end"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["countdown"].exists); XCTAssertFalse(app.descendants(matching: .any)["completion"].exists)
    }
    private func shortBreaks(_ mode: String = "approved") -> XCUIApplication { app(mode, extra: ["--break-timing", "short"]) }
    func testBreakFlowReBlocksAndResumes() {
        let app = shortBreaks(); app.buttons["start"].tap()
        XCTAssertTrue(app.buttons["breakStart"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["breaksLeft"].label, "쉬는 시간 3번 남았어요")
        app.buttons["breakStart"].tap()
        // The short 1-second wait can pass between UI test polls, so accept the wait or the break here.
        // `testCancelWaitReturnsToFocusWithSameBreaksLeft` asserts `breakWait` with the 15-second standard wait.
        let waitOrBreak = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", ["breakWait", "breakCountdown"])).firstMatch
        XCTAssertTrue(waitOrBreak.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["breakCountdown"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["selection"].exists); XCTAssertTrue(app.buttons["end"].exists)
        captureReport(app, name: "break-countdown")
        XCTAssertTrue(app.buttons["resume"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["deadlineNotice"].exists); XCTAssertTrue(app.buttons["end"].exists)
        captureReport(app, name: "break-over")
        app.buttons["resume"].tap()
        let countdown = app.staticTexts["countdown"]
        XCTAssertTrue(app.buttons["breakStart"].waitForExistence(timeout: 5)); XCTAssertTrue(countdown.exists)
        XCTAssertEqual(app.staticTexts["breaksLeft"].label, "쉬는 시간 2번 남았어요")
        let paused = countdown.label
        expectation(for: NSPredicate(format: "label != %@", paused), evaluatedWith: countdown); waitForExpectations(timeout: 5)
    }
    func testCancelWaitReturnsToFocusWithSameBreaksLeft() {
        // The standard 15-second wait leaves time to cancel.
        let app = app(); app.buttons["start"].tap()
        XCTAssertTrue(app.buttons["breakStart"].waitForExistence(timeout: 5)); app.buttons["breakStart"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["breakWait"].waitForExistence(timeout: 5))
        captureReport(app, name: "break-wait")
        app.buttons["breakWaitCancel"].tap()
        XCTAssertTrue(app.buttons["breakStart"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["breaksLeft"].label, "쉬는 시간 3번 남았어요")
        XCTAssertFalse(app.staticTexts["breakCountdown"].exists)
    }
    func testThirdBreakLeavesOnlyEnd() {
        let app = shortBreaks(); app.buttons["start"].tap()
        for _ in 0..<3 {
            XCTAssertTrue(app.buttons["breakStart"].waitForExistence(timeout: 5)); app.buttons["breakStart"].tap()
            XCTAssertTrue(app.buttons["resume"].waitForExistence(timeout: 15)); app.buttons["resume"].tap()
        }
        XCTAssertTrue(app.staticTexts["countdown"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["end"].exists)
        XCTAssertFalse(app.buttons["breakStart"].exists); XCTAssertFalse(app.staticTexts["breaksLeft"].exists)
    }
    func testMissedDeadlineRecordsUnfocusedSession() {
        // The start tap leaves 10 seconds of focus: a break taken at once and never resumed reaches the deadline about 19 seconds after the tap.
        let app = shortBreaks("ending-soon")
        let start = app.buttons["start"], breakStart = app.buttons["breakStart"]
        XCTAssertTrue(start.waitForExistence(timeout: 8)); start.tap()
        // A loaded host can drop a synthesized tap. `start()` is synchronous, so a delivered tap has shown the session controls before `tap()` returns;
        // tap again only when they are absent and `start` still takes a tap. The 10 seconds count from the tap that starts the session.
        if !breakStart.waitForExistence(timeout: 5), !app.buttons["end"].exists, start.exists, start.isHittable { start.tap() }
        XCTAssertTrue(breakStart.waitForExistence(timeout: 5)); breakStart.tap()
        XCTAssertTrue(app.staticTexts["breakCountdown"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["resume"].waitForExistence(timeout: 10))
        let notice = app.staticTexts["deadlineNotice"]
        expectation(for: NSPredicate(format: "label CONTAINS '기록되지 않아요'"), evaluatedWith: notice); waitForExpectations(timeout: 15)
        captureReport(app, name: "deadline-notice")
        let summary = app.buttons["todaySummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 30))
        XCTAssertEqual(summary.label, "오늘 집중 0분 · 0회")
        XCTAssertFalse(app.descendants(matching: .any)["completion"].exists)
        // The summary appears while the timer screen swaps back, and a tap then can miss; tap again only when the history sheet
        // is not up and the summary still takes a tap (an open sheet covers it).
        expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: summary); waitForExpectations(timeout: 5)
        summary.tap()
        if !app.buttons["historyDone"].waitForExistence(timeout: 3), summary.isHittable { summary.tap() }
        XCTAssertTrue(app.staticTexts["시간 초과로 집중에서 제외"].waitForExistence(timeout: 5))
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
