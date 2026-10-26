import XCTest
@testable import FocusCore

final class SessionControlTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func fixture() -> (SessionControl, MemoryControlStore, FakeMonitoring, FakeShield) {
        let store = MemoryControlStore(), monitor = FakeMonitoring(), shield = FakeShield()
        return (SessionControl(store: store, monitoring: monitor, shield: shield), store, monitor, shield)
    }
    func testStartUses25MinuteNonRepeatingIntervalAndCommitsActive() throws {
        let (engine, store, monitor, shield) = fixture()
        let s = try engine.start(now: now, authorized: { true }, apply: { shield.apply() }, matches: { shield.applied })
        XCTAssertEqual(s.phase, .active)
        XCTAssertEqual(s.expiresAt.timeIntervalSince(s.startedAt), 1500)
        XCTAssertEqual(monitor.intervals[s.id]?.1, now.addingTimeInterval(1500))
        XCTAssertEqual(store.envelope.session?.id, s.id)
        XCTAssertTrue(shield.applied)
    }
    func testDeniedAuthorizationCannotStartOrApply() {
        let (engine, store, monitor, shield) = fixture()
        XCTAssertThrowsError(try engine.start(now: now, authorized: { false }, apply: { shield.apply() }, matches: { true }))
        XCTAssertNil(store.envelope.session); XCTAssertFalse(shield.applied); XCTAssertTrue(monitor.intervals.isEmpty)
    }
    func testRegistrationFailureRollsBackWithoutActiveState() {
        let (engine, store, monitor, shield) = fixture(); monitor.failRegistration = true
        XCTAssertThrowsError(try engine.start(now: now, authorized: { true }, apply: { shield.apply() }, matches: { true }))
        XCTAssertEqual(store.envelope.session?.phase, .terminal)
        XCTAssertEqual(store.envelope.session?.reason, .startFailed)
        XCTAssertFalse(shield.applied); XCTAssertTrue(monitor.intervals.isEmpty)
    }
    func testRegistrationReadbackFailureRollsBack() {
        let (engine, store, monitor, shield) = fixture(); monitor.hideRegistration = true
        XCTAssertThrowsError(try engine.start(now: now, authorized: { true }, apply: { shield.apply() }, matches: { true }))
        XCTAssertEqual(store.envelope.session?.phase, .terminal); XCTAssertFalse(shield.applied)
    }
    func testShieldMismatchRollsBack() {
        let (engine, store, monitor, shield) = fixture()
        XCTAssertThrowsError(try engine.start(now: now, authorized: { true }, apply: { shield.apply() }, matches: { false }))
        XCTAssertEqual(store.envelope.session?.phase, .terminal); XCTAssertFalse(shield.applied); XCTAssertTrue(monitor.intervals.isEmpty)
    }
    func testFailedActiveSaveRollsBack() {
        let (engine, store, monitor, shield) = fixture(); store.failPhase = .active
        XCTAssertThrowsError(try engine.start(now: now, authorized: { true }, apply: { shield.apply() }, matches: { true }))
        XCTAssertNotEqual(store.envelope.session?.phase, .active); XCTAssertFalse(shield.applied); XCTAssertTrue(monitor.intervals.isEmpty)
    }
    func testDoubleStartDoesNotClearCurrentSession() throws {
        let (engine, store, _, shield) = fixture()
        let a = try engine.start(now: now, authorized: { true }, apply: { shield.apply() }, matches: { true })
        XCTAssertThrowsError(try engine.start(now: now, authorized: { true }, apply: {}, matches: { true }))
        XCTAssertEqual(store.envelope.session?.id, a.id); XCTAssertTrue(shield.applied)
    }
    func testEarlyCallbackDoesNotEndActiveSession() throws {
        let (engine, store, _, shield) = fixture()
        let a = try engine.start(now: now, authorized: { true }, apply: { shield.apply() }, matches: { true })
        try engine.handleCallback(activityName: a.activityName, now: now.addingTimeInterval(1499), authorized: true)
        XCTAssertEqual(store.envelope.session?.phase, .active); XCTAssertTrue(shield.applied)
    }
    func testExpiryClearsOnlyOwnMonitoringAndPreservesObservationTime() throws {
        let (engine, store, monitor, shield) = fixture()
        let a = try engine.start(now: now, authorized: { true }, apply: { shield.apply() }, matches: { true })
        let unrelated = UUID(); monitor.intervals[unrelated] = (now, now.addingTimeInterval(3000))
        try engine.handleCallback(activityName: a.activityName, now: now.addingTimeInterval(1510), authorized: true)
        XCTAssertEqual(store.envelope.session?.reason, .expired)
        XCTAssertEqual(store.envelope.session?.observedAt, now.addingTimeInterval(1510))
        XCTAssertFalse(shield.applied); XCTAssertNotNil(monitor.intervals[unrelated]); XCTAssertNil(monitor.intervals[a.id])
    }
    func testStaleCallbackCannotClearNewSession() throws {
        let (engine, store, _, shield) = fixture()
        let a = try engine.start(now: now, authorized: { true }, apply: { shield.apply() }, matches: { true })
        try engine.finish(id: a.id, reason: .earlyExit, now: now.addingTimeInterval(1))
        try engine.acknowledgeTerminal(id: a.id)
        let b = try engine.start(now: now.addingTimeInterval(2), authorized: { true }, apply: { shield.apply() }, matches: { true })
        try engine.handleCallback(activityName: a.activityName, now: now.addingTimeInterval(1700), authorized: true)
        try engine.finish(id: a.id, reason: .earlyExit, now: now.addingTimeInterval(1700))
        XCTAssertEqual(store.envelope.session?.id, b.id); XCTAssertEqual(store.envelope.session?.phase, .active); XCTAssertTrue(shield.applied)
    }
    func testRepeatedFinishIsIdempotent() throws {
        let (engine, store, _, shield) = fixture()
        let a = try engine.start(now: now, authorized: { true }, apply: { shield.apply() }, matches: { true })
        try engine.finish(id: a.id, reason: .earlyExit, now: now.addingTimeInterval(10))
        try engine.finish(id: a.id, reason: .expired, now: now.addingTimeInterval(1500))
        XCTAssertEqual(store.envelope.session?.reason, .earlyExit); XCTAssertEqual(shield.clears, 1)
    }
    func testTerminalMustBeImportedBeforeNewStart() throws {
        let (engine, _, _, shield) = fixture()
        let a = try engine.start(now: now, authorized: { true }, apply: { shield.apply() }, matches: { true })
        try engine.finish(id: a.id, reason: .earlyExit, now: now)
        XCTAssertThrowsError(try engine.start(now: now, authorized: { true }, apply: {}, matches: { true }))
    }
    func testPreparingAndEndingAreRecovered() throws {
        for phase in [SessionPhase.preparing, .ending] {
            let (engine, store, _, shield) = fixture()
            var s = ControlSession(startedAt: now); s.phase = phase
            if phase == .ending { s.reason = .earlyExit; s.observedAt = now.addingTimeInterval(4) }
            store.envelope.session = s; shield.apply()
            let result = try engine.reconcile(now: now.addingTimeInterval(5), authorized: true)
            XCTAssertEqual(result.session?.phase, .terminal); XCTAssertFalse(shield.applied)
            XCTAssertEqual(result.session?.reason, phase == .preparing ? .recoveryInterrupted : .earlyExit)
        }
    }
    func testRevocationAndClockChangeInterruptSession() throws {
        for revoked in [true, false] {
            let (engine, _, _, shield) = fixture()
            _ = try engine.start(now: now, authorized: { true }, apply: { shield.apply() }, matches: { true })
            let result = try engine.reconcile(now: now, authorized: !revoked, clockChanged: !revoked)
            XCTAssertEqual(result.session?.reason, revoked ? .authorizationRevoked : .clockChanged)
            XCTAssertFalse(shield.applied)
        }
    }
    func testEndingWriteFailureStillAttemptsCleanup() throws {
        let (engine, store, monitor, shield) = fixture()
        let a = try engine.start(now: now, authorized: { true }, apply: { shield.apply() }, matches: { true })
        store.failPhase = .ending
        _ = try? engine.finish(id: a.id, reason: .earlyExit, now: now)
        XCTAssertFalse(shield.applied); XCTAssertNil(monitor.intervals[a.id])
    }
    func testUnreadableStateBlocksStartAndClearsOwnShield() {
        let (engine, store, _, shield) = fixture(); store.failRead = true; shield.apply()
        XCTAssertThrowsError(try engine.start(now: now, authorized: { true }, apply: {}, matches: { true }))
        XCTAssertFalse(shield.applied)
    }
}

enum FixtureFailure: Error { case injected }
final class MemoryControlStore: ControlStore, LockedControl {
    var envelope = ControlEnvelope(), failPhase: SessionPhase?, failRead = false
    func withExclusiveAccess<T>(_ body: (LockedControl) throws -> T) throws -> T { try body(self) }
    func load() throws -> ControlEnvelope { if failRead { throw FixtureFailure.injected }; return envelope }
    func save(_ envelope: ControlEnvelope) throws {
        if let failPhase, envelope.session?.phase == failPhase { throw FixtureFailure.injected }
        self.envelope = envelope
    }
}
final class FakeMonitoring: MonitoringClient {
    var intervals: [UUID: (Date, Date)] = [:], failRegistration = false, hideRegistration = false
    func register(id: UUID, start: Date, end: Date) throws {
        if failRegistration { throw FixtureFailure.injected }; intervals[id] = (start, end)
    }
    func isRegistered(id: UUID) -> Bool { !hideRegistration && intervals[id] != nil }
    func stop(id: UUID) { intervals.removeValue(forKey: id) }
}
final class FakeShield: ShieldClient {
    var applied = false, clears = 0
    func apply() { applied = true }
    func clear() { applied = false; clears += 1 }
}
