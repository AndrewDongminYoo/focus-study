import XCTest
import FamilyControls

@MainActor final class FocusModelTests: XCTestCase {
    private func fixture() -> (FocusModel, ModelTestHistory, ModelTestStore, ModelTestShield, SessionControl) {
        let store = ModelTestStore(), shield = ModelTestShield(), monitoring = ModelTestMonitoring()
        let engine = SessionControl(store: store, monitoring: monitoring, shield: shield)
        let services = FocusServices(authorization: ModelTestAuthorization(), selection: ModelTestSelection(), engine: engine, applySelection: { _ in shield.applied = true }, matchesSelection: { _ in shield.applied }, isFixture: true)
        let history = ModelTestHistory(acknowledge: engine.acknowledgeTerminal)
        return (FocusModel(services: services, history: history), history, store, shield, engine)
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
    var status: AccessStatus { .approved }
    func requestIndividual() async {}
    func refresh() {}
    func hasAccessNow() -> Bool { true }
}
@MainActor private final class ModelTestSelection: SelectionStoring {
    var selection = FamilyActivitySelection()
    var counts: (apps: Int, websites: Int, categories: Int) { (1,0,0) }
    func save(_ selection: FamilyActivitySelection) throws {}
}
