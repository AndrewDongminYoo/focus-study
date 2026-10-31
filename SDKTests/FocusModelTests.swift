import XCTest
import FamilyControls

@MainActor final class FocusModelTests: XCTestCase {
    private func fixture(defaults: UserDefaults = UserDefaults(suiteName: UUID().uuidString)!) -> (FocusModel, ModelTestHistory, ModelTestStore, ModelTestShield, SessionControl) {
        let store = ModelTestStore(), shield = ModelTestShield(), monitoring = ModelTestMonitoring()
        let engine = SessionControl(store: store, monitoring: monitoring, shield: shield)
        var services = FocusServices(authorization: ModelTestAuthorization(), selection: ModelTestSelection(), engine: engine, applySelection: { _ in shield.applied = true }, matchesSelection: { _ in shield.applied }, isFixture: true)
        services.settings = FocusSettings(defaults: defaults)
        let history = ModelTestHistory(acknowledge: engine.acknowledgeTerminal)
        return (FocusModel(services: services, history: history), history, store, shield, engine)
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
    func stop(id: UUID) { ids.remove(id) }
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
