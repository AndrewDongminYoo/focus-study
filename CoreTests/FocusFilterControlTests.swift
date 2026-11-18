import XCTest
@testable import FocusCore

/// The fake world of the filter sections: the control file, the focus and break artifacts and the everyday store.
private struct FilterState: Equatable {
    var envelope = ControlEnvelope()
    var focus: [UUID: Date] = [:]
    var breaks = Set<String>()
    var copies = Set<UUID>()
    var focusShield = false
    var everydayShield = false
    var everydayActivities = Set<String>()
    static func == (a: FilterState, b: FilterState) -> Bool {
        a.envelope.session == b.envelope.session && a.envelope.filterActivation == b.envelope.filterActivation && a.focus == b.focus && a.breaks == b.breaks
            && a.copies == b.copies && a.focusShield == b.focusShield && a.everydayShield == b.everydayShield && a.everydayActivities == b.everydayActivities
    }
}
/// The pattern of `EverydayWorld` in `EverydayControlTests`: every effect is logged, and a snapshot is recorded after each change.
private final class FilterWorld: ControlStore, LockedControl, MonitoringClient, ShieldClient, BreakSelectionStore {
    var state: FilterState
    var log: [String] = []
    /// Every saved envelope, in order.
    var saved: [ControlEnvelope] = []
    var snapshots: [FilterState] = []
    var recording = false
    var failReads = false, failRegister = false, hideRegistration = false
    var schedule: EverydaySchedule?
    /// The index of the throwable effect (save, registration or copy write) that throws once.
    var throwAtEffect: Int?
    private(set) var effects = 0
    init(_ state: FilterState = FilterState()) { self.state = state }
    private func record(_ event: String) {
        log.append(event)
        if recording, snapshots.last != state { snapshots.append(state) }
    }
    private func mayThrow() throws {
        let index = effects; effects += 1
        if throwAtEffect == index { throwAtEffect = nil; throw FixtureFailure.injected }
    }
    func withExclusiveAccess<T>(timeout: TimeInterval?, _ body: (LockedControl) throws -> T) throws -> T { try body(self) }
    func load() throws -> ControlEnvelope { if failReads { throw FixtureFailure.injected }; return state.envelope }
    func save(_ envelope: ControlEnvelope) throws {
        try mayThrow()
        state.envelope = envelope; saved.append(envelope)
        record("save:\(envelope.session.map { "\($0.phase)" } ?? "none"):\(envelope.filterActivation == nil ? "unmarked" : "marker")")
    }
    var registeredSessionIDs: [UUID] { Array(state.focus.keys) }
    func register(id: UUID, start: Date, end: Date) throws {
        try mayThrow()
        if failRegister { throw FixtureFailure.injected }
        state.focus[id] = end; record("focus.register")
    }
    func isRegistered(id: UUID) -> Bool { !hideRegistration && state.focus[id] != nil }
    func stop(id: UUID) { state.focus[id] = nil; state.breaks = state.breaks.filter { !$0.hasPrefix(id.uuidString) }; record("focus.stop") }
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws {
        try mayThrow(); state.breaks.insert("\(id.uuidString).\(index)"); record("break.register")
    }
    func isBreakRegistered(id: UUID, index: Int) -> Bool { state.breaks.contains("\(id.uuidString).\(index)") }
    var registeredBreaks: [(id: UUID, index: Int)] {
        state.breaks.map { key in let parts = key.split(separator: "."); return (UUID(uuidString: String(parts[0]))!, Int(parts[1])!) }
    }
    func stopBreak(id: UUID, index: Int) { state.breaks.remove("\(id.uuidString).\(index)"); record("break.stop") }
    private static func name(_ revision: UUID, _ part: EverydayPart) -> String {
        switch part { case .range: "\(revision.uuidString).range"; case .window(let n): "\(revision.uuidString).window.\(n)" }
    }
    func registerEveryday(revision: UUID, part: EverydayPart, start: Int, end: Int) throws {
        state.everydayActivities.insert(Self.name(revision, part)); record("everyday.register")
    }
    var registeredEveryday: [(revision: UUID, part: EverydayPart)] {
        state.everydayActivities.map { name in
            let parts = name.split(separator: ".")
            return (UUID(uuidString: String(parts[0]))!, parts[1] == "range" ? .range : .window(Int(parts[2])!))
        }
    }
    func stopEveryday(revision: UUID, part: EverydayPart) { state.everydayActivities.remove(Self.name(revision, part)); record("everyday.stop") }
    func clear() { state.focusShield = false; record("focus.clear") }
    func restoreShield(id: UUID) -> Bool {
        guard state.copies.contains(id) else { return false }
        state.focusShield = true; record("focus.restore"); return true
    }
    func exists(id: UUID) -> Bool { state.copies.contains(id) }
    func remove(id: UUID) { state.copies.remove(id); record("copy.remove") }
    func removeAll(except id: UUID?) { state.copies = state.copies.filter { $0 == id } }
    func saveCopy(_ id: UUID) throws { try mayThrow(); state.copies.insert(id); record("copy.save") }
    func apply() { state.focusShield = true; record("focus.apply") }
}
private final class FilterLayer: EverydayLayerStore {
    let world: FilterWorld
    init(_ world: FilterWorld) { self.world = world }
    func load() throws -> EverydaySchedule? { world.schedule }
    func storeMatches() -> Bool { world.state.everydayShield }
    func applyStored() -> Bool { world.state.everydayShield = true; world.log.append("everyday.apply"); return true }
    var hasShield: Bool { world.state.everydayShield }
    func clearShield() { world.state.everydayShield = false; world.log.append("everyday.clear") }
}

final class FocusFilterControlTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!; return calendar
    }()
    /// 10:00 in Seoul.
    private var t0: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 10))! }
    private func at(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }
    private func engine(_ world: FilterWorld) -> SessionControl {
        SessionControl(store: world, monitoring: world, shield: world, breakSelection: world, everyday: FilterLayer(world), calendar: calendar)
    }
    @discardableResult
    private func on(_ engine: SessionControl, _ world: FilterWorld, at now: Date, access: AccessState = .approved, ready: Bool = true, matches: Bool = true) throws -> FocusFilterStart {
        try engine.startFromFocusFilter(now: now, length: 1500, authorized: { access }, selectionReady: ready, apply: { world.apply() }, matches: { matches && world.state.focusShield })
    }
    private func manual(_ engine: SessionControl, _ world: FilterWorld, at now: Date) throws -> ControlSession {
        try engine.start(now: now, authorized: { .approved }, apply: { world.apply() }, matches: { world.state.focusShield })
    }
    private func started(_ result: FocusFilterStart, file: StaticString = #filePath, line: UInt = #line) -> ControlSession? {
        guard case .started(let session) = result else { XCTFail("not started: \(result)", file: file, line: line); return nil }
        return session
    }
    /// A stored session in `phase`, with the artifacts that the phase has after a section with access approved.
    private func stored(_ phase: SessionPhase, origin: SessionOrigin?, marker: UUID?) -> FilterWorld {
        var session = ControlSession(startedAt: t0); session.origin = origin; session.phase = phase
        let world = FilterWorld()
        switch phase {
        case .waiting: session.pausedAt = at(100); session.waitEndsAt = at(115)
        case .onBreak, .breakOver:
            session.breaksTaken = 1; session.pausedAt = at(100); session.breakEndsAt = at(295); session.deadlineCredit = 195
            if phase == .onBreak { world.state.copies = [session.id]; world.state.breaks = ["\(session.id.uuidString).1"] }
        case .ending, .terminal: session.reason = .earlyExit; session.observedAt = at(90)
        case .preparing, .active: break
        }
        if [.active, .waiting, .onBreak, .breakOver].contains(phase) { world.state.focus[session.id] = at(2100) }
        world.state.focusShield = phase == .active || phase == .waiting || phase == .breakOver
        world.state.envelope.session = session; world.state.envelope.filterActivation = marker
        return world
    }
    private let effectEvents = ["focus.register", "focus.stop", "focus.clear", "focus.apply", "focus.restore", "break.register", "break.stop", "copy.remove"]
    private func assertNoFocusEffects(_ world: FilterWorld, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        for event in effectEvents { XCTAssertFalse(world.log.contains(event), "\(event): \(context)", file: file, line: line) }
    }

    // MARK: On call

    func testOnCallStartsAFilterSessionAndWritesTheMarkerWithPreparing() throws {
        let world = FilterWorld(), engine = engine(world)
        let session = try XCTUnwrap(started(try on(engine, world, at: t0)))
        XCTAssertEqual(session.origin, .focusFilter); XCTAssertEqual(session.phase, .active)
        let first = try XCTUnwrap(world.saved.first)
        XCTAssertEqual(first.session?.phase, .preparing); XCTAssertEqual(first.session?.origin, .focusFilter)
        let marker = try XCTUnwrap(first.filterActivation)
        XCTAssertEqual(world.saved.map { $0.session?.phase }, [.preparing, .active])
        XCTAssertEqual(world.state.envelope.filterActivation, marker); XCTAssertEqual(world.state.envelope.session?.origin, .focusFilter)
        XCTAssertNotNil(world.state.focus[session.id]); XCTAssertTrue(world.state.focusShield)
    }
    func testRepeatedOnCallChangesNothing() throws {
        let marker = UUID()
        let empty = FilterWorld(); empty.state.envelope.filterActivation = marker
        var worlds = [("none", empty)]
        for phase in [SessionPhase.preparing, .active, .waiting, .onBreak, .breakOver, .ending, .terminal] {
            worlds.append(("\(phase)", stored(phase, origin: .manual, marker: marker)))
        }
        for (name, world) in worlds {
            let before = world.state
            world.log = []
            XCTAssertEqual(try on(engine(world), world, at: at(110)), .repeated, name)
            XCTAssertTrue(world.saved.isEmpty, name); assertNoFocusEffects(world, name)
            XCTAssertEqual(world.state.envelope.session, before.envelope.session, name); XCTAssertEqual(world.state.envelope.filterActivation, marker, name)
        }
        // A stale waiting session with a break copy: only the M2 cleanup changes it, exactly as a reconcile does.
        for now in [at(120), at(130)] {
            let repeated = stored(.waiting, origin: .focusFilter, marker: marker), reconciled = stored(.waiting, origin: .focusFilter, marker: marker)
            for world in [repeated, reconciled] { world.state.copies = [world.state.envelope.session!.id] }
            reconciled.state.envelope.session = repeated.state.envelope.session; reconciled.state.focus = repeated.state.focus; reconciled.state.copies = repeated.state.copies
            XCTAssertEqual(try on(engine(repeated), repeated, at: now), .repeated)
            try engine(reconciled).reconcile(now: now, authorized: .approved)
            XCTAssertEqual(repeated.log.filter { $0.hasPrefix("save") || $0.hasPrefix("focus") || $0.hasPrefix("break") },
                           reconciled.log.filter { $0.hasPrefix("save") || $0.hasPrefix("focus") || $0.hasPrefix("break") }, "\(now)")
            XCTAssertFalse(repeated.log.isEmpty, "\(now)")
            XCTAssertEqual(repeated.state, reconciled.state, "\(now)")
            XCTAssertEqual(repeated.state.envelope.filterActivation, marker); XCTAssertEqual(repeated.state.envelope.session?.origin, .focusFilter)
        }
    }
    func testRefusalsSetTheMarkerAndStartNothing() throws {
        var cases: [(String, FilterWorld, AccessState, Bool, FocusFilterRefusal)] = [
            // `unknown` no longer refuses (2026-11-16 extension design, decision 20); `testFilterStartAcceptsUnknownAccess` covers it.
            ("access", FilterWorld(), .denied, true, .access),
            ("selection", FilterWorld(), .approved, false, .selection),
        ]
        for phase in [SessionPhase.preparing, .active, .waiting, .onBreak, .breakOver, .ending] {
            cases.append(("\(phase)", stored(phase, origin: .manual, marker: nil), .approved, true, .busy))
        }
        cases.append(("terminal", stored(.terminal, origin: .manual, marker: nil), .approved, true, .history))
        for (name, world, access, ready, reason) in cases {
            let before = world.state.envelope.session
            world.log = []
            XCTAssertEqual(try on(engine(world), world, at: at(110), access: access, ready: ready), .refused(reason), name)
            XCTAssertNotNil(world.state.envelope.filterActivation, name)
            XCTAssertEqual(world.saved.last?.filterActivation, world.state.envelope.filterActivation, name)
            XCTAssertEqual(world.state.envelope.session, before, name)
            for event in ["focus.register", "focus.apply", "break.register", "focus.restore"] { XCTAssertFalse(world.log.contains(event), "\(event): \(name)") }
        }
    }
    func testStartFailureRollsBackAndKeepsTheMarker() throws {
        for failure in ["registration", "verification", "matches"] {
            let world = FilterWorld(), engine = engine(world)
            if failure == "registration" { world.failRegister = true }
            if failure == "verification" { world.hideRegistration = true }
            XCTAssertThrowsError(try on(engine, world, at: t0, matches: failure != "matches"), failure)
            let session = try XCTUnwrap(world.state.envelope.session, failure)
            XCTAssertEqual(session.phase, .terminal, failure); XCTAssertEqual(session.reason, .startFailed, failure)
            XCTAssertEqual(session.origin, .focusFilter, failure)
            XCTAssertEqual(world.state.envelope.filterActivation, world.saved.first?.filterActivation, failure)
            XCTAssertNotNil(world.state.envelope.filterActivation, failure)
            XCTAssertFalse(world.state.focusShield, failure); XCTAssertNil(world.state.focus[session.id], failure)
        }
    }
    func testManualStartStoresManualAndKeepsItsBehavior() throws {
        let world = FilterWorld(), engine = engine(world)
        let session = try manual(engine, world, at: t0)
        XCTAssertEqual(session.origin, .manual); XCTAssertEqual(world.state.envelope.session?.origin, .manual)
        XCTAssertEqual(world.saved.map { $0.session?.origin }, [.manual, .manual])
        XCTAssertNil(world.state.envelope.filterActivation)
    }

    // MARK: Off call

    func testOffCallEndsOnlyAFilterSession() throws {
        for phase in [SessionPhase.active, .waiting, .onBreak, .breakOver] {
            for origin in [nil, SessionOrigin.manual, .focusFilter] {
                for marker in [nil, UUID()] {
                    let context = "\(phase) \(origin.map { "\($0)" } ?? "none") \(marker != nil)"
                    let world = stored(phase, origin: origin, marker: marker), before = world.state.envelope.session
                    try engine(world).endFromFocusFilter(now: at(110), authorized: .approved)
                    let after = try XCTUnwrap(world.state.envelope.session, context)
                    if origin == .focusFilter {
                        XCTAssertEqual(after.phase, .terminal, context); XCTAssertEqual(after.reason, .earlyExit, context)
                        XCTAssertTrue(world.state.focus.isEmpty, context); XCTAssertFalse(world.state.focusShield, context)
                        XCTAssertTrue(world.state.breaks.isEmpty, context); XCTAssertTrue(world.state.copies.isEmpty, context)
                    } else {
                        XCTAssertEqual(after, before, context); XCTAssertNotNil(world.state.focus[after.id], context)
                    }
                    XCTAssertNil(world.state.envelope.filterActivation, context)
                }
            }
        }
    }
    func testOffCallLetsTheTimedEndWin() throws {
        let slack = BreakTiming.standard.slack
        for origin in [SessionOrigin.manual, .focusFilter] {
            let expired = stored(.active, origin: origin, marker: UUID())
            try engine(expired).endFromFocusFilter(now: at(1500), authorized: .approved)
            XCTAssertEqual(expired.state.envelope.session?.reason, .expired, "\(origin)")
            let missed = stored(.onBreak, origin: origin, marker: UUID())
            try engine(missed).endFromFocusFilter(now: at(1500 + 195 + slack), authorized: .approved)
            XCTAssertEqual(missed.state.envelope.session?.reason, .deadlineMissed, "\(origin)")
            let revoked = stored(.active, origin: origin, marker: UUID())
            try engine(revoked).endFromFocusFilter(now: at(110), authorized: .denied)
            XCTAssertEqual(revoked.state.envelope.session?.reason, .authorizationRevoked, "\(origin)")
            for world in [expired, missed, revoked] {
                XCTAssertEqual(world.state.envelope.session?.phase, .terminal, "\(origin)"); XCTAssertNil(world.state.envelope.filterActivation, "\(origin)")
            }
        }
    }
    func testOffCallClearsTheMarkerInTheSaveOfEnding() throws {
        let world = FilterWorld(), engine = engine(world)
        try on(engine, world, at: t0)
        world.saved = []
        try engine.endFromFocusFilter(now: at(200), authorized: .approved)
        XCTAssertEqual(world.saved.map { $0.session?.phase }, [.ending, .terminal])
        XCTAssertTrue(world.saved.allSatisfy { $0.filterActivation == nil })
    }
    func testOffCallWithoutAFilterSessionSavesOnlyAStoredMarker() throws {
        let marked = FilterWorld(); marked.state.envelope.filterActivation = UUID()
        try engine(marked).endFromFocusFilter(now: t0, authorized: .approved)
        XCTAssertEqual(marked.saved.count, 1); XCTAssertNil(marked.saved.first?.filterActivation); XCTAssertNil(marked.state.envelope.session)
        let unmarked = FilterWorld()
        try engine(unmarked).endFromFocusFilter(now: t0, authorized: .approved)
        XCTAssertTrue(unmarked.saved.isEmpty)
    }
    func testOffCallDuringABreakRemovesBreakArtifactsAndBlocksTheEverydayLayer() throws {
        let world = stored(.onBreak, origin: .focusFilter, marker: UUID())
        world.schedule = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 8 * 60, rangeEnd: 18 * 60, windows: [])
        let id = try XCTUnwrap(world.state.envelope.session?.id)
        try engine(world).endFromFocusFilter(now: at(200), authorized: .approved)
        XCTAssertEqual(world.state.envelope.session?.reason, .earlyExit)
        XCTAssertTrue(world.state.copies.isEmpty); XCTAssertTrue(world.state.breaks.isEmpty); XCTAssertNil(world.state.focus[id]); XCTAssertFalse(world.state.focusShield)
        let order = ["save:ending:unmarked", "focus.clear", "focus.stop", "copy.remove", "everyday.apply", "save:terminal:unmarked"].map { world.log.firstIndex(of: $0) }
        XCTAssertFalse(order.contains(nil), "\(world.log)")
        XCTAssertEqual(order.compactMap { $0 }, order.compactMap { $0 }.sorted(), "\(world.log)")
        XCTAssertTrue(world.state.everydayShield)
    }

    // MARK: Off call after a caught error (#53)

    /// A filter-started session that the off call released: no focus restriction, no break artifact and no marker is left.
    private func assertReleased(_ world: FilterWorld, _ reason: EndReason, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(world.throwAtEffect, "the injected failure did not happen: \(context)", file: file, line: line)
        XCTAssertEqual(world.state.envelope.session?.phase, .terminal, context, file: file, line: line)
        XCTAssertEqual(world.state.envelope.session?.reason, reason, context, file: file, line: line)
        XCTAssertFalse(world.state.focusShield, "focus shield: \(context)", file: file, line: line)
        XCTAssertTrue(world.state.focus.isEmpty, "focus activity: \(context)", file: file, line: line)
        XCTAssertTrue(world.state.breaks.isEmpty, "break activity: \(context)", file: file, line: line)
        XCTAssertTrue(world.state.copies.isEmpty, "break copy: \(context)", file: file, line: line)
        XCTAssertNil(world.state.envelope.filterActivation, "marker: \(context)", file: file, line: line)
        XCTAssertTrue(world.saved.allSatisfy { $0.filterActivation == nil }, "marker in a save: \(context)", file: file, line: line)
    }
    /// A stale wait at 130 s that an interrupted break start left: the break copy and the break activity exist in `waiting`.
    private func interruptedBreakStart(origin: SessionOrigin) -> FilterWorld {
        let world = stored(.waiting, origin: origin, marker: UUID()), id = world.state.envelope.session!.id
        world.state.copies = [id]; world.state.breaks = ["\(id.uuidString).1"]
        return world
    }
    func testOffCallReleasesAFilterSessionWhenTheReBlockSaveFails() throws {
        // The break ended at 295 s, so the reconcile restores the focus shield and then throws at the save of `breakOver`, its first throwable effect.
        let world = stored(.onBreak, origin: .focusFilter, marker: UUID())
        world.throwAtEffect = world.effects
        XCTAssertNoThrow(try engine(world).endFromFocusFilter(now: at(300), authorized: .approved))
        XCTAssertTrue(world.log.contains("focus.restore"), "\(world.log)")
        assertReleased(world, .earlyExit, "re-block")
        XCTAssertEqual(world.saved.map { $0.session?.phase }, [.ending, .terminal])
    }
    func testOffCallReleasesAFilterSessionWhenTheCleanupSaveFails() throws {
        // The wait cancel of the cleanup registers the focus end (effect 0), then saves `active` (effect 1).
        for effect in [0, 1] {
            let world = interruptedBreakStart(origin: .focusFilter)
            world.throwAtEffect = effect
            XCTAssertNoThrow(try engine(world).endFromFocusFilter(now: at(130), authorized: .approved), "effect \(effect)")
            assertReleased(world, .earlyExit, "cleanup effect \(effect)")
        }
        // Without a break copy, the wait cancel of the reconcile throws instead.
        for effect in [0, 1] {
            let world = stored(.waiting, origin: .focusFilter, marker: UUID())
            world.throwAtEffect = effect
            XCTAssertNoThrow(try engine(world).endFromFocusFilter(now: at(130), authorized: .approved), "effect \(effect)")
            assertReleased(world, .earlyExit, "reconcile effect \(effect)")
        }
    }
    func testOffCallAfterACaughtErrorNeverEndsATimedOutSessionAsEarlyExit() throws {
        // Before the focus end, the off call with the caught error gives the reason of the same call without it.
        let clean = interruptedBreakStart(origin: .focusFilter), failing = interruptedBreakStart(origin: .focusFilter)
        failing.throwAtEffect = 1
        try engine(clean).endFromFocusFilter(now: at(130), authorized: .approved)
        XCTAssertNoThrow(try engine(failing).endFromFocusFilter(now: at(130), authorized: .approved))
        XCTAssertEqual(clean.state.envelope.session?.reason, .earlyExit)
        assertReleased(failing, .earlyExit, "before the focus end")
        // After the focus end (1525 s with the cancelled wait), the M2 registered-end rule ends the session before the Focus-off rule runs.
        // So the Focus-off rule never records `.earlyExit` for a session whose time is up, and the end's own result propagates as today.
        let expired = interruptedBreakStart(origin: .focusFilter)
        try engine(expired).endFromFocusFilter(now: at(1600), authorized: .approved)
        XCTAssertEqual(expired.state.envelope.session?.reason, .expired)
        let late = interruptedBreakStart(origin: .focusFilter)
        late.throwAtEffect = 1
        XCTAssertThrowsError(try engine(late).endFromFocusFilter(now: at(1600), authorized: .approved))
        XCTAssertNil(late.throwAtEffect)
        XCTAssertEqual(late.state.envelope.session?.phase, .terminal); XCTAssertEqual(late.state.envelope.session?.reason, .recoveryInterrupted)
        XCTAssertFalse(late.state.focusShield); XCTAssertTrue(late.state.focus.isEmpty); XCTAssertTrue(late.state.breaks.isEmpty); XCTAssertTrue(late.state.copies.isEmpty)
        // The cleanup's own end saves before step 2, and the error stops step 5, so the activation check clears the marker.
        XCTAssertNotNil(late.state.envelope.filterActivation)
    }
    func testOffCallKeepsTheAccessReasonAfterACaughtError() throws {
        // Without access the reconcile ends the session before any wait cancel or re-block, so only a cleanup error reaches this rule.
        let clean = interruptedBreakStart(origin: .focusFilter), failing = interruptedBreakStart(origin: .focusFilter)
        failing.throwAtEffect = 1
        try engine(clean).endFromFocusFilter(now: at(130), authorized: .denied)
        XCTAssertNoThrow(try engine(failing).endFromFocusFilter(now: at(130), authorized: .denied))
        XCTAssertEqual(clean.state.envelope.session?.reason, .authorizationRevoked)
        assertReleased(failing, .authorizationRevoked, "access")
    }
    /// The 2026-11-11 access-state design: Focus off with `unknown` access, such as with the app not running, is never a revocation.
    func testOffCallWithUnknownAccessNeverEndsAsRevoked() throws {
        let clean = interruptedBreakStart(origin: .focusFilter), failing = interruptedBreakStart(origin: .focusFilter)
        failing.throwAtEffect = 1
        try engine(clean).endFromFocusFilter(now: at(130), authorized: .unknown)
        XCTAssertNoThrow(try engine(failing).endFromFocusFilter(now: at(130), authorized: .unknown))
        XCTAssertEqual(clean.state.envelope.session?.reason, .earlyExit)
        assertReleased(failing, .earlyExit, "unknown access")
        let expired = stored(.active, origin: .focusFilter, marker: UUID())
        try engine(expired).endFromFocusFilter(now: at(1500), authorized: .unknown)
        XCTAssertEqual(expired.state.envelope.session?.reason, .expired)
    }
    func testOffCallStillThrowsForAManualSessionWhenReconcileFails() throws {
        let reBlock = stored(.onBreak, origin: .manual, marker: UUID())
        reBlock.throwAtEffect = reBlock.effects
        XCTAssertThrowsError(try engine(reBlock).endFromFocusFilter(now: at(300), authorized: .approved))
        XCTAssertNil(reBlock.throwAtEffect)
        XCTAssertEqual(reBlock.state.envelope.session?.phase, .onBreak); XCTAssertNil(reBlock.state.envelope.session?.reason)
        XCTAssertTrue(reBlock.state.focusShield); XCTAssertNotNil(reBlock.state.focus[reBlock.state.envelope.session!.id])
        XCTAssertFalse(reBlock.log.contains("focus.clear"), "\(reBlock.log)")
        let cleanup = interruptedBreakStart(origin: .manual)
        cleanup.throwAtEffect = 1
        XCTAssertThrowsError(try engine(cleanup).endFromFocusFilter(now: at(130), authorized: .approved))
        XCTAssertNil(cleanup.throwAtEffect)
        XCTAssertEqual(cleanup.state.envelope.session?.phase, .waiting); XCTAssertNil(cleanup.state.envelope.session?.reason)
        XCTAssertTrue(cleanup.state.focusShield); XCTAssertNotNil(cleanup.state.focus[cleanup.state.envelope.session!.id])
    }

    // MARK: Activation check

    func testClearFilterActivationComparesTheStoredMarker() throws {
        let marker = UUID()
        for (stored, matching, cleared) in [(marker as UUID?, marker, true), (marker, UUID(), false), (nil, marker, false)] {
            let world = self.stored(.active, origin: .focusFilter, marker: stored), before = world.state.envelope.session
            try engine(world).clearFilterActivation(matching: matching, now: at(110))
            XCTAssertEqual(world.saved.count, cleared ? 1 : 0)
            XCTAssertEqual(world.state.envelope.filterActivation, cleared ? nil : stored)
            XCTAssertEqual(world.state.envelope.session, before); assertNoFocusEffects(world, "clear \(cleared)")
        }
    }

    // MARK: Guards across sequences

    func testOneSessionPerActivationAcrossSequences() throws {
        // On, S1 completes (an open session rolls over, so "집중 종료" after the base length ends it), the import removes it, a repeated on call.
        let world = FilterWorld(), engine = engine(world)
        let s1 = try XCTUnwrap(started(try on(engine, world, at: t0)))
        try engine.finish(id: s1.id, reason: .earlyExit, now: at(1500))
        XCTAssertEqual(world.state.envelope.session?.reason, .expired)
        try engine.acknowledgeTerminal(id: s1.id)
        XCTAssertEqual(try on(engine, world, at: at(1510)), .repeated); XCTAssertNil(world.state.envelope.session)
        // Then off, then on: S2 starts.
        try engine.endFromFocusFilter(now: at(1520), authorized: .approved)
        let s2 = try XCTUnwrap(started(try on(engine, world, at: at(1530))))
        XCTAssertNotEqual(s2.id, s1.id)

        // On, refused for access, access approved, a repeated on call.
        let refused = FilterWorld(), refusedEngine = self.engine(refused)
        XCTAssertEqual(try on(refusedEngine, refused, at: t0, access: .denied), .refused(.access))
        XCTAssertEqual(try on(refusedEngine, refused, at: at(10)), .repeated); XCTAssertNil(refused.state.envelope.session)

        // On, S1 starts, the off call is lost, so S1 rolls over at its focus end (2026-11-16 extension design).
        // With the check, the app ends S1 and, after the import, the next on starts S2; without it, the next on is a repeated call and S1 keeps running.
        for checked in [true, false] {
            let lost = FilterWorld(), lostEngine = self.engine(lost)
            let first = try XCTUnwrap(started(try on(lostEngine, lost, at: t0)))
            try lostEngine.reconcile(now: at(1500), authorized: .approved)
            XCTAssertEqual(lost.state.envelope.session?.phase, .active)
            if checked, let marker = try lostEngine.snapshot().filterActivation {
                try lostEngine.clearFilterActivation(matching: marker, now: at(1600))
                XCTAssertEqual(lost.state.envelope.session?.reason, .expired); try lostEngine.acknowledgeTerminal(id: first.id)
            }
            let next = try on(lostEngine, lost, at: at(1700))
            if checked { XCTAssertNotNil(started(next)) } else {
                XCTAssertEqual(next, .repeated); XCTAssertEqual(lost.state.envelope.session?.id, first.id); XCTAssertEqual(lost.state.envelope.session?.phase, .active)
            }
        }

        // The off call of one activation arrives after the on call of the next: it ends S2 and clears the marker.
        let late = FilterWorld(), lateEngine = self.engine(late)
        let a = try XCTUnwrap(started(try on(lateEngine, late, at: t0)))
        try lateEngine.endFromFocusFilter(now: at(10), authorized: .approved); try lateEngine.acknowledgeTerminal(id: a.id)
        let b = try XCTUnwrap(started(try on(lateEngine, late, at: at(20))))
        try lateEngine.endFromFocusFilter(now: at(30), authorized: .approved)
        XCTAssertEqual(late.state.envelope.session?.id, b.id); XCTAssertEqual(late.state.envelope.session?.reason, .earlyExit)
        XCTAssertNil(late.state.envelope.filterActivation)

        // A filter session in each break phase ends as `.earlyExit` on the off call; a focus end that passed first wins.
        for phase in ["waiting", "onBreak", "breakOver", "expired"] {
            let breaking = FilterWorld(), breakingEngine = self.engine(breaking)
            let s = try XCTUnwrap(started(try on(breakingEngine, breaking, at: t0)))
            var offAt = at(1500)
            if phase != "expired" {
                let waiting = try breakingEngine.requestBreak(id: s.id, now: at(100)); offAt = at(105)
                if phase != "waiting" {
                    try breakingEngine.startBreak(id: s.id, now: waiting.waitEndsAt!, saveSelection: { try breaking.saveCopy(s.id) }); offAt = at(200)
                }
                if phase == "breakOver" { try breakingEngine.reconcile(now: at(295), authorized: .approved); offAt = at(300) }
                XCTAssertEqual(breaking.state.envelope.session?.phase.rawValue, phase)
            }
            try breakingEngine.endFromFocusFilter(now: offAt, authorized: .approved)
            XCTAssertEqual(breaking.state.envelope.session?.reason, phase == "expired" ? .expired : .earlyExit, phase)
            XCTAssertTrue(breaking.state.breaks.isEmpty, phase); XCTAssertTrue(breaking.state.copies.isEmpty, phase); XCTAssertTrue(breaking.state.focus.isEmpty, phase)
        }
    }
    func testFocusOffNeverEndsAManualSessionAcrossSequences() throws {
        // A manual session M runs, on, off.
        let world = FilterWorld(), engine = engine(world)
        let m = try manual(engine, world, at: t0)
        XCTAssertEqual(try on(engine, world, at: at(10)), .refused(.busy)); XCTAssertNotNil(world.state.envelope.filterActivation)
        try engine.endFromFocusFilter(now: at(20), authorized: .approved)
        XCTAssertEqual(world.state.envelope.session?.id, m.id); XCTAssertEqual(world.state.envelope.session?.phase, .active)
        XCTAssertNil(world.state.envelope.filterActivation)

        // On, S1 starts, "집중 종료", a manual M, a repeated on call, off.
        let other = FilterWorld(), otherEngine = self.engine(other)
        let s1 = try XCTUnwrap(started(try on(otherEngine, other, at: t0)))
        try otherEngine.finish(id: s1.id, reason: .earlyExit, now: at(10)); try otherEngine.acknowledgeTerminal(id: s1.id)
        let m2 = try manual(otherEngine, other, at: at(20))
        XCTAssertEqual(try on(otherEngine, other, at: at(30)), .repeated)
        try otherEngine.endFromFocusFilter(now: at(40), authorized: .approved)
        XCTAssertEqual(other.state.envelope.session?.id, m2.id); XCTAssertEqual(other.state.envelope.session?.phase, .active)
        XCTAssertEqual(other.state.envelope.session?.origin, .manual); XCTAssertNotNil(other.state.focus[m2.id]); XCTAssertTrue(other.state.focusShield)

        // A manual session in each break phase stays in that phase after an off call.
        for phase in ["waiting", "onBreak", "breakOver"] {
            let breaking = FilterWorld(), breakingEngine = self.engine(breaking)
            let s = try manual(breakingEngine, breaking, at: t0)
            let waiting = try breakingEngine.requestBreak(id: s.id, now: at(100)); var offAt = at(105)
            if phase != "waiting" { try breakingEngine.startBreak(id: s.id, now: waiting.waitEndsAt!, saveSelection: { try breaking.saveCopy(s.id) }); offAt = at(200) }
            if phase == "breakOver" { try breakingEngine.reconcile(now: at(295), authorized: .approved); offAt = at(300) }
            let before = breaking.state.envelope.session
            try breakingEngine.endFromFocusFilter(now: offAt, authorized: .approved)
            XCTAssertEqual(breaking.state.envelope.session, before, phase)
        }

        // Focus A starts S1; a switch that sends off then on ends S1 and starts S2.
        let switching = FilterWorld(), switchingEngine = self.engine(switching)
        let a = try XCTUnwrap(started(try on(switchingEngine, switching, at: t0)))
        try switchingEngine.endFromFocusFilter(now: at(10), authorized: .approved)
        XCTAssertEqual(switching.state.envelope.session?.reason, .earlyExit)
        try switchingEngine.acknowledgeTerminal(id: a.id)
        XCTAssertNotNil(started(try on(switchingEngine, switching, at: at(20))))
    }
    func testFilterFieldsSurviveEveryTransition() throws {
        let world = FilterWorld(), engine = engine(world)
        let s = try XCTUnwrap(started(try on(engine, world, at: t0)))
        let marker = try XCTUnwrap(world.state.envelope.filterActivation)
        func check(_ step: String, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(world.state.envelope.filterActivation, marker, step, file: file, line: line)
            if let session = world.state.envelope.session { XCTAssertEqual(session.origin, .focusFilter, step, file: file, line: line) }
        }
        _ = try engine.requestBreak(id: s.id, now: at(100)); check("requestBreak")
        try engine.cancelWait(id: s.id, now: at(105)); check("cancelWait")
        let waiting = try engine.requestBreak(id: s.id, now: at(200)); check("requestBreak 2")
        try engine.startBreak(id: s.id, now: waiting.waitEndsAt!, saveSelection: { try world.saveCopy(s.id) }); check("startBreak")
        let breakEnd = try XCTUnwrap(world.state.envelope.session?.breakEndsAt)
        try engine.reconcile(now: breakEnd, authorized: .approved); check("re-block")
        XCTAssertEqual(world.state.envelope.session?.phase, .breakOver)
        try engine.resume(id: s.id, now: breakEnd.addingTimeInterval(5)); check("resume")
        // A focus `didEnd` here would be nothing due in its own end, which ends the session (2026-11-18 single-interval amendment, decision 12).
        for kind in [CallbackKind.didStart, .willEndWarning] {
            try engine.handleCallback(activityName: s.activityName, kind: kind, now: breakEnd.addingTimeInterval(10), authorized: .approved); check("callback \(kind)")
        }
        XCTAssertEqual(world.state.envelope.session?.phase, .active)
        try engine.finish(id: s.id, reason: .earlyExit, now: breakEnd.addingTimeInterval(20)); check("finish")
        try engine.acknowledgeTerminal(id: s.id); check("acknowledgeTerminal")
        XCTAssertNil(world.state.envelope.session)
        let schedule = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 8 * 60, rangeEnd: 18 * 60, windows: [])
        try engine.saveEveryday(schedule, now: breakEnd.addingTimeInterval(30), authorized: { .approved }, containsStoredSelection: { true }, write: { world.schedule = $0 })
        check("saveEveryday")
    }
    func testControlReadFailureInAFilterSectionThrows() throws {
        let sections: [(String, (SessionControl, FilterWorld) throws -> Void)] = [
            ("start", { try self.on($0, $1, at: self.t0) }),
            ("end", { engine, _ in try engine.endFromFocusFilter(now: self.t0, authorized: .approved) }),
            ("check", { engine, _ in try engine.clearFilterActivation(matching: UUID(), now: self.t0) }),
        ]
        for (name, run) in sections {
            let world = stored(.active, origin: .focusFilter, marker: UUID()), id = world.state.envelope.session!.id
            world.state.everydayShield = true; world.failReads = true
            XCTAssertThrowsError(try run(engine(world), world), name)
            XCTAssertFalse(world.state.focusShield, name); XCTAssertFalse(world.state.everydayShield, name); XCTAssertNil(world.state.focus[id], name)
            XCTAssertTrue(world.saved.isEmpty, name)
        }
    }

    // MARK: Interruptions

    /// The spec table "Gaps between steps", after a reconcile with access approved.
    private func assertGapTable(_ world: FilterWorld, _ rule: (ControlSession?, UUID?) -> Bool, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        let session = world.state.envelope.session, marker = world.state.envelope.filterActivation
        XCTAssertTrue(rule(session, marker), "phase \(session.map { "\($0.phase)" } ?? "none"), marker \(marker != nil): \(context)", file: file, line: line)
        XCTAssertNotEqual(session?.phase, .preparing, context, file: file, line: line); XCTAssertNotEqual(session?.phase, .ending, context, file: file, line: line)
        if let session, session.phase != .terminal {
            XCTAssertNotNil(world.state.focus[session.id], "focus activity: \(context)", file: file, line: line)
        } else {
            XCTAssertTrue(world.state.focus.isEmpty, "focus activity: \(context)", file: file, line: line)
            XCTAssertFalse(world.state.focusShield, "focus shield: \(context)", file: file, line: line)
        }
        if session?.phase != .onBreak { XCTAssertTrue(world.state.breaks.isEmpty && world.state.copies.isEmpty, "break artifacts: \(context)", file: file, line: line) }
    }
    func testInterruptionAtEveryStepKeepsTheGapTable() throws {
        struct Scenario {
            let name: String
            let setup: () throws -> FilterWorld
            let run: (SessionControl, FilterWorld) throws -> Void
            let now: Date
            /// The marker and the stored phase that the gap table allows.
            let rule: (ControlSession?, UUID?) -> Bool
            /// The stricter rule after one thrown effect, when the table gives one.
            var thrown: ((ControlSession?, UUID?) -> Bool)? = nil
        }
        let filterSession: () throws -> FilterWorld = {
            let world = FilterWorld(); _ = try self.on(self.engine(world), world, at: self.t0); return world
        }
        let filterBreak: () throws -> FilterWorld = {
            let world = try filterSession(), engine = self.engine(world), id = world.state.envelope.session!.id
            let waiting = try engine.requestBreak(id: id, now: self.at(100))
            try engine.startBreak(id: id, now: waiting.waitEndsAt!, saveSelection: { try world.saveCopy(id) })
            return world
        }
        // A thrown error in the end section, also in its cleanup or reconcile, ends the filter-started session (#53).
        let ended: (ControlSession?, UUID?) -> Bool = { $0?.phase == .terminal && $0?.origin == .focusFilter && $1 == nil }
        // A process exit after a save of the reconcile that does not end the session leaves that phase with the marker cleared.
        let exitedAfterReconcile: (ControlSession?, UUID?) -> Bool = { $0?.origin == .focusFilter && ($0?.phase != .terminal || $1 == nil) }
        let scenarios = [
            Scenario(name: "start", setup: { FilterWorld() }, run: { try self.on($0, $1, at: self.t0) }, now: at(1), rule: { ($1 != nil) == ($0 != nil) }),
            Scenario(name: "refusal", setup: { FilterWorld() }, run: { try self.on($0, $1, at: self.t0, ready: false) }, now: at(1), rule: { session, _ in session == nil }),
            Scenario(name: "end", setup: filterSession, run: { engine, _ in try engine.endFromFocusFilter(now: self.at(200), authorized: .approved) }, now: at(201),
                     rule: { ($1 == nil) == ($0?.phase == .terminal) && $0?.origin == .focusFilter }, thrown: ended),
            Scenario(name: "end during a break", setup: filterBreak, run: { engine, _ in try engine.endFromFocusFilter(now: self.at(200), authorized: .approved) }, now: at(201),
                     rule: { ($1 == nil) == ($0?.phase == .terminal) && $0?.origin == .focusFilter }, thrown: ended),
            Scenario(name: "end after the break end", setup: filterBreak, run: { engine, _ in try engine.endFromFocusFilter(now: self.at(300), authorized: .approved) },
                     now: at(301), rule: exitedAfterReconcile, thrown: ended),
            Scenario(name: "end in an interrupted break start", setup: {
                let world = try filterSession(), engine = self.engine(world), id = world.state.envelope.session!.id
                _ = try engine.requestBreak(id: id, now: self.at(100)); try world.saveCopy(id)
                return world
            }, run: { engine, _ in try engine.endFromFocusFilter(now: self.at(130), authorized: .approved) }, now: at(131), rule: exitedAfterReconcile, thrown: ended),
            Scenario(name: "off with a manual session", setup: {
                let world = FilterWorld(), engine = self.engine(world)
                _ = try self.manual(engine, world, at: self.t0); _ = try self.on(engine, world, at: self.at(1))
                return world
            }, run: { engine, _ in try engine.endFromFocusFilter(now: self.at(200), authorized: .approved) }, now: at(201),
                     rule: { session, _ in session?.phase == .active && session?.origin == .manual }),
            Scenario(name: "activation check", setup: filterSession, run: { engine, world in
                try engine.clearFilterActivation(matching: world.state.envelope.filterActivation!, now: self.at(200))
            // The check ends a session that was open for its marker (2026-11-16 extension design, "Activation check").
            }, now: at(201), rule: { session, marker in (session?.phase == .active && marker != nil) || (session?.phase == .terminal && marker == nil) }),
        ]
        for scenario in scenarios {
            // Exit pass: a new engine starts from each recorded state, reconciles, then gets a repeated on call.
            let world = try scenario.setup()
            world.recording = true; world.snapshots = [world.state]
            try? scenario.run(engine(world), world)
            XCTAssertGreaterThan(world.snapshots.count, 1, scenario.name)
            for (index, snapshot) in world.snapshots.enumerated() {
                let context = "\(scenario.name) exit \(index)"
                let exited = FilterWorld(snapshot), engine = engine(exited)
                _ = try? engine.reconcile(now: scenario.now, authorized: .approved)
                assertGapTable(exited, scenario.rule, context)
                let marker = exited.state.envelope.filterActivation, session = exited.state.envelope.session
                let replay = try on(engine, exited, at: scenario.now)
                if marker != nil { XCTAssertEqual(replay, .repeated, context); XCTAssertEqual(exited.state.envelope.session, session, context) }
                else if session == nil { XCTAssertNotNil(started(replay), context) }
                else {
                    if case .started = replay { XCTFail("a second session: \(context)") }
                    XCTAssertEqual(exited.state.envelope.session?.id, session?.id, context)
                }
            }
            // Throw pass: each throwable effect throws once, then reconcile runs.
            let counting = try scenario.setup(), base = counting.effects
            try? scenario.run(engine(counting), counting)
            for offset in 0..<(counting.effects - base) {
                let thrown = try scenario.setup(), engine = engine(thrown)
                thrown.throwAtEffect = thrown.effects + offset
                try? scenario.run(engine, thrown)
                _ = try? engine.reconcile(now: scenario.now, authorized: .approved)
                assertGapTable(thrown, scenario.thrown ?? scenario.rule, "\(scenario.name) throw \(offset)")
            }
        }
    }

    // MARK: Open sessions (2026-11-16 Focus filter extension design)

    /// The Monitor's `intervalDidEnd`. As on the device (2026-11-18), the system deletes the one-shot interval after a callback at or after its end,
    /// also when the section registered it again inside the callback.
    private func didEnd(_ engine: SessionControl, _ session: ControlSession, at now: Date, world: FilterWorld? = nil) throws {
        // Decided at entry: a registration made inside the callback is deleted with the interval that ended.
        let ended = world.flatMap { $0.state.focus[session.id] }.map { $0 <= now } ?? false
        defer { if ended, let world { world.state.focus[session.id] = nil } }
        try engine.handleCallback(activityName: session.activityName, kind: .didEnd, now: now, authorized: .approved)
    }
    private var boundLength: TimeInterval { (ControlSession.maxLength / 1500).rounded(.down) * 1500 }
    private func openStart(_ engine: SessionControl, _ world: FilterWorld) throws -> ControlSession {
        try XCTUnwrap(started(try on(engine, world, at: t0)))
    }
    private func storedSession(_ world: FilterWorld) throws -> ControlSession { try XCTUnwrap(world.state.envelope.session) }
    private func assertEnded(_ world: FilterWorld, _ reason: EndReason, length: TimeInterval, _ context: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let session = try XCTUnwrap(world.state.envelope.session, context, file: file, line: line)
        XCTAssertEqual(session.phase, .terminal, context, file: file, line: line)
        XCTAssertEqual(session.reason, reason, context, file: file, line: line)
        XCTAssertEqual(session.length, length, accuracy: 0.001, context, file: file, line: line)
        XCTAssertTrue(session.hasValidLength, context, file: file, line: line)
        XCTAssertFalse(world.state.focusShield, context, file: file, line: line)
    }
    func testOnCallStoresActivationAndBaseLength() throws {
        let world = FilterWorld(), engine = engine(world)
        let session = try openStart(engine, world)
        XCTAssertEqual(session.activation, world.state.envelope.filterActivation)
        XCTAssertNotNil(session.activation); XCTAssertEqual(session.baseLength, 1500)
        XCTAssertTrue(world.state.envelope.sessionIsOpen)
    }
    // 2026-11-18 single-interval amendment: one interval to the bound end, and a rollover that only changes the stored session.

    func testOpenSessionRegistersOneIntervalToTheBoundEnd() throws {
        let world = FilterWorld(), engine = engine(world)
        let session = try openStart(engine, world)
        XCTAssertEqual(boundLength, 604_500)
        XCTAssertEqual(world.state.focus[session.id], at(boundLength))
        let registrations = world.log.filter { $0 == "focus.register" }.count
        try engine.reconcile(now: at(1500), authorized: .approved)
        let after = try storedSession(world)
        XCTAssertEqual(after.phase, .active); XCTAssertEqual(after.length, 3000)
        XCTAssertEqual(world.state.focus[session.id], at(boundLength)); XCTAssertTrue(world.state.focusShield)
        XCTAssertEqual(world.log.filter { $0 == "focus.register" }.count, registrations, "a catch-up registers nothing")
    }
    func testLateSectionCatchesUpInOneSection() throws {
        let world = FilterWorld(), engine = engine(world)
        let session = try openStart(engine, world)
        try engine.reconcile(now: at(4000), authorized: .approved)
        XCTAssertEqual(try storedSession(world).length, 4500); XCTAssertEqual(world.state.focus[session.id], at(boundLength))
    }
    func testEverySectionCatchesUpBeforeItsOwnStep() throws {
        // A break past a chunk end is available: `requestBreak` reads the caught-up session (decision 11).
        let world = FilterWorld(), engine = engine(world)
        let session = try openStart(engine, world)
        let waiting = try engine.requestBreak(id: session.id, now: at(2000))
        XCTAssertEqual(waiting.phase, .waiting); XCTAssertEqual(waiting.length, 3000)
    }
    func testABoundEndCallbackEndsTheSessionWithTheBoundLength() throws {
        let world = FilterWorld(), engine = engine(world)
        let session = try openStart(engine, world)
        try didEnd(engine, session, at: at(boundLength), world: world)
        try assertEnded(world, .expired, length: boundLength, "bound end on time")
    }
    func testNothingDueInItsOwnEndEndsTheSession() throws {
        // A focus `didEnd` before anything is due (an earlier build's chunk end, or a missed marker) ends the session (decision 12).
        let early = FilterWorld(), earlyEngine = engine(early)
        let a = try openStart(earlyEngine, early)
        try didEnd(earlyEngine, a, at: at(600), world: early)
        try assertEnded(early, .recoveryInterrupted, length: 1500, "before the base length")
        let past = FilterWorld(), pastEngine = engine(past)
        let b = try openStart(pastEngine, past)
        try didEnd(pastEngine, b, at: at(2000), world: past)
        try assertEnded(past, .expired, length: 2000, "past the base length counts with the open focused time")
    }
    func testAFailedCatchUpSaveInItsOwnEndStillEndsTheSession() throws {
        // Decision 9: no later callback comes, so the section continues in memory and lifts the shield.
        let world = FilterWorld(), engine = engine(world)
        let session = try openStart(engine, world)
        world.throwAtEffect = world.effects
        try? didEnd(engine, session, at: at(boundLength), world: world)
        try assertEnded(world, .expired, length: boundLength, "failed catch-up save in its own end")
    }
    func testACappedWaitingEndEndsWithTheOpenFocusedTime() throws {
        // Bounds: pauses push the waiting end past `startedAt + 192 h`; at the cap the catch-up stops below the bound and decision 12 ends the session.
        let world = FilterWorld(), engine = engine(world)
        let session = try openStart(engine, world)
        var paused = try storedSession(world); paused.pausedSeconds = 30 * 3600; paused.deadlineCredit = 30 * 3600; world.state.envelope.session = paused
        let waiting = try engine.requestBreak(id: session.id, now: at(100))
        let shift = try XCTUnwrap(waiting.waitEndsAt).addingTimeInterval(BreakTiming.standard.staleWaitGrace).timeIntervalSince(at(100))
        let end = try XCTUnwrap(world.state.focus[session.id])
        XCTAssertEqual(end, at(ControlSession.maxIntervalLength))
        try didEnd(engine, session, at: end, world: world)
        // The open focused time at the cap: 192 h minus the 30 h of pauses and the cancelled wait.
        try assertEnded(world, .expired, length: ControlSession.maxIntervalLength - 30 * 3600 - shift, "capped waiting end")
    }
    func testALateCappedCallbackRecordsNoTimeAfterTheCap() throws {
        // 8 h late, the catch-up at the arrival time would pass the bound and end as a timed `.expired` with the bound length (PR #176 review).
        for late: TimeInterval in [60, 8 * 3600] {
            let world = FilterWorld(), engine = engine(world)
            let session = try openStart(engine, world)
            var paused = try storedSession(world); paused.pausedSeconds = 30 * 3600; paused.deadlineCredit = 30 * 3600; world.state.envelope.session = paused
            let waiting = try engine.requestBreak(id: session.id, now: at(100))
            let shift = try XCTUnwrap(waiting.waitEndsAt).addingTimeInterval(BreakTiming.standard.staleWaitGrace).timeIntervalSince(at(100))
            try didEnd(engine, session, at: at(ControlSession.maxIntervalLength + late), world: world)
            try assertEnded(world, .expired, length: ControlSession.maxIntervalLength - 30 * 3600 - shift, "capped end \(late) s late")
        }
    }
    func testAFailedReBlockSaveAtTheCapStillEndsTheSession() throws {
        // A break whose deadline is after the 192 h cap: the cap's `didEnd` re-blocks, the save of `breakOver` fails, and the end still lifts the shield.
        let world = FilterWorld(), engine = engine(world)
        let session = try openStart(engine, world)
        // A session near its bound with 30 h of pauses, so the break deadline falls after the cap.
        var paused = try storedSession(world); paused.pausedSeconds = 30 * 3600; paused.deadlineCredit = 30 * 3600
        paused.expiresAt = t0.addingTimeInterval(400 * 1500); world.state.envelope.session = paused
        let waiting = try engine.requestBreak(id: session.id, now: at(100))
        try engine.startBreak(id: session.id, now: try XCTUnwrap(waiting.waitEndsAt), saveSelection: { try world.saveCopy(session.id) })
        let end = try XCTUnwrap(world.state.focus[session.id])
        XCTAssertEqual(end, at(ControlSession.maxIntervalLength))
        world.throwAtEffect = world.effects
        try? didEnd(engine, session, at: end, world: world)
        XCTAssertFalse(world.state.focusShield)
        XCTAssertEqual(world.state.envelope.session?.phase, .terminal)
    }
    func testStartupRecoveryOfALostBoundEndIsNotCounted() throws {
        let world = FilterWorld(), engine = engine(world)
        let session = try openStart(engine, world)
        world.state.focus[session.id] = nil
        try StartupRecovery(engine: engine).endCurrent(now: at(ControlSession.maxLength + 60))
        XCTAssertEqual(try storedSession(world).reason, .recoveryInterrupted)
    }
    func testAFiftyMinuteBaseRecordsTheBoundLengthOnTimeAndLate() throws {
        // Decision 17 with a base that does not divide one week.
        for (offset, name) in [(0.0, "on time"), (600, "late")] {
            let world = FilterWorld(), engine = engine(world)
            let session = try XCTUnwrap(started(try engine.startFromFocusFilter(now: t0, length: 3000, authorized: { .approved }, selectionReady: true,
                                                                                    apply: { world.apply() }, matches: { world.state.focusShield })))
            XCTAssertEqual(world.state.focus[session.id], at(603_000))
            try didEnd(engine, session, at: at(603_000 + offset), world: world)
            try assertEnded(world, .expired, length: 603_000, name)
        }
        // A bound end that never runs: the system deleted the interval, so the Focus off finds it missing (decision 17).
        let world = FilterWorld(), engine = engine(world)
        let session = try XCTUnwrap(started(try engine.startFromFocusFilter(now: t0, length: 3000, authorized: { .approved }, selectionReady: true,
                                                                                apply: { world.apply() }, matches: { world.state.focusShield })))
        world.state.focus[session.id] = nil
        try engine.endFromFocusFilter(now: at(603_600), authorized: .approved)
        XCTAssertEqual(try storedSession(world).reason, .recoveryInterrupted)
    }
    func testACleanupRegistrationInItsOwnEndEndsTheSession() throws {
        // An interrupted break start leaves a `waiting` session with its copy; inside its own end the cleanup's registration counts as failed.
        let world = FilterWorld(), engine = engine(world)
        let session = try openStart(engine, world)
        _ = try engine.requestBreak(id: session.id, now: at(100)); try world.saveCopy(session.id)
        let registrations = world.log.filter { $0 == "focus.register" }.count
        try didEnd(engine, session, at: at(105), world: world)
        XCTAssertEqual(world.log.filter { $0 == "focus.register" }.count, registrations, "no registration inside its own end")
        let ended = try storedSession(world)
        XCTAssertEqual(ended.phase, .terminal); XCTAssertEqual(ended.reason, .recoveryInterrupted); XCTAssertFalse(world.state.focusShield)
    }
    func testTheActivitySnapshotKeepsTheActivationOnlyWhileOpen() throws {
        let world = FilterWorld(), engine = engine(world)
        _ = try openStart(engine, world)
        XCTAssertNotNil(try engine.activitySnapshot()?.activation)
        world.state.envelope.filterActivation = nil
        XCTAssertNil(try engine.activitySnapshot()?.activation)
        XCTAssertNotNil(world.state.envelope.session?.activation, "the stored session is unchanged")
    }
    func testAStaleWaitCancelledLateKeepsRolling() throws {
        // Decision 10: the app opens the next day; the reconcile cancels the stale wait and catches up again before the timed end.
        let world = FilterWorld(), engine = engine(world)
        let session = try openStart(engine, world)
        _ = try engine.requestBreak(id: session.id, now: at(100))
        try engine.reconcile(now: at(86_400), authorized: .approved)
        let after = try storedSession(world)
        XCTAssertEqual(after.phase, .active); XCTAssertGreaterThan(after.focusEnd, at(86_400)); XCTAssertTrue(after.hasValidLength)
    }
    func testAWaitingEndCallbackRecordsTheBoundLength() throws {
        // Decisions 6 and 12: at the registered `waiting` end the stale-wait cancel's registration is skipped, and the catch-up reaches the bound.
        let world = FilterWorld(), engine = engine(world)
        let session = try openStart(engine, world)
        _ = try engine.requestBreak(id: session.id, now: at(100))
        let end = try XCTUnwrap(world.state.focus[session.id])
        XCTAssertGreaterThan(end, at(boundLength))
        try didEnd(engine, session, at: end, world: world)
        try assertEnded(world, .expired, length: boundLength, "waiting end")
    }
    func testTheRegisteredEndIsCappedAtTheProbedInterval() throws {
        var session = ControlSession(startedAt: t0, length: 1500)
        session.phase = .active; session.origin = .focusFilter; session.baseLength = 1500
        XCTAssertEqual(session.openActiveEnd(timing: .standard), at(boundLength))
        session.pausedSeconds = 30 * 3600; session.deadlineCredit = 30 * 3600
        XCTAssertEqual(session.openActiveEnd(timing: .standard), at(ControlSession.maxIntervalLength))
        // The deadline comes first at every chunk or at none.
        session.deadlineCredit = 0
        XCTAssertEqual(session.openActiveEnd(timing: .standard), session.deadline(timing: .standard))
    }
    func testTheOpenFocusedTimeIsCappedAtTheBoundLength() {
        // Decision 17: with a 50-minute base, an on-time, a late or a lost bound end records 603,000 s.
        var session = ControlSession(startedAt: t0, length: 3000)
        session.baseLength = 3000
        XCTAssertEqual(session.boundLength, 603_000)
        XCTAssertEqual(session.openFocused(at: t0.addingTimeInterval(ControlSession.maxLength + 600)), 603_000)
    }
    func testFocusOffKeepsTheMarkerUntilTheSaveOfEnding() throws {
        // Decision 16: the stale-wait cancel inside the Focus off section saves `active` with the marker still set.
        let world = FilterWorld(), engine = engine(world)
        let session = try openStart(engine, world)
        _ = try engine.requestBreak(id: session.id, now: at(100))
        world.recording = true; world.snapshots = [world.state]
        try engine.endFromFocusFilter(now: at(1000), authorized: .approved)
        for snapshot in world.snapshots where snapshot.envelope.session.map({ SessionControl.isRunning($0.phase) }) == true {
            XCTAssertNotNil(snapshot.envelope.filterActivation, "a running session is never saved with the marker cleared")
        }
        let endingIndex = try XCTUnwrap(world.saved.firstIndex { $0.session?.phase == .ending })
        let cancelled = try XCTUnwrap(world.saved[..<endingIndex].last { $0.session?.phase == .active }, "the stale-wait cancel saved `active` first")
        XCTAssertEqual(cancelled.filterActivation, session.activation)
        XCTAssertNil(world.saved[endingIndex].filterActivation)
        XCTAssertNil(world.state.envelope.filterActivation)
    }
    func testStartupRecoveryOfAnOpenSessionPastAChunkEndCountsTheFocusedTime() throws {
        let world = FilterWorld(), engine = engine(world)
        _ = try openStart(engine, world)
        try StartupRecovery(engine: engine).endCurrent(now: at(2000))
        try assertEnded(world, .expired, length: 2000, "endCurrent")
    }
    func testManualSessionAndClearedActivationDoNotRollOver() throws {
        let manualWorld = FilterWorld(), manualEngine = engine(manualWorld)
        let manualSession = try manual(manualEngine, manualWorld, at: t0)
        try didEnd(manualEngine, manualSession, at: at(1500))
        try assertEnded(manualWorld, .expired, length: 1500, "manual")
        let world = FilterWorld(), engine = engine(world)
        let session = try openStart(engine, world)
        world.state.envelope.filterActivation = nil
        try didEnd(engine, session, at: at(1500))
        try assertEnded(world, .expired, length: 1500, "cleared activation")
    }
    func testDeadlineBeforeTheFocusEndIsNotRolledOver() throws {
        let world = FilterWorld(), engine = engine(world)
        let session = try openStart(engine, world)
        var paused = try storedSession(world); paused.pausedSeconds = 900; world.state.envelope.session = paused
        try didEnd(engine, session, at: at(2100))
        try assertEnded(world, .deadlineMissed, length: 1500, "deadline first")
    }
    func testRolloverStopsAtTheOneWeekBound() throws {
        let world = FilterWorld(), engine = engine(world)
        let session = try openStart(engine, world)
        let length = (ControlSession.maxLength / 1500).rounded(.down) * 1500
        var long = try storedSession(world); long.expiresAt = t0.addingTimeInterval(length); world.state.envelope.session = long
        try didEnd(engine, session, at: t0.addingTimeInterval(length))
        try assertEnded(world, .expired, length: length, "bound")
    }
    func testALateCallbackThatReachesTheBoundKeepsTheCaughtUpLength() throws {
        let world = FilterWorld(), engine = engine(world)
        let session = try openStart(engine, world)
        try didEnd(engine, session, at: t0.addingTimeInterval(ControlSession.maxLength))
        try assertEnded(world, .expired, length: (ControlSession.maxLength / 1500).rounded(.down) * 1500, "late callback at the bound")
    }
    func testACatchUpNeedsNoRegistration() throws {
        let world = FilterWorld(), engine = engine(world)
        let session = try openStart(engine, world)
        world.failRegister = true
        try engine.reconcile(now: at(1600), authorized: .approved)
        XCTAssertEqual(try storedSession(world).phase, .active); XCTAssertEqual(world.state.focus[session.id], at(boundLength))
    }
    func testAThrownCatchUpSaveOutsideItsOwnEndCatchesUpLater() throws {
        let world = FilterWorld(), engine = engine(world)
        _ = try openStart(engine, world)
        world.throwAtEffect = world.effects
        XCTAssertThrowsError(try engine.reconcile(now: at(1500), authorized: .approved))
        XCTAssertEqual(try storedSession(world).length, 1500)
        try engine.reconcile(now: at(3000), authorized: .approved)
        let after = try storedSession(world)
        XCTAssertEqual(after.phase, .active); XCTAssertEqual(after.length, 4500); XCTAssertTrue(world.state.focusShield)
    }
    func testFocusOffBeforeTheBaseLengthIsAnEarlyExit() throws {
        let world = FilterWorld(), engine = engine(world)
        _ = try openStart(engine, world)
        try engine.endFromFocusFilter(now: at(600), authorized: .approved)
        try assertEnded(world, .earlyExit, length: 1500, "before base")
        XCTAssertNil(world.state.envelope.filterActivation)
    }
    func testFocusOffAfterARolloverRecordsTheFocusedTime() throws {
        let world = FilterWorld(), engine = engine(world)
        _ = try openStart(engine, world)
        try engine.reconcile(now: at(1500), authorized: .approved)
        try engine.endFromFocusFilter(now: at(2000), authorized: .approved)
        try assertEnded(world, .expired, length: 2000, "after rollover")
    }
    func testFocusOffAfterALostRolloverRecordsTheUncappedTime() throws {
        let world = FilterWorld(), engine = engine(world)
        _ = try openStart(engine, world)
        try engine.endFromFocusFilter(now: at(2400), authorized: .approved)
        try assertEnded(world, .expired, length: 2400, "lost rollover")
    }
    func testAMissingRegistrationStillEndsAnOpenSessionAsInterrupted() throws {
        // The read-failure cleanup clears the shield and stops monitoring; a later section must not roll that session over or count its time.
        // Every end of an open session converges on `endOpen`, so each caller is covered: a callback, Focus off, the activation check and "집중 종료".
        for path in ["didEnd", "focusOff", "check", "finish"] {
            let world = FilterWorld(), engine = engine(world)
            let session = try openStart(engine, world)
            let marker = try XCTUnwrap(world.state.envelope.filterActivation)
            world.failReads = true
            XCTAssertThrowsError(try engine.reconcile(now: at(100), authorized: .approved))
            world.failReads = false
            XCTAssertFalse(world.state.focusShield)
            switch path {
            case "didEnd": try didEnd(engine, session, at: at(1600))
            case "focusOff": try engine.endFromFocusFilter(now: at(2000), authorized: .approved)
            case "check": try engine.clearFilterActivation(matching: marker, now: at(2000))
            default: try engine.finish(id: session.id, reason: .earlyExit, now: at(2000))
            }
            let ended = try storedSession(world)
            XCTAssertEqual(ended.phase, .terminal, path); XCTAssertEqual(ended.reason, .recoveryInterrupted, path)
            // The cleanup's catch-up runs before the reconcile ends the session; the recorded length is not counted.
            XCTAssertEqual(ended.length, 3000, path)
        }
    }
    func testFocusOffAfterTheDeadlineIsDeadlineMissed() throws {
        let world = FilterWorld(), engine = engine(world)
        _ = try openStart(engine, world)
        var paused = try storedSession(world); paused.pausedSeconds = 900; world.state.envelope.session = paused
        try engine.endFromFocusFilter(now: at(2200), authorized: .approved)
        try assertEnded(world, .deadlineMissed, length: 1500, "deadline")
    }
    func testFocusOffDuringABreakExcludesTheOpenPause() throws {
        let world = FilterWorld(), engine = engine(world)
        let session = try openStart(engine, world)
        try engine.reconcile(now: at(1500), authorized: .approved)
        _ = try engine.requestBreak(id: session.id, now: at(1600))
        try engine.startBreak(id: session.id, now: at(1615), saveSelection: { try world.saveCopy(session.id) })
        try engine.endFromFocusFilter(now: at(1700), authorized: .approved)
        try assertEnded(world, .expired, length: 1600, "on break")
    }
    func testActivationCheckEndsAnOpenSession() throws {
        for (offset, reason, length) in [(600.0, EndReason.earlyExit, 1500.0), (2000, .expired, 2000)] {
            let world = FilterWorld(), engine = engine(world)
            _ = try openStart(engine, world)
            let marker = try XCTUnwrap(world.state.envelope.filterActivation)
            try engine.clearFilterActivation(matching: marker, now: at(offset))
            try assertEnded(world, reason, length: length, "check at \(offset)")
            XCTAssertNil(world.state.envelope.filterActivation)
        }
    }
    func testPersonEndOfAnOpenSessionKeepsTheMarker() throws {
        for (offset, reason, length) in [(600.0, EndReason.earlyExit, 1500.0), (2000, .expired, 2000)] {
            let world = FilterWorld(), engine = engine(world)
            let session = try openStart(engine, world)
            let marker = world.state.envelope.filterActivation
            try engine.finish(id: session.id, reason: .earlyExit, now: at(offset))
            try assertEnded(world, reason, length: length, "finish at \(offset)")
            XCTAssertEqual(world.state.envelope.filterActivation, marker)
        }
    }
    func testARetryOfAnEndingOpenSessionKeepsItsSavedReason() throws {
        // "집중 종료" saves `ending` as `.expired` with the focused time, then the save of `terminal` fails; the app retries with `.earlyExit`.
        let world = FilterWorld(), engine = engine(world)
        let session = try openStart(engine, world)
        // The catch-up is saved first, so the failing effect below is the save of `terminal`.
        try engine.reconcile(now: at(2000), authorized: .approved)
        world.throwAtEffect = world.effects + 1
        XCTAssertThrowsError(try engine.finish(id: session.id, reason: .earlyExit, now: at(2000)))
        XCTAssertEqual(world.state.envelope.session?.phase, .ending); XCTAssertEqual(world.state.envelope.session?.reason, .expired)
        try engine.finish(id: session.id, reason: .earlyExit, now: at(2010))
        try assertEnded(world, .expired, length: 2000, "retry")
        XCTAssertEqual(world.state.envelope.session?.observedAt, at(2000))
    }
    func testFilterStartAcceptsUnknownAccess() throws {
        let denied = FilterWorld(), deniedEngine = engine(denied)
        let world = FilterWorld(), unknownEngine = engine(world)
        XCTAssertNotNil(started(try on(unknownEngine, world, at: t0, access: .unknown)))
        XCTAssertTrue(world.state.focusShield)
        XCTAssertEqual(try on(deniedEngine, denied, at: t0, access: .denied), .refused(.access))
    }

    // MARK: Call order across processes (2026-11-16 Focus filter extension design)

    private func onCall(_ engine: SessionControl, _ world: FilterWorld, at now: Date, calledAt: Date) throws -> FocusFilterStart {
        try engine.startFromFocusFilter(now: now, length: 1500, authorized: { .approved }, selectionReady: true, apply: { world.apply() },
                                        matches: { world.state.focusShield }, calledAt: calledAt)
    }
    func testAStaleOnCallChangesNothingOfItsOwn() throws {
        let world = FilterWorld(), engine = engine(world)
        XCTAssertTrue(try engine.endFromFocusFilter(now: at(20), authorized: .approved, calledAt: at(20)))
        XCTAssertEqual(world.state.envelope.filterCallAt, at(20))
        world.log = []; let saves = world.saved.count
        XCTAssertEqual(try onCall(engine, world, at: at(21), calledAt: at(10)), .stale)
        XCTAssertNil(world.state.envelope.session); XCTAssertNil(world.state.envelope.filterActivation)
        XCTAssertEqual(world.saved.count, saves); assertNoFocusEffects(world, "stale on")
    }
    func testAStaleOffCallLeavesTheSessionRunning() throws {
        let world = FilterWorld(), engine = engine(world)
        _ = try XCTUnwrap(started(try onCall(engine, world, at: at(20), calledAt: at(20))))
        let before = world.state.envelope
        XCTAssertFalse(try engine.endFromFocusFilter(now: at(21), authorized: .approved, calledAt: at(10)))
        XCTAssertEqual(world.state.envelope.session, before.session); XCTAssertEqual(world.state.envelope.filterActivation, before.filterActivation)
        XCTAssertTrue(world.state.focusShield)
    }
    func testEqualArrivalTimesKeepTheLockOrder() throws {
        let world = FilterWorld(), engine = engine(world)
        XCTAssertTrue(try engine.endFromFocusFilter(now: at(20), authorized: .approved, calledAt: at(20)))
        XCTAssertNotNil(started(try onCall(engine, world, at: at(21), calledAt: at(20))))
    }
    func testActivationCheckMakesAnEarlierOnCallStale() throws {
        let world = FilterWorld(), engine = engine(world)
        _ = try XCTUnwrap(started(try onCall(engine, world, at: at(20), calledAt: at(20))))
        let marker = try XCTUnwrap(world.state.envelope.filterActivation)
        try engine.clearFilterActivation(matching: marker, now: at(60))
        try engine.acknowledgeTerminal(id: try XCTUnwrap(world.state.envelope.session?.id))
        XCTAssertEqual(try onCall(engine, world, at: at(61), calledAt: at(30)), .stale)
        XCTAssertNil(world.state.envelope.session)
    }
    func testAMissingCallTimeMakesNoCallStale() throws {
        let world = FilterWorld(), engine = engine(world)
        XCTAssertNotNil(started(try onCall(engine, world, at: at(20), calledAt: at(5))))
        XCTAssertEqual(world.state.envelope.filterCallAt, at(5))
        XCTAssertTrue(try engine.endFromFocusFilter(now: at(30), authorized: .approved))
        XCTAssertEqual(world.state.envelope.session?.reason, .earlyExit)
    }
    func testAnAcceptedRepeatedCallStoresItsTime() throws {
        let world = FilterWorld(), engine = engine(world)
        _ = try XCTUnwrap(started(try onCall(engine, world, at: at(20), calledAt: at(20))))
        XCTAssertEqual(try onCall(engine, world, at: at(40), calledAt: at(40)), .repeated)
        XCTAssertEqual(world.state.envelope.filterCallAt, at(40))
        XCTAssertEqual(try onCall(engine, world, at: at(41), calledAt: at(30)), .stale)
    }
    func testAnInputRefusalIsOrderedAndSetsTheMarker() throws {
        let world = FilterWorld(), engine = engine(world)
        let refuse: (Date, Date) throws -> FocusFilterStart = { now, calledAt in
            try engine.startFromFocusFilter(now: now, length: 1500, authorized: { .approved }, selectionReady: true, apply: { world.apply() },
                                            matches: { world.state.focusShield }, calledAt: calledAt, inputRefusal: .error)
        }
        XCTAssertEqual(try refuse(at(20), at(20)), .refused(.error))
        XCTAssertNotNil(world.state.envelope.filterActivation); XCTAssertNil(world.state.envelope.session); assertNoFocusEffects(world, "input refusal")
        XCTAssertTrue(try engine.endFromFocusFilter(now: at(40), authorized: .approved, calledAt: at(40)))
        XCTAssertEqual(try refuse(at(41), at(30)), .stale, "an older call is stale before its input refusal")
        XCTAssertNil(world.state.envelope.filterActivation)
        let denied = FilterWorld(), deniedEngine = self.engine(denied)
        XCTAssertEqual(try deniedEngine.startFromFocusFilter(now: at(1), length: 1500, authorized: { .denied }, selectionReady: true, apply: {}, matches: { true },
                                                         inputRefusal: .error), .refused(.access), "access is checked first")
    }
    func testTheActivationCheckEndsWithTheSectionTimeAndOrdersWithTheCheckTime() throws {
        let world = FilterWorld(), engine = engine(world)
        _ = try XCTUnwrap(started(try onCall(engine, world, at: at(0), calledAt: at(0))))
        let marker = try XCTUnwrap(world.state.envelope.filterActivation)
        // The check read the Focus before the base length; the section runs after it.
        try engine.clearFilterActivation(matching: marker, now: at(1600), calledAt: at(1490))
        XCTAssertEqual(world.state.envelope.session?.reason, .expired); XCTAssertEqual(world.state.envelope.session?.length, 1600)
        XCTAssertEqual(world.state.envelope.filterCallAt, at(1490))
    }
}
