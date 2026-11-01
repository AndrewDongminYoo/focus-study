import XCTest
import FamilyControls
import ManagedSettings

@MainActor final class EverydaySettingsModelTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!; return calendar
    }()
    /// 10:00 in Seoul: inside the range 08:00-18:00 and before lunch.
    private var tenAM: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 10))! }
    private func fixture() -> (EverydaySettingsModel, ModelTestEverydayLayer, ModelTestMonitoring, ModelTestSelection) {
        let layer = ModelTestEverydayLayer(), monitoring = ModelTestMonitoring(), shield = ModelTestShield(), selection = ModelTestSelection()
        let engine = SessionControl(store: ModelTestStore(), monitoring: monitoring, shield: shield, breakSelection: ModelTestBreakSelection(), everyday: layer, calendar: calendar)
        var services = FocusServices(authorization: ModelTestAuthorization(), selection: selection, engine: engine,
                                     applySelection: { _ in shield.applied = true }, matchesSelection: { _ in shield.applied }, isFixture: true)
        services.settings = FocusSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        services.everydaySelection = { layer.schedule == nil ? nil : layer.selection }
        services.everydayContains = { layer.contains($0) }
        services.writeEveryday = { layer.write($0, $1) }
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
    func testSaveInsideTheRangeShowsTheRefusalWithTheRangeEnd() {
        let (settings, layer, _, _) = fixture()
        storedLayer(layer, settings)
        let stored = layer.schedule
        settings.refresh()
        settings.draft.enabled = false
        settings.save()
        XCTAssertEqual(settings.refusalMessage, "제한 시간에는 더 엄격하게만 바꿀 수 있어요. 18:00부터 자유롭게 바꿀 수 있어요.")
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
}
