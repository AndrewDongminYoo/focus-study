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
                let recovery = StartupRecovery(engine: SessionControl(store: store, monitoring: monitor, shield: shield))
                XCTAssertThrowsError(try recovery.prepare(now: now, authorized: true, loadStorage: { throw FixtureFailure.injected }))
                XCTAssertFalse(shield.applied); XCTAssertEqual(store.envelope.session?.phase, .terminal)
                XCTAssertNotNil(store.envelope.session) // Never acknowledge without durable history.
            }
        }
    }
    func testActiveSessionCanEndAndStorageCanRetryAfterBootstrapFailure() throws {
        let store = MemoryControlStore(), monitor = FakeMonitoring(), shield = FakeShield()
        let engine = SessionControl(store: store, monitoring: monitor, shield: shield)
        let session = try engine.start(now: now, authorized: { true }, apply: { shield.apply() }, matches: { true })
        let recovery = StartupRecovery(engine: engine)
        XCTAssertThrowsError(try recovery.prepare(now: now, authorized: true, loadStorage: { throw FixtureFailure.injected }))
        try recovery.endCurrent(now: now.addingTimeInterval(10))
        XCTAssertFalse(shield.applied); XCTAssertEqual(store.envelope.session?.reason, .earlyExit)
        var loaded = false
        try recovery.prepare(now: now, authorized: true, loadStorage: { loaded = true })
        XCTAssertTrue(loaded); XCTAssertEqual(store.envelope.session?.id, session.id)
    }
}
