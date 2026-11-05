import XCTest
final class FocusFlowTests: XCTestCase {
    func app(_ mode: String = "approved", selected: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", mode] + (selected ? ["--selected"] : []) + extra; app.launch(); return app
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
        captureReport(app, name: "history-empty")
    }
    func testHistoryErrorDoesNotShowSuccessfulSummaryOrEmptyState() {
        let app = app("registration-failure")
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: ready)); app.buttons["start"].tap()
        XCTAssertTrue(app.staticTexts["startError"].waitForExistence(timeout: 5))
        let error = app.staticTexts["startError"].label
        XCTAssertEqual(app.buttons["todaySummary"].label, "오늘의 기록")
        openToday(app)
        XCTAssertTrue(app.staticTexts["historyError"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["historyError"].label, error)
        XCTAssertFalse(app.staticTexts["historySummary"].exists)
        XCTAssertFalse(app.staticTexts["아직 기록이 없어요."].exists)
        captureReport(app, name: "history-error")
        app.buttons["historyRetry"].tap()
        XCTAssertTrue(app.staticTexts["historySummary"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["historyError"].exists)
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
        // Early return now exposes `resume` during the break; the deadline notice identifies the natural end.
        XCTAssertTrue(app.staticTexts["deadlineNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["resume"].exists); XCTAssertTrue(app.buttons["end"].exists)
        let notice = app.staticTexts["deadlineNotice"], initialNotice = app.staticTexts["deadlineNotice"].label
        expectation(for: NSPredicate(format: "label != %@", initialNotice), evaluatedWith: notice)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["end"].isHittable)
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
        XCTAssertTrue(start.waitForExistence(timeout: ready)); start.tap()
        // A loaded host can drop a synthesized tap. `start()` is synchronous, so a delivered tap has shown the session controls before `tap()` returns;
        // tap again only when they are absent and `start` still takes a tap. The 10 seconds count from the tap that starts the session.
        if !breakStart.waitForExistence(timeout: 5), !app.buttons["end"].exists, start.exists, start.isHittable { start.tap() }
        XCTAssertTrue(breakStart.waitForExistence(timeout: ready)); breakStart.tap()
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
