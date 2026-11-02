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
    func withExclusiveAccess<T>(_ body: (LockedControl) throws -> T) throws -> T { try body(self) }
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
    private func on(_ engine: SessionControl, _ world: FilterWorld, at now: Date, access: Bool = true, ready: Bool = true, matches: Bool = true) throws -> FocusFilterStart {
        try engine.startFromFocusFilter(now: now, length: 1500, authorized: { access }, selectionReady: ready, apply: { world.apply() }, matches: { matches && world.state.focusShield })
    }
    private func manual(_ engine: SessionControl, _ world: FilterWorld, at now: Date) throws -> ControlSession {
        try engine.start(now: now, authorized: { true }, apply: { world.apply() }, matches: { world.state.focusShield })
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
            try engine(reconciled).reconcile(now: now, authorized: true)
            XCTAssertEqual(repeated.log.filter { $0.hasPrefix("save") || $0.hasPrefix("focus") || $0.hasPrefix("break") },
                           reconciled.log.filter { $0.hasPrefix("save") || $0.hasPrefix("focus") || $0.hasPrefix("break") }, "\(now)")
            XCTAssertFalse(repeated.log.isEmpty, "\(now)")
            XCTAssertEqual(repeated.state, reconciled.state, "\(now)")
            XCTAssertEqual(repeated.state.envelope.filterActivation, marker); XCTAssertEqual(repeated.state.envelope.session?.origin, .focusFilter)
        }
    }
    func testRefusalsSetTheMarkerAndStartNothing() throws {
        var cases: [(String, FilterWorld, Bool, Bool, FocusFilterRefusal)] = [
            ("access", FilterWorld(), false, true, .access), ("selection", FilterWorld(), true, false, .selection),
        ]
        for phase in [SessionPhase.preparing, .active, .waiting, .onBreak, .breakOver, .ending] {
            cases.append(("\(phase)", stored(phase, origin: .manual, marker: nil), true, true, .busy))
        }
        cases.append(("terminal", stored(.terminal, origin: .manual, marker: nil), true, true, .history))
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
                    try engine(world).endFromFocusFilter(now: at(110), authorized: true)
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
            try engine(expired).endFromFocusFilter(now: at(1500), authorized: true)
            XCTAssertEqual(expired.state.envelope.session?.reason, .expired, "\(origin)")
            let missed = stored(.onBreak, origin: origin, marker: UUID())
            try engine(missed).endFromFocusFilter(now: at(1500 + 195 + slack), authorized: true)
            XCTAssertEqual(missed.state.envelope.session?.reason, .deadlineMissed, "\(origin)")
            let revoked = stored(.active, origin: origin, marker: UUID())
            try engine(revoked).endFromFocusFilter(now: at(110), authorized: false)
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
        try engine.endFromFocusFilter(now: at(200), authorized: true)
        XCTAssertEqual(world.saved.map { $0.session?.phase }, [.ending, .terminal])
        XCTAssertTrue(world.saved.allSatisfy { $0.filterActivation == nil })
    }
    func testOffCallWithoutAFilterSessionSavesOnlyAStoredMarker() throws {
        let marked = FilterWorld(); marked.state.envelope.filterActivation = UUID()
        try engine(marked).endFromFocusFilter(now: t0, authorized: true)
        XCTAssertEqual(marked.saved.count, 1); XCTAssertNil(marked.saved.first?.filterActivation); XCTAssertNil(marked.state.envelope.session)
        let unmarked = FilterWorld()
        try engine(unmarked).endFromFocusFilter(now: t0, authorized: true)
        XCTAssertTrue(unmarked.saved.isEmpty)
    }
    func testOffCallDuringABreakRemovesBreakArtifactsAndBlocksTheEverydayLayer() throws {
        let world = stored(.onBreak, origin: .focusFilter, marker: UUID())
        world.schedule = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 8 * 60, rangeEnd: 18 * 60, windows: [])
        let id = try XCTUnwrap(world.state.envelope.session?.id)
        try engine(world).endFromFocusFilter(now: at(200), authorized: true)
        XCTAssertEqual(world.state.envelope.session?.reason, .earlyExit)
        XCTAssertTrue(world.state.copies.isEmpty); XCTAssertTrue(world.state.breaks.isEmpty); XCTAssertNil(world.state.focus[id]); XCTAssertFalse(world.state.focusShield)
        let order = ["save:ending:unmarked", "focus.clear", "focus.stop", "copy.remove", "everyday.apply", "save:terminal:unmarked"].map { world.log.firstIndex(of: $0) }
        XCTAssertFalse(order.contains(nil), "\(world.log)")
        XCTAssertEqual(order.compactMap { $0 }, order.compactMap { $0 }.sorted(), "\(world.log)")
        XCTAssertTrue(world.state.everydayShield)
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
        // On, S1 completes by time, the import removes it, a repeated on call.
        let world = FilterWorld(), engine = engine(world)
        let s1 = try XCTUnwrap(started(try on(engine, world, at: t0)))
        XCTAssertEqual(try engine.reconcile(now: at(1500), authorized: true).session?.reason, .expired)
        try engine.acknowledgeTerminal(id: s1.id)
        XCTAssertEqual(try on(engine, world, at: at(1510)), .repeated); XCTAssertNil(world.state.envelope.session)
        // Then off, then on: S2 starts.
        try engine.endFromFocusFilter(now: at(1520), authorized: true)
        let s2 = try XCTUnwrap(started(try on(engine, world, at: at(1530))))
        XCTAssertNotEqual(s2.id, s1.id)

        // On, refused for access, access approved, a repeated on call.
        let refused = FilterWorld(), refusedEngine = self.engine(refused)
        XCTAssertEqual(try on(refusedEngine, refused, at: t0, access: false), .refused(.access))
        XCTAssertEqual(try on(refusedEngine, refused, at: at(10)), .repeated); XCTAssertNil(refused.state.envelope.session)

        // On, S1 starts, the off call is lost, S1 ends by time, the app opens and checks, the next on starts S2.
        for checked in [true, false] {
            let lost = FilterWorld(), lostEngine = self.engine(lost)
            let first = try XCTUnwrap(started(try on(lostEngine, lost, at: t0)))
            try lostEngine.reconcile(now: at(1500), authorized: true); try lostEngine.acknowledgeTerminal(id: first.id)
            if checked, let marker = try lostEngine.snapshot().filterActivation { try lostEngine.clearFilterActivation(matching: marker, now: at(1600)) }
            let next = try on(lostEngine, lost, at: at(1700))
            if checked { XCTAssertNotNil(started(next)) } else { XCTAssertEqual(next, .repeated); XCTAssertNil(lost.state.envelope.session) }
        }

        // The off call of one activation arrives after the on call of the next: it ends S2 and clears the marker.
        let late = FilterWorld(), lateEngine = self.engine(late)
        let a = try XCTUnwrap(started(try on(lateEngine, late, at: t0)))
        try lateEngine.endFromFocusFilter(now: at(10), authorized: true); try lateEngine.acknowledgeTerminal(id: a.id)
        let b = try XCTUnwrap(started(try on(lateEngine, late, at: at(20))))
        try lateEngine.endFromFocusFilter(now: at(30), authorized: true)
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
                if phase == "breakOver" { try breakingEngine.reconcile(now: at(295), authorized: true); offAt = at(300) }
                XCTAssertEqual(breaking.state.envelope.session?.phase.rawValue, phase)
            }
            try breakingEngine.endFromFocusFilter(now: offAt, authorized: true)
            XCTAssertEqual(breaking.state.envelope.session?.reason, phase == "expired" ? .expired : .earlyExit, phase)
            XCTAssertTrue(breaking.state.breaks.isEmpty, phase); XCTAssertTrue(breaking.state.copies.isEmpty, phase); XCTAssertTrue(breaking.state.focus.isEmpty, phase)
        }
    }
    func testFocusOffNeverEndsAManualSessionAcrossSequences() throws {
        // A manual session M runs, on, off.
        let world = FilterWorld(), engine = engine(world)
        let m = try manual(engine, world, at: t0)
        XCTAssertEqual(try on(engine, world, at: at(10)), .refused(.busy)); XCTAssertNotNil(world.state.envelope.filterActivation)
        try engine.endFromFocusFilter(now: at(20), authorized: true)
        XCTAssertEqual(world.state.envelope.session?.id, m.id); XCTAssertEqual(world.state.envelope.session?.phase, .active)
        XCTAssertNil(world.state.envelope.filterActivation)

        // On, S1 starts, "집중 종료", a manual M, a repeated on call, off.
        let other = FilterWorld(), otherEngine = self.engine(other)
        let s1 = try XCTUnwrap(started(try on(otherEngine, other, at: t0)))
        try otherEngine.finish(id: s1.id, reason: .earlyExit, now: at(10)); try otherEngine.acknowledgeTerminal(id: s1.id)
        let m2 = try manual(otherEngine, other, at: at(20))
        XCTAssertEqual(try on(otherEngine, other, at: at(30)), .repeated)
        try otherEngine.endFromFocusFilter(now: at(40), authorized: true)
        XCTAssertEqual(other.state.envelope.session?.id, m2.id); XCTAssertEqual(other.state.envelope.session?.phase, .active)
        XCTAssertEqual(other.state.envelope.session?.origin, .manual); XCTAssertNotNil(other.state.focus[m2.id]); XCTAssertTrue(other.state.focusShield)

        // A manual session in each break phase stays in that phase after an off call.
        for phase in ["waiting", "onBreak", "breakOver"] {
            let breaking = FilterWorld(), breakingEngine = self.engine(breaking)
            let s = try manual(breakingEngine, breaking, at: t0)
            let waiting = try breakingEngine.requestBreak(id: s.id, now: at(100)); var offAt = at(105)
            if phase != "waiting" { try breakingEngine.startBreak(id: s.id, now: waiting.waitEndsAt!, saveSelection: { try breaking.saveCopy(s.id) }); offAt = at(200) }
            if phase == "breakOver" { try breakingEngine.reconcile(now: at(295), authorized: true); offAt = at(300) }
            let before = breaking.state.envelope.session
            try breakingEngine.endFromFocusFilter(now: offAt, authorized: true)
            XCTAssertEqual(breaking.state.envelope.session, before, phase)
        }

        // Focus A starts S1; a switch that sends off then on ends S1 and starts S2.
        let switching = FilterWorld(), switchingEngine = self.engine(switching)
        let a = try XCTUnwrap(started(try on(switchingEngine, switching, at: t0)))
        try switchingEngine.endFromFocusFilter(now: at(10), authorized: true)
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
        try engine.reconcile(now: breakEnd, authorized: true); check("re-block")
        XCTAssertEqual(world.state.envelope.session?.phase, .breakOver)
        try engine.resume(id: s.id, now: breakEnd.addingTimeInterval(5)); check("resume")
        for kind in [CallbackKind.didStart, .willEndWarning, .didEnd] {
            try engine.handleCallback(activityName: s.activityName, kind: kind, now: breakEnd.addingTimeInterval(10), authorized: true); check("callback \(kind)")
        }
        XCTAssertEqual(world.state.envelope.session?.phase, .active)
        try engine.finish(id: s.id, reason: .earlyExit, now: breakEnd.addingTimeInterval(20)); check("finish")
        try engine.acknowledgeTerminal(id: s.id); check("acknowledgeTerminal")
        XCTAssertNil(world.state.envelope.session)
        let schedule = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 8 * 60, rangeEnd: 18 * 60, windows: [])
        try engine.saveEveryday(schedule, now: breakEnd.addingTimeInterval(30), authorized: { true }, containsStoredSelection: { true }, write: { world.schedule = schedule })
        check("saveEveryday")
    }
    func testControlReadFailureInAFilterSectionThrows() throws {
        let sections: [(String, (SessionControl, FilterWorld) throws -> Void)] = [
            ("start", { try self.on($0, $1, at: self.t0) }),
            ("end", { engine, _ in try engine.endFromFocusFilter(now: self.t0, authorized: true) }),
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
        }
        let filterSession: () throws -> FilterWorld = {
            let world = FilterWorld(); _ = try self.on(self.engine(world), world, at: self.t0); return world
        }
        let scenarios = [
            Scenario(name: "start", setup: { FilterWorld() }, run: { try self.on($0, $1, at: self.t0) }, now: at(1), rule: { ($1 != nil) == ($0 != nil) }),
            Scenario(name: "refusal", setup: { FilterWorld() }, run: { try self.on($0, $1, at: self.t0, ready: false) }, now: at(1), rule: { session, _ in session == nil }),
            Scenario(name: "end", setup: filterSession, run: { engine, _ in try engine.endFromFocusFilter(now: self.at(200), authorized: true) }, now: at(201),
                     rule: { ($1 == nil) == ($0?.phase == .terminal) && $0?.origin == .focusFilter }),
            Scenario(name: "end during a break", setup: {
                let world = try filterSession(), engine = self.engine(world), id = world.state.envelope.session!.id
                let waiting = try engine.requestBreak(id: id, now: self.at(100))
                try engine.startBreak(id: id, now: waiting.waitEndsAt!, saveSelection: { try world.saveCopy(id) })
                return world
            }, run: { engine, _ in try engine.endFromFocusFilter(now: self.at(200), authorized: true) }, now: at(201),
                     rule: { ($1 == nil) == ($0?.phase == .terminal) && $0?.origin == .focusFilter }),
            Scenario(name: "off with a manual session", setup: {
                let world = FilterWorld(), engine = self.engine(world)
                _ = try self.manual(engine, world, at: self.t0); _ = try self.on(engine, world, at: self.at(1))
                return world
            }, run: { engine, _ in try engine.endFromFocusFilter(now: self.at(200), authorized: true) }, now: at(201),
                     rule: { session, _ in session?.phase == .active && session?.origin == .manual }),
            Scenario(name: "activation check", setup: filterSession, run: { engine, world in
                try engine.clearFilterActivation(matching: world.state.envelope.filterActivation!, now: self.at(200))
            }, now: at(201), rule: { session, _ in session?.phase == .active }),
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
                _ = try? engine.reconcile(now: scenario.now, authorized: true)
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
                _ = try? engine.reconcile(now: scenario.now, authorized: true)
                assertGapTable(thrown, scenario.rule, "\(scenario.name) throw \(offset)")
            }
        }
    }
}
