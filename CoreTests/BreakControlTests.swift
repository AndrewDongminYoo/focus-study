import XCTest
@testable import FocusCore

private struct Registration: Equatable { var start: Date; var end: Date }
private struct BreakKey: Hashable { var id: UUID; var index: Int }
private struct BreakRegistration: Equatable { var start: Date; var end: Date; var warning: TimeInterval }
/// The whole fake world: the stored envelope, the registrations, the selection copies and the shield.
private struct WorldState: Equatable {
    var envelope = ControlEnvelope()
    var focus: [UUID: Registration] = [:]
    var breaks: [BreakKey: BreakRegistration] = [:]
    var copies = Set<UUID>()
    var shieldOn = false
    // Logs; they do not take part in the snapshot comparison.
    var clears = 0
    var focusLog: [Registration] = []
    var savedPhases: [SessionPhase?] = []
    static func == (a: WorldState, b: WorldState) -> Bool {
        a.envelope.schemaVersion == b.envelope.schemaVersion && a.envelope.session == b.envelope.session
            && a.focus == b.focus && a.breaks == b.breaks && a.copies == b.copies && a.shieldOn == b.shieldOn
    }
}
private final class World: ControlStore, LockedControl, MonitoringClient, ShieldClient, BreakSelectionStore {
    var state: WorldState
    /// While `recording`, the state after each effect that changed it.
    var snapshots: [WorldState] = []
    var recording = false
    var failSavePhases: [SessionPhase] = []
    var failAllSaves = false, failReads = false, failBreakRegistration = false, failAllFocusRegistrations = false, shieldMismatch = false
    var failFocusCalls = Set<Int>()
    /// The index of the throwable effect (save, registration, copy write) that throws once.
    var throwAtEffect: Int?
    private(set) var effects = 0, focusCalls = 0, restoreCalls = 0
    init(_ state: WorldState = WorldState()) { self.state = state }
    private func record() { if recording, snapshots.last != state { snapshots.append(state) } }
    private func mayThrow() throws {
        let index = effects; effects += 1
        if throwAtEffect == index { throwAtEffect = nil; throw FixtureFailure.injected }
    }
    /// Errors that the next lock sections throw before their body runs, one per section.
    var lockFailures: [Error] = []
    func withExclusiveAccess<T>(_ body: (LockedControl) throws -> T) throws -> T {
        if !lockFailures.isEmpty { throw lockFailures.removeFirst() }
        return try body(self)
    }
    func load() throws -> ControlEnvelope { if failReads { throw FixtureFailure.injected }; return state.envelope }
    func save(_ envelope: ControlEnvelope) throws {
        try mayThrow()
        if failAllSaves { throw FixtureFailure.injected }
        if let phase = envelope.session?.phase, let index = failSavePhases.firstIndex(of: phase) { failSavePhases.remove(at: index); throw FixtureFailure.injected }
        state.envelope = envelope; state.savedPhases.append(envelope.session?.phase); record()
    }
    var registeredSessionIDs: [UUID] { Array(state.focus.keys) + state.breaks.keys.map(\.id) }
    func register(id: UUID, start: Date, end: Date) throws {
        focusCalls += 1
        try mayThrow()
        if failAllFocusRegistrations || failFocusCalls.contains(focusCalls) { throw FixtureFailure.injected }
        state.focus[id] = Registration(start: start, end: end); state.focusLog.append(Registration(start: start, end: end)); record()
    }
    func isRegistered(id: UUID) -> Bool { state.focus[id] != nil }
    func stop(id: UUID) { state.focus[id] = nil; state.breaks = state.breaks.filter { $0.key.id != id }; record() }
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws {
        try mayThrow()
        if failBreakRegistration { throw FixtureFailure.injected }
        state.breaks[BreakKey(id: id, index: index)] = BreakRegistration(start: start, end: end, warning: warning); record()
    }
    func isBreakRegistered(id: UUID, index: Int) -> Bool { state.breaks[BreakKey(id: id, index: index)] != nil }
    var registeredBreaks: [(id: UUID, index: Int)] { state.breaks.keys.map { (id: $0.id, index: $0.index) } }
    func stopBreak(id: UUID, index: Int) { state.breaks[BreakKey(id: id, index: index)] = nil; record() }
    // The M2 world has no everyday layer; `EverydayControlTests` covers it.
    func registerEveryday(revision: UUID, part: EverydayPart, start: Int, end: Int) throws {}
    var registeredEveryday: [(revision: UUID, part: EverydayPart)] { [] }
    func stopEveryday(revision: UUID, part: EverydayPart) {}
    func clear() { state.shieldOn = false; state.clears += 1; record() }
    func restoreShield(id: UUID) -> Bool {
        restoreCalls += 1
        guard state.copies.contains(id) else { return false }
        state.shieldOn = true; record()
        return !shieldMismatch
    }
    func exists(id: UUID) -> Bool { state.copies.contains(id) }
    func remove(id: UUID) { state.copies.remove(id); record() }
    func removeAll(except id: UUID?) { state.copies = state.copies.filter { $0 == id }; record() }
    func saveCopy(_ id: UUID) throws { try mayThrow(); state.copies.insert(id); record() }
}

final class BreakControlTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }
    private func engine(_ world: World) -> SessionControl { SessionControl(store: world, monitoring: world, shield: world, breakSelection: world, everyday: FakeEverydayStore()) }
    private func stored(_ world: World) -> ControlSession { world.state.envelope.session! }
    private func focusName(_ id: UUID) -> String { "focus.\(id.uuidString)" }
    private func breakName(_ id: UUID, _ index: Int) -> String { "focus.\(id.uuidString).break.\(index)" }
    /// A 1500-second session that started at `t0` with the shield on.
    private func started(_ world: World) throws -> (SessionControl, UUID) {
        let engine = engine(world)
        let session = try engine.start(now: t0, authorized: { true }, apply: { world.state.shieldOn = true }, matches: { world.state.shieldOn })
        return (engine, session.id)
    }
    /// Requests a break at `request` and starts it when the wait is over.
    private func takeBreak(_ engine: SessionControl, _ world: World, _ id: UUID, at request: TimeInterval) throws {
        let waiting = try engine.requestBreak(id: id, now: at(request))
        try engine.startBreak(id: id, now: waiting.waitEndsAt!, saveSelection: { try world.saveCopy(id) })
    }
    private func reBlockAtBreakEnd(_ engine: SessionControl, _ world: World) throws {
        try engine.reconcile(now: stored(world).breakEndsAt!, authorized: true)
    }
    /// Break 1 requested at +300 (break +315 to +495), re-blocked at +495: the stored phase is `breakOver` with the deadline +2295.
    private func afterReBlock(_ world: World) throws -> (SessionControl, UUID) {
        let (engine, id) = try started(world)
        try takeBreak(engine, world, id, at: 300); try reBlockAtBreakEnd(engine, world)
        XCTAssertEqual(stored(world).phase, .breakOver)
        return (engine, id)
    }
    /// The focus activity end that the spec gives for the stored phase (spec "Monitoring activities").
    private func expectedFocusEnd(_ s: ControlSession) -> Date? {
        let timing = BreakTiming.standard, deadline = s.deadline(timing: timing), activeEnd = min(s.focusEnd, deadline)
        switch s.phase {
        case .active: return activeEnd
        case .waiting: return activeEnd.addingTimeInterval(s.waitEndsAt!.addingTimeInterval(timing.staleWaitGrace).timeIntervalSince(s.pausedAt!))
        case .onBreak, .breakOver: return deadline
        default: return nil
        }
    }
    /// The spec table "Break artifacts", the registered end of the stored phase, and the shield.
    private func assertArtifactTable(_ world: World, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        let session = world.state.envelope.session
        let onBreak = session?.phase == .onBreak ? session : nil
        XCTAssertTrue(world.state.copies.isSubset(of: onBreak.map { Set([$0.id]) } ?? []), "copies: \(context)", file: file, line: line)
        XCTAssertTrue(Set(world.state.breaks.keys).isSubset(of: onBreak.map { Set([BreakKey(id: $0.id, index: $0.breaksTaken ?? 0)]) } ?? []), "breaks: \(context)", file: file, line: line)
        guard let session else { return }
        if session.phase == .terminal { XCTAssertNil(world.state.focus[session.id], "focus stopped: \(context)", file: file, line: line) }
        else if let expected = expectedFocusEnd(session) { XCTAssertEqual(world.state.focus[session.id]?.end, expected, "focus end: \(context)", file: file, line: line) }
        if session.phase != .onBreak && session.phase != .terminal { XCTAssertTrue(world.state.shieldOn, "shield: \(context)", file: file, line: line) }
    }
    /// The snapshot after the overwrite of a transition, before its save.
    private func overwriteSnapshot(_ world: World, storedPhase: SessionPhase, end: Date, file: StaticString = #filePath, line: UInt = #line) throws -> World {
        let id = stored(world).id
        let snapshot = try XCTUnwrap(world.snapshots.first { $0.envelope.session?.phase == storedPhase && $0.focus[id]?.end == end }, file: file, line: line)
        return World(snapshot)
    }

    // MARK: Break pass

    func testThreeBreaksUseWaitsOf15And30And60SecondsAndNoFourth() throws {
        let world = World(); let (engine, id) = try started(world)
        for (index, (request, wait)) in [(100.0, 15.0), (300, 30), (520, 60)].enumerated() {
            let waiting = try engine.requestBreak(id: id, now: at(request))
            XCTAssertEqual(waiting.waitEndsAt, at(request + wait))
            try engine.startBreak(id: id, now: at(request + wait), saveSelection: { try world.saveCopy(id) })
            XCTAssertEqual(world.state.breaks[BreakKey(id: id, index: index + 1)], BreakRegistration(start: at(request + wait), end: at(request + wait + 900), warning: 720))
            try reBlockAtBreakEnd(engine, world)
            try engine.resume(id: id, now: at(request + wait + 181))
            XCTAssertEqual(stored(world).phase, .active)
        }
        XCTAssertEqual(stored(world).breaksTaken, 3); XCTAssertEqual(stored(world).breaksLeft, 0)
        XCTAssertThrowsError(try engine.requestBreak(id: id, now: at(800))) { XCTAssertEqual($0 as? ControlIssue, .breakUnavailable) }
        XCTAssertEqual(stored(world).phase, .active)
    }
    func testCancelledWaitKeepsBreakCountAndWaitAndCreditsDeadline() throws {
        let world = World(); let (engine, id) = try started(world)
        _ = try engine.requestBreak(id: id, now: at(100))
        try engine.cancelWait(id: id, now: at(105))
        let s = stored(world)
        XCTAssertEqual(s.phase, .active); XCTAssertEqual(s.breaksTaken ?? 0, 0)
        XCTAssertEqual(s.pausedSeconds, 5); XCTAssertEqual(s.deadlineCredit, 5); XCTAssertNil(s.pausedAt); XCTAssertNil(s.waitEndsAt)
        XCTAssertEqual(world.state.focus[id]?.end, at(1505))
        XCTAssertEqual(try engine.requestBreak(id: id, now: at(200)).waitEndsAt, at(215))
    }
    func testStartBreakBeforeWaitEndsThrowsBreakUnavailable() throws {
        let world = World(); let (engine, id) = try started(world)
        _ = try engine.requestBreak(id: id, now: at(100))
        XCTAssertThrowsError(try engine.startBreak(id: id, now: at(110), saveSelection: { try world.saveCopy(id) })) { XCTAssertEqual($0 as? ControlIssue, .breakUnavailable) }
        XCTAssertEqual(stored(world).phase, .waiting); XCTAssertTrue(world.state.shieldOn); XCTAssertTrue(world.state.copies.isEmpty)
    }
    func testStartBreakRegistersFifteenMinuteBreakWithTwelveMinuteWarningThenClearsShield() throws {
        let world = World(); let (engine, id) = try started(world)
        _ = try engine.requestBreak(id: id, now: at(100))
        world.recording = true
        try engine.startBreak(id: id, now: at(115), saveSelection: { try world.saveCopy(id) })
        XCTAssertEqual(world.state.breaks[BreakKey(id: id, index: 1)], BreakRegistration(start: at(115), end: at(1015), warning: 720))
        let s = stored(world)
        XCTAssertEqual(s.phase, .onBreak); XCTAssertEqual(s.breaksTaken, 1); XCTAssertEqual(s.breakEndsAt, at(295)); XCTAssertEqual(s.deadlineCredit, 195)
        XCTAssertEqual(world.state.focus[id]?.end, at(2295)); XCTAssertTrue(world.state.copies.contains(id))
        let cleared = try XCTUnwrap(world.snapshots.first { !$0.shieldOn })
        XCTAssertEqual(cleared.envelope.session?.phase, .onBreak)
        XCTAssertEqual(world.state.clears, 1)
    }
    func testStartBreakFailureNeverClearsShieldAndReturnsToActive() throws {
        let world = World(); let (engine, id) = try started(world)
        _ = try engine.requestBreak(id: id, now: at(100)); world.failBreakRegistration = true
        XCTAssertThrowsError(try engine.startBreak(id: id, now: at(115), saveSelection: { try world.saveCopy(id) }))
        XCTAssertEqual(world.state.clears, 0); XCTAssertTrue(world.state.shieldOn)
        XCTAssertEqual(stored(world).phase, .active); XCTAssertTrue(world.state.copies.isEmpty); XCTAssertTrue(world.state.breaks.isEmpty)
    }
    func testStartBreakSaveFailureNeverClearsShieldAndRollsBack() throws {
        let world = World(); let (engine, id) = try started(world)
        _ = try engine.requestBreak(id: id, now: at(100)); world.failSavePhases = [.onBreak]
        XCTAssertThrowsError(try engine.startBreak(id: id, now: at(115), saveSelection: { try world.saveCopy(id) }))
        XCTAssertEqual(world.state.clears, 0); XCTAssertTrue(world.state.breaks.isEmpty); XCTAssertTrue(world.state.copies.isEmpty)
        let s = stored(world)
        XCTAssertEqual(s.phase, .active)
        XCTAssertEqual(world.state.focusLog.last?.end, min(s.focusEnd, s.deadline(timing: .standard)))
        XCTAssertEqual(world.state.focusLog.last?.end, at(1515))
    }
    func testStartBreakRollbackSaveFailureRestoresWaitingEnd() throws {
        let world = World(); let (engine, id) = try started(world)
        _ = try engine.requestBreak(id: id, now: at(100)); world.failSavePhases = [.onBreak, .active]
        XCTAssertThrowsError(try engine.startBreak(id: id, now: at(115), saveSelection: { try world.saveCopy(id) }))
        XCTAssertEqual(world.state.clears, 0); XCTAssertEqual(stored(world).phase, .waiting)
        XCTAssertEqual(world.state.focusLog.last?.end, at(1525))
        XCTAssertTrue(world.state.breaks.isEmpty); XCTAssertTrue(world.state.copies.isEmpty)
    }

    // MARK: Save failure after an overwrite

    func testRequestBreakSaveFailureRestoresActiveEnd() throws {
        let world = World(); let (engine, id) = try started(world)
        world.failSavePhases = [.waiting]
        XCTAssertThrowsError(try engine.requestBreak(id: id, now: at(100)))
        XCTAssertEqual(stored(world).phase, .active); XCTAssertEqual(world.state.focusLog.last?.end, at(1500))
    }
    func testCancelWaitSaveFailureRestoresWaitingEnd() throws {
        let world = World(); let (engine, id) = try started(world)
        _ = try engine.requestBreak(id: id, now: at(100)); world.failSavePhases = [.active]
        XCTAssertThrowsError(try engine.cancelWait(id: id, now: at(105)))
        XCTAssertEqual(stored(world).phase, .waiting); XCTAssertEqual(world.state.focusLog.last?.end, at(1525))
        try engine.reconcile(now: at(1525), authorized: true)
        XCTAssertEqual(stored(world).pausedSeconds, 25); XCTAssertEqual(stored(world).reason, .expired)
    }
    func testResumeSaveFailureRestoresDeadlineEnd() throws {
        let world = World(); let (engine, id) = try afterReBlock(world)
        world.failSavePhases = [.active]
        XCTAssertThrowsError(try engine.resume(id: id, now: at(600)))
        XCTAssertEqual(stored(world).phase, .breakOver); XCTAssertEqual(world.state.focusLog.last?.end, at(2295))
        try engine.reconcile(now: at(2295), authorized: true)
        XCTAssertEqual(stored(world).reason, .deadlineMissed); XCTAssertFalse(world.state.shieldOn)
    }
    func testStaleWaitCancelSaveFailureWithPastEndEndsSafely() throws {
        let world = World(); let (engine, id) = try started(world)
        _ = try engine.requestBreak(id: id, now: at(100))
        world.state.breaks[BreakKey(id: id, index: 1)] = BreakRegistration(start: at(100), end: at(1000), warning: 720)
        world.failSavePhases = [.active]
        XCTAssertThrowsError(try engine.reconcile(now: at(125 + 3600), authorized: true))
        XCTAssertFalse(world.state.shieldOn); XCTAssertNil(world.state.focus[id]); XCTAssertTrue(world.state.breaks.isEmpty)
        XCTAssertEqual(stored(world).phase, .terminal); XCTAssertEqual(stored(world).reason, .recoveryInterrupted)
    }
    func testSaveAndRestoreFailureEndsAsRecoveryInterrupted() throws {
        let world = World(); let (engine, id) = try afterReBlock(world)
        let clears = world.state.clears
        world.failAllSaves = true; world.failFocusCalls = [world.focusCalls + 2]
        XCTAssertThrowsError(try engine.resume(id: id, now: at(600)))
        XCTAssertEqual(world.state.clears, clears + 1); XCTAssertNil(world.state.focus[id])
        XCTAssertEqual(stored(world).phase, .breakOver)
        world.failAllSaves = false
        try engine.reconcile(now: at(601), authorized: true)
        XCTAssertEqual(stored(world).reason, .recoveryInterrupted)
    }

    // MARK: Process exit between overwrite and save (callback with nothing due)

    func testResumeExitBeforeSaveRegistersDeadlineAtStaleEnd() throws {
        let world = World(); let (engine, id) = try afterReBlock(world)
        world.recording = true
        try engine.resume(id: id, now: at(600))
        let exited = try overwriteSnapshot(world, storedPhase: .breakOver, end: at(1800))
        XCTAssertEqual(exited.state.focus[id]?.end, at(1800))
        try self.engine(exited).handleCallback(activityName: focusName(id), kind: .didEnd, now: at(1800), authorized: true)
        XCTAssertEqual(stored(exited).phase, .breakOver); XCTAssertEqual(exited.state.focus[id]?.end, at(2295))
        try self.engine(exited).handleCallback(activityName: focusName(id), kind: .didEnd, now: at(2295), authorized: true)
        XCTAssertEqual(stored(exited).reason, .deadlineMissed); XCTAssertFalse(exited.state.shieldOn)
    }
    func testCancelWaitExitNearFocusEndRegistersWaitingEndAgain() throws {
        let world = World(); let (engine, id) = try started(world)
        _ = try engine.requestBreak(id: id, now: at(1495))
        world.recording = true
        try engine.cancelWait(id: id, now: at(1496))
        let exited = try overwriteSnapshot(world, storedPhase: .waiting, end: at(1495 + 6))
        XCTAssertEqual(exited.state.focus[id]?.end, at(1501))
        try self.engine(exited).handleCallback(activityName: focusName(id), kind: .didEnd, now: at(1501), authorized: true)
        XCTAssertEqual(stored(exited).phase, .waiting); XCTAssertEqual(exited.state.focus[id]?.end, at(1495 + 30))
        try self.engine(exited).handleCallback(activityName: focusName(id), kind: .didEnd, now: at(1525), authorized: true)
        XCTAssertEqual(stored(exited).pausedSeconds, 25); XCTAssertEqual(stored(exited).reason, .expired)
    }
    func testRequestBreakExitEndsWithinWaitPlusGrace() throws {
        let world = World(); let (engine, id) = try started(world)
        world.recording = true
        _ = try engine.requestBreak(id: id, now: at(1400))
        let exited = try overwriteSnapshot(world, storedPhase: .active, end: at(1525))
        XCTAssertEqual(exited.state.focus[id]?.end, at(1525))
        try self.engine(exited).handleCallback(activityName: focusName(id), kind: .didEnd, now: at(1525), authorized: true)
        let s = stored(exited)
        XCTAssertEqual(s.reason, .expired); XCTAssertEqual(s.recordedEnd.map { $0.timeIntervalSince(s.startedAt) }, 1500)
    }
    func testNothingDueRegistrationFailureEndsAsRecoveryInterrupted() throws {
        let world = World(); let (engine, id) = try afterReBlock(world)
        world.recording = true
        try engine.resume(id: id, now: at(600))
        let exited = try overwriteSnapshot(world, storedPhase: .breakOver, end: at(1800))
        exited.failAllFocusRegistrations = true
        try? self.engine(exited).handleCallback(activityName: focusName(id), kind: .didEnd, now: at(1800), authorized: true)
        XCTAssertFalse(exited.state.shieldOn); XCTAssertEqual(stored(exited).reason, .recoveryInterrupted)
    }
    func testDidStartAndEarlierSessionDidEndNeverRegisterFocusActivity() throws {
        let world = World(); let (engine, id) = try afterReBlock(world)
        world.recording = true
        try engine.resume(id: id, now: at(600))
        let exited = try overwriteSnapshot(world, storedPhase: .breakOver, end: at(1800))
        let registrations = exited.focusCalls
        try self.engine(exited).handleCallback(activityName: focusName(id), kind: .didStart, now: at(1800), authorized: true)
        try self.engine(exited).handleCallback(activityName: focusName(UUID()), kind: .didEnd, now: at(1800), authorized: true)
        XCTAssertEqual(exited.focusCalls, registrations); XCTAssertEqual(exited.state.focus[id]?.end, at(1800))
    }

    // MARK: Re-block

    func testWarningCallbackReBlocksStopsBreakActivityAndRemovesCopy() throws {
        let world = World(); let (engine, id) = try started(world)
        try takeBreak(engine, world, id, at: 100)
        try engine.handleCallback(activityName: breakName(id, 1), kind: .willEndWarning, now: at(290), authorized: true)
        XCTAssertEqual(stored(world).phase, .breakOver); XCTAssertTrue(world.state.shieldOn)
        XCTAssertTrue(world.state.breaks.isEmpty); XCTAssertTrue(world.state.copies.isEmpty)
        XCTAssertEqual(world.state.focus[id]?.end, at(2295))
    }
    /// Returns the given times in order, so a test sees which attempt read which time.
    private func clock(_ times: [Date]) -> (now: () -> Date, calls: () -> Int) {
        var index = 0
        return ({ defer { index += 1 }; return times[min(index, times.count - 1)] }, { index })
    }
    func testWarningCallbackRetriesLockTimeoutAndStillReBlocks() throws {
        let world = World(); let (engine, id) = try started(world)
        try takeBreak(engine, world, id, at: 100)
        world.lockFailures = [ControlIssue.lockTimeout]
        let clock = clock([at(290), at(291)]); var pauses: [TimeInterval] = []
        try engine.handleCallbackRetryingLock(activityName: breakName(id, 1), kind: .willEndWarning, now: clock.now, authorized: { true }, sleep: { pauses.append($0) })
        XCTAssertEqual(pauses, [0.25]); XCTAssertEqual(clock.calls(), 2)
        XCTAssertEqual(stored(world).phase, .breakOver); XCTAssertTrue(world.state.shieldOn)
        XCTAssertTrue(world.state.breaks.isEmpty); XCTAssertTrue(world.state.copies.isEmpty)
    }
    func testFocusEndCallbackRetriesLockTimeoutWithFreshTime() throws {
        let world = World(); let (engine, id) = try started(world)
        world.lockFailures = [ControlIssue.lockTimeout]
        // The first time is before the focus end, so only the fresh time of the retry can end the session.
        let clock = clock([at(1499), at(1500)]); var pauses: [TimeInterval] = []
        try engine.handleCallbackRetryingLock(activityName: focusName(id), kind: .didEnd, now: clock.now, authorized: { true }, sleep: { pauses.append($0) })
        XCTAssertEqual(pauses, [0.25]); XCTAssertEqual(stored(world).reason, .expired)
        XCTAssertFalse(world.state.shieldOn); XCTAssertNil(world.state.focus[id])
    }
    func testCallbackRetryStopsAfterFourLockTimeouts() throws {
        let world = World(); let (engine, id) = try started(world)
        try takeBreak(engine, world, id, at: 100)
        world.lockFailures = Array(repeating: ControlIssue.lockTimeout, count: 5)
        let before = world.state; var pauses: [TimeInterval] = []
        XCTAssertThrowsError(try engine.handleCallbackRetryingLock(activityName: breakName(id, 1), kind: .willEndWarning, now: { self.at(290) }, authorized: { true }, sleep: { pauses.append($0) })) {
            XCTAssertEqual($0 as? ControlIssue, .lockTimeout)
        }
        XCTAssertEqual(pauses.count, 4); XCTAssertTrue(world.lockFailures.isEmpty); XCTAssertEqual(world.state, before)
    }
    func testCallbackRetryIgnoresOtherErrors() throws {
        let world = World(); let (engine, id) = try started(world)
        try takeBreak(engine, world, id, at: 100)
        world.lockFailures = [ControlIssue.io, ControlIssue.lockTimeout]
        let before = world.state; var pauses: [TimeInterval] = []
        XCTAssertThrowsError(try engine.handleCallbackRetryingLock(activityName: breakName(id, 1), kind: .willEndWarning, now: { self.at(290) }, authorized: { true }, sleep: { pauses.append($0) })) {
            XCTAssertEqual($0 as? ControlIssue, .io)
        }
        XCTAssertTrue(pauses.isEmpty); XCTAssertEqual(world.lockFailures.count, 1); XCTAssertEqual(world.state, before)
    }
    func testStaleBreakCallbackDoesNotTouchNewerBreak() throws {
        let world = World(); let (engine, id) = try started(world)
        try takeBreak(engine, world, id, at: 100); try reBlockAtBreakEnd(engine, world)
        try engine.resume(id: id, now: at(300))
        try takeBreak(engine, world, id, at: 400)
        let clears = world.state.clears, restores = world.restoreCalls
        try engine.handleCallback(activityName: breakName(id, 1), kind: .willEndWarning, now: at(450), authorized: true)
        XCTAssertEqual(stored(world).phase, .onBreak); XCTAssertEqual(stored(world).breaksTaken, 2)
        XCTAssertEqual(world.state.clears, clears); XCTAssertEqual(world.restoreCalls, restores); XCTAssertFalse(world.state.shieldOn)
        XCTAssertTrue(world.isBreakRegistered(id: id, index: 2)); XCTAssertTrue(world.state.copies.contains(id))
    }
    func testWarningCallbackAfterDeadlineEndsAsDeadlineMissed() throws {
        let world = World(), id = UUID()
        var s = ControlSession(startedAt: t0, id: id); s.phase = .onBreak; s.breaksTaken = 1
        s.pausedAt = at(2000); s.breakEndsAt = at(2180); s.deadlineCredit = 0 // deadline +2100
        world.state.envelope.session = s; world.state.focus[id] = Registration(start: t0, end: at(2100))
        world.state.breaks[BreakKey(id: id, index: 1)] = BreakRegistration(start: at(2000), end: at(2900), warning: 720); world.state.copies = [id]
        try engine(world).handleCallback(activityName: breakName(id, 1), kind: .willEndWarning, now: at(2105), authorized: true)
        XCTAssertEqual(stored(world).reason, .deadlineMissed)
        XCTAssertFalse(world.state.savedPhases.contains(.breakOver)); XCTAssertEqual(world.restoreCalls, 0)
        XCTAssertFalse(world.state.shieldOn); XCTAssertGreaterThan(world.state.clears, 0)
        XCTAssertTrue(world.state.copies.isEmpty); XCTAssertTrue(world.state.breaks.isEmpty); XCTAssertNil(world.state.focus[id])
    }
    func testDidStartCallbackOfBreakNeverReBlocks() throws {
        let world = World(); let (engine, id) = try started(world)
        try takeBreak(engine, world, id, at: 100)
        try engine.handleCallback(activityName: breakName(id, 1), kind: .didStart, now: at(116), authorized: true)
        XCTAssertEqual(stored(world).phase, .onBreak); XCTAssertFalse(world.state.shieldOn); XCTAssertEqual(world.restoreCalls, 0)
    }
    func testReBlockWithoutCopyEndsAsRecoveryInterrupted() throws {
        let world = World(); let (engine, id) = try started(world)
        try takeBreak(engine, world, id, at: 100)
        world.state.copies.removeAll()
        try engine.reconcile(now: at(295), authorized: true)
        XCTAssertEqual(stored(world).reason, .recoveryInterrupted); XCTAssertFalse(world.state.shieldOn)
    }
    func testReBlockWithMismatchedStoreEndsAsRecoveryInterrupted() throws {
        let world = World(); let (engine, id) = try started(world)
        try takeBreak(engine, world, id, at: 100); world.shieldMismatch = true
        try engine.reconcile(now: at(295), authorized: true)
        XCTAssertEqual(stored(world).reason, .recoveryInterrupted); XCTAssertFalse(world.state.shieldOn)
    }

    // MARK: Waits and deadline

    func testStaleWaitIsCancelledAsOfWaitEndPlusGrace() throws {
        let world = World(); let (engine, id) = try started(world)
        _ = try engine.requestBreak(id: id, now: at(100))
        try engine.reconcile(now: at(125 + 3600), authorized: true)
        let s = stored(world)
        XCTAssertEqual(s.pausedSeconds, 25); XCTAssertEqual(s.deadlineCredit, 25); XCTAssertEqual(s.breaksTaken ?? 0, 0)
    }
    func testWaitThatCrossesPreviousDeadlineDoesNotMissDeadline() throws {
        let world = World(); let (engine, id) = try started(world)
        try takeBreak(engine, world, id, at: 100); try reBlockAtBreakEnd(engine, world)
        try engine.resume(id: id, now: at(295 + 590))
        XCTAssertEqual(stored(world).focusEnd, at(2285)); XCTAssertEqual(stored(world).deadline(timing: .standard), at(2295))
        _ = try engine.requestBreak(id: id, now: at(2280))
        try engine.reconcile(now: at(2300), authorized: true)
        XCTAssertEqual(stored(world).phase, .waiting)
        try engine.startBreak(id: id, now: at(2310), saveSelection: { try world.saveCopy(id) })
        XCTAssertEqual(stored(world).phase, .onBreak); XCTAssertEqual(stored(world).deadline(timing: .standard), at(2295 + 30 + 180))
    }
    func testStartBreakAfterGraceThrowsBreakUnavailable() throws {
        let world = World(); let (engine, id) = try started(world)
        _ = try engine.requestBreak(id: id, now: at(100))
        XCTAssertThrowsError(try engine.startBreak(id: id, now: at(125), saveSelection: { try world.saveCopy(id) })) { XCTAssertEqual($0 as? ControlIssue, .breakUnavailable) }
        XCTAssertTrue(world.state.shieldOn); XCTAssertTrue(world.state.copies.isEmpty)
    }
    func testDeadlineAfterReBlockEndsAsDeadlineMissedAndClearsRestrictions() throws {
        let world = World(); let (engine, id) = try started(world)
        try takeBreak(engine, world, id, at: 100); try reBlockAtBreakEnd(engine, world)
        XCTAssertEqual(world.state.focus[id]?.end, at(2295))
        try engine.reconcile(now: at(2294), authorized: true); XCTAssertEqual(stored(world).phase, .breakOver)
        try engine.handleCallback(activityName: focusName(id), kind: .didEnd, now: at(2295), authorized: true)
        XCTAssertEqual(stored(world).reason, .deadlineMissed); XCTAssertFalse(world.state.shieldOn); XCTAssertNil(world.state.focus[id])
    }
    func testResumeAfterDeadlineEndsAsDeadlineMissed() throws {
        let world = World(); let (engine, id) = try afterReBlock(world)
        try engine.resume(id: id, now: at(2295))
        XCTAssertEqual(stored(world).reason, .deadlineMissed); XCTAssertFalse(world.state.shieldOn)
    }
    func testResumeAfterOneLongGapEndsAtDeadlineNotAtFocusEnd() throws {
        let world = World(); let (engine, id) = try afterReBlock(world)
        try engine.resume(id: id, now: at(1195))
        XCTAssertEqual(stored(world).focusEnd, at(2395)); XCTAssertEqual(world.state.focus[id]?.end, at(2295))
        try engine.reconcile(now: at(2294), authorized: true); XCTAssertEqual(stored(world).phase, .active)
        try engine.reconcile(now: at(2295), authorized: true)
        XCTAssertEqual(stored(world).reason, .deadlineMissed); XCTAssertFalse(world.state.shieldOn)
    }
    /// Break 1 at +100 (re-block +295, resume +795), break 2 at +800 (re-block +1010, resume +1510): deadline +2505, focus end +2905.
    private func twoGaps(_ world: World) throws -> (SessionControl, UUID) {
        let (engine, id) = try started(world)
        try takeBreak(engine, world, id, at: 100); try reBlockAtBreakEnd(engine, world); try engine.resume(id: id, now: at(795))
        try takeBreak(engine, world, id, at: 800); XCTAssertEqual(stored(world).breakEndsAt, at(1010))
        try reBlockAtBreakEnd(engine, world); try engine.resume(id: id, now: at(1510))
        XCTAssertEqual(stored(world).deadline(timing: .standard), at(2505)); XCTAssertEqual(stored(world).focusEnd, at(2905))
        return (engine, id)
    }
    func testTwoGapsThatTogetherExceedSlackEndAtDeadline() throws {
        let world = World(); let (engine, _) = try twoGaps(world)
        try engine.reconcile(now: at(2504), authorized: true); XCTAssertEqual(stored(world).phase, .active)
        try engine.reconcile(now: at(2505), authorized: true)
        XCTAssertEqual(stored(world).reason, .deadlineMissed); XCTAssertFalse(world.state.shieldOn)
    }
    func testLateReconcileAfterBothTimesUsesTheEarlierOne() throws {
        let missed = World(); let (missedEngine, _) = try twoGaps(missed)
        try missedEngine.reconcile(now: at(9000), authorized: true)
        XCTAssertEqual(stored(missed).reason, .deadlineMissed)
        let completed = World(); let (engine, id) = try started(completed)
        try takeBreak(engine, completed, id, at: 100); try reBlockAtBreakEnd(engine, completed); try engine.resume(id: id, now: at(296))
        XCTAssertLessThan(stored(completed).focusEnd, stored(completed).deadline(timing: .standard))
        try engine.reconcile(now: at(9000), authorized: true)
        XCTAssertEqual(stored(completed).reason, .expired)
    }
    /// A break requested with 10 minutes of focus left; the resume at +1100 gives the focus end +1700.
    private func resumedNearEnd(_ world: World) throws -> (SessionControl, UUID) {
        let (engine, id) = try started(world)
        try takeBreak(engine, world, id, at: 900); try reBlockAtBreakEnd(engine, world); try engine.resume(id: id, now: at(1100))
        return (engine, id)
    }
    func testResumeRegistersFocusActivityFromStartedAtToNewFocusEnd() throws {
        let world = World(); let (_, id) = try resumedNearEnd(world)
        XCTAssertEqual(world.state.focus[id], Registration(start: t0, end: at(1700)))
    }
    func testReconcileAtNewFocusEndExpiresAndNotBefore() throws {
        let world = World(); let (engine, _) = try resumedNearEnd(world)
        try engine.reconcile(now: at(1699), authorized: true); XCTAssertEqual(stored(world).phase, .active)
        try engine.reconcile(now: at(1700), authorized: true); XCTAssertEqual(stored(world).reason, .expired)
    }
    func testBreakRequestOnVersion1SessionSavesVersion2() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID(), start = Date(timeIntervalSinceReferenceDate: 800_000_000), file = directory.appendingPathComponent("control.json")
        let json = #"{"schemaVersion":1,"session":{"id":"\#(id.uuidString)","startedAt":\#(start.timeIntervalSinceReferenceDate),"expiresAt":\#(start.timeIntervalSinceReferenceDate + 1500),"phase":"active"}}"#
        try Data(json.utf8).write(to: file)
        let world = World(); world.state.focus[id] = Registration(start: start, end: start.addingTimeInterval(1500))
        let engine = SessionControl(store: SharedControlStore(directory: directory), monitoring: world, shield: world, breakSelection: world, everyday: FakeEverydayStore())
        _ = try engine.requestBreak(id: id, now: start.addingTimeInterval(60))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 2)
        XCTAssertEqual((object["session"] as? [String: Any])?["phase"] as? String, "waiting")
    }

    // MARK: Break artifacts

    func testStartRemovesLeftoverSelectionCopies() throws {
        let world = World(), leftover = UUID()
        world.state.copies = [leftover, UUID()]
        world.state.breaks[BreakKey(id: leftover, index: 2)] = BreakRegistration(start: t0, end: at(900), warning: 720)
        let (_, id) = try started(world)
        XCTAssertTrue(world.state.copies.isEmpty); XCTAssertTrue(world.state.breaks.isEmpty); XCTAssertEqual(stored(world).id, id)
    }
    func testEveryLockSectionRemovesArtifactsTheStoredPhaseDoesNotAllow() throws {
        let phases: [SessionPhase?] = [nil, .preparing, .active, .waiting, .onBreak, .breakOver, .ending, .terminal]
        for phase in phases {
            for section in ["reconcile", "start", "callback"] {
                let world = World(), id = UUID(), other = UUID()
                if let phase {
                    var s = ControlSession(startedAt: t0, id: id); s.phase = phase
                    switch phase {
                    case .waiting: s.pausedAt = at(190); s.waitEndsAt = at(205)
                    case .onBreak: s.breaksTaken = 2; s.pausedAt = at(150); s.breakEndsAt = at(400); s.deadlineCredit = 400
                    case .breakOver: s.breaksTaken = 1; s.pausedAt = at(150); s.breakEndsAt = at(180); s.deadlineCredit = 195
                    case .ending, .terminal: s.reason = .earlyExit; s.observedAt = at(190)
                    case .preparing, .active: break
                    }
                    world.state.envelope.session = s
                    // In `waiting`, a leftover copy means that the registered end can still be the deadline.
                    if phase != .terminal { world.state.focus[id] = Registration(start: t0, end: phase == .waiting ? s.deadline(timing: .standard) : expectedFocusEnd(s) ?? at(1500)) }
                }
                world.state.shieldOn = phase != .onBreak && phase != .terminal
                world.state.copies = [id, other]
                for owner in [id, other] { for index in 1...3 { world.state.breaks[BreakKey(id: owner, index: index)] = BreakRegistration(start: t0, end: at(900), warning: 720) } }
                let engine = engine(world)
                switch section {
                case "reconcile": _ = try? engine.reconcile(now: at(200), authorized: true)
                case "start": _ = try? engine.start(now: at(200), authorized: { true }, apply: { world.state.shieldOn = true }, matches: { true })
                default: try? engine.handleCallback(activityName: focusName(UUID()), kind: .didEnd, now: at(200), authorized: true)
                }
                let context = "\(phase.map(\.rawValue) ?? "none") \(section)"
                assertArtifactTable(world, context)
                if phase == .onBreak { XCTAssertTrue(world.state.copies.contains(id), context); XCTAssertTrue(world.isBreakRegistered(id: id, index: 2), context) }
                if phase == .waiting { XCTAssertEqual(world.state.focusLog.last?.end, at(1525), context) }
            }
        }
    }
    func testInterruptionAtEveryStepOfBreakAndEndTransitionsKeepsTheArtifactTable() throws {
        struct Scenario {
            let name: String
            let setup: (World) throws -> (SessionControl, UUID)
            let run: (SessionControl, World, UUID) throws -> Void
            let now: Date
            /// Transitions 1, 2 and 5: the exit pass delivers the focus activity's `.didEnd` instead of a reconcile.
            var overwrite = false
            /// Transition 3: the exit pass also reconciles 1 hour after `waitEndsAt` + grace.
            var later: Date?
            var boundAfterActiveEnd: TimeInterval?
        }
        let requested: (TimeInterval) -> (World) throws -> (SessionControl, UUID) = { offset in { world in
            let (engine, id) = try self.started(world); _ = try engine.requestBreak(id: id, now: self.at(offset)); return (engine, id)
        } }
        let onBreak: (World) throws -> (SessionControl, UUID) = { world in
            let (engine, id) = try self.started(world); try self.takeBreak(engine, world, id, at: 100); return (engine, id)
        }
        let startBreak: (SessionControl, World, UUID) throws -> Void = { engine, world, id in try engine.startBreak(id: id, now: self.at(115), saveSelection: { try world.saveCopy(id) }) }
        let scenarios = [
            Scenario(name: "request", setup: { try self.started($0) }, run: { engine, _, id in _ = try engine.requestBreak(id: id, now: self.at(1400)) }, now: at(1400), overwrite: true, boundAfterActiveEnd: 15 + 10),
            Scenario(name: "cancel by the person", setup: requested(1495), run: { engine, _, id in try engine.cancelWait(id: id, now: self.at(1496)) }, now: at(1496), overwrite: true),
            Scenario(name: "stale-wait cancel", setup: requested(1495), run: { engine, _, _ in try engine.reconcile(now: self.at(1520 + 3600), authorized: true) }, now: at(1520 + 3600), overwrite: true),
            Scenario(name: "break start", setup: requested(100), run: startBreak, now: at(115), later: at(125 + 3600)),
            Scenario(name: "break start rollback", setup: { world in let result = try requested(100)(world); world.failSavePhases = [.onBreak]; return result }, run: startBreak, now: at(115), later: at(125 + 3600)),
            Scenario(name: "break start rollback with a failed cancel", setup: { world in let result = try requested(100)(world); world.failSavePhases = [.onBreak, .active]; return result }, run: startBreak, now: at(115), later: at(125 + 3600)),
            Scenario(name: "re-block", setup: onBreak, run: { engine, _, id in try engine.handleCallback(activityName: self.breakName(id, 1), kind: .willEndWarning, now: self.at(295), authorized: true) }, now: at(295)),
            Scenario(name: "resume", setup: { try self.afterReBlock($0) }, run: { engine, _, id in try engine.resume(id: id, now: self.at(600)) }, now: at(600), overwrite: true),
            Scenario(name: "end during a break", setup: onBreak, run: { engine, _, id in try engine.finish(id: id, reason: .earlyExit, now: self.at(200)) }, now: at(200)),
            Scenario(name: "cleanup after an interrupted break start", setup: { world in
                let (engine, id) = try requested(100)(world)
                world.state.copies = [id]; world.state.breaks[BreakKey(id: id, index: 1)] = BreakRegistration(start: self.at(115), end: self.at(1015), warning: 720)
                world.state.focus[id] = Registration(start: self.t0, end: self.at(2295))
                return (engine, id)
            }, run: { engine, _, _ in try engine.reconcile(now: self.at(116), authorized: true) }, now: at(116)),
        ]
        for scenario in scenarios {
            // Exit pass: a new process starts from each recorded state.
            let world = World(); let (engine, id) = try scenario.setup(world)
            world.recording = true; world.snapshots = [world.state]
            try? scenario.run(engine, world, id)
            for (index, snapshot) in world.snapshots.enumerated() {
                for time in [scenario.now] + (scenario.later.map { [$0] } ?? []) {
                    let exited = World(snapshot), restarted = self.engine(exited)
                    let context = "\(scenario.name) exit \(index) at +\(time.timeIntervalSince(t0))"
                    if scenario.overwrite {
                        let callback = max(snapshot.focus[id]?.end ?? time, time)
                        try? restarted.handleCallback(activityName: focusName(id), kind: .didEnd, now: callback, authorized: true)
                    } else { _ = try? restarted.reconcile(now: time, authorized: true) }
                    assertArtifactTable(exited, context)
                    if let bound = scenario.boundAfterActiveEnd {
                        let s = stored(exited)
                        XCTAssertEqual(s.phase, .terminal, context); XCTAssertEqual(s.reason, .expired, context)
                        XCTAssertLessThanOrEqual(s.observedAt!, s.expiresAt.addingTimeInterval(bound), context)
                    }
                }
            }
            // Throw pass: each throwable effect throws once, then reconcile runs.
            let counting = World(); let (countingEngine, countingID) = try scenario.setup(counting)
            let base = counting.effects
            try? scenario.run(countingEngine, counting, countingID)
            for offset in 0..<(counting.effects - base) {
                let thrown = World(); let (engine, id) = try scenario.setup(thrown)
                thrown.throwAtEffect = thrown.effects + offset
                try? scenario.run(engine, thrown, id)
                _ = try? engine.reconcile(now: scenario.now, authorized: true)
                assertArtifactTable(thrown, "\(scenario.name) throw \(offset)")
            }
        }
    }
    func testEndDuringBreakStopsBothActivitiesAndRemovesCopy() throws {
        let world = World(); let (engine, id) = try started(world)
        try takeBreak(engine, world, id, at: 100)
        try engine.finish(id: id, reason: .earlyExit, now: at(200))
        XCTAssertEqual(stored(world).reason, .earlyExit); XCTAssertEqual(stored(world).phase, .terminal)
        XCTAssertNil(world.state.focus[id]); XCTAssertTrue(world.state.breaks.isEmpty); XCTAssertTrue(world.state.copies.isEmpty); XCTAssertFalse(world.state.shieldOn)
    }
    func testReadFailureStopsBreakActivitiesAndRemovesAllCopies() throws {
        let world = World(), id = UUID(), other = UUID()
        world.state.shieldOn = true; world.state.copies = [id, other]; world.state.focus[id] = Registration(start: t0, end: at(1500))
        world.state.breaks[BreakKey(id: id, index: 1)] = BreakRegistration(start: t0, end: at(900), warning: 720)
        world.state.breaks[BreakKey(id: other, index: 3)] = BreakRegistration(start: t0, end: at(900), warning: 720)
        world.failReads = true
        XCTAssertThrowsError(try engine(world).snapshot())
        XCTAssertFalse(world.state.shieldOn); XCTAssertTrue(world.state.copies.isEmpty); XCTAssertTrue(world.state.breaks.isEmpty); XCTAssertTrue(world.state.focus.isEmpty)
    }
}
