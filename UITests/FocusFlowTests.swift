import XCTest
final class FocusFlowTests: XCTestCase {
    func app(_ mode: String = "approved", selected: Bool = true, extra: [String] = [], environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", mode] + (selected ? ["--selected"] : []) + extra
        app.launchEnvironment.merge(environment) { $1 }; app.launch(); return app
    }
    /// A `TZ` with a fixed offset in which launch falls between 12:00 and 12:30, computed like `FixtureEverydayLayer.noonCalendar(now:)`.
    /// The `expiring` and `ending-soon` sessions start about one session length before now, and today's history keeps a record on its start day,
    /// so a launch in the first minutes after local midnight would put that record on yesterday.
    private func noonZone() -> [String: String] {
        let seconds = Int(Date().timeIntervalSince1970) % 86_400, lateHalf = seconds % 3600 >= 1800
        return ["TZ": TimeZone(secondsFromGMT: (12 - seconds / 3600) * 3600 - (lateHalf ? 1800 : 0))!.identifier]
    }
    /// Today's history and the usage report open from the one-line summary at the bottom of the timer screen.
    private func openToday(_ app: XCUIApplication) {
        let summary = app.buttons["todaySummary"], done = app.buttons["historyDone"]
        XCTAssertTrue(summary.waitForExistence(timeout: ready))
        waitHittable(summary)
        summary.tap()
        // Retry only while the summary still takes a tap and the sheet has not appeared.
        if !done.waitForExistence(timeout: 3), summary.isHittable { summary.tap() }
        XCTAssertTrue(done.waitForExistence(timeout: ready))
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
        let app = app("expiring", environment: noonZone())
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
        XCTAssertTrue(app.buttons["lengthPicker"].waitForExistence(timeout: 5))
        app.buttons["lengthPicker"].tap(); app.buttons["45분"].tap()
        captureReport(app, name: "settings")
        app.buttons["settingsDone"].tap()
        XCTAssertTrue(app.staticTexts["countdown"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["countdown"].label, "남은 시간 45분 0초")
    }
    func testTimerControlsHaveComfortableTouchTargets() {
        let app = app()
        for identifier in ["selection", "settingsButton", "todaySummary"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: ready))
            XCTAssertGreaterThanOrEqual(button.frame.width, 44, identifier)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, identifier)
        }
        captureReport(app, name: "timer-touch-targets")
    }
    func testEndConfirmationKeepsContinuationVisibleInBottomSheet() {
        let app = app()
        app.buttons["start"].tap()
        XCTAssertTrue(app.buttons["end"].waitForExistence(timeout: 8))
        app.buttons["end"].tap()
        let keepFocusing = app.buttons["계속 집중하기"]
        XCTAssertTrue(keepFocusing.waitForExistence(timeout: 5))
        if keepFocusing.exists {
            XCTAssertTrue(keepFocusing.isHittable)
            let window = app.windows.firstMatch.frame
            XCTAssertGreaterThan(app.staticTexts["endConfirmation"].frame.minY, window.minY + window.height * 0.5)
            XCTAssertGreaterThan(keepFocusing.frame.minY, window.minY + window.height * 0.5)
            captureReport(app, name: "compact-end-confirmation")
            keepFocusing.tap()
            XCTAssertTrue(app.buttons["end"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["start"].exists)
        }
    }
    func testEndConfirmationAtLargestTextSizeKeepsContinuationReachable() {
        let app = app(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.buttons["start"].tap()
        let end = app.buttons["end"]
        XCTAssertTrue(end.waitForExistence(timeout: 8))
        for _ in 0..<4 where !end.isHittable { app.swipeUp() }
        end.tap()
        let keepFocusing = app.buttons["계속 집중하기"]
        XCTAssertTrue(keepFocusing.waitForExistence(timeout: 5))
        for _ in 0..<5 where !keepFocusing.isHittable { app.swipeUp() }
        XCTAssertTrue(keepFocusing.isHittable)
        captureReport(app, name: "end-confirmation-largest-text")
        keepFocusing.tap()
        XCTAssertTrue(end.waitForExistence(timeout: 5))
    }
    func testEditorSheetsOpenAtLargeHeight() {
        let app = app()
        app.buttons["settingsButton"].tap()
        let done = app.buttons["settingsDone"]
        XCTAssertTrue(done.waitForExistence(timeout: ready))
        XCTAssertLessThan(done.frame.minY, app.frame.height * 0.2)
        captureReport(app, name: "large-settings-sheet")
        done.tap()
        app.buttons["selection"].tap()
        let cancel = app.buttons["pickerCancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: ready))
        XCTAssertLessThan(cancel.frame.minY, app.frame.height * 0.2)
        captureReport(app, name: "large-selection-sheet")
        cancel.tap()
        XCTAssertTrue(app.buttons["start"].isEnabled)
    }
    func testSolidControlsPreserveTheFocusFlow() {
        let app = app(extra: ["--solid-controls"])
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: ready))
        captureReport(app, name: "solid-controls-timer")
        app.buttons["start"].tap()
        XCTAssertTrue(app.buttons["end"].waitForExistence(timeout: 8))
        app.buttons["end"].tap()
        XCTAssertTrue(app.buttons["계속 집중하기"].waitForExistence(timeout: 5))
        captureReport(app, name: "solid-controls-confirmation")
        app.buttons["계속 집중하기"].tap()
        XCTAssertTrue(app.buttons["end"].waitForExistence(timeout: 5))
    }
    func testEverydayUnsavedChangesCanBeKeptOrDiscardedFromSettings() {
        let app = app()
        _ = openEveryday(app)
        let add = app.buttons["everydayAddWindow"]
        waitHittable(add); add.tap()
        app.buttons["직접 정하기"].tap()
        XCTAssertTrue(app.otherElements["everydayWindow.1"].waitForExistence(timeout: 5))
        captureReport(app, name: "everyday-unsaved-footer")
        app.buttons["settingsDone"].tap()
        let discard = app.buttons["변경 버리기"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        captureReport(app, name: "everyday-unsaved-confirmation")
        let keepEditing = app.buttons["계속 편집"]
        guard keepEditing.waitForExistence(timeout: 5) else {
            XCTFail("Discard confirmation must expose the keep-editing action")
            return
        }
        XCTAssertTrue(keepEditing.isHittable)
        keepEditing.tap()
        XCTAssertTrue(app.otherElements["everydayWindow.1"].exists)
        app.buttons["settingsDone"].tap(); discard.tap()
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 5))
        _ = openEveryday(app)
        XCTAssertFalse(app.otherElements["everydayWindow.1"].exists)
        app.buttons["everydayAddWindow"].tap(); app.buttons["직접 정하기"].tap()
        XCTAssertTrue(app.buttons["everydayBack"].waitForExistence(timeout: 5))
        app.buttons["everydayBack"].tap()
        XCTAssertTrue(keepEditing.waitForExistence(timeout: 5))
        XCTAssertTrue(discard.isHittable)
        captureReport(app, name: "everyday-back-unsaved-confirmation")
        keepEditing.tap()
        XCTAssertTrue(app.otherElements["everydayWindow.1"].exists)
        app.buttons["everydayBack"].tap(); discard.tap()
        XCTAssertTrue(app.buttons["lengthPicker"].waitForExistence(timeout: 5))
        app.buttons["settingsDone"].tap()
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 5))
    }
    func testSlowSyntheticStartCompletesAfterFeedback() {
        let app = app(extra: ["--start-delay", "3"])
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: ready))
        captureReport(app, name: "slow-start-before")
        app.buttons["start"].tap()
        XCTAssertTrue(app.buttons["end"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["start"].exists)
        captureReport(app, name: "slow-start-active")
    }
    /// The break feedback with the given text; `--break-delay` keeps it on screen without blocking the app.
    private func breakProgress(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'breakProgress' AND label == %@", text)).firstMatch
    }
    /// A 5-second hold outlasts the roughly 1-second existence polling and the property reads that follow on a slow CI runner.
    func testSlowBreakRequestAndReturnShowProgressAndDisableActions() {
        let app = app(extra: ["--break-delay", "5"])
        let start = app.buttons["start"], breakStart = app.buttons["breakStart"], end = app.buttons["end"]
        XCTAssertTrue(start.waitForExistence(timeout: ready)); start.tap()
        XCTAssertTrue(breakStart.waitForExistence(timeout: ready)); breakStart.tap()
        XCTAssertTrue(breakProgress(app, "쉬는 시간을 준비하고 있어요").waitForExistence(timeout: 5))
        XCTAssertFalse(breakStart.isEnabled); XCTAssertFalse(end.isEnabled)
        captureReport(app, name: "break-request-pending")
        // A second tap on the disabled action does not request a second break.
        breakStart.tap()
        XCTAssertTrue(app.descendants(matching: .any)["breakWait"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["breaksLeft"].label, "다른 앱으로 나가면 집중으로 돌아가요. 이번 쉬는 시간을 쓰면 2번 남아요.")
        let cancel = app.buttons["breakWaitCancel"]
        XCTAssertTrue(cancel.isEnabled); cancel.tap()
        XCTAssertTrue(breakProgress(app, "집중으로 돌아가고 있어요").waitForExistence(timeout: 5))
        XCTAssertFalse(cancel.isEnabled); XCTAssertFalse(end.isEnabled)
        captureReport(app, name: "break-wait-return-pending")
        XCTAssertTrue(breakStart.waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["breaksLeft"].label, "쉬는 시간 3번 남았어요")
        XCTAssertTrue(breakStart.isEnabled); XCTAssertTrue(end.isEnabled)
    }
    /// The standard 15-second wait: `--break-timing short` leaves too little break time for two 5-second holds.
    func testSlowAutomaticBreakStartAndResumeShowProgress() {
        let app = app(extra: ["--break-delay", "5"])
        let start = app.buttons["start"], breakStart = app.buttons["breakStart"]
        XCTAssertTrue(start.waitForExistence(timeout: ready)); start.tap()
        XCTAssertTrue(breakStart.waitForExistence(timeout: ready)); breakStart.tap()
        XCTAssertTrue(breakProgress(app, "쉬는 시간을 시작하고 있어요").waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["breakWaitCancel"].isEnabled); XCTAssertFalse(app.buttons["end"].isEnabled)
        captureReport(app, name: "break-start-pending")
        let resume = app.buttons["resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 8)); XCTAssertTrue(resume.isEnabled)
        resume.tap()
        XCTAssertTrue(breakProgress(app, "집중으로 돌아가고 있어요").waitForExistence(timeout: 5))
        XCTAssertFalse(resume.isEnabled); XCTAssertFalse(app.buttons["end"].isEnabled)
        captureReport(app, name: "break-resume-pending")
        XCTAssertTrue(breakStart.waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["breaksLeft"].label, "쉬는 시간 2번 남았어요")
    }
    func testDiscardAlertAtLargestTextKeepsBothActionsReachable() {
        let app = app(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        _ = openEveryday(app)
        let toggle = app.switches["everydayToggle"]
        flip(toggle)
        let draftValue = toggle.value as? String
        XCTAssertTrue(app.buttons["everydaySave"].isHittable)
        captureReport(app, name: "everyday-unsaved-footer-largest-text")
        app.buttons["settingsDone"].tap()
        let keepEditing = app.buttons["계속 편집"], discard = app.buttons["변경 버리기"]
        XCTAssertTrue(keepEditing.waitForExistence(timeout: 5))
        XCTAssertTrue(keepEditing.isHittable)
        XCTAssertTrue(discard.isHittable)
        captureReport(app, name: "everyday-discard-largest-text")
        keepEditing.tap()
        XCTAssertEqual(toggle.value as? String, draftValue)
        XCTAssertTrue(app.staticTexts["everydayUnsavedChanges"].isHittable)
        app.buttons["everydayBack"].tap()
        XCTAssertTrue(keepEditing.waitForExistence(timeout: 5))
        XCTAssertTrue(discard.isHittable)
        discard.tap()
        XCTAssertTrue(app.buttons["lengthPicker"].waitForExistence(timeout: 5))
        app.buttons["settingsDone"].tap()
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 5))
    }
    func testEverydayEmptySelectionShowsLocalValidation() {
        let app = app()
        _ = openEveryday(app)
        flip(app.switches["everydayToggle"])
        let issue = app.staticTexts["everydaySelectionIssue"]
        for _ in 0..<4 where !issue.isHittable { app.swipeUp() }
        XCTAssertTrue(issue.isHittable)
        let save = app.buttons["everydaySave"]
        XCTAssertTrue(save.exists); XCTAssertFalse(save.isEnabled)
        captureReport(app, name: "everyday-inline-selection-error")
    }
    func testOnboardingAtLargestTextSizeKeepsNavigationAndContentReachable() {
        let app = app("onboarding", selected: false, extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let next = app.buttons["onboardingNext"]
        XCTAssertTrue(next.waitForExistence(timeout: ready))
        XCTAssertTrue(next.isHittable)
        let privacy = app.staticTexts["데이터는 기기에만 저장돼요"]
        for _ in 0..<5 where !privacy.isHittable { app.swipeUp() }
        XCTAssertTrue(privacy.isHittable)
        XCTAssertTrue(next.isHittable)
        captureReport(app, name: "onboarding-largest-text-scrolled")
        next.tap()
        let authorize = app.buttons["authorize"]
        for _ in 0..<5 where !authorize.isHittable { app.swipeUp() }
        XCTAssertTrue(authorize.isHittable)
        captureReport(app, name: "onboarding-permission-largest-text")
    }
    func testHistoryDistinguishesCompletedSessionAtConfiguredLength() {
        let app = app("history", extra: ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"])
        XCTAssertTrue(app.buttons["todaySummary"].waitForExistence(timeout: ready))
        let summary = app.buttons["todaySummary"].label
        captureReport(app, name: "timer-summary-mixed-history")
        openToday(app)
        XCTAssertTrue(app.staticTexts["historySummary"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["historySummary"].label, summary)
        XCTAssertEqual(summary, "오늘 집중 1시간 15분 · 2회")
        XCTAssertTrue(app.staticTexts["25분 완료"].exists)
        XCTAssertTrue(app.staticTexts["50분 완료"].exists)
        XCTAssertEqual(app.images.matching(identifier: "completedSessionIcon").count, 2)
        XCTAssertTrue(app.staticTexts["집중 종료"].exists)
        XCTAssertTrue(app.staticTexts["시간 초과로 집중에서 제외"].exists)
        XCTAssertFalse(app.staticTexts["50분 만료"].exists)
        captureReport(app, name: "history-completed-and-ended")
    }
    func testEmptyHistoryShowsZeroSummary() {
        let app = app(extra: ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"])
        XCTAssertTrue(app.buttons["todaySummary"].waitForExistence(timeout: ready))
        let summary = app.buttons["todaySummary"].label
        openToday(app)
        XCTAssertTrue(app.staticTexts["historySummary"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["historySummary"].label, summary)
        XCTAssertEqual(summary, "오늘 집중 0분 · 0회")
        XCTAssertTrue(app.staticTexts["아직 기록이 없어요."].exists)
        XCTAssertTrue(app.staticTexts["historyStreak"].waitForExistence(timeout: ready))
        XCTAssertEqual(app.staticTexts["historyStreak"].label, "연속 집중 0일")
        captureReport(app, name: "history-empty")
    }
    /// `streak` seeds completed sessions on today and the 2 days before it, and an older completed day behind a day without one.
    /// The seed and the model read the launch time zone, and just after local midnight the run ends yesterday, so the number is 3 at every launch time.
    func testHistoryShowsTheStreakOfTheSeededDays() {
        let app = app("streak", extra: ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"], environment: noonZone())
        openToday(app)
        let summary = app.staticTexts["historySummary"], streak = app.staticTexts["historyStreak"]
        XCTAssertTrue(summary.waitForExistence(timeout: ready)); XCTAssertTrue(streak.waitForExistence(timeout: ready))
        XCTAssertEqual(summary.label, "오늘 집중 25분 · 1회")
        XCTAssertEqual(streak.label, "연속 집중 3일")
        XCTAssertGreaterThanOrEqual(streak.frame.minY, summary.frame.maxY, "the streak line is below the summary")
        XCTAssertFalse(app.buttons["historyStreak"].exists, "the streak line is plain text, not a control")
        captureReport(app, name: "history-streak")
    }
    /// The streak belongs to the history sheet only: the idle screen, a running session, the break screen and the completion card never show it.
    func testTimerScreenNeverShowsTheStreak() {
        let app = shortBreaks("streak", lenient: true, environment: noonZone())
        let start = app.buttons["start"], breakStart = app.buttons["breakStart"], streak = app.descendants(matching: .any)["historyStreak"]
        XCTAssertTrue(start.waitForExistence(timeout: ready)); XCTAssertTrue(app.buttons["todaySummary"].waitForExistence(timeout: ready))
        XCTAssertFalse(streak.exists, "idle")
        XCTAssertFalse(app.staticTexts["연속 집중 3일"].exists, "idle")
        waitHittable(start); start.tap()
        XCTAssertTrue(breakStart.waitForExistence(timeout: ready))
        XCTAssertFalse(streak.exists, "during a session")
        waitHittable(breakStart); breakStart.tap()
        XCTAssertTrue(app.otherElements["breakScreen"].waitForExistence(timeout: ready))
        XCTAssertFalse(streak.exists, "waiting for a break")
        XCTAssertTrue(breakStarted(app).waitForExistence(timeout: ready))
        XCTAssertFalse(streak.exists, "on break")
        app.terminate()
        let completed = self.app("expiring", environment: noonZone())
        XCTAssertTrue(completed.descendants(matching: .any)["completion"].waitForExistence(timeout: ready))
        XCTAssertFalse(completed.descendants(matching: .any)["historyStreak"].exists, "completion card")
        XCTAssertFalse(completed.staticTexts["연속 집중 1일"].exists, "completion card")
    }
    /// `history-failure` keeps every history read failing, so no refresh between the queries can replace the error state.
    /// The recovery after a successful read is `FocusModelTests.testHistoryRetryClearsTheErrorAndLoadsRecordsAfterAFailedRead`.
    func testHistoryErrorDoesNotShowSuccessfulSummaryOrEmptyState() {
        let app = app("history-failure")
        let error = "기록을 불러오지 못했어요. 다시 확인해 주세요. 진행 중인 세션은 종료할 수 있어요."
        openToday(app)
        let message = app.staticTexts["historyError"]
        XCTAssertTrue(message.waitForExistence(timeout: ready))
        XCTAssertEqual(message.label, error)
        XCTAssertFalse(app.staticTexts["historySummary"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["historyStreak"].exists)
        XCTAssertFalse(app.staticTexts["아직 기록이 없어요."].exists)
        XCTAssertTrue(app.buttons["historyRetry"].exists)
        captureReport(app, name: "history-error")
        app.buttons["historyRetry"].tap()
        XCTAssertFalse(app.staticTexts["historySummary"].waitForExistence(timeout: 3))
        XCTAssertTrue(message.exists)
        XCTAssertEqual(message.label, error)
        XCTAssertFalse(app.descendants(matching: .any)["historyStreak"].exists)
        XCTAssertFalse(app.staticTexts["아직 기록이 없어요."].exists)
    }
    func testKoreanSystemTimePicker() {
        let app = app(extra: ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"])
        _ = openEveryday(app)
        let picker = app.datePickers["everydayRangeStart"]
        XCTAssertTrue(picker.waitForExistence(timeout: ready))
        picker.tap()
        captureReport(app, name: "korean-system-time-picker")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "korean-system-time-picker-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.firstMatch.waitForExistence(timeout: ready))
        let values = wheels.allElementsBoundByIndex.compactMap { $0.value as? String }
        XCTAssertTrue(values.contains { $0.contains("시") }, values.description)
        XCTAssertTrue(values.contains { $0.contains("분") }, values.description)
    }
    /// The everyday layer opens from its row in the settings sheet.
    private func openEveryday(_ app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: ready)); app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.buttons["everydayRow"].waitForExistence(timeout: ready)); app.buttons["everydayRow"].tap()
        let status = app.staticTexts["everydayStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: ready))
        return status
    }
    /// Precondition waits only absorb CI runner stalls (about 17 s on one wait, 20 s to synthesize one tap and 34 s at launch were measured),
    /// so they share this timeout; assertions about behavior keep their own.
    private let ready: TimeInterval = 30
    private func waitHittable(_ element: XCUIElement) {
        expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: element); waitForExpectations(timeout: ready)
    }
    /// A `Toggle` in a `Form` can take the tap on its label without flipping; the inner switch is the fallback.
    private func flip(_ toggle: XCUIElement) {
        let before = toggle.value as? String
        toggle.tap()
        if toggle.value as? String == before { toggle.switches.firstMatch.tap() }
        XCTAssertNotEqual(toggle.value as? String, before)
    }
    func testEverydayPreviewShowsDraftSeparatelyFromStoredSchedule() {
        let app = app(extra: ["--everyday-fixture", "preview"])
        _ = openEveryday(app)
        let draftClock = app.descendants(matching: .any)["everydayDraftClock"]
        scrollEveryday(app, to: draftClock)
        XCTAssertEqual(draftClock.label, "하루 일정표")
        captureReport(app, name: "everyday-preview-clock")
        let draft = app.staticTexts["everydayDraftSegment.1"]
        scrollEveryday(app, to: draft)
        XCTAssertEqual(draft.label, "08:00부터 12:00까지, 제한")
        XCTAssertEqual(app.staticTexts["everydayDraftSegment.2"].label, "12:00부터 13:00까지, 해제")
        XCTAssertEqual(app.staticTexts["everydayDraftSegment.3"].label, "13:00부터 18:00까지, 제한")
        captureReport(app, name: "everyday-preview")
        let stored = app.buttons["저장된 일정"]
        scrollEveryday(app, to: stored); stored.tap()
        let storedClock = app.descendants(matching: .any)["everydayStoredClock"]
        scrollEveryday(app, to: storedClock)
        XCTAssertEqual(storedClock.label, "하루 일정표")
        let storedFirst = app.staticTexts["everydayStoredSegment.1"]
        scrollEveryday(app, to: storedFirst)
        XCTAssertEqual(storedFirst.label, "08:00부터 12:00까지, 제한")
        captureReport(app, name: "everyday-preview-stored")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "everyday-preview-accessibility"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        // The two clock rows sit between the stored rows and the windows section; a button under the navigation bar is hittable but takes no tap.
        let delete = app.buttons["삭제"].firstMatch, belowBar = app.navigationBars["매일 제한"].frame.maxY + 12
        for _ in 0..<8 where !(delete.isHittable && delete.frame.minY > belowBar) { app.swipeDown() }
        delete.tap()
        scrollEveryday(app, to: draft)
        XCTAssertEqual(draft.label, "08:00부터 18:00까지, 제한")
        scrollEveryday(app, to: storedFirst)
        XCTAssertEqual(storedFirst.label, "08:00부터 12:00까지, 제한")
        captureReport(app, name: "everyday-preview-unsaved-comparison")
        app.buttons["everydaySave"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["everydaySaveSuccess"].waitForExistence(timeout: 5))
        XCTAssertEqual(storedFirst.label, "08:00부터 18:00까지, 제한")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["everydayRow"].tap()
        scrollEveryday(app, to: draft)
        XCTAssertEqual(draft.label, "08:00부터 18:00까지, 제한")
    }
    func testEverydayPreviewRejectsOverlappingDraftWithoutReplacingStoredSchedule() {
        let app = app(extra: ["--everyday-fixture", "preview"])
        _ = openEveryday(app)
        let add = app.buttons["everydayAddWindow"]
        scrollEveryday(app, to: add); add.tap()
        let lunch = app.buttons["점심"]
        if !lunch.waitForExistence(timeout: 3), add.isHittable { add.tap() }
        XCTAssertTrue(lunch.waitForExistence(timeout: 5)); lunch.tap()
        XCTAssertTrue(app.staticTexts["everydayWindowsIssue"].waitForExistence(timeout: 5))
        let invalid = app.staticTexts["everydayDraftInvalid"]
        scrollEveryday(app, to: invalid)
        XCTAssertTrue(invalid.isHittable)
        XCTAssertFalse(app.staticTexts["everydayDraftSegment.1"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["everydayDraftClock"].exists, "an invalid draft shows no clock")
        XCTAssertFalse(app.buttons["everydaySave"].isEnabled)
        let stored = app.buttons["저장된 일정"]
        scrollEveryday(app, to: stored); stored.tap()
        XCTAssertTrue(app.descendants(matching: .any)["everydayStoredClock"].waitForExistence(timeout: 5))
        let storedFirst = app.staticTexts["everydayStoredSegment.1"]
        scrollEveryday(app, to: storedFirst)
        XCTAssertEqual(storedFirst.label, "08:00부터 12:00까지, 제한")
        captureReport(app, name: "everyday-preview-invalid")
    }
    func testEverydayPreviewAtLargestText() {
        let app = app(extra: ["--everyday-fixture", "preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        _ = openEveryday(app)
        let first = app.staticTexts["everydayDraftSegment.1"], second = app.staticTexts["everydayDraftSegment.2"], third = app.staticTexts["everydayDraftSegment.3"]
        let clock = app.descendants(matching: .any)["everydayDraftClock"]
        scrollEveryday(app, to: clock)
        // The large save-status area covers more than scrollEveryday's bottom margin; bring the whole clock above it for the capture.
        let clockTop = app.navigationBars["매일 제한"].frame.maxY + 12
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        let end = start.withOffset(CGVector(dx: 0, dy: clockTop - clock.frame.minY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertGreaterThanOrEqual(clock.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(clock.frame.maxX, app.frame.maxX)
        XCTAssertGreaterThanOrEqual(clock.frame.minY, app.navigationBars["매일 제한"].frame.maxY)
        let visible = app.buttons["everydaySave"].frame.minY - app.navigationBars["매일 제한"].frame.maxY
        XCTAssertLessThanOrEqual(clock.frame.height, visible, "the whole clock fits between the navigation bar and the save button")
        captureReport(app, name: "everyday-preview-clock-largest-text")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertLessThan(clock.frame.midY, first.frame.minY, "the clock sits above the text rows")
        scrollEveryday(app, to: first)
        XCTAssertEqual(first.label, "08:00부터 12:00까지, 제한")
        captureReport(app, name: "everyday-preview-largest-text")
        scrollEveryday(app, to: third)
        XCTAssertLessThan(first.frame.minY, second.frame.minY)
        XCTAssertLessThan(second.frame.minY, third.frame.minY)
        XCTAssertTrue(app.buttons["everydaySave"].isHittable)
        captureReport(app, name: "everyday-preview-largest-text-end")
    }
    func testEverydayWindowTimesShareOneLine() {
        let app = app(extra: ["--everyday-fixture", "preview"])
        _ = openEveryday(app)
        let (start, end) = windowTimes(app, row: 1)
        XCTAssertLessThanOrEqual(abs(start.frame.midY - end.frame.midY), 4, "start \(start.frame), end \(end.frame)")
        XCTAssertLessThanOrEqual(start.frame.maxX, end.frame.minX)
        captureReport(app, name: "everyday-window-one-line")
    }
    func testEverydayWindowTimesWrapAtLargestText() {
        let app = app(extra: ["--everyday-fixture", "preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        _ = openEveryday(app)
        let (start, end) = windowTimes(app, row: 1)
        XCTAssertFalse(start.frame.intersects(end.frame), "start \(start.frame), end \(end.frame)")
        let window = app.windows.firstMatch.frame
        for picker in [start, end] {
            XCTAssertGreaterThanOrEqual(picker.frame.minX, window.minX)
            XCTAssertLessThanOrEqual(picker.frame.maxX, window.maxX)
        }
        captureReport(app, name: "everyday-window-largest-text")
    }
    /// The start and end pickers of one window row; the pickers carry no label of their own, the row's text does.
    private func windowTimes(_ app: XCUIApplication, row: Int) -> (start: XCUIElement, end: XCUIElement) {
        let window = app.otherElements["everydayWindow.\(row)"]
        let start = window.datePickers.element(boundBy: 0), end = window.datePickers.element(boundBy: 1)
        scrollEveryday(app, to: end)
        XCTAssertEqual(window.datePickers.count, 2)
        XCTAssertTrue(start.exists, app.debugDescription)
        return (start, end)
    }
    private func scrollEveryday(_ app: XCUIApplication, to element: XCUIElement) {
        let top = app.navigationBars["매일 제한"].frame.maxY + 12
        let bottom = app.buttons["everydaySave"].frame.minY - 80
        for _ in 0..<20 {
            if element.isHittable, element.frame.midY > top, element.frame.maxY < bottom { break }
            let down = element.exists && element.frame.midY < top
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.35 : 0.60))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.60 : 0.35))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
    }
    func testEverydayLayerTurnsOnFromSettings() {
        let app = app()
        let status = openEveryday(app)
        XCTAssertEqual(status.label, "꺼져 있어요")
        let selection = app.buttons["everydaySelection"], fixtureSelect = app.buttons["fixtureSelect"]
        // A tap while the everyday screen still slides in can miss; tap again only when the sheet did not open and the row still takes a tap.
        waitHittable(selection)
        selection.tap()
        // A late second tap only presents the same sheet again.
        if !fixtureSelect.waitForExistence(timeout: 3), selection.isHittable { selection.tap() }
        XCTAssertTrue(fixtureSelect.waitForExistence(timeout: ready))
        waitHittable(fixtureSelect)
        fixtureSelect.tap(); app.buttons["pickerSave"].tap()
        // An empty draft makes the save below refuse, so a missed fixture tap fails here instead.
        expectation(for: NSPredicate(format: "label CONTAINS '앱 1개'"), evaluatedWith: app.buttons["everydaySelection"]); waitForExpectations(timeout: ready)
        // The count follows the draft while the sheet is still up, so wait for the sheet to go and the switch to take a tap.
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: fixtureSelect); waitForExpectations(timeout: ready)
        let toggle = app.switches["everydayToggle"]
        waitHittable(toggle)
        flip(toggle)
        app.buttons["everydaySave"].tap()
        expectation(for: NSPredicate(format: "label BEGINSWITH '켜져 있어요' OR label BEGINSWITH '지금 제한하고 있어요'"), evaluatedWith: status)
        waitForExpectations(timeout: 5)
        let refusal = app.staticTexts["everydayRefusal"]
        XCTAssertFalse(refusal.exists, refusal.exists ? refusal.label : "")
        let success = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'everydaySaveSuccess' AND label CONTAINS '저장했어요' ")).firstMatch
        XCTAssertTrue(success.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["everydaySave"].isEnabled)
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
        // The refusal names the failed condition and points to the off-for-today action, which is offered inside the range.
        XCTAssertTrue(refusal.label.hasPrefix("제한 시간에는 매일 제한을 끌 수 없어요."), refusal.label)
        XCTAssertTrue(refusal.label.hasSuffix("‘오늘만 끄기’를 누르면 오늘은 제한을 끌 수 있어요."), refusal.label)
        XCTAssertTrue(status.label.hasPrefix("지금 제한하고 있어요"), status.label)
        XCTAssertTrue(app.buttons["everydayOffToday"].exists)
    }
    func testEverydayOffForTodayWaitsCanBeCancelledAndThenTurnsTheLayerOff() {
        // A shortened synthetic wait; nothing reaches real restrictions.
        let app = app(extra: ["--everyday-fixture", "blocking", "--everyday-off-wait", "8"])
        let status = openEveryday(app)
        XCTAssertTrue(status.label.hasPrefix("지금 제한하고 있어요"), status.label)
        let action = app.buttons["everydayOffToday"], wait = app.descendants(matching: .any)["everydayOffWait"], cancel = app.buttons["everydayOffCancel"]
        XCTAssertTrue(action.waitForExistence(timeout: ready)); waitHittable(action)
        action.tap()
        XCTAssertTrue(wait.waitForExistence(timeout: ready))
        XCTAssertNotNil(wait.label.range(of: #"^\d+초 뒤에 오늘 매일 제한이 꺼져요$"#, options: .regularExpression), wait.label)
        captureReport(app, name: "everyday-off-wait")
        cancel.tap()
        XCTAssertTrue(action.waitForExistence(timeout: ready))
        XCTAssertFalse(wait.exists)
        XCTAssertTrue(status.label.hasPrefix("지금 제한하고 있어요"), "a cancelled wait changes nothing: \(status.label)")
        waitHittable(action)
        action.tap()
        XCTAssertTrue(wait.waitForExistence(timeout: ready))
        expectation(for: NSPredicate(format: "label BEGINSWITH '오늘은 꺼 두었어요 · 내일 ' AND label ENDSWITH '부터 다시 제한해요'"), evaluatedWith: status)
        waitForExpectations(timeout: ready)
        XCTAssertFalse(action.exists, "once a day")
        XCTAssertFalse(app.staticTexts["everydayRefusal"].exists)
        captureReport(app, name: "everyday-off-today")
    }
    func testEverydayOffForTodayWaitStopsInTheBackgroundAndWhenSettingsClose() {
        // The same 8-second synthetic wait; nothing reaches real restrictions.
        let app = app(extra: ["--everyday-fixture", "blocking", "--everyday-off-wait", "8"])
        var status = openEveryday(app)
        let action = app.buttons["everydayOffToday"], wait = app.descendants(matching: .any)["everydayOffWait"]
        XCTAssertTrue(action.waitForExistence(timeout: ready)); waitHittable(action)
        action.tap()
        XCTAssertTrue(wait.waitForExistence(timeout: ready))
        // Leaving the app cancels the wait, as it cancels the M2 wait.
        XCUIDevice.shared.press(.home)
        expectation(for: NSPredicate { _, _ in app.state != .runningForeground }, evaluatedWith: nil)
        waitForExpectations(timeout: ready)
        app.activate()
        XCTAssertTrue(action.waitForExistence(timeout: ready), "the cancelled wait gives the action back")
        XCTAssertFalse(wait.exists)
        XCTAssertTrue(status.label.hasPrefix("지금 제한하고 있어요"), "a cancelled wait changes nothing: \(status.label)")
        // Closing the settings sheet cancels it too: the layer still blocks after the wait would have ended.
        waitHittable(action); action.tap()
        XCTAssertTrue(wait.waitForExistence(timeout: ready))
        app.buttons["settingsDone"].tap()
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: ready))
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "past the wait end")], timeout: 10)
        status = openEveryday(app)
        XCTAssertTrue(status.label.hasPrefix("지금 제한하고 있어요"), status.label)
        XCTAssertTrue(action.waitForExistence(timeout: ready))
    }
    func testThreeWindowsAreTheLimit() {
        let app = app()
        _ = openEveryday(app)
        let add = app.buttons["everydayAddWindow"]
        for template in ["점심", "등교", "하교"] {
            // One-line window rows can leave the button under the save area, which takes the tap.
            scrollEveryday(app, to: add)
            XCTAssertTrue(add.isEnabled, template); add.tap()
            XCTAssertTrue(app.buttons[template].waitForExistence(timeout: 5), template); app.buttons[template].tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["everydayWindow.3"].waitForExistence(timeout: 5))
        // Three window rows push the button below the fold, and the Form renders only visible rows.
        for _ in 0..<4 where !add.exists { app.swipeUp() }
        XCTAssertTrue(add.exists)
        XCTAssertFalse(add.isEnabled)
    }
    func testTimerScreenShowsTheEverydayStatusRowWhileTheLayerBlocks() {
        let app = app(extra: ["--everyday-fixture", "blocking"])
        let row = app.buttons["everydayStatusRow"]
        XCTAssertTrue(row.waitForExistence(timeout: ready))
        let time = assertBlockingLine(row)
        for identifier in ["start", "settingsButton", "todaySummary"] { XCTAssertTrue(app.buttons[identifier].exists, identifier) }
        // The settings controls stay in the settings sheet; only the one-line row is on the timer screen.
        for identifier in ["everydayRow", "everydayStatus", "everydayToggle", "everydaySave"] {
            XCTAssertFalse(app.descendants(matching: .any)[identifier].exists, identifier)
        }
        XCTAssertGreaterThanOrEqual(row.frame.minY, app.staticTexts["restrictionSummary"].frame.maxY)
        XCTAssertLessThanOrEqual(row.frame.maxY, app.buttons["todaySummary"].frame.minY)
        captureReport(app, name: "everyday-status-row-idle")
        let status = openEverydayFromRow(app, row)
        // The row and the settings screen read the same planned end in the engine's calendar.
        XCTAssertEqual(status.label, "지금 제한하고 있어요 · \(time)")
        // Back returns to the settings list, and closing the sheet returns to the timer.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let settingsRow = app.buttons["everydayRow"]
        XCTAssertTrue(settingsRow.waitForExistence(timeout: ready)); waitHittable(settingsRow)
        app.buttons["settingsDone"].tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: ready)); waitHittable(row)
    }
    func testCompletionCardShowsTheEverydayStatusRowBelowTheReleaseNote() {
        let app = app("expiring", extra: ["--everyday-fixture", "blocking"])
        let completion = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'completion' AND label CONTAINS '집중을 마쳤어요'")).firstMatch
        XCTAssertTrue(completion.waitForExistence(timeout: 15))
        let row = app.buttons["everydayStatusRow"]
        XCTAssertTrue(row.waitForExistence(timeout: ready))
        let time = assertBlockingLine(row)
        XCTAssertGreaterThanOrEqual(row.frame.minY, app.staticTexts["releaseDelayNote"].frame.maxY)
        XCTAssertLessThanOrEqual(row.frame.maxY, app.buttons["completionDismiss"].frame.minY)
        captureReport(app, name: "everyday-status-row-completion")
        XCTAssertEqual(openEverydayFromRow(app, row).label, "지금 제한하고 있어요 · \(time)")
    }
    func testEverydayStatusRowIsHiddenDuringASessionAndOnBreak() {
        // The standard timing: a slow query can outlast the 3-second short break, and the row must be checked while the break runs.
        let app = app(extra: ["--everyday-fixture", "blocking"])
        let row = app.descendants(matching: .any)["everydayStatusRow"], start = app.buttons["start"]
        XCTAssertTrue(row.waitForExistence(timeout: ready)); waitHittable(start)
        start.tap()
        XCTAssertTrue(app.buttons["breakStart"].waitForExistence(timeout: ready))
        XCTAssertFalse(row.exists)
        app.buttons["breakStart"].tap()
        XCTAssertTrue(app.otherElements["breakScreen"].waitForExistence(timeout: 15))
        XCTAssertFalse(row.exists)
        XCTAssertTrue(app.staticTexts["breakCountdown"].waitForExistence(timeout: 30))
        XCTAssertFalse(row.exists)
    }
    func testEverydayStatusRowIsHiddenWhileTheLayerDoesNotBlock() {
        // No schedule; an enabled layer that the fixture's noon puts inside the 12:00-13:00 lunch window; the same layer turned off.
        let cases: [(extra: [String], settingsLine: String)] = [
            ([], "꺼져 있어요"), (["--everyday-fixture", "preview"], "켜져 있어요 · 13:00부터 제한해요"), (["--everyday-fixture", "off"], "꺼져 있어요")
        ]
        for (extra, settingsLine) in cases {
            let app = app(extra: extra)
            // The settings row proves that the model read this status before the timer screen is checked.
            XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: ready)); app.buttons["settingsButton"].tap()
            let settingsRow = app.buttons["everydayRow"]
            XCTAssertTrue(settingsRow.waitForExistence(timeout: ready))
            XCTAssertTrue(settingsRow.label.contains(settingsLine), "\(extra): \(settingsRow.label)")
            app.buttons["settingsDone"].tap()
            expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: settingsRow); waitForExpectations(timeout: ready)
            XCTAssertTrue(app.buttons["start"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["everydayStatusRow"].exists, "\(extra)")
            app.terminate()
        }
    }
    func testEverydayStatusRowAtLargestTextStaysReachable() {
        let app = app(extra: ["--everyday-fixture", "blocking", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let row = app.buttons["everydayStatusRow"]
        XCTAssertTrue(row.waitForExistence(timeout: ready))
        _ = assertBlockingLine(row)
        for _ in 0..<3 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable)
        captureReport(app, name: "everyday-status-row-largest-text")
    }
    /// Asserts the blocking copy of the timer's everyday row and returns its planned end, "HH:MM까지".
    private func assertBlockingLine(_ row: XCUIElement) -> String {
        XCTAssertNotNil(row.label.range(of: #"^매일 제한 중 · \d{2}:\d{2}까지$"#, options: .regularExpression), row.label)
        return row.label.components(separatedBy: " · ").last ?? ""
    }
    /// The timer's everyday row opens the settings sheet with the everyday screen already pushed.
    private func openEverydayFromRow(_ app: XCUIApplication, _ row: XCUIElement) -> XCUIElement {
        let status = app.staticTexts["everydayStatus"]
        waitHittable(row)
        row.tap()
        // Retry only while the row still takes a tap and the sheet has not appeared.
        if !status.waitForExistence(timeout: 3), row.isHittable { row.tap() }
        XCTAssertTrue(status.waitForExistence(timeout: ready))
        return status
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
    func testFocusGuideAtLargestTextScrollsToTheEnd() {
        let app = app(extra: ["--focus-filter-refusal", "busy", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: ready)); app.buttons["settingsButton"].tap()
        // At the largest text the guide row sits below the fold of the settings sheet.
        let row = app.buttons["focusGuideRow"]
        for _ in 0..<12 where !(row.exists && row.isHittable) { dragUp(app) }
        waitHittable(row); row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["focusGuide"].waitForExistence(timeout: ready))
        captureReport(app, name: "focus-guide-largest-text-1")
        let refusal = app.staticTexts["focusFilterRefusal"]
        let last = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "긴급 알림은 iOS 설정을 따라요")).firstMatch
        var sawRefusal = refusal.exists, page = 1
        while !(last.exists && last.isHittable), page < 40 {
            dragUp(app); page += 1
            sawRefusal = sawRefusal || refusal.exists
            captureReport(app, name: "focus-guide-largest-text-\(page)")
        }
        XCTAssertTrue(sawRefusal, "the stored refusal shows while scrolling the guide")
        XCTAssertTrue(last.isHittable, "the last guide row comes into view")
        // The row is hittable while its detail is still below the fold; one more drag shows the end of the list.
        dragUp(app)
        captureReport(app, name: "focus-guide-largest-text-end")
    }
    /// One slow drag that scrolls the visible list up by about half of the screen, so consecutive captures overlap.
    private func dragUp(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)), withVelocity: .slow, thenHoldForDuration: 0.1)
    }
    func testCompletionCopyUsesSessionLength() {
        let app = app("expiring", extra: ["--length", "40"])
        // The Label exposes its icon and text under the same identifier, in a runtime-dependent order (iOS 26.5 lists the icon, labelled "Selected", first).
        let completion = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'completion' AND label CONTAINS '집중을 마쳤어요'")).firstMatch
        XCTAssertTrue(completion.waitForExistence(timeout: 15))
        XCTAssertTrue(completion.label.contains("40분"), completion.label); XCTAssertFalse(completion.label.contains("25분"), completion.label)
    }
    func testReloadRecreatesReportContentWithinSameDay() {
        let app = app(extra: ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"])
        openReport(app)
        let generation = app.staticTexts["reportGeneration"]
        XCTAssertTrue(generation.waitForExistence(timeout: 8))
        let firstInstance = generation.label
        let reload = app.navigationBars.buttons["reportReload"]
        XCTAssertTrue(reload.waitForExistence(timeout: 5))
        reload.tap()
        let changed = NSPredicate(format: "label != %@", firstInstance)
        expectation(for: changed, evaluatedWith: generation)
        waitForExpectations(timeout: 5)
        captureReport(app, name: "report-toolbar-reloaded")
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
        XCTAssertTrue(app.buttons["lengthPicker"].waitForExistence(timeout: 5))
        app.buttons["lengthPicker"].tap(); app.buttons["40분"].tap()
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
    /// Access that is not known yet keeps the timer screen; the start tap requests access and starts only after the value reads approved.
    func testCheckingAccessKeepsTheStartControlAsTheRecovery() {
        let app = app("checking")
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 8)); XCTAssertTrue(app.buttons["start"].isEnabled)
        XCTAssertTrue(app.staticTexts["startBlocker"].exists); XCTAssertFalse(app.buttons["authorize"].exists)
        captureReport(app, name: "access-checking")
        app.buttons["start"].tap()
        XCTAssertTrue(app.buttons["end"].waitForExistence(timeout: 8))
    }
    func testCheckingAccessAtLargestTextSizeKeepsTheStartControlReachable() {
        let app = app("checking", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let start = app.buttons["start"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        for _ in 0..<4 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.isHittable); XCTAssertTrue(start.isEnabled)
        captureReport(app, name: "access-checking-largest-text")
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
    /// `lenient` is for a test that never reaches the deadline: `short-lenient` keeps the short waits and break, with the standard slack and
    /// a 5-minute stale-wait grace, so a query that holds the app's main thread for tens of seconds cannot make the automatic break start late enough to be refused.
    private func shortBreaks(_ mode: String = "approved", lenient: Bool = false, environment: [String: String] = [:]) -> XCUIApplication {
        app(mode, extra: ["--break-timing", lenient ? "short-lenient" : "short"], environment: environment)
    }
    /// The break countdown or, after the break, the deadline notice: the break started.
    /// A slow CI runner can spend several seconds on one query, which outlasts the 3-second short break,
    /// so short-timing tests assert this outcome; the standard-timing tests assert the countdown itself.
    private func breakStarted(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", ["breakCountdown", "deadlineNotice"])).firstMatch
    }
    func testDedicatedBreakScreenCanReturnToFocusBeforeBreakEnds() {
        let app = app(); app.buttons["start"].tap()
        XCTAssertTrue(app.buttons["breakStart"].waitForExistence(timeout: 5))
        let clock = app.staticTexts["countdown"].frame
        XCTAssertGreaterThan(app.buttons["breakStart"].frame.minY - clock.maxY, 80)
        app.buttons["breakStart"].tap()
        XCTAssertTrue(app.otherElements["breakScreen"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["countdown"].exists)
        XCTAssertTrue(app.staticTexts["breakCountdown"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.buttons["resume"].exists)
        captureReport(app, name: "break-early-return-initial")
        let breakClock = app.staticTexts["breakCountdown"], initialBreak = app.staticTexts["breakCountdown"].label
        expectation(for: NSPredicate(format: "label != %@", initialBreak), evaluatedWith: breakClock)
        waitForExpectations(timeout: 5)
        let end = app.buttons["end"]
        XCTAssertTrue(end.isHittable); XCTAssertTrue(app.frame.contains(end.frame))
        end.tap()
        XCTAssertTrue(app.buttons["종료하기"].waitForExistence(timeout: 5))
        if app.buttons["계속 집중하기"].exists { app.buttons["계속 집중하기"].tap() }
        else { app.otherElements["PopoverDismissRegion"].tap() }
        XCTAssertTrue(app.buttons["resume"].waitForExistence(timeout: 5))
        captureReport(app, name: "break-early-return")
        app.buttons["resume"].tap()
        XCTAssertTrue(app.staticTexts["countdown"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.otherElements["breakScreen"].exists)
        XCTAssertEqual(app.staticTexts["breaksLeft"].label, "쉬는 시간 2번 남았어요")
        let focusClock = app.staticTexts["countdown"], initialFocus = app.staticTexts["countdown"].label
        expectation(for: NSPredicate(format: "label != %@", initialFocus), evaluatedWith: focusClock)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["end"].isHittable)
        captureReport(app, name: "focus-after-early-return")
    }
    func testBreakScreenAtLargestTextSizeKeepsReturnReachable() {
        let app = app(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.buttons["start"].tap()
        let takeBreak = app.buttons["breakStart"]
        XCTAssertTrue(takeBreak.waitForExistence(timeout: 5))
        if !takeBreak.isHittable { app.swipeUp() }
        takeBreak.tap()
        XCTAssertTrue(app.otherElements["breakScreen"].waitForExistence(timeout: 5))
        captureReport(app, name: "break-wait-largest-text")
        XCTAssertTrue(app.staticTexts["breakCountdown"].waitForExistence(timeout: 25))
        let resume = app.buttons["resume"]
        XCTAssertTrue(resume.exists)
        for _ in 0..<3 where !resume.isHittable { app.swipeUp() }
        XCTAssertTrue(resume.isHittable)
        captureReport(app, name: "break-return-largest-text")
        resume.tap()
        XCTAssertTrue(app.buttons["breakStart"].waitForExistence(timeout: 8))
    }
    func testBreakFlowReBlocksAndResumes() {
        // No step here depends on how long one accessibility query takes (#109): the lenient timing admits the automatic break start
        // however late its tick runs, and each wait below is for a state that then stays until the next tap.
        let app = shortBreaks(lenient: true); app.buttons["start"].tap()
        XCTAssertTrue(app.buttons["breakStart"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["breaksLeft"].label, "쉬는 시간 3번 남았어요")
        app.buttons["breakStart"].tap()
        // The 1-second wait and the 3-second break can pass during one slow query, so the break that started is checked here.
        // `testCancelWaitReturnsToFocusWithSameBreaksLeft` asserts `breakWait` with the 15-second standard wait.
        XCTAssertTrue(breakStarted(app).waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["selection"].exists); XCTAssertTrue(app.buttons["end"].exists)
        captureReport(app, name: "break-started")
        // Early return now exposes `resume` during the break; the deadline notice identifies the natural end.
        XCTAssertTrue(app.staticTexts["deadlineNotice"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["resume"].exists); XCTAssertTrue(app.buttons["end"].exists)
        // The standard 10-minute slack of the lenient timing keeps the notice counting down, so its label still changes after a slow query.
        // `testMissedDeadlineRecordsUnfocusedSession` asserts the final text with the 15-second short slack.
        let notice = app.staticTexts["deadlineNotice"], initialNotice = app.staticTexts["deadlineNotice"].label
        expectation(for: NSPredicate(format: "label != %@", initialNotice), evaluatedWith: notice)
        waitForExpectations(timeout: 15)
        XCTAssertTrue(app.buttons["end"].isHittable)
        captureReport(app, name: "break-over")
        app.buttons["resume"].tap()
        let countdown = app.staticTexts["countdown"]
        XCTAssertTrue(app.buttons["breakStart"].waitForExistence(timeout: 15)); XCTAssertTrue(countdown.exists)
        XCTAssertEqual(app.staticTexts["breaksLeft"].label, "쉬는 시간 2번 남았어요")
        let paused = countdown.label
        expectation(for: NSPredicate(format: "label != %@", paused), evaluatedWith: countdown); waitForExpectations(timeout: 15)
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
        // Three automatic break starts and no deadline: the lenient timing keeps a slow query from refusing any of them.
        let app = shortBreaks(lenient: true); app.buttons["start"].tap()
        for _ in 0..<3 {
            XCTAssertTrue(app.buttons["breakStart"].waitForExistence(timeout: 15)); app.buttons["breakStart"].tap()
            XCTAssertTrue(app.buttons["resume"].waitForExistence(timeout: 15)); app.buttons["resume"].tap()
        }
        XCTAssertTrue(app.staticTexts["countdown"].waitForExistence(timeout: 15)); XCTAssertTrue(app.buttons["end"].exists)
        XCTAssertFalse(app.buttons["breakStart"].exists); XCTAssertFalse(app.staticTexts["breaksLeft"].exists)
    }
    func testMissedDeadlineRecordsUnfocusedSession() {
        // The start tap leaves 10 seconds of focus: a break taken at once and never resumed reaches the deadline about 29 seconds after the tap
        // (10 s of focus, a 1 s wait, a 3 s break and a 15 s slack); the notice stops counting about 10 seconds before that.
        let app = shortBreaks("ending-soon", environment: noonZone())
        let start = app.buttons["start"], breakStart = app.buttons["breakStart"]
        XCTAssertTrue(start.waitForExistence(timeout: ready)); start.tap()
        // A loaded host can drop a synthesized tap. A delivered tap first reserves the pending start and disables the button.
        // Retry only if no session controls appeared and the button is still enabled. The 10 seconds count from the accepted start body.
        if !breakStart.waitForExistence(timeout: 5), !app.buttons["end"].exists, start.exists, start.isEnabled, start.isHittable { start.tap() }
        XCTAssertTrue(breakStart.waitForExistence(timeout: ready)); breakStart.tap()
        XCTAssertTrue(breakStarted(app).waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["resume"].waitForExistence(timeout: 15))
        let notice = app.staticTexts["deadlineNotice"]
        expectation(for: NSPredicate(format: "label CONTAINS '기록되지 않아요'"), evaluatedWith: notice); waitForExpectations(timeout: 30)
        captureReport(app, name: "deadline-notice")
        let summary = app.buttons["todaySummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 30))
        XCTAssertEqual(summary.label, "오늘 집중 0분 · 0회")
        XCTAssertFalse(app.descendants(matching: .any)["completion"].exists)
        // The summary appears while the timer screen swaps back, and a tap then can miss; tap again only when the history sheet
        // is not up and the summary still takes a tap (an open sheet covers it).
        waitHittable(summary)
        summary.tap()
        // A late second tap only presents the same history sheet again.
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
    func testReleaseDelayNoteShowsOnlyOnCompletion() {
        let app = app("expiring")
        let note = app.descendants(matching: .any)["releaseDelayNote"]
        XCTAssertTrue(app.descendants(matching: .any)["completion"].waitForExistence(timeout: 15))
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertEqual(note.label, "제한이 풀리기까지 조금 걸릴 수 있어요.")
        app.buttons["completionDismiss"].tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 5)); XCTAssertFalse(note.exists)
        // Only the launch session is backdated in `expiring`; a session started here runs its full length.
        app.buttons["start"].tap()
        XCTAssertTrue(app.buttons["end"].waitForExistence(timeout: ready)); XCTAssertFalse(note.exists)
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
        XCTAssertTrue(app.staticTexts["웹사이트 전체를 제한해요. 브라우저에 따라 제한되지 않을 수 있어요."].exists)
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
