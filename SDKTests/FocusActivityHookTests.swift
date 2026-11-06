import XCTest

@MainActor final class FocusActivityHookTests: XCTestCase {
    private final class Events { var phases: [SessionPhase?] = [] }
    private func fixture() -> (FocusModel, ModelTestStore, ModelTestHistory, Events) {
        let store = ModelTestStore(), monitor = ModelTestMonitoring(), shield = ModelTestShield()
        let engine = SessionControl(store: store, monitoring: monitor, shield: shield, breakSelection: ModelTestBreakSelection(), everyday: ModelTestEverydayLayer())
        var services = FocusServices(authorization: ModelTestAuthorization(), selection: ModelTestSelection(), engine: engine,
                                     applySelection: { _ in shield.applied = true }, matchesSelection: { _ in shield.applied }, isFixture: true)
        services.settings = FocusSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let events = Events()
        services.activityDidChange = { events.phases.append((try? engine.snapshot())?.session?.phase) }
        let history = ModelTestHistory(acknowledge: engine.acknowledgeTerminal)
        return (FocusModel(services: services, history: history), store, history, events)
    }
    func testRefreshPublishesAfterTheControlSnapshot() {
        let (model, _, _, events) = fixture()
        model.refresh()
        XCTAssertEqual(events.phases, [nil])
    }
    func testStartAndEndPublishCommittedStateWithoutChangingSuccess() {
        let (model, _, _, events) = fixture()
        model.start()
        XCTAssertTrue(model.isActive)
        XCTAssertEqual(events.phases.compactMap { $0 }.last, .active)
        events.phases = []
        model.end()
        XCTAssertNil(model.current)
        XCTAssertEqual(events.phases, [nil])
    }
    func testControlReadFailureStillInvalidatesTheDisplay() {
        let (model, store, _, events) = fixture()
        store.failRead = true
        model.refresh()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(events.phases, [nil])
    }
    func testEndWriteFailureStillPublishesTheCommittedTerminalState() {
        let (model, store, _, events) = fixture()
        model.start(); events.phases = []; store.failSavePhase = .ending
        model.end()
        XCTAssertEqual(store.envelope.session?.phase, .terminal)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(events.phases, [.terminal])
    }
    func testHistoryFailureKeepsTheConfirmedSessionAndNotifiesDisplay() {
        let (model, _, history, events) = fixture()
        model.start(); history.failFetch = true; events.phases = []
        model.refresh()
        XCTAssertTrue(model.isActive); XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(events.phases, [.active])
    }
    func testBackgroundFilterOffNotifiesEvenWhenStorageFactoryCannotLoad() async throws {
        let (model, _, _, events) = fixture()
        var notified = 0
        let holder = FocusRuntimeHolder(engine: model.services.engine, authorization: model.services.authorization, settings: model.services.settings,
                                        activityDidChange: { notified += 1 }) { throw ControlIssue.io }
        try await holder.focusDidChange(startsSession: false)
        XCTAssertEqual(notified, 1)
        XCTAssertTrue(events.phases.isEmpty)
    }
}
