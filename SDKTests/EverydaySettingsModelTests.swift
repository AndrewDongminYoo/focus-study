import XCTest
import FamilyControls
import ManagedSettings

@MainActor final class EverydaySettingsModelTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!; return calendar
    }()
    /// 10:00 in Seoul: inside the range 08:00-18:00 and before lunch.
    private var tenAM: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 10))! }
    private func fixture(writeFailure: @escaping () -> Bool = { false }) -> (EverydaySettingsModel, ModelTestEverydayLayer, ModelTestMonitoring, ModelTestSelection) {
        let layer = ModelTestEverydayLayer(), monitoring = ModelTestMonitoring(), shield = ModelTestShield(), selection = ModelTestSelection()
        let engine = SessionControl(store: ModelTestStore(), monitoring: monitoring, shield: shield, breakSelection: ModelTestBreakSelection(), everyday: layer, calendar: calendar)
        var services = FocusServices(authorization: ModelTestAuthorization(), selection: selection, engine: engine,
                                     applySelection: { _ in shield.applied = true }, matchesSelection: { _ in shield.applied }, isFixture: true)
        services.settings = FocusSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        services.everydaySelection = { layer.schedule == nil ? nil : layer.selection }
        services.everydayContains = { layer.contains($0) }
        services.writeEveryday = {
            if writeFailure() { throw ModelTestError.storage }
            layer.write($0, $1)
        }
        services.writeEverydayOffDay = {
            if writeFailure() { throw ModelTestError.storage }
            layer.writeOffDay($0)
        }
        let focus = FocusModel(services: services, history: ModelTestHistory(acknowledge: engine.acknowledgeTerminal))
        let settings = EverydaySettingsModel(focus: focus)
        settings.clock = { self.tenAM }
        return (settings, layer, monitoring, selection)
    }
    private func apps(_ range: Range<Int>) -> FamilyActivitySelection {
        var selection = FamilyActivitySelection(includeEntireCategory: true); selection.applicationTokens = syntheticApps(range); return selection
    }
    /// The stored layer 08:00-18:00 with lunch, on, with one app, converged at 10:00 as a launch would do it.
    private func storedLayer(_ layer: ModelTestEverydayLayer, _ settings: EverydaySettingsModel) {
        layer.write(EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 480, rangeEnd: 1080, windows: [EverydaySchedule.template(.lunch)!]), apps(0..<1))
        _ = try? settings.focus.services.engine.reconcile(now: tenAM, authorized: true)
    }

    func testNewLayerStartsFromTheStandardRangeAndIsOff() {
        let (settings, _, _, _) = fixture()
        settings.refresh()
        XCTAssertFalse(settings.draft.enabled); XCTAssertEqual(settings.draft.rangeStart, 480); XCTAssertEqual(settings.draft.rangeEnd, 1080)
        XCTAssertTrue(settings.draft.windows.isEmpty); XCTAssertNil(settings.status?.schedule)
        XCTAssertEqual(EverydaySettingsModel.statusLine(settings.status), "꺼져 있어요")
        XCTAssertTrue(settings.canEdit)
    }
    func testPreviewPartitionsTheRangeAndSortsThreeWindows() {
        typealias Segment = EverydaySettingsModel.PreviewSegment
        var schedule = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 480, rangeEnd: 1080, windows: [])
        XCTAssertEqual(EverydaySettingsModel.previewSegments(for: schedule), [Segment(start: 480, end: 1080, blocked: true)])
        schedule.windows = [EverydayWindow(kind: .lunch, start: 720, end: 780)]
        XCTAssertEqual(EverydaySettingsModel.previewSegments(for: schedule), [
            Segment(start: 480, end: 720, blocked: true), Segment(start: 720, end: 780, blocked: false), Segment(start: 780, end: 1080, blocked: true)
        ])
        schedule.windows = [EverydayWindow(kind: .fromSchool, start: 960, end: 990),
                            EverydayWindow(kind: .lunch, start: 720, end: 780), EverydayWindow(kind: .toSchool, start: 480, end: 510)]
        XCTAssertEqual(EverydaySettingsModel.previewSegments(for: schedule), [
            Segment(start: 480, end: 510, blocked: false), Segment(start: 510, end: 720, blocked: true),
            Segment(start: 720, end: 780, blocked: false), Segment(start: 780, end: 960, blocked: true),
            Segment(start: 960, end: 990, blocked: false), Segment(start: 990, end: 1080, blocked: true)
        ])
    }
    func testPreviewOmitsZeroLengthGapsAndRejectsInvalidOrDisabledSchedules() {
        typealias Segment = EverydaySettingsModel.PreviewSegment
        var schedule = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 480, rangeEnd: 1080, windows: [
            EverydayWindow(kind: .custom, start: 960, end: 1080), EverydayWindow(kind: .custom, start: 900, end: 960)
        ])
        XCTAssertEqual(EverydaySettingsModel.previewSegments(for: schedule), [
            Segment(start: 480, end: 900, blocked: true), Segment(start: 900, end: 960, blocked: false), Segment(start: 960, end: 1080, blocked: false)
        ])
        schedule.windows[1].end = 965
        XCTAssertNil(EverydaySettingsModel.previewSegments(for: schedule), "overlap must not produce an applied-looking preview")
        schedule.windows = []; schedule.rangeEnd = 500
        XCTAssertNil(EverydaySettingsModel.previewSegments(for: schedule))
        schedule.rangeEnd = 1080; schedule.enabled = false
        XCTAssertEqual(EverydaySettingsModel.previewSegments(for: schedule), [])
    }
    func testDayClockFractionPlacesMidnightAtZeroAndKeepsTheLatestRangeEndBeforeOneTurn() {
        XCTAssertEqual(EverydaySettingsModel.dayClockFraction(0), 0)
        XCTAssertEqual(EverydaySettingsModel.dayClockFraction(360), 0.25)
        XCTAssertEqual(EverydaySettingsModel.dayClockFraction(720), 0.5)
        XCTAssertEqual(EverydaySettingsModel.dayClockFraction(1080), 0.75)
        XCTAssertEqual(EverydaySettingsModel.dayClockFraction(EverydaySchedule.latestRangeEnd), 1435.0 / 1440.0)
        XCTAssertLessThan(EverydaySettingsModel.dayClockFraction(EverydaySchedule.latestRangeEnd), 1)
        let schedule = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 0, rangeEnd: EverydaySchedule.latestRangeEnd, windows: [
            EverydayWindow(kind: .custom, start: 1315, end: EverydaySchedule.latestRangeEnd)
        ])
        let segments = EverydaySettingsModel.previewSegments(for: schedule) ?? []
        XCTAssertEqual(segments.count, 2)
        let fractions = segments.map { (EverydaySettingsModel.dayClockFraction($0.start), EverydaySettingsModel.dayClockFraction($0.end)) }
        XCTAssertEqual(fractions.first?.0, 0, "a range that starts at midnight starts at the top")
        XCTAssertEqual(fractions.last?.1, 1435.0 / 1440.0, "a range that ends at the latest end stops before midnight")
        for (start, end) in fractions { XCTAssertLessThan(start, end, "no arc wraps past midnight") }
    }
    func testPreviewKeepsStoredScheduleThroughRefusalFailureSaveAndReentry() {
        var fail = false
        let (settings, layer, _, _) = fixture(writeFailure: { fail })
        storedLayer(layer, settings); settings.refresh()
        let stored = settings.status?.schedule
        settings.draft.enabled = false; settings.save()
        XCTAssertEqual(settings.status?.schedule, stored); XCTAssertNotNil(settings.refusalMessage); XCTAssertNil(settings.successMessage)
        settings.draft.enabled = true; settings.draft.windows = []
        fail = true
        settings.save()
        XCTAssertEqual(settings.status?.schedule, stored); XCTAssertNotNil(settings.refusalMessage); XCTAssertNil(settings.successMessage)
        XCTAssertEqual(EverydaySettingsModel.previewSegments(for: settings.draft)?.count, 1)
        XCTAssertEqual(EverydaySettingsModel.previewSegments(for: settings.status!.schedule!)?.count, 3)
        fail = false
        settings.save()
        XCTAssertNotNil(settings.successMessage); XCTAssertNil(settings.refusalMessage)
        settings.refresh()
        XCTAssertEqual(settings.status?.schedule, settings.draft)
        XCTAssertEqual(EverydaySettingsModel.previewSegments(for: settings.status!.schedule!)?.count, 1)
    }
    func testDirtyStateComparesEditableValuesAndTokensRatherThanRevisionOrWindowOrder() {
        let (settings, layer, _, _) = fixture()
        storedLayer(layer, settings)
        settings.refresh()
        XCTAssertFalse(settings.hasChanges); XCTAssertFalse(settings.canSave)
        settings.draft.revision = UUID()
        XCTAssertFalse(settings.hasChanges)
        settings.draft.rangeEnd += 5
        XCTAssertTrue(settings.hasChanges); XCTAssertTrue(settings.canSave)
        settings.draft.rangeEnd -= 5
        XCTAssertFalse(settings.hasChanges)
        settings.draftSelection = apps(1..<2)
        XCTAssertTrue(settings.hasChanges, "a different app with the same count is an edit")
        settings.draftSelection = apps(0..<1)
        XCTAssertFalse(settings.hasChanges)
        settings.draft.windows = [EverydaySchedule.template(.lunch)!, EverydaySchedule.template(.fromSchool)!]
        layer.write(settings.draft, settings.draftSelection)
        settings.refresh()
        settings.draft.windows.reverse()
        XCTAssertFalse(settings.hasChanges)
    }
    func testUnchangedSaveDoesNotWriteAndSuccessfulSaveClearsDirtyState() {
        let (settings, layer, _, _) = fixture()
        settings.refresh()
        settings.save()
        XCTAssertEqual(layer.writes, 0); XCTAssertNil(settings.successMessage)
        settings.draft.rangeEnd += 5
        settings.save()
        XCTAssertEqual(layer.writes, 1); XCTAssertFalse(settings.hasChanges); XCTAssertFalse(settings.canSave)
        XCTAssertEqual(settings.successMessage, "매일 제한을 저장했어요.")
        settings.draft.rangeEnd += 5
        XCTAssertTrue(settings.hasChanges); XCTAssertNil(settings.successMessage)
    }
    func testRefusedSaveKeepsDraftDirtyAndNeverShowsSuccess() {
        let (settings, layer, _, _) = fixture()
        storedLayer(layer, settings)
        settings.refresh()
        settings.draft.enabled = false
        settings.save()
        XCTAssertNotNil(settings.refusalMessage); XCTAssertNil(settings.successMessage)
        XCTAssertTrue(settings.hasChanges); XCTAssertFalse(settings.draft.enabled)
        settings.draft.enabled = true
        XCTAssertNil(settings.refusalMessage); XCTAssertFalse(settings.hasChanges)
    }
    func testValidationFeedbackBelongsToTheRelatedSectionAndDisablesSave() {
        let (settings, _, _, _) = fixture()
        settings.refresh()
        settings.draft.rangeEnd = 510
        XCTAssertNotNil(settings.rangeIssue); XCTAssertNil(settings.windowsIssue); XCTAssertFalse(settings.canSave)
        settings.draft.rangeEnd = 1080
        settings.draft.windows = [EverydayWindow(kind: .custom, start: 600, end: 610)]
        XCTAssertNil(settings.rangeIssue); XCTAssertNotNil(settings.windowsIssue); XCTAssertFalse(settings.canSave)
        settings.draft.windows = []; settings.draft.enabled = true
        XCTAssertNotNil(settings.selectionIssue); XCTAssertFalse(settings.canSave)
        settings.draftSelection = apps(0..<1)
        XCTAssertNil(settings.selectionIssue); XCTAssertTrue(settings.canSave)
    }
    func testStrictOnlyGuidanceIncludesWindowsAndEndsAtTheStoredRangeEnd() {
        let (settings, layer, _, _) = fixture()
        storedLayer(layer, settings)
        settings.refresh()
        let expected = "제한 시간에는 더 엄격하게만 바꿀 수 있어요. 18:00부터 자유롭게 바꿀 수 있어요."
        XCTAssertEqual(settings.strictOnlyMessage, expected)
        settings.clock = { self.tenAM.addingTimeInterval(2.5 * 3600) }
        settings.refreshStatus()
        XCTAssertFalse(settings.status?.blocksNow ?? true)
        XCTAssertEqual(settings.strictOnlyMessage, expected, "lunch still uses the strict-only rule")
        settings.clock = { self.tenAM.addingTimeInterval(8 * 3600) }
        settings.refreshStatus()
        XCTAssertNil(settings.strictOnlyMessage)
    }
    func testTemplatesAddSuggestedTimesAndCustomHasNone() {
        let (settings, _, _, _) = fixture()
        settings.refresh()
        settings.addWindow(.toSchool)
        settings.addWindow(.custom)
        XCTAssertEqual(settings.draft.windows.map(\.start), [480, 510]); XCTAssertEqual(settings.draft.windows.last?.end, 540)
        settings.addWindow(.lunch)
        XCTAssertEqual(settings.draft.windows.map(\.kind), [.toSchool, .custom, .lunch]); XCTAssertEqual(settings.draft.windows.last?.end, 780)
        XCTAssertFalse(settings.canAddWindow)
        settings.addWindow(.fromSchool)
        XCTAssertEqual(settings.draft.windows.count, 3)
        settings.removeWindow(at: 1)
        settings.addWindow(.fromSchool)
        XCTAssertEqual(settings.draft.windows.last, EverydayWindow(kind: .fromSchool, start: 960, end: 990))
        XCTAssertTrue(settings.draft.isValid)
    }
    func testDraftIssueNamesTheBrokenRule() {
        let (settings, _, _, _) = fixture()
        settings.refresh()
        settings.draft.rangeEnd = 510
        XCTAssertEqual(settings.draftIssue, "제한 끝을 제한 시작보다 1시간 이상 늦게 정해 주세요.", "a 30-minute range without windows")
        settings.draft.rangeEnd = 1080; settings.draft.windows = [EverydayWindow(kind: .custom, start: 600, end: 610)]
        XCTAssertEqual(settings.draftIssue, "잠시 풀어 두는 시간은 한 번에 15분에서 2시간까지 정할 수 있어요.", "a 10-minute window")
        settings.draft.windows = [EverydaySchedule.template(.lunch)!, EverydayWindow(kind: .custom, start: 750, end: 810)]
        XCTAssertEqual(settings.draftIssue, "잠시 풀어 두는 시간이 서로 겹쳐요. 겹치지 않게 바꿔 주세요.", "overlapping windows")
        settings.draft.windows = [EverydayWindow(kind: .custom, start: 450, end: 510)]
        XCTAssertEqual(settings.draftIssue, "잠시 풀어 두는 시간은 제한 시간 안에서 정할 수 있어요.", "a window before the range")
        settings.draft.rangeEnd = 540; settings.draft.windows = [EverydayWindow(kind: .custom, start: 480, end: 540)]
        XCTAssertEqual(settings.draftIssue, "잠시 풀어 두는 시간이 제한 시간을 모두 채우고 있어요. 제한할 시간을 남겨 주세요.", "windows cover the range")
        settings.draft.rangeEnd = 1080; settings.draft.windows = []
        XCTAssertNil(settings.draftIssue, "a valid draft that is off")
    }
    func testEveryScheduleIssueHasItsOwnMessage() {
        let messages = EverydayScheduleIssue.allCases.map(EverydaySettingsModel.message(for:))
        XCTAssertEqual(messages, [
            "시간은 5분 단위로 정할 수 있어요.",
            "제한 시간은 00:00부터 23:55 사이로 정할 수 있어요.",
            "제한 끝을 제한 시작보다 1시간 이상 늦게 정해 주세요.",
            "잠시 풀어 두는 시간은 3개까지 정할 수 있어요.",
            "잠시 풀어 두는 시간은 한 번에 15분에서 2시간까지 정할 수 있어요.",
            "잠시 풀어 두는 시간은 제한 시간 안에서 정할 수 있어요.",
            "잠시 풀어 두는 시간이 서로 겹쳐요. 겹치지 않게 바꿔 주세요.",
            "잠시 풀어 두는 시간이 제한 시간을 모두 채우고 있어요. 제한할 시간을 남겨 주세요.",
        ])
        XCTAssertEqual(Set(messages).count, messages.count)
    }
    func testSaveInsideTheRangeShowsTheRefusalWithTheRangeEnd() {
        let (settings, layer, _, _) = fixture()
        storedLayer(layer, settings)
        let stored = layer.schedule
        settings.refresh()
        settings.draft.enabled = false
        settings.save()
        XCTAssertEqual(settings.refusalMessage, "제한 시간에는 매일 제한을 끌 수 없어요. 18:00부터 자유롭게 바꿀 수 있어요. ‘오늘만 끄기’를 누르면 오늘은 제한을 끌 수 있어요.")
        XCTAssertEqual(layer.schedule, stored); XCTAssertEqual(layer.writes, 1)
        // A stricter edit is accepted at once.
        settings.draft.enabled = true; settings.draft.windows = []
        settings.save()
        XCTAssertNil(settings.refusalMessage); XCTAssertEqual(layer.writes, 2); XCTAssertEqual(layer.schedule?.windows, [])
    }
    func testEditingIsLockedDuringAFocusSession() throws {
        let (settings, layer, _, _) = fixture()
        settings.focus.completeOnboarding(); settings.focus.start()
        XCTAssertTrue(settings.focus.isActive)
        settings.refresh()
        XCTAssertFalse(settings.canEdit)
        settings.draft.enabled = true; settings.draftSelection = apps(0..<1)
        settings.save()
        XCTAssertEqual(settings.refusalMessage, "집중 시간이 끝난 뒤에 바꿀 수 있어요.")
        XCTAssertEqual(layer.writes, 0)
    }
    func testStatusShowsBlockingNowAndTheNextChange() {
        let (settings, layer, _, _) = fixture()
        storedLayer(layer, settings)
        settings.refresh()
        let status = settings.status
        XCTAssertEqual(status?.blocksNow, true)
        XCTAssertEqual(status?.nextChange, calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12)))
        XCTAssertEqual(EverydaySettingsModel.statusLine(status, calendar: calendar), "지금 제한하고 있어요 · 12:00까지")
        XCTAssertTrue(settings.draft.enabled); XCTAssertEqual(settings.counts.apps, 1)
        let evening = tenAM.addingTimeInterval(9 * 3600)
        settings.clock = { evening }
        // The range-end callback of the Monitor clears the store.
        _ = try? settings.focus.services.engine.reconcile(now: evening, authorized: true)
        settings.refresh()
        XCTAssertEqual(EverydaySettingsModel.statusLine(settings.status, calendar: calendar), "켜져 있어요 · 08:00부터 제한해요")
    }
    func testStatusReadAfterABoundaryKeepsTheDraft() {
        let (settings, layer, _, _) = fixture()
        storedLayer(layer, settings)
        settings.refresh()
        settings.draft.windows = []
        let lunch = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))!
        XCTAssertEqual(EverydaySettingsModel.statusReadDelay(settings.status, now: tenAM, retried: false), 2 * 3600 + EverydaySettingsModel.boundaryGrace)
        let read = lunch.addingTimeInterval(EverydaySettingsModel.boundaryGrace)
        settings.clock = { read }
        // Before the window-start callback of the Monitor, the store still holds the shield.
        settings.refreshStatus()
        XCTAssertEqual(settings.status?.issue, .notCleared)
        _ = try? settings.focus.services.engine.reconcile(now: read, authorized: true)
        settings.refreshStatus()
        XCTAssertEqual(EverydaySettingsModel.statusLine(settings.status, calendar: calendar), "켜져 있어요 · 13:00부터 제한해요")
        XCTAssertEqual(settings.draft.windows, [])
    }
    func testStatusReadDelayRetriesAnIssueOnceAndSkipsAPassedBoundary() {
        let next = tenAM.addingTimeInterval(3600)
        func status(_ issue: EverydayIssue?, next: Date?) -> EverydayStatus { EverydayStatus(schedule: nil, blocksNow: true, nextChange: next, issue: issue) }
        XCTAssertNil(EverydaySettingsModel.statusReadDelay(nil, now: tenAM, retried: false))
        XCTAssertNil(EverydaySettingsModel.statusReadDelay(status(nil, next: nil), now: tenAM, retried: false))
        XCTAssertEqual(EverydaySettingsModel.statusReadDelay(status(.notApplied, next: next), now: tenAM, retried: false), EverydaySettingsModel.issueRetry)
        XCTAssertEqual(EverydaySettingsModel.statusReadDelay(status(.notApplied, next: next), now: tenAM, retried: true), 3600 + EverydaySettingsModel.boundaryGrace)
        XCTAssertEqual(EverydaySettingsModel.statusReadDelay(status(.registrationFailed, next: next), now: tenAM, retried: false), 3600 + EverydaySettingsModel.boundaryGrace)
        // A late window-start or range-end callback can still clear a shield left on.
        XCTAssertEqual(EverydaySettingsModel.statusReadDelay(status(.notCleared, next: next), now: tenAM, retried: false), EverydaySettingsModel.issueRetry)
        XCTAssertEqual(EverydaySettingsModel.statusLine(status(.notCleared, next: next)), "제한이 아직 풀리지 않았어요. 앱을 다시 열면 풀어요.")
        // A lock timeout keeps the passed boundary: one retry, then no reads until a lock section of the app.
        let passed = tenAM.addingTimeInterval(-5)
        XCTAssertEqual(EverydaySettingsModel.statusReadDelay(status(.unchecked, next: passed), now: tenAM, retried: false), EverydaySettingsModel.issueRetry)
        XCTAssertNil(EverydaySettingsModel.statusReadDelay(status(.unchecked, next: passed), now: tenAM, retried: true))
        // A boundary sooner than the retry comes first.
        XCTAssertEqual(EverydaySettingsModel.statusReadDelay(status(.notApplied, next: tenAM.addingTimeInterval(3)), now: tenAM, retried: false), 3 + EverydaySettingsModel.boundaryGrace)
    }
    func testFollowStatusReadsAtEachDueTimeAndStopsWhenNoReadIsDue() async {
        let lunch = tenAM.addingTimeInterval(2 * 3600)
        var status: EverydayStatus? = EverydayStatus(schedule: nil, blocksNow: true, nextChange: lunch, issue: nil)
        var now = tenAM, waits: [TimeInterval] = [], reads = 0
        await EverydaySettingsModel.followStatus({ status }, now: { now }, sleep: { waits.append($0); now = now.addingTimeInterval($0) }) {
            reads += 1
            // The first read crosses lunch and finds the next boundary; the second finds no more change today.
            status = reads == 1 ? EverydayStatus(schedule: nil, blocksNow: false, nextChange: lunch.addingTimeInterval(3600), issue: nil)
                                : EverydayStatus(schedule: nil, blocksNow: true, nextChange: nil, issue: nil)
        }
        // The second wait starts at lunch plus the grace, so it is exactly one hour.
        XCTAssertEqual(waits, [2 * 3600 + EverydaySettingsModel.boundaryGrace, 3600])
        XCTAssertEqual(reads, 2)
    }
    func testUnreadableFileShowsTheIssueAndAllowsSettingUpAgain() {
        let (settings, layer, _, _) = fixture()
        storedLayer(layer, settings); layer.unreadable = true
        settings.refresh()
        XCTAssertEqual(settings.status?.issue, .unreadable)
        XCTAssertEqual(EverydaySettingsModel.statusLine(settings.status), "설정을 불러오지 못했어요. 다시 설정해 주세요.")
        XCTAssertEqual(settings.draft.rangeStart, EverydaySchedule.standard.rangeStart); XCTAssertFalse(settings.draft.enabled)
        settings.draft.enabled = true; settings.draftSelection = apps(5..<6)
        settings.save()
        XCTAssertNil(settings.refusalMessage)
        XCTAssertEqual(layer.schedule?.enabled, true); XCTAssertNil(settings.status?.issue)
    }
    func testUnreadableFileCanBeReplacedWithTheUnchangedStandardDraft() {
        let (settings, layer, _, _) = fixture()
        storedLayer(layer, settings); layer.unreadable = true
        settings.refresh()
        XCTAssertEqual(settings.status?.issue, .unreadable)
        XCTAssertFalse(settings.hasChanges)
        XCTAssertTrue(settings.canSave, "the standard draft can replace an unreadable file without a dummy edit")
        settings.save()
        XCTAssertNil(settings.refusalMessage); XCTAssertNotNil(settings.successMessage)
        XCTAssertEqual(layer.writes, 2); XCTAssertFalse(layer.unreadable)
        XCTAssertEqual(layer.schedule?.enabled, false)
        XCTAssertEqual(layer.schedule?.rangeStart, EverydaySchedule.standard.rangeStart)
        XCTAssertEqual(layer.schedule?.rangeEnd, EverydaySchedule.standard.rangeEnd)
        XCTAssertEqual(layer.schedule?.windows, [])
        XCTAssertNil(settings.status?.issue)
        XCTAssertFalse(settings.hasChanges); XCTAssertFalse(settings.canSave)
        settings.save()
        XCTAssertEqual(layer.writes, 2, "after recovery an unchanged draft remains a no-op")
    }
    func testEverydaySaveRefusesAUnionOver50() {
        let (settings, layer, monitoring, focusSelection) = fixture()
        focusSelection.selection = apps(0..<30)
        settings.refresh()
        settings.draft.enabled = true; settings.draftSelection = apps(30..<51)
        settings.save()
        XCTAssertEqual(settings.refusalMessage, "집중 시간과 매일 제한을 합쳐 앱은 50개까지 고를 수 있어요.")
        XCTAssertEqual(layer.writes, 0); XCTAssertTrue(monitoring.everyday.isEmpty)
        settings.draftSelection = apps(10..<50)
        settings.save()
        XCTAssertNil(settings.refusalMessage); XCTAssertEqual(layer.writes, 1)
    }
    func testTimerLineShowsOnlyABlockingLayerOrAnIssue() {
        let on = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 480, rangeEnd: 1080, windows: [])
        var off = on; off.enabled = false
        let noon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12, minute: 5))!
        func line(_ schedule: EverydaySchedule?, blocks: Bool, next: Date? = nil, issue: EverydayIssue? = nil) -> String? {
            EverydaySettingsModel.timerLine(EverydayStatus(schedule: schedule, blocksNow: blocks, nextChange: next, issue: issue), calendar: calendar)
        }
        XCTAssertNil(EverydaySettingsModel.timerLine(nil, calendar: calendar))
        // `blocksNow` stays true, so only the schedule hides these rows.
        XCTAssertNil(line(nil, blocks: true, next: noon))
        XCTAssertNil(line(off, blocks: true, next: noon))
        XCTAssertNil(line(on, blocks: false, next: noon), "the idle screen shows no line about the next start")
        XCTAssertEqual(line(on, blocks: true, next: noon), "매일 제한 중 · 12:05까지")
        XCTAssertEqual(line(on, blocks: true), "매일 제한 중")
        // A status the app could not confirm never reads as released, whatever the schedule says.
        for issue in [EverydayIssue.unreadable, .registrationFailed, .notApplied, .notCleared, .unchecked] {
            XCTAssertEqual(line(nil, blocks: false, issue: issue), "매일 제한을 확인해 주세요", "\(issue)")
            XCTAssertEqual(line(off, blocks: false, next: noon, issue: issue), "매일 제한을 확인해 주세요", "\(issue)")
        }
    }
    // MARK: Off for today

    private func at(_ hour: Int, _ minute: Int = 0, _ second: Int = 0, day: Int = 2) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second))!
    }
    /// The stored layer, read at 10:00, with the off-for-today wait started then.
    private func waiting() -> (EverydaySettingsModel, ModelTestEverydayLayer) {
        let (settings, layer, _, _) = fixture()
        storedLayer(layer, settings); settings.refresh()
        XCTAssertTrue(settings.offersOffForToday)
        settings.startOffWait()
        XCTAssertNotNil(settings.offWait)
        return (settings, layer)
    }
    /// One tick of the wait's timer at `time`, in the scene phase that the screen reported last.
    private func tick(_ settings: EverydaySettingsModel, at time: Date) {
        settings.clock = { time }; settings.tickOffWait()
    }
    func testOffWaitRunsTheSectionOnceAtItsEndAndKeepsTheDraft() {
        let (settings, layer) = waiting()
        settings.draft.windows = []
        XCTAssertEqual(settings.offWaitRemaining, 30); XCTAssertEqual(settings.offWaitProgress, 0)
        tick(settings, at: tenAM.addingTimeInterval(10))
        XCTAssertEqual(settings.offWaitRemaining, 20); XCTAssertEqual(settings.offWaitProgress ?? 0, 1.0 / 3, accuracy: 0.001)
        XCTAssertNil(layer.schedule?.offDay); XCTAssertEqual(layer.writes, 1)
        tick(settings, at: tenAM.addingTimeInterval(30))
        XCTAssertEqual(layer.schedule?.offDay, "2026-11-02"); XCTAssertEqual(layer.writes, 2)
        XCTAssertNil(settings.offWait); XCTAssertNil(settings.refusalMessage)
        XCTAssertEqual(settings.status?.offForToday, true); XCTAssertEqual(settings.status?.blocksNow, false)
        XCTAssertEqual(EverydaySettingsModel.statusLine(settings.status, calendar: calendar), "오늘은 꺼 두었어요 · 내일 08:00부터 다시 제한해요")
        XCTAssertFalse(settings.offersOffForToday, "once a day")
        XCTAssertEqual(settings.draft.windows, [], "the action does not save or reset the draft"); XCTAssertTrue(settings.hasChanges)
        // The strict-only message stays inside the range, because the five conditions still apply.
        XCTAssertNotNil(settings.strictOnlyMessage)
        tick(settings, at: tenAM.addingTimeInterval(31))
        XCTAssertEqual(layer.writes, 2, "the section runs once")
        // The timer-screen row shows nothing for a layer that is off for today.
        XCTAssertNil(EverydaySettingsModel.timerLine(settings.status, calendar: calendar))
    }
    func testBackgroundCancelsTheWaitAndChangesNothing() {
        let (settings, layer) = waiting()
        settings.sceneDidLeaveForeground()
        XCTAssertNil(settings.offWait)
        settings.clock = { self.tenAM.addingTimeInterval(30) }; settings.sceneDidBecomeActive()
        tick(settings, at: tenAM.addingTimeInterval(30))
        XCTAssertEqual(layer.writes, 1); XCTAssertNil(layer.schedule?.offDay)
        XCTAssertTrue(settings.offersOffForToday, "a cancelled wait does not use the day's action")
    }
    func testClosingTheScreenCancelsTheWaitAndChangesNothing() {
        let (settings, layer) = waiting()
        settings.screenDidClose()
        XCTAssertNil(settings.offWait)
        tick(settings, at: tenAM.addingTimeInterval(30))
        XCTAssertEqual(layer.writes, 1); XCTAssertNil(layer.schedule?.offDay)
    }
    func testInactiveKeepsTheWaitAndActiveRunsItOnceWithinTheGrace() {
        let (settings, layer) = waiting()
        settings.sceneDidBecomeInactive()
        tick(settings, at: tenAM.addingTimeInterval(30))
        XCTAssertNotNil(settings.offWait, "an inactive overlay keeps the wait"); XCTAssertEqual(layer.writes, 1)
        settings.clock = { self.tenAM.addingTimeInterval(39) }; settings.sceneDidBecomeActive()
        XCTAssertEqual(layer.schedule?.offDay, "2026-11-02"); XCTAssertEqual(layer.writes, 2); XCTAssertNil(settings.offWait)
        tick(settings, at: tenAM.addingTimeInterval(40))
        XCTAssertEqual(layer.writes, 2, "the section runs once")
    }
    func testAWaitPastItsGraceCountsAsCancelled() {
        let (settings, layer) = waiting()
        settings.sceneDidBecomeInactive()
        tick(settings, at: tenAM.addingTimeInterval(35))
        settings.clock = { self.tenAM.addingTimeInterval(40) }; settings.sceneDidBecomeActive()
        XCTAssertNil(settings.offWait); XCTAssertNil(settings.refusalMessage)
        XCTAssertEqual(layer.writes, 1); XCTAssertNil(layer.schedule?.offDay)
    }
    /// The spec's guard row: a wait started at 23:54:45 in a range of 00:00-23:55, then Control Center held open past midnight.
    func testAWaitHeldInactivePastMidnightNeverTurnsTheNextDayOff() {
        let (settings, layer, _, _) = fixture()
        let start = at(23, 54, 45)
        layer.write(EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 0, rangeEnd: 1435, windows: []), apps(0..<1))
        _ = try? settings.focus.services.engine.reconcile(now: start, authorized: true)
        settings.clock = { start }; settings.refresh()
        XCTAssertTrue(settings.offersOffForToday)
        settings.startOffWait()
        settings.sceneDidBecomeInactive()
        tick(settings, at: at(23, 55, 20))
        XCTAssertNotNil(settings.offWait, "the grace runs to 23:55:25")
        settings.clock = { self.at(0, 0, 5, day: 3) }; settings.sceneDidBecomeActive()
        XCTAssertNil(settings.offWait); XCTAssertNil(settings.refusalMessage)
        XCTAssertEqual(layer.writes, 1); XCTAssertNil(layer.schedule?.offDay, "the section never runs with a now of the next day")
    }
    func testTheActionIsOfferedOnlyInsideTheRangeWithTheLayerOnEditingOpenAndAccess() {
        let (settings, layer, _, _) = fixture()
        settings.refresh()
        XCTAssertFalse(settings.offersOffForToday, "no stored layer")
        storedLayer(layer, settings); settings.refresh()
        XCTAssertTrue(settings.offersOffForToday)
        settings.clock = { self.at(12, 30) }; settings.refreshStatus()
        XCTAssertTrue(settings.offersOffForToday, "also during a window")
        for time in [at(7, 59), at(18, 0)] {
            settings.clock = { time }; settings.refreshStatus()
            XCTAssertFalse(settings.offersOffForToday, "\(time)")
        }
        settings.clock = { self.tenAM }; settings.refreshStatus()
        (settings.focus.services.authorization as? ModelTestAuthorization)?.status = .denied
        settings.refreshStatus()
        XCTAssertFalse(settings.offersOffForToday, "without access")
        (settings.focus.services.authorization as? ModelTestAuthorization)?.status = .approved
        settings.refreshStatus()
        XCTAssertTrue(settings.offersOffForToday)
        settings.startOffWait()
        XCTAssertFalse(settings.offersOffForToday, "not while the wait is open")
        settings.cancelOffWait()
        layer.schedule?.enabled = false; settings.refreshStatus()
        XCTAssertFalse(settings.offersOffForToday, "a stored layer that is off")
    }
    func testTheActionIsNotOfferedDuringAFocusSession() {
        let (settings, layer, _, _) = fixture()
        storedLayer(layer, settings)
        settings.focus.completeOnboarding(); settings.focus.start()
        XCTAssertTrue(settings.focus.isActive)
        settings.refresh()
        XCTAssertFalse(settings.offersOffForToday)
        settings.startOffWait()
        XCTAssertNil(settings.offWait)
    }
    func testARefusedSectionShowsItsReasonAndReadsTheStatusAgain() {
        let (settings, layer) = waiting()
        // A save elsewhere changed the stored revision during the wait.
        layer.schedule?.revision = UUID()
        tick(settings, at: tenAM.addingTimeInterval(30))
        XCTAssertEqual(settings.refusalMessage, "매일 제한이 바뀌어서 끄지 않았어요. 다시 시도해 주세요.")
        XCTAssertNil(layer.schedule?.offDay); XCTAssertNil(settings.offWait)
        XCTAssertEqual(settings.status?.schedule?.revision, layer.schedule?.revision)
        // The range end passed during the wait: editing is open now.
        let (late, lateLayer, _, _) = fixture()
        storedLayer(lateLayer, late)
        late.clock = { self.at(17, 59, 50) }; late.refresh(); late.startOffWait()
        tick(late, at: at(18, 0, 20))
        XCTAssertEqual(late.refusalMessage, "제한 시간이 끝났어요. 지금은 자유롭게 바꿀 수 있어요.")
        XCTAssertNil(lateLayer.schedule?.offDay)
    }
    func testOffRefusalCopy() {
        let cases: [(Error, String)] = [
            (ControlIssue.unauthorized, "스크린 타임 권한을 허용하면 끌 수 있어요."),
            (ControlIssue.busy, "집중 시간이 끝난 뒤에 끌 수 있어요."),
            (EverydayOffRefusal.unreadable, "설정을 불러오지 못해서 끄지 않았어요. 다시 설정해 주세요."),
            (EverydayOffRefusal.notOn, "매일 제한이 이미 꺼져 있어요."),
            (EverydayOffRefusal.revisionChanged, "매일 제한이 바뀌어서 끄지 않았어요. 다시 시도해 주세요."),
            (EverydayOffRefusal.outsideRange, "제한 시간이 끝났어요. 지금은 자유롭게 바꿀 수 있어요."),
            (EverydayOffRefusal.alreadyOff, "오늘은 이미 꺼 두었어요."),
            (ControlIssue.lockTimeout, "오늘만 끄지 못했어요. 제한은 그대로예요. 다시 시도해 주세요."),
        ]
        for (error, message) in cases { XCTAssertEqual(EverydaySettingsModel.offMessage(for: error), message, "\(error)") }
    }
    func testRefusedSaveNamesTheConditionAndPointsToTheActionOnlyWhenOffered() {
        let (settings, layer, _, _) = fixture()
        storedLayer(layer, settings); settings.refresh()
        settings.draft.windows = [EverydaySchedule.template(.lunch)!, EverydayWindow(kind: .custom, start: 900, end: 930)]
        settings.save()
        XCTAssertEqual(settings.refusalMessage, "제한 시간에는 풀어 두는 시간을 더하거나 늘리거나 옮길 수 없어요. 18:00부터 자유롭게 바꿀 수 있어요. ‘오늘만 끄기’를 누르면 오늘은 제한을 끌 수 있어요.")
        settings.startOffWait(); tick(settings, at: tenAM.addingTimeInterval(30))
        settings.draft.windows = [EverydaySchedule.template(.lunch)!]; settings.draft.enabled = false
        settings.save()
        XCTAssertEqual(settings.refusalMessage, "제한 시간에는 매일 제한을 끌 수 없어요. 18:00부터 자유롭게 바꿀 수 있어요.", "no pointer while off for today")
        let messages = EverydayLockReason.allCases.map { EverydaySettingsModel.lockMessage($0, opensAt: 1080, offersOffForToday: false) }
        XCTAssertEqual(messages, [
            "제한 시간에는 매일 제한을 끌 수 없어요. 18:00부터 자유롭게 바꿀 수 있어요.",
            "제한 시간에는 지금 시각이 빠지게 제한 시간을 바꿀 수 없어요. 18:00부터 자유롭게 바꿀 수 있어요.",
            "제한 시간에는 제한 끝을 앞당길 수 없어요. 18:00부터 자유롭게 바꿀 수 있어요.",
            "제한 시간에는 풀어 두는 시간을 더하거나 늘리거나 옮길 수 없어요. 18:00부터 자유롭게 바꿀 수 있어요.",
            "제한 시간에는 고른 앱과 웹사이트를 뺄 수 없어요. 18:00부터 자유롭게 바꿀 수 있어요.",
        ])
    }
    func testAStricterSaveWhileOffForTodayKeepsTheOffDay() {
        let (settings, layer) = waiting()
        tick(settings, at: tenAM.addingTimeInterval(30))
        settings.draft.windows = []
        settings.save()
        XCTAssertNil(settings.refusalMessage); XCTAssertEqual(layer.schedule?.windows, [])
        XCTAssertEqual(layer.schedule?.offDay, "2026-11-02"); XCTAssertEqual(settings.status?.offForToday, true)
        XCTAssertFalse(settings.hasChanges, "the off day never counts as an unsaved edit")
    }
    func testTheScreenAlsoReadsTheStatusAtTodaysRangeStartAndEnd() {
        let early = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 480, rangeEnd: 1080, windows: [EverydayWindow(kind: .toSchool, start: 480, end: 510)])
        // Before a range that starts with a window, the next change is the window end; the screen also reads at the range start.
        let before = EverydayStatus(schedule: early, blocksNow: false, nextChange: at(8, 30), issue: nil)
        XCTAssertEqual(EverydaySettingsModel.statusReadDelay(before, now: at(7, 0), retried: false), 5400 + EverydaySettingsModel.boundaryGrace)
        XCTAssertEqual(EverydaySettingsModel.statusReadDelay(before, now: at(7, 0), retried: false, rangeCalendar: calendar), 3600 + EverydaySettingsModel.boundaryGrace)
        // On a day that is off, the next change is tomorrow; the screen also reads at today's range end.
        let off = EverydayStatus(schedule: early, blocksNow: false, nextChange: at(8, 30, day: 3), issue: nil, offForToday: true)
        XCTAssertEqual(EverydaySettingsModel.statusReadDelay(off, now: at(10, 0), retried: false, rangeCalendar: calendar), 8 * 3600 + EverydaySettingsModel.boundaryGrace)
        XCTAssertEqual(EverydaySettingsModel.statusReadDelay(off, now: at(18, 0), retried: false, rangeCalendar: calendar),
                       at(8, 30, day: 3).timeIntervalSince(at(18, 0)) + EverydaySettingsModel.boundaryGrace, "edges that have passed are skipped")
    }
}
