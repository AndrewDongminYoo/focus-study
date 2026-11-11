import XCTest
@testable import FocusCore

final class SessionControlTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func fixture() -> (SessionControl, MemoryControlStore, FakeMonitoring, FakeShield) {
        let store = MemoryControlStore(), monitor = FakeMonitoring(), shield = FakeShield()
        return (SessionControl(store: store, monitoring: monitor, shield: shield, breakSelection: FakeBreakSelection(), everyday: FakeEverydayStore()), store, monitor, shield)
    }
    func testStartUses25MinuteNonRepeatingIntervalAndCommitsActive() throws {
        let (engine, store, monitor, shield) = fixture()
        let s = try engine.start(now: now, authorized: { .approved }, apply: { shield.apply() }, matches: { shield.applied })
        XCTAssertEqual(s.phase, .active)
        XCTAssertEqual(s.expiresAt.timeIntervalSince(s.startedAt), 1500)
        XCTAssertEqual(monitor.intervals[s.id]?.1, now.addingTimeInterval(1500))
        XCTAssertEqual(store.envelope.session?.id, s.id)
        XCTAssertTrue(shield.applied)
    }
    func testStartUsesRequestedLengthForExpiryAndMonitorInterval() throws {
        let (engine, _, monitor, shield) = fixture()
        let s = try engine.start(now: now, length: 2400, authorized: { .approved }, apply: { shield.apply() }, matches: { shield.applied })
        XCTAssertEqual(s.length, 2400); XCTAssertEqual(monitor.intervals[s.id]?.1, now.addingTimeInterval(2400))
    }
    func testDeniedAuthorizationCannotStartOrApply() {
        let (engine, store, monitor, shield) = fixture()
        XCTAssertThrowsError(try engine.start(now: now, authorized: { .denied }, apply: { shield.apply() }, matches: { true }))
        XCTAssertNil(store.envelope.session); XCTAssertFalse(shield.applied); XCTAssertTrue(monitor.intervals.isEmpty)
    }
    func testRegistrationFailureRollsBackWithoutActiveState() {
        let (engine, store, monitor, shield) = fixture(); monitor.failRegistration = true
        XCTAssertThrowsError(try engine.start(now: now, authorized: { .approved }, apply: { shield.apply() }, matches: { true }))
        XCTAssertEqual(store.envelope.session?.phase, .terminal)
        XCTAssertEqual(store.envelope.session?.reason, .startFailed)
        XCTAssertFalse(shield.applied); XCTAssertTrue(monitor.intervals.isEmpty)
    }
    func testRegistrationReadbackFailureRollsBack() {
        let (engine, store, monitor, shield) = fixture(); monitor.hideRegistration = true
        XCTAssertThrowsError(try engine.start(now: now, authorized: { .approved }, apply: { shield.apply() }, matches: { true }))
        XCTAssertEqual(store.envelope.session?.phase, .terminal); XCTAssertFalse(shield.applied)
    }
    func testShieldMismatchRollsBack() {
        let (engine, store, monitor, shield) = fixture()
        XCTAssertThrowsError(try engine.start(now: now, authorized: { .approved }, apply: { shield.apply() }, matches: { false }))
        XCTAssertEqual(store.envelope.session?.phase, .terminal); XCTAssertFalse(shield.applied); XCTAssertTrue(monitor.intervals.isEmpty)
    }
    func testFailedActiveSaveRollsBack() {
        let (engine, store, monitor, shield) = fixture(); store.failPhase = .active
        XCTAssertThrowsError(try engine.start(now: now, authorized: { .approved }, apply: { shield.apply() }, matches: { true }))
        XCTAssertNotEqual(store.envelope.session?.phase, .active); XCTAssertFalse(shield.applied); XCTAssertTrue(monitor.intervals.isEmpty)
    }
    func testDoubleStartDoesNotClearCurrentSession() throws {
        let (engine, store, _, shield) = fixture()
        let a = try engine.start(now: now, authorized: { .approved }, apply: { shield.apply() }, matches: { true })
        XCTAssertThrowsError(try engine.start(now: now, authorized: { .approved }, apply: {}, matches: { true }))
        XCTAssertEqual(store.envelope.session?.id, a.id); XCTAssertTrue(shield.applied)
    }
    func testEarlyCallbackDoesNotEndActiveSession() throws {
        let (engine, store, _, shield) = fixture()
        let a = try engine.start(now: now, authorized: { .approved }, apply: { shield.apply() }, matches: { true })
        try engine.handleCallback(activityName: a.activityName, kind: .didEnd, now: now.addingTimeInterval(1499), authorized: .approved)
        XCTAssertEqual(store.envelope.session?.phase, .active); XCTAssertTrue(shield.applied)
    }
    func testExpiryClearsOnlyOwnMonitoringAndPreservesObservationTime() throws {
        let (engine, store, monitor, shield) = fixture()
        let a = try engine.start(now: now, authorized: { .approved }, apply: { shield.apply() }, matches: { true })
        let unrelated = UUID(); monitor.intervals[unrelated] = (now, now.addingTimeInterval(3000))
        try engine.handleCallback(activityName: a.activityName, kind: .didEnd, now: now.addingTimeInterval(1510), authorized: .approved)
        XCTAssertEqual(store.envelope.session?.reason, .expired)
        XCTAssertEqual(store.envelope.session?.observedAt, now.addingTimeInterval(1510))
        XCTAssertFalse(shield.applied); XCTAssertNotNil(monitor.intervals[unrelated]); XCTAssertNil(monitor.intervals[a.id])
    }
    func testStaleCallbackCannotClearNewSession() throws {
        let (engine, store, _, shield) = fixture()
        let a = try engine.start(now: now, authorized: { .approved }, apply: { shield.apply() }, matches: { true })
        try engine.finish(id: a.id, reason: .earlyExit, now: now.addingTimeInterval(1))
        try engine.acknowledgeTerminal(id: a.id)
        let b = try engine.start(now: now.addingTimeInterval(2), authorized: { .approved }, apply: { shield.apply() }, matches: { true })
        try engine.handleCallback(activityName: a.activityName, kind: .didEnd, now: now.addingTimeInterval(1700), authorized: .approved)
        try engine.finish(id: a.id, reason: .earlyExit, now: now.addingTimeInterval(1700))
        XCTAssertEqual(store.envelope.session?.id, b.id); XCTAssertEqual(store.envelope.session?.phase, .active); XCTAssertTrue(shield.applied)
    }
    func testRepeatedFinishIsIdempotent() throws {
        let (engine, store, _, shield) = fixture()
        let a = try engine.start(now: now, authorized: { .approved }, apply: { shield.apply() }, matches: { true })
        try engine.finish(id: a.id, reason: .earlyExit, now: now.addingTimeInterval(10))
        try engine.finish(id: a.id, reason: .expired, now: now.addingTimeInterval(1500))
        XCTAssertEqual(store.envelope.session?.reason, .earlyExit); XCTAssertEqual(shield.clears, 1)
    }
    func testTerminalMustBeImportedBeforeNewStart() throws {
        let (engine, _, _, shield) = fixture()
        let a = try engine.start(now: now, authorized: { .approved }, apply: { shield.apply() }, matches: { true })
        try engine.finish(id: a.id, reason: .earlyExit, now: now)
        XCTAssertThrowsError(try engine.start(now: now, authorized: { .approved }, apply: {}, matches: { true }))
    }
    func testPreparingAndEndingAreRecovered() throws {
        for phase in [SessionPhase.preparing, .ending] {
            let (engine, store, _, shield) = fixture()
            var s = ControlSession(startedAt: now); s.phase = phase
            if phase == .ending { s.reason = .earlyExit; s.observedAt = now.addingTimeInterval(4) }
            store.envelope.session = s; shield.apply()
            let result = try engine.reconcile(now: now.addingTimeInterval(5), authorized: .approved)
            XCTAssertEqual(result.session?.phase, .terminal); XCTAssertFalse(shield.applied)
            XCTAssertEqual(result.session?.reason, phase == .preparing ? .recoveryInterrupted : .earlyExit)
        }
    }
    func testRevocationAndClockChangeInterruptSession() throws {
        for revoked in [true, false] {
            let (engine, _, _, shield) = fixture()
            _ = try engine.start(now: now, authorized: { .approved }, apply: { shield.apply() }, matches: { true })
            let result = try engine.reconcile(now: now, authorized: revoked ? .denied : .approved, clockChanged: !revoked)
            XCTAssertEqual(result.session?.reason, revoked ? .authorizationRevoked : .clockChanged)
            XCTAssertFalse(shield.applied)
        }
    }
    /// The 2026-11-11 access-state design: only `denied` is a revocation; `unknown` runs every other reconcile step as with access.
    func testUnknownAccessSkipsOnlyTheRevocationStep() throws {
        let (engine, store, _, shield) = fixture()
        let s = try engine.start(now: now, authorized: { .approved }, apply: { shield.apply() }, matches: { true })
        var result = try engine.reconcile(now: now.addingTimeInterval(10), authorized: .unknown)
        XCTAssertEqual(result.session?.phase, .active); XCTAssertTrue(shield.applied)
        result = try engine.reconcile(now: now.addingTimeInterval(20), authorized: .unknown, clockChanged: true)
        XCTAssertEqual(result.session?.reason, .clockChanged, "the clock step still runs")
        try engine.acknowledgeTerminal(id: result.session!.id)
        let t = try engine.start(now: now, authorized: { .approved }, apply: { shield.apply() }, matches: { true })
        result = try engine.reconcile(now: now.addingTimeInterval(1500), authorized: .unknown)
        XCTAssertEqual(result.session?.reason, .expired, "a timed end keeps its timed reason")
        XCTAssertNotEqual(s.id, t.id); XCTAssertFalse(shield.applied); XCTAssertEqual(store.envelope.session?.phase, .terminal)
    }
    func testUnknownAccessCannotStartOrApply() {
        let (engine, store, monitor, shield) = fixture()
        XCTAssertThrowsError(try engine.start(now: now, authorized: { .unknown }, apply: { shield.apply() }, matches: { true })) {
            XCTAssertEqual($0 as? ControlIssue, .unauthorized)
        }
        XCTAssertNil(store.envelope.session); XCTAssertFalse(shield.applied); XCTAssertTrue(monitor.intervals.isEmpty)
        // An access value that changes to `unknown` during the start fails its verification and rolls back.
        var reads = 0
        XCTAssertThrowsError(try engine.start(now: now, authorized: { reads += 1; return reads == 1 ? .approved : .unknown }, apply: { shield.apply() }, matches: { true }))
        XCTAssertEqual(store.envelope.session?.reason, .startFailed); XCTAssertFalse(shield.applied)
    }
    func testEndingWriteFailureStillAttemptsCleanup() throws {
        let (engine, store, monitor, shield) = fixture()
        let a = try engine.start(now: now, authorized: { .approved }, apply: { shield.apply() }, matches: { true })
        store.failPhase = .ending
        _ = try? engine.finish(id: a.id, reason: .earlyExit, now: now)
        XCTAssertFalse(shield.applied); XCTAssertNil(monitor.intervals[a.id])
    }
    func testUnreadableStateBlocksStartAndClearsOwnShield() {
        let (engine, store, _, shield) = fixture(); store.failRead = true; shield.apply()
        XCTAssertThrowsError(try engine.start(now: now, authorized: { .approved }, apply: {}, matches: { true }))
        XCTAssertFalse(shield.applied)
    }
    func testFailedCleanupWritesCannotRestoreActiveAfterEngineRestart() throws {
        for restoredAt in [now.addingTimeInterval(12), now.addingTimeInterval(1510)] {
        let (engine, store, monitor, shield) = fixture()
        let a = try engine.start(now: now, authorized: { .approved }, apply: { shield.apply() }, matches: { true })
        store.failAllWrites = true
        XCTAssertThrowsError(try engine.finish(id: a.id, reason: .earlyExit, now: now.addingTimeInterval(10)))
        XCTAssertEqual(store.envelope.session?.phase, .active); XCTAssertFalse(shield.applied)
        let restarted = SessionControl(store: store, monitoring: monitor, shield: shield, breakSelection: FakeBreakSelection(), everyday: FakeEverydayStore())
        XCTAssertThrowsError(try restarted.reconcile(now: now.addingTimeInterval(11), authorized: .approved))
        store.failAllWrites = false
        let result = try restarted.reconcile(now: restoredAt, authorized: .approved)
        XCTAssertEqual(result.session?.phase, .terminal); XCTAssertEqual(result.session?.reason, .recoveryInterrupted)
        }
    }
    func testTransientReadFailureStopsOwnedMonitoringAndCannotRestoreActiveAfterRestart() throws {
        let (engine, store, monitor, shield) = fixture()
        let a = try engine.start(now: now, authorized: { .approved }, apply: { shield.apply() }, matches: { true })
        store.failRead = true
        XCTAssertThrowsError(try engine.snapshot()); XCTAssertFalse(shield.applied)
        XCTAssertNil(monitor.intervals[a.id])
        store.failRead = false
        let restarted = SessionControl(store: store, monitoring: monitor, shield: shield, breakSelection: FakeBreakSelection(), everyday: FakeEverydayStore())
        let result = try restarted.reconcile(now: now.addingTimeInterval(10), authorized: .approved)
        XCTAssertEqual(result.session?.phase, .terminal); XCTAssertEqual(result.session?.reason, .recoveryInterrupted)
    }

}

enum FixtureFailure: Error { case injected }
final class MemoryControlStore: ControlStore, LockedControl {
    var envelope = ControlEnvelope(), failPhase: SessionPhase?, failRead = false, failAllWrites = false
    func withExclusiveAccess<T>(timeout: TimeInterval?, _ body: (LockedControl) throws -> T) throws -> T { try body(self) }
    func load() throws -> ControlEnvelope { if failRead { throw FixtureFailure.injected }; return envelope }
    func save(_ envelope: ControlEnvelope) throws {
        if failAllWrites { throw FixtureFailure.injected }
        if let failPhase, envelope.session?.phase == failPhase { throw FixtureFailure.injected }
        self.envelope = envelope
    }
}
final class FakeMonitoring: MonitoringClient {
    var registeredSessionIDs: [UUID] { Array(intervals.keys) }
    var intervals: [UUID: (Date, Date)] = [:], failRegistration = false, hideRegistration = false
    var breaks = Set<String>()
    func register(id: UUID, start: Date, end: Date) throws {
        if failRegistration { throw FixtureFailure.injected }; intervals[id] = (start, end)
    }
    func isRegistered(id: UUID) -> Bool { !hideRegistration && intervals[id] != nil }
    func stop(id: UUID) { intervals.removeValue(forKey: id); breaks = breaks.filter { !$0.hasPrefix(id.uuidString) } }
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws { breaks.insert("\(id.uuidString).\(index)") }
    func isBreakRegistered(id: UUID, index: Int) -> Bool { breaks.contains("\(id.uuidString).\(index)") }
    var registeredBreaks: [(id: UUID, index: Int)] { breaks.compactMap { key in
        let parts = key.split(separator: "."); return UUID(uuidString: String(parts[0])).map { ($0, Int(parts[1])!) }
    } }
    func stopBreak(id: UUID, index: Int) { breaks.remove("\(id.uuidString).\(index)") }
    var everyday: [(revision: UUID, part: EverydayPart)] = []
    func registerEveryday(revision: UUID, part: EverydayPart, start: Int, end: Int) throws { everyday.append((revision, part)) }
    var registeredEveryday: [(revision: UUID, part: EverydayPart)] { everyday }
    func stopEveryday(revision: UUID, part: EverydayPart) { everyday.removeAll { $0.revision == revision && $0.part == part } }
}
/// An everyday layer in memory; without a schedule, no layer is set up.
final class FakeEverydayStore: EverydayLayerStore {
    var schedule: EverydaySchedule?, shieldOn = false
    func load() throws -> EverydaySchedule? { schedule }
    func storeMatches() -> Bool { shieldOn }
    func applyStored() -> Bool { shieldOn = true; return true }
    var hasShield: Bool { shieldOn }
    func clearShield() { shieldOn = false }
}
final class FakeBreakSelection: BreakSelectionStore {
    var copies = Set<UUID>()
    func restoreShield(id: UUID) -> Bool { copies.contains(id) }
    func exists(id: UUID) -> Bool { copies.contains(id) }
    func remove(id: UUID) { copies.remove(id) }
    func removeAll(except id: UUID?) { copies = copies.filter { $0 == id } }
}
final class FakeShield: ShieldClient {
    var applied = false, clears = 0
    func apply() { applied = true }
    func clear() { applied = false; clears += 1 }
}
