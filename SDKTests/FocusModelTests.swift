import XCTest
import FamilyControls

@MainActor final class FocusModelTests: XCTestCase {
    private func fixture(defaults: UserDefaults = UserDefaults(suiteName: UUID().uuidString)!) -> (FocusModel, ModelTestHistory, ModelTestStore, ModelTestShield, SessionControl) {
        let store = ModelTestStore(), shield = ModelTestShield(), monitoring = ModelTestMonitoring()
        let (model, history, _) = makeModel(store: store, monitoring: monitoring, shield: shield, defaults: defaults, timing: .standard)
        return (model, history, store, shield, model.services.engine)
    }
    private func makeModel(store: ModelTestStore, monitoring: ModelTestMonitoring, shield: ModelTestShield, defaults: UserDefaults, timing: BreakTiming) -> (FocusModel, ModelTestHistory, ModelTestBreakSelection) {
        let copies = ModelTestBreakSelection(); copies.onRestore = { shield.applied = true }
        let engine = SessionControl(store: store, monitoring: monitoring, shield: shield, breakSelection: copies, timing: timing)
        var services = FocusServices(authorization: ModelTestAuthorization(), selection: ModelTestSelection(), engine: engine, applySelection: { _ in shield.applied = true }, matchesSelection: { _ in shield.applied }, isFixture: true)
        services.settings = FocusSettings(defaults: defaults)
        services.saveBreakSelection = { selection, id in copies.saved.append((selection, id)); copies.copies.insert(id) }
        let history = ModelTestHistory(acknowledge: engine.acknowledgeTerminal)
        return (FocusModel(services: services, history: history), history, copies)
    }
    /// Waits of 0 seconds and a 50-millisecond break, so that the model's own clock drives every phase.
    private func breakFixture(slack: TimeInterval = 600) -> (FocusModel, ModelTestBreakSelection, ModelTestShield) {
        let shield = ModelTestShield()
        let (model, _, copies) = makeModel(store: ModelTestStore(), monitoring: ModelTestMonitoring(), shield: shield, defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                           timing: BreakTiming(waits: [0, 0, 0], breakLength: 0.05, slack: slack, staleWaitGrace: 5))
        model.completeOnboarding(); model.start()
        XCTAssertTrue(model.isActive)
        return (model, copies, shield)
    }
    /// One break from the request to the re-block.
    private func takeBreak(_ model: FocusModel) {
        model.requestBreak(); XCTAssertEqual(model.current?.phase, .waiting)
        model.tick(); XCTAssertEqual(model.current?.phase, .onBreak)
        usleep(80_000); model.tick(); XCTAssertEqual(model.current?.phase, .breakOver)
    }
    private func doubles(_ model: FocusModel) -> (ModelTestAuthorization, ModelTestSelection) {
        (model.services.authorization as! ModelTestAuthorization, model.services.selection as! ModelTestSelection)
    }
    func testRouteForNewUserFollowsOnboardingOrder() {
        let (model, _, _, _, _) = fixture(); let (access, selection) = doubles(model)
        access.status = .notRequested; selection.counts = (0, 0, 0)
        XCTAssertEqual(model.route, .onboarding(.intro))
        access.status = .denied; XCTAssertEqual(model.route, .onboarding(.permission))
        access.status = .approved; XCTAssertEqual(model.route, .onboarding(.selection))
        selection.counts = (1, 0, 0); XCTAssertEqual(model.route, .onboarding(.length))
        model.completeOnboarding(); XCTAssertEqual(model.route, .timer)
    }
    func testRelaunchAfterSelectionResumesAtLengthStep() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let (first, _, _, _, _) = fixture(defaults: defaults)
        first.services.settings.migrateIfNeeded(hasSelection: false)
        XCTAssertEqual(first.route, .onboarding(.length))
        let (relaunched, _, _, _, _) = fixture(defaults: defaults)
        relaunched.services.settings.migrateIfNeeded(hasSelection: true)
        XCTAssertEqual(relaunched.route, .onboarding(.length))
    }
    func testExistingSelectionMigratesEvenWhenFirstAccessReadIsNotApproved() {
        let (model, _, _, _, _) = fixture(); let (access, selection) = doubles(model)
        access.status = .denied; selection.counts = (1, 0, 0)
        model.services.settings.migrateIfNeeded(hasSelection: true)
        access.status = .approved
        XCTAssertEqual(model.route, .timer)
    }
    func testRevokedAccessAfterCompletionShowsPermissionThenTimer() throws {
        let (model, _, _, shield, engine) = fixture(); let (access, _) = doubles(model)
        model.completeOnboarding()
        _ = try engine.start(now: Date(), authorized: { true }, apply: { shield.applied = true }, matches: { true })
        model.refresh(); XCTAssertTrue(model.isActive)
        access.status = .denied; model.refresh()
        XCTAssertFalse(model.isActive); XCTAssertFalse(shield.applied)
        XCTAssertEqual(model.route, .onboarding(.permission))
        access.status = .approved; XCTAssertEqual(model.route, .timer)
    }
    func testStartUsesConfiguredLength() {
        let (model, _, _, _, _) = fixture(); model.services.settings.lengthMinutes = 40; model.completeOnboarding()
        XCTAssertEqual(model.remaining, 2400)
        model.start(); XCTAssertEqual(model.current?.length, 2400)
    }
    func testChangingLengthDuringSessionKeepsRunningSession() {
        let (model, _, _, _, _) = fixture(); model.completeOnboarding()
        model.start(); let end = model.current?.expiresAt
        model.services.settings.lengthMinutes = 50; model.refresh()
        XCTAssertEqual(model.current?.expiresAt, end); XCTAssertEqual(model.current?.length, 1500)
    }
    func testHistoryFetchFailurePreservesActiveControlsAndCanEndRestrictions() throws {
        let (model, history, _, shield, engine) = fixture()
        let session = try engine.start(now: Date(), authorized: { true }, apply: { shield.applied = true }, matches: { true })
        history.failFetch = true
        model.refresh()
        XCTAssertEqual(model.current?.id, session.id)
        XCTAssertTrue(model.isActive); XCTAssertNotNil(model.errorMessage)
        model.end()
        XCTAssertFalse(shield.applied)
        XCTAssertNil(try engine.snapshot().session)
    }
    func testControlReadFailureStillInvalidatesPreviouslyConfirmedSession() throws {
        let (model, _, store, shield, engine) = fixture()
        _ = try engine.start(now: Date(), authorized: { true }, apply: { shield.applied = true }, matches: { true })
        model.refresh(); XCTAssertTrue(model.isActive)
        store.failRead = true
        model.refresh()
        XCTAssertNil(model.current); XCTAssertFalse(model.isActive); XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(shield.applied)
    }
    func testOnlyAFullSessionIsMarkedCompletedUntilDismissed() throws {
        let (model, _, _, shield, engine) = fixture()
        let session = try engine.start(now: Date().addingTimeInterval(-1500), authorized: { true }, apply: { shield.applied = true }, matches: { true })
        model.refresh()
        XCTAssertEqual(model.completedSessionID, session.id); XCTAssertNil(model.current)
        model.dismissCompletion()
        XCTAssertNil(model.completedSessionID)
        model.start(); XCTAssertTrue(model.isActive)
        model.end()
        XCTAssertNil(model.completedSessionID)
    }
    func testCompletionKeepsTheSessionsOwnLengthAfterTheSettingChanges() throws {
        let (model, _, _, shield, engine) = fixture()
        _ = try engine.start(now: Date().addingTimeInterval(-2400), length: 2400, authorized: { true }, apply: { shield.applied = true }, matches: { true })
        model.services.settings.lengthMinutes = 25
        model.refresh()
        XCTAssertEqual(model.completedLength, 2400)
        model.dismissCompletion(); XCTAssertNil(model.completedLength)
    }
    func testStartBlockerNamesTheFirstUnmetCondition() throws {
        let (model, history, _, shield, engine) = fixture()
        let selection = try XCTUnwrap(model.services.selection as? ModelTestSelection)
        model.refresh(); XCTAssertNil(model.startBlocker)
        selection.counts = (0, 0, 0)
        XCTAssertEqual(model.startBlocker, .selection)
        history.failFetch = true; model.refresh()
        XCTAssertEqual(model.startBlocker, .error)
        history.failFetch = false; selection.counts = (1, 0, 0); model.refresh()
        _ = try engine.start(now: Date(), authorized: { true }, apply: { shield.applied = true }, matches: { true })
        model.refresh(); XCTAssertNil(model.startBlocker)
    }
    func testRequestBreakPausesRemaining() throws {
        let (model, _, store, shield, engine) = fixture()
        let session = try engine.start(now: Date().addingTimeInterval(-300), authorized: { true }, apply: { shield.applied = true }, matches: { true })
        model.refresh(); XCTAssertEqual(model.remaining, 1200)
        model.requestBreak()
        XCTAssertEqual(store.envelope.session?.phase, .waiting); XCTAssertTrue(model.isInSession); XCTAssertFalse(model.isActive)
        let paused = model.remaining
        usleep(1_100_000); model.tick()
        XCTAssertEqual(model.remaining, paused); XCTAssertEqual(model.current?.id, session.id)
        XCTAssertNotNil(model.waitProgress); XCTAssertTrue(shield.applied)
    }
    func testLeavingForegroundCancelsWaitAndKeepsBreaksLeft() {
        let (model, copies, shield) = breakFixture()
        model.requestBreak(); XCTAssertEqual(model.current?.phase, .waiting)
        model.sceneDidLeaveForeground()
        XCTAssertEqual(model.current?.phase, .active); XCTAssertEqual(model.breaksLeft, 3)
        XCTAssertTrue(copies.saved.isEmpty); XCTAssertTrue(shield.applied)
    }
    func testTickStartsBreakAfterWaitWithFrozenSelection() {
        let (model, copies, shield) = breakFixture()
        let id = model.current?.id
        model.requestBreak(); model.tick()
        XCTAssertEqual(model.current?.phase, .onBreak); XCTAssertEqual(model.current?.breaksTaken, 1)
        XCTAssertEqual(copies.saved.map(\.1), [id].compactMap { $0 })
        XCTAssertEqual(copies.saved.first?.0.applicationTokens, model.services.selection.selection.applicationTokens)
        XCTAssertEqual(copies.saved.first?.0.webDomainTokens, model.services.selection.selection.webDomainTokens)
        XCTAssertFalse(shield.applied); XCTAssertNotNil(model.breakRemaining)
    }
    func testSelectionIsLockedDuringBreakAndAfterReBlock() {
        let (model, _, _) = breakFixture()
        model.requestBreak(); model.tick()
        XCTAssertEqual(model.current?.phase, .onBreak); XCTAssertTrue(model.isInSession)
        XCTAssertThrowsError(try model.saveSelection(FamilyActivitySelection()))
        usleep(80_000); model.tick()
        XCTAssertEqual(model.current?.phase, .breakOver); XCTAssertTrue(model.isInSession)
        XCTAssertThrowsError(try model.saveSelection(FamilyActivitySelection()))
    }
    func testResumeContinuesCountdownFromPausedValue() {
        let (model, _, shield) = breakFixture()
        takeBreak(model)
        XCTAssertTrue(shield.applied)
        let paused = model.remaining
        model.resume()
        XCTAssertEqual(model.current?.phase, .active)
        XCTAssertLessThanOrEqual(abs(model.remaining - paused), 1)
    }
    func testResumeRemainingReachesZeroWhenSessionCanNoLongerComplete() {
        let (roomy, _, _) = breakFixture()
        takeBreak(roomy)
        XCTAssertGreaterThan(roomy.resumeRemaining ?? 0, 590)
        let (late, _, _) = breakFixture(slack: 0)
        takeBreak(late)
        XCTAssertEqual(late.resumeRemaining, 0)
    }
    func testNoBreakActionAfterThirdBreak() {
        let (model, _, _) = breakFixture()
        for _ in 0..<3 { takeBreak(model); model.resume() }
        XCTAssertEqual(model.breaksLeft, 0); XCTAssertEqual(model.current?.phase, .active)
        let before = model.current
        model.requestBreak()
        XCTAssertEqual(model.current, before); XCTAssertNil(model.errorMessage)
    }
}
private final class ModelTestBreakSelection: BreakSelectionStore {
    var copies = Set<UUID>(), saved: [(FamilyActivitySelection, UUID)] = []
    var onRestore: () -> Void = {}
    func restoreShield(id: UUID) -> Bool { guard copies.contains(id) else { return false }; onRestore(); return true }
    func exists(id: UUID) -> Bool { copies.contains(id) }
    func remove(id: UUID) { copies.remove(id) }
    func removeAll(except id: UUID?) { copies = copies.filter { $0 == id } }
}
private enum ModelTestError: Error { case storage }
private final class ModelTestStore: ControlStore, LockedControl {
    var envelope = ControlEnvelope(), failRead = false
    func withExclusiveAccess<T>(_ body: (LockedControl) throws -> T) throws -> T { try body(self) }
    func load() throws -> ControlEnvelope { if failRead { throw ModelTestError.storage }; return envelope }
    func save(_ envelope: ControlEnvelope) throws { self.envelope = envelope }
}
private final class ModelTestMonitoring: MonitoringClient {
    var ids = Set<UUID>(); var registeredSessionIDs: [UUID] { Array(ids) }
    func register(id: UUID, start: Date, end: Date) throws { ids.insert(id) }
    func isRegistered(id: UUID) -> Bool { ids.contains(id) }
    func stop(id: UUID) { ids.remove(id); breaks.removeAll { $0.id == id } }
    var breaks: [(id: UUID, index: Int)] = []
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws { breaks.append((id, index)) }
    func isBreakRegistered(id: UUID, index: Int) -> Bool { breaks.contains { $0.id == id && $0.index == index } }
    var registeredBreaks: [(id: UUID, index: Int)] { breaks }
    func stopBreak(id: UUID, index: Int) { breaks.removeAll { $0.id == id && $0.index == index } }
}
private final class ModelTestShield: ShieldClient {
    var applied = false
    func clear() { applied = false }
}
@MainActor private final class ModelTestHistory: SessionHistoryProviding {
    var failFetch = false
    let acknowledge: (UUID) throws -> Void
    init(acknowledge: @escaping (UUID) throws -> Void) { self.acknowledge = acknowledge }
    func importTerminal(_ session: ControlSession) throws { try acknowledge(session.id) }
    func records(on date: Date, calendar: Calendar) throws -> [SessionRecord] { if failFetch { throw ModelTestError.storage }; return [] }
}
@MainActor private final class ModelTestAuthorization: AuthorizationProviding {
    var status: AccessStatus = .approved
    func requestIndividual() async {}
    func refresh() {}
    func hasAccessNow() -> Bool { status == .approved }
}
@MainActor private final class ModelTestSelection: SelectionStoring {
    var selection = FamilyActivitySelection()
    var counts: (apps: Int, websites: Int, categories: Int) = (1, 0, 0)
    func save(_ selection: FamilyActivitySelection) throws {}
}
