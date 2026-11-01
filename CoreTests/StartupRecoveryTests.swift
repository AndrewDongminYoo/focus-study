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
                let recovery = StartupRecovery(engine: SessionControl(store: store, monitoring: monitor, shield: shield, breakSelection: FakeBreakSelection(), everyday: FakeEverydayStore()))
                XCTAssertThrowsError(try recovery.prepare(now: now, authorized: true, loadStorage: { throw FixtureFailure.injected }))
                XCTAssertFalse(shield.applied); XCTAssertEqual(store.envelope.session?.phase, .terminal)
                XCTAssertNotNil(store.envelope.session) // Never acknowledge without durable history.
            }
        }
    }
    func testActiveSessionCanEndAndStorageCanRetryAfterBootstrapFailure() throws {
        let store = MemoryControlStore(), monitor = FakeMonitoring(), shield = FakeShield()
        let engine = SessionControl(store: store, monitoring: monitor, shield: shield, breakSelection: FakeBreakSelection(), everyday: FakeEverydayStore())
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
        try StartupRecovery(engine: SessionControl(store: store, monitoring: monitor, shield: shield, breakSelection: FakeBreakSelection(), everyday: FakeEverydayStore())).endCurrent(now: now.addingTimeInterval(offset))
        return store.envelope.session?.reason
    }
    func testEndCurrentAfterBreakIsNotExpiredAtNominalEnd() throws {
        XCTAssertEqual(try endCurrent(paused: 300, credit: 480, at: 1500), .earlyExit)
    }
    func testEndCurrentAfterDeadlineWithLateFocusEndIsDeadlineMissed() throws {
        XCTAssertEqual(try endCurrent(paused: 895, credit: 195, at: 9000), .deadlineMissed)
    }
    /// The recorded `observedAt` drives the end and its history; the everyday layer follows the wall clock of the section.
    func testEndCurrentOfAnEndingSessionConvergesTheEverydayLayerAtTheWallClock() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let at = { (hour: Int) in calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: hour))! }
        // Observed outside the range and ended inside it, then the reverse.
        for (observed, wallClock, blocks) in [(7, 10, true), (10, 19, false)] {
            let store = MemoryControlStore(), monitor = FakeMonitoring(), shield = FakeShield(), everyday = FakeEverydayStore()
            everyday.schedule = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 480, rangeEnd: 1080, windows: [])
            everyday.shieldOn = blocks
            var session = ControlSession(startedAt: at(observed).addingTimeInterval(-600)); session.phase = .ending
            session.reason = .earlyExit; session.observedAt = at(observed)
            store.envelope.session = session
            let engine = SessionControl(store: store, monitoring: monitor, shield: shield, breakSelection: FakeBreakSelection(), everyday: everyday, calendar: calendar)
            try StartupRecovery(engine: engine).endCurrent(now: at(wallClock))
            XCTAssertEqual(store.envelope.session?.phase, .terminal)
            XCTAssertEqual(store.envelope.session?.observedAt, at(observed))
            XCTAssertEqual(everyday.shieldOn, blocks, "observed \(observed):00, ended \(wallClock):00")
        }
    }
}
