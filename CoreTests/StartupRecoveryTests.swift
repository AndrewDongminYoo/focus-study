import XCTest
@testable import FocusCore
final class StartupRecoveryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 10000)
    func testSelectionOrDatabaseFailureCannotBlockPreparingOrEndingRecovery() throws {
        for phase in [SessionPhase.preparing, .ending] {
            for _ in ["selection", "database"] {
                let store = MemoryControlStore(), monitor = FakeMonitoring(), shield = FakeShield()
                var session = ControlSession(startedAt: now); session.phase = phase
                if phase == .ending { session.reason = .earlyExit; session.observedAt = now }
                store.envelope.session = session; shield.apply()
                let recovery = StartupRecovery(engine: SessionControl(store: store, monitoring: monitor, shield: shield, breakSelection: FakeBreakSelection()))
                XCTAssertThrowsError(try recovery.prepare(now: now, authorized: true, loadStorage: { throw FixtureFailure.injected }))
                XCTAssertFalse(shield.applied); XCTAssertEqual(store.envelope.session?.phase, .terminal)
                XCTAssertNotNil(store.envelope.session) // Never acknowledge without durable history.
            }
        }
    }
    func testActiveSessionCanEndAndStorageCanRetryAfterBootstrapFailure() throws {
        let store = MemoryControlStore(), monitor = FakeMonitoring(), shield = FakeShield()
        let engine = SessionControl(store: store, monitoring: monitor, shield: shield, breakSelection: FakeBreakSelection())
        let session = try engine.start(now: now, authorized: { true }, apply: { shield.apply() }, matches: { true })
        let recovery = StartupRecovery(engine: engine)
        XCTAssertThrowsError(try recovery.prepare(now: now, authorized: true, loadStorage: { throw FixtureFailure.injected }))
        try recovery.endCurrent(now: now.addingTimeInterval(10))
        XCTAssertFalse(shield.applied); XCTAssertEqual(store.envelope.session?.reason, .earlyExit)
        var loaded = false
        try recovery.prepare(now: now, authorized: true, loadStorage: { loaded = true })
        XCTAssertTrue(loaded); XCTAssertEqual(store.envelope.session?.id, session.id)
    }
    private func endCurrent(paused: TimeInterval, credit: TimeInterval, at offset: TimeInterval) throws -> EndReason? {
        let store = MemoryControlStore(), monitor = FakeMonitoring(), shield = FakeShield()
        var session = ControlSession(startedAt: now); session.phase = .active; session.pausedSeconds = paused; session.deadlineCredit = credit
        store.envelope.session = session; monitor.intervals[session.id] = (now, now.addingTimeInterval(9000))
        try StartupRecovery(engine: SessionControl(store: store, monitoring: monitor, shield: shield, breakSelection: FakeBreakSelection())).endCurrent(now: now.addingTimeInterval(offset))
        return store.envelope.session?.reason
    }
    func testEndCurrentAfterBreakIsNotExpiredAtNominalEnd() throws {
        XCTAssertEqual(try endCurrent(paused: 300, credit: 480, at: 1500), .earlyExit)
    }
    func testEndCurrentAfterDeadlineWithLateFocusEndIsDeadlineMissed() throws {
        XCTAssertEqual(try endCurrent(paused: 895, credit: 195, at: 9000), .deadlineMissed)
    }
}
