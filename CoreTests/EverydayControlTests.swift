import XCTest
@testable import FocusCore

private struct Activity: Hashable { var revision: UUID; var part: EverydayPart }
private struct StoredLayer: Equatable { var schedule: EverydaySchedule; var selection: Set<String> }
/// The whole fake world of both layers. `store` is the `everydayLayer` contents; `nil` is a store without a shield setting.
private struct EverydayState: Equatable {
    var envelope = ControlEnvelope()
    var focus: [UUID: Date] = [:]
    var breaks = Set<String>()
    var copies = Set<UUID>()
    var focusShield = false
    var file: StoredLayer?
    var fileCorrupt = false
    var activities = Set<Activity>()
    var store: Set<String>?
    static func == (a: EverydayState, b: EverydayState) -> Bool {
        a.envelope.session == b.envelope.session && a.focus == b.focus && a.breaks == b.breaks && a.copies == b.copies && a.focusShield == b.focusShield
            && a.file == b.file && a.fileCorrupt == b.fileCorrupt && a.activities == b.activities && a.store == b.store
    }
}
private final class EverydayWorld: ControlStore, LockedControl, MonitoringClient, ShieldClient, BreakSelectionStore {
    var state: EverydayState
    /// Every effect in order, also those that changed nothing.
    var log: [String] = []
    /// While `recording`, the state after each effect that changed it.
    var snapshots: [EverydayState] = []
    var recording = false
    var failReads = false, failWrite = false, storeMismatch = false, hideRegistrations = false
    var failSavePhases: [SessionPhase] = []
    var failEverydayParts = Set<EverydayPart>()
    /// The index of the throwable effect (save, registration, copy or file write) that throws once.
    var throwAtEffect: Int?
    private(set) var effects = 0
    /// Every everyday stop, by name. The protocol takes one name per call, so no stop can pass an empty list.
    private(set) var everydayStops: [Activity] = []
    init(_ state: EverydayState = EverydayState()) { self.state = state }
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
        if let phase = envelope.session?.phase, let index = failSavePhases.firstIndex(of: phase) { failSavePhases.remove(at: index); throw FixtureFailure.injected }
        state.envelope = envelope; record("save:\(envelope.session.map { "\($0.phase)" } ?? "none")")
    }
    var registeredSessionIDs: [UUID] { Array(state.focus.keys) }
    func register(id: UUID, start: Date, end: Date) throws { try mayThrow(); state.focus[id] = end; record("focus.register") }
    func isRegistered(id: UUID) -> Bool { state.focus[id] != nil }
    func stop(id: UUID) { state.focus[id] = nil; state.breaks = state.breaks.filter { !$0.hasPrefix(id.uuidString) }; record("focus.stop") }
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws {
        try mayThrow(); state.breaks.insert("\(id.uuidString).\(index)"); record("break.register")
    }
    func isBreakRegistered(id: UUID, index: Int) -> Bool { state.breaks.contains("\(id.uuidString).\(index)") }
    var registeredBreaks: [(id: UUID, index: Int)] {
        state.breaks.map { key in let parts = key.split(separator: "."); return (UUID(uuidString: String(parts[0]))!, Int(parts[1])!) }
    }
    func stopBreak(id: UUID, index: Int) { state.breaks.remove("\(id.uuidString).\(index)"); record("break.stop") }
    func registerEveryday(revision: UUID, part: EverydayPart, start: Int, end: Int) throws {
        try mayThrow()
        if failEverydayParts.contains(part) { throw FixtureFailure.injected }
        let activity = Activity(revision: revision, part: part)
        if !hideRegistrations { state.activities.insert(activity) }
        record("everyday.register")
    }
    var registeredEveryday: [(revision: UUID, part: EverydayPart)] { state.activities.map { (revision: $0.revision, part: $0.part) } }
    func stopEveryday(revision: UUID, part: EverydayPart) {
        let activity = Activity(revision: revision, part: part)
        everydayStops.append(activity); state.activities.remove(activity); record("everyday.stop")
    }
    func clear() { state.focusShield = false; record("focus.clear") }
    func restoreShield(id: UUID) -> Bool {
        guard state.copies.contains(id) else { return false }
        state.focusShield = true; record("focus.restore"); return true
    }
    func exists(id: UUID) -> Bool { state.copies.contains(id) }
    func remove(id: UUID) { state.copies.remove(id); record("copy.remove") }
    func removeAll(except id: UUID?) { state.copies = state.copies.filter { $0 == id } }
    func saveCopy(_ id: UUID) throws { try mayThrow(); state.copies.insert(id); record("copy.save") }
    // The everyday file and store, reached through `LayerView`.
    func readFile() throws -> EverydaySchedule? {
        log.append("file.read")
        if state.fileCorrupt { throw FixtureFailure.injected }
        return state.file?.schedule
    }
    func writeFile(_ layer: StoredLayer) throws {
        try mayThrow()
        if failWrite { throw FixtureFailure.injected }
        state.file = layer; state.fileCorrupt = false; record("file.write")
    }
    func applyStore() -> Bool {
        guard let file = state.file else { return false }
        state.store = storeMismatch ? Set(file.selection.sorted().prefix(1)) : file.selection
        record("everyday.apply")
        return state.store == file.selection
    }
    func clearStore() { state.store = nil; record("everyday.clear") }
}
private final class LayerView: EverydayLayerStore {
    let world: EverydayWorld
    init(_ world: EverydayWorld) { self.world = world }
    func load() throws -> EverydaySchedule? { try world.readFile() }
    func storeMatches() -> Bool { world.state.store != nil && world.state.store == world.state.file?.selection }
    func applyStored() -> Bool { world.applyStore() }
    var hasShield: Bool { world.state.store != nil }
    func clearShield() { world.clearStore() }
}

final class EverydayControlTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!; return calendar
    }()
    /// 10:00 in Seoul: inside the default range and before lunch.
    private var t0: Date { clock(10, 0) }
    private func clock(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: hour, minute: minute, second: second))!
    }
    private func at(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }
    private let s1: Set<String> = ["app1", "site1"]
    private var s2: Set<String> { s1.union(["app2"]) }
    private let lunch = EverydayWindow(kind: .lunch, start: 12 * 60, end: 13 * 60)
    private func layer(_ start: Int = 8 * 60, _ end: Int = 18 * 60, windows: [EverydayWindow]? = nil, enabled: Bool = true) -> EverydaySchedule {
        EverydaySchedule(revision: UUID(), enabled: enabled, rangeStart: start, rangeEnd: end, windows: windows ?? [lunch])
    }
    private func activities(_ schedule: EverydaySchedule) -> Set<Activity> {
        Set(SessionControl.everydayActivities(schedule).map { Activity(revision: schedule.revision, part: $0.part) })
    }
    private func engine(_ world: EverydayWorld) -> SessionControl {
        SessionControl(store: world, monitoring: world, shield: world, breakSelection: world, everyday: LayerView(world), calendar: calendar)
    }
    private func save(_ engine: SessionControl, _ world: EverydayWorld, _ schedule: EverydaySchedule, _ selection: Set<String>, at now: Date, access: Bool = true) throws {
        try engine.saveEveryday(schedule, now: now, authorized: { access }, containsStoredSelection: { selection.isSuperset(of: world.state.file?.selection ?? []) },
                                write: { try world.writeFile(StoredLayer(schedule: $0, selection: selection)) })
    }
    /// The default layer with lunch and `s1`, saved at 07:00 and applied at 10:00.
    private func onLayer(_ world: EverydayWorld) throws -> (SessionControl, EverydaySchedule) {
        let engine = engine(world), schedule = layer()
        try save(engine, world, schedule, s1, at: clock(7, 0))
        try engine.reconcile(now: t0, authorized: true)
        XCTAssertEqual(world.state.store, s1); XCTAssertEqual(world.state.activities, activities(schedule))
        return (engine, schedule)
    }
    private func started(_ engine: SessionControl, _ world: EverydayWorld) throws -> UUID {
        try engine.start(now: t0, authorized: { true }, apply: { world.state.focusShield = true }, matches: { world.state.focusShield }).id
    }
    /// Break 1 requested at +100, started at +115, until +295.
    private func takeBreak(_ engine: SessionControl, _ world: EverydayWorld, _ id: UUID) throws {
        let waiting = try engine.requestBreak(id: id, now: at(100))
        try engine.startBreak(id: id, now: waiting.waitEndsAt!, saveSelection: { try world.saveCopy(id) })
    }
    private func phase(_ world: EverydayWorld) -> SessionPhase? { world.state.envelope.session?.phase }
    private func name(_ revision: UUID, _ part: String) -> String { "everyday.\(revision.uuidString).\(part)" }

    // MARK: Convergence

    func testConvergenceAppliesInsideTheRangeAndClearsInAWindowAndAfterTheRange() throws {
        let world = EverydayWorld(), engine = engine(world)
        try save(engine, world, layer(), s1, at: clock(7, 0))
        XCTAssertNil(world.state.store)
        for (time, store) in [(t0, s1), (clock(12, 30), nil), (clock(13, 0), s1), (clock(18, 0), nil), (clock(7, 59, 59), nil)] as [(Date, Set<String>?)] {
            try engine.reconcile(now: time, authorized: true)
            XCTAssertEqual(world.state.store, store, "\(time)")
        }
    }
    func testConvergenceRegistersTheStoredRevisionAndThenStopsOthers() throws {
        let earlier = layer(), stored = layer()
        let world = EverydayWorld(EverydayState(file: StoredLayer(schedule: stored, selection: s1), activities: activities(earlier)))
        try engine(world).reconcile(now: t0, authorized: true)
        XCTAssertEqual(world.state.activities, activities(stored))
        let lastRegister = try XCTUnwrap(world.log.lastIndex(of: "everyday.register")), firstStop = try XCTUnwrap(world.log.firstIndex(of: "everyday.stop"))
        XCTAssertLessThan(lastRegister, firstStop)
        XCTAssertEqual(world.state.store, s1)
    }
    func testEarlierRevisionStaysWhileTheStoredRevisionIsIncomplete() throws {
        let earlier = layer(), stored = layer()
        let world = EverydayWorld(EverydayState(file: StoredLayer(schedule: stored, selection: s1), activities: activities(earlier)))
        world.failEverydayParts = [.window(1)]
        let engine = engine(world)
        try engine.reconcile(now: t0, authorized: true)
        XCTAssertTrue(activities(earlier).isSubset(of: world.state.activities))
        XCTAssertTrue(world.state.activities.contains(Activity(revision: stored.revision, part: .range)))
        XCTAssertEqual(try engine.everydayStatus(now: t0, authorized: true).issue, .registrationFailed)
        XCTAssertEqual(world.state.store, s1, "the store follows the stored file")
        world.failEverydayParts = []
        try engine.reconcile(now: t0, authorized: true)
        XCTAssertEqual(world.state.activities, activities(stored))
        XCTAssertNil(try engine.everydayStatus(now: t0, authorized: true).issue)
    }
    func testStatusReportsAShieldLeftOnWhenTheLayerDoesNotBlock() throws {
        // A window-start or range-end callback that came late or never came leaves the store applied.
        for time in [clock(12, 30), clock(18, 0)] {
            let world = EverydayWorld()
            let (engine, _) = try onLayer(world)
            let status = try engine.everydayStatus(now: time, authorized: true)
            XCTAssertFalse(status.blocksNow, "\(time)"); XCTAssertEqual(status.issue, .notCleared, "\(time)")
            XCTAssertEqual(world.state.store, s1, "the status section changes nothing")
            try engine.reconcile(now: time, authorized: true)
            XCTAssertNil(world.state.store)
            XCTAssertNil(try engine.everydayStatus(now: time, authorized: true).issue, "\(time)")
        }
    }
    func testDidStartSectionNeverRegisters() throws {
        let stored = layer()
        let world = EverydayWorld(EverydayState(file: StoredLayer(schedule: stored, selection: s1)))
        world.hideRegistrations = true
        let engine = engine(world)
        try engine.handleCallback(activityName: name(stored.revision, "range"), kind: .didStart, now: t0, authorized: true)
        XCTAssertFalse(world.log.contains("everyday.register"))
        XCTAssertEqual(world.state.store, s1, "the store still converges")
        try engine.handleCallback(activityName: name(stored.revision, "range"), kind: .didStart, now: t0, authorized: true)
        XCTAssertFalse(world.log.contains("everyday.register"))
        try engine.handleCallback(activityName: name(stored.revision, "window.1"), kind: .didEnd, now: t0, authorized: true)
        XCTAssertEqual(world.log.filter { $0 == "everyday.register" }.count, 2)
        world.hideRegistrations = false; world.log = []
        try engine.reconcile(now: t0, authorized: true)
        XCTAssertEqual(world.log.filter { $0 == "everyday.register" }.count, 2)
        XCTAssertEqual(world.state.activities, activities(stored))
    }
    func testStopsAlwaysNameTheirActivities() throws {
        // A stop of an earlier revision during a break leaves the focus and break activities alone: each stop names one everyday activity.
        let world = EverydayWorld()
        let (engine, earlier) = try onLayer(world)
        let id = try started(engine, world)
        try takeBreak(engine, world, id)
        let stored = layer()
        world.state.file = StoredLayer(schedule: stored, selection: s1)
        try engine.handleCallback(activityName: name(earlier.revision, "range"), kind: .didEnd, now: at(200), authorized: true)
        XCTAssertEqual(Set(world.everydayStops), activities(earlier))
        XCTAssertNotNil(world.state.focus[id]); XCTAssertTrue(world.isBreakRegistered(id: id, index: 1))
        XCTAssertEqual(world.state.activities, activities(stored))
        // Without access, every everyday activity stops by name, and the session ends by the M2 rule only through its own callback.
        world.state.activities.insert(Activity(revision: UUID(), part: .window(3)))
        try engine.handleCallback(activityName: name(stored.revision, "range"), kind: .didEnd, now: at(201), authorized: false)
        XCTAssertTrue(world.state.activities.isEmpty)
        XCTAssertNotNil(world.state.focus[id]); XCTAssertTrue(world.isBreakRegistered(id: id, index: 1)); XCTAssertEqual(phase(world), .onBreak)
        XCTAssertTrue(world.everydayStops.allSatisfy { $0.revision != id })
    }
    func testLateCallbackOfEarlierRevisionFollowsTheNewFile() throws {
        let world = EverydayWorld()
        let (engine, earlier) = try onLayer(world)
        // Outside the range, a turn-off is accepted.
        try save(engine, world, layer(enabled: false), s1, at: clock(18, 30))
        XCTAssertTrue(world.state.activities.isEmpty); XCTAssertNil(world.state.store)
        for kind in [CallbackKind.didStart, .didEnd, .willEndWarning] {
            try engine.handleCallback(activityName: name(earlier.revision, "window.1"), kind: kind, now: clock(18, 31), authorized: true)
            try engine.handleCallback(activityName: name(earlier.revision, "range"), kind: kind, now: t0.addingTimeInterval(86400), authorized: true)
        }
        XCTAssertTrue(world.state.activities.isEmpty); XCTAssertNil(world.state.store)
        // A new revision with another range: the earlier callback applies only what the new file allows.
        let next = layer(14 * 60, 16 * 60, windows: [])
        try save(engine, world, next, s2, at: clock(18, 40))
        try engine.handleCallback(activityName: name(earlier.revision, "range"), kind: .didStart, now: t0.addingTimeInterval(86400), authorized: true)
        XCTAssertNil(world.state.store); XCTAssertEqual(world.state.activities, activities(next))
        try engine.handleCallback(activityName: name(earlier.revision, "window.1"), kind: .didEnd, now: clock(15, 0).addingTimeInterval(86400), authorized: true)
        XCTAssertEqual(world.state.store, s2); XCTAssertEqual(world.state.activities, activities(next))
    }
    func testUnreadableFileClearsTheStoreAndKeepsActivities() throws {
        let world = EverydayWorld()
        let (engine, schedule) = try onLayer(world)
        world.state.fileCorrupt = true
        try engine.reconcile(now: t0, authorized: true)
        XCTAssertNil(world.state.store); XCTAssertEqual(world.state.activities, activities(schedule))
        let status = try engine.everydayStatus(now: t0, authorized: true)
        XCTAssertEqual(status.issue, .unreadable); XCTAssertNil(status.schedule); XCTAssertFalse(status.blocksNow)
    }
    func testUnauthorizedSectionStopsEveryEverydayActivityAndClearsTheStore() throws {
        let world = EverydayWorld()
        let (engine, _) = try onLayer(world)
        world.state.activities.insert(Activity(revision: UUID(), part: .range))
        try engine.reconcile(now: t0, authorized: false)
        XCTAssertTrue(world.state.activities.isEmpty); XCTAssertNil(world.state.store)
        XCTAssertNotNil(world.state.file, "the file stays")
    }
    func testAccessBackRegistersAndApplies() throws {
        let world = EverydayWorld()
        let (engine, schedule) = try onLayer(world)
        try engine.reconcile(now: t0, authorized: false)
        XCTAssertTrue(world.state.activities.isEmpty)
        try engine.reconcile(now: t0, authorized: true)
        XCTAssertEqual(world.state.activities, activities(schedule)); XCTAssertEqual(world.state.store, s1)
    }

    // MARK: Save

    func testSaveRefusedDuringASessionWithBusy() throws {
        for phase in [SessionPhase.preparing, .active, .waiting, .onBreak, .breakOver, .ending] {
            let world = EverydayWorld(), engine = engine(world)
            var session = ControlSession(startedAt: t0); session.phase = phase
            if phase == .ending { session.reason = .earlyExit; session.observedAt = t0 }
            world.state.envelope.session = session
            XCTAssertThrowsError(try save(engine, world, layer(), s1, at: clock(7, 0))) { XCTAssertEqual($0 as? ControlIssue, .busy, "\(phase)") }
            XCTAssertNil(world.state.file, "\(phase)"); XCTAssertTrue(world.state.activities.isEmpty, "\(phase)")
        }
        let world = EverydayWorld(), engine = engine(world)
        var terminal = ControlSession(startedAt: t0); terminal.phase = .terminal; terminal.reason = .earlyExit; terminal.observedAt = t0
        world.state.envelope.session = terminal
        try save(engine, world, layer(), s1, at: clock(7, 0))
        XCTAssertNotNil(world.state.file)
    }
    func testSaveRefusedWithoutAccessRegistersAndWritesNothing() throws {
        let edits: [(String, (EverydaySchedule) -> EverydaySchedule)] = [
            ("turn-on", { _ in self.layer() }), ("edit", { _ in self.layer(windows: []) }), ("turn-off", { _ in self.layer(enabled: false) }),
        ]
        for (name, edit) in edits {
            let world = EverydayWorld()
            let (engine, stored) = try onLayer(world)
            if name == "turn-on" { world.state.file?.schedule.enabled = false }
            let before = world.state.file
            world.log = []
            XCTAssertThrowsError(try save(engine, world, edit(stored), s2, at: t0, access: false)) { XCTAssertEqual($0 as? ControlIssue, .unauthorized, name) }
            XCTAssertFalse(world.log.contains("everyday.register"), name); XCTAssertFalse(world.log.contains("file.write"), name)
            XCTAssertEqual(world.state.file, before, name)
            XCTAssertTrue(world.state.activities.isEmpty, name); XCTAssertNil(world.state.store, name)
        }
    }
    func testStatusWithoutAccessDoesNotBlock() throws {
        let world = EverydayWorld()
        let (engine, schedule) = try onLayer(world)
        let status = try engine.everydayStatus(now: t0, authorized: false)
        XCTAssertFalse(status.blocksNow); XCTAssertNil(status.nextChange); XCTAssertEqual(status.schedule, schedule)
        XCTAssertNil(status.issue, "a shield without access is not in force, so it is not reported as not cleared")
        let approved = try engine.everydayStatus(now: t0, authorized: true)
        XCTAssertTrue(approved.blocksNow); XCTAssertEqual(approved.nextChange, clock(12, 0)); XCTAssertNil(approved.issue)
    }
    func testSaveInsideTheRangeRefusesLooserEdits() throws {
        let looser: [(String, EverydaySchedule, Set<String>, Date, EverydayLockReason)] = [
            ("turn off", layer(enabled: false), s1, t0, .turnsOff),
            ("lengthen lunch", layer(windows: [EverydayWindow(kind: .lunch, start: 12 * 60, end: 13 * 60 + 30)]), s1, t0, .unblocksTime),
            ("add a window at 15:00", layer(windows: [lunch, EverydayWindow(kind: .custom, start: 15 * 60, end: 15 * 60 + 30)]), s1, t0, .unblocksTime),
            ("move the range end earlier", layer(8 * 60, 17 * 60), s1, t0, .rangeEndsEarlier),
            ("lengthen lunch during lunch", layer(windows: [EverydayWindow(kind: .lunch, start: 12 * 60, end: 13 * 60 + 30)]), s1, clock(12, 30), .unblocksTime),
            ("remove an app", layer(), ["site1"], t0, .removesSelection),
            ("move the range start past now during lunch", layer(13 * 60, 18 * 60, windows: []), s1, clock(12, 30), .rangeExcludesNow),
        ]
        for (name, schedule, selection, now, reason) in looser {
            let world = EverydayWorld()
            let (engine, stored) = try onLayer(world)
            world.log = []
            XCTAssertThrowsError(try save(engine, world, schedule, selection, at: now)) { XCTAssertEqual($0 as? EverydayLockReason, reason, name) }
            XCTAssertFalse(world.log.contains("everyday.register"), name); XCTAssertFalse(world.log.contains("file.write"), name)
            XCTAssertEqual(world.state.file?.schedule, stored, name)
        }
        let world = EverydayWorld()
        let (engine, _) = try onLayer(world)
        try save(engine, world, layer(7 * 60, 19 * 60, windows: []), s2, at: t0)
        XCTAssertEqual(world.state.store, s2, "an accepted edit applies at once")
    }
    func testSaveRefusesARangeEndPulledBackToATrailingWindow() throws {
        let world = EverydayWorld(), engine = engine(world)
        let late = EverydayWindow(kind: .custom, start: 17 * 60, end: 18 * 60)
        try save(engine, world, layer(windows: [lunch, late]), s1, at: clock(7, 0))
        let stored = world.state.file?.schedule
        // The blocked times are the same, but the lock would end at 17:00 instead of the stored 18:00.
        XCTAssertThrowsError(try save(engine, world, layer(8 * 60, 17 * 60), s1, at: t0)) { XCTAssertEqual($0 as? EverydayLockReason, .rangeEndsEarlier) }
        XCTAssertEqual(world.state.file?.schedule, stored)
    }
    func testAcceptedEditsKeepTheLockUntilTheStoredRangeEnd() throws {
        let world = EverydayWorld()
        let (engine, _) = try onLayer(world)
        let short = EverydayWindow(kind: .lunch, start: 12 * 60, end: 12 * 60 + 45)
        // Each edit is tried in turn; after each one, accepted or not, the layer must not turn off or lose an app before the stored range end.
        let attempts: [(String, EverydaySchedule, Date, Bool)] = [
            ("shorten lunch during lunch", layer(windows: [short]), clock(12, 30), true),
            ("move the range start past now, same blocked times", layer(12 * 60 + 45, 18 * 60, windows: []), clock(12, 30), false),
            ("move the range end later", layer(8 * 60, 19 * 60, windows: [short]), clock(12, 31), true),
            ("move the range start to now", layer(12 * 60 + 30, 19 * 60, windows: []), clock(12, 32), true),
            ("move the range start past now", layer(12 * 60 + 35, 19 * 60, windows: []), clock(12, 33), false),
        ]
        for (name, schedule, now, accepted) in attempts {
            let before = world.state.file?.schedule
            XCTAssertEqual((try? save(engine, world, schedule, s1, at: now)) != nil, accepted, name)
            XCTAssertEqual(world.state.file?.schedule, accepted ? schedule : before, name)
            XCTAssertThrowsError(try save(engine, world, layer(enabled: false), s1, at: now)) { XCTAssertEqual($0 as? EverydayLockReason, .turnsOff, "turn off after: \(name)") }
        }
        let stored = world.state.file?.schedule
        for now in [clock(12, 34), clock(17, 59, 59), clock(18, 0), clock(18, 59, 59)] {
            XCTAssertThrowsError(try save(engine, world, layer(enabled: false), s1, at: now)) { XCTAssertEqual($0 as? EverydayLockReason, .turnsOff, "\(now)") }
            XCTAssertThrowsError(try save(engine, world, layer(windows: []), [], at: now)) { XCTAssertNotNil($0 as? EverydayLockReason, "\(now)") }
            XCTAssertEqual(world.state.file?.schedule, stored, "\(now)")
        }
        try save(engine, world, layer(enabled: false), s1, at: clock(19, 0))
        XCTAssertEqual(world.state.file?.schedule.enabled, false, "editing opens again at the range end of the last accepted edit")
    }
    func testSaveOrderRegistersBeforeWriteAndStopsAfter() throws {
        let world = EverydayWorld()
        let (engine, _) = try onLayer(world)
        world.log = []
        let next = layer(windows: [])
        try save(engine, world, next, s2, at: t0)
        let write = try XCTUnwrap(world.log.firstIndex(of: "file.write"))
        XCTAssertLessThan(try XCTUnwrap(world.log.firstIndex(of: "everyday.register")), write)
        XCTAssertGreaterThan(try XCTUnwrap(world.log.firstIndex(of: "everyday.stop")), write)
        XCTAssertGreaterThan(try XCTUnwrap(world.log.firstIndex(of: "everyday.apply")), write)
        XCTAssertEqual(world.state.activities, activities(next)); XCTAssertEqual(world.state.store, s2)
    }
    func testSaveRegistrationOrWriteFailureStopsNewActivitiesAndKeepsTheFile() throws {
        for failure in ["registration", "write"] {
            let world = EverydayWorld()
            let (engine, stored) = try onLayer(world)
            let next = layer(7 * 60, 18 * 60)
            if failure == "registration" { world.failEverydayParts = [.window(1)] } else { world.failWrite = true }
            XCTAssertThrowsError(try save(engine, world, next, s2, at: t0), failure)
            XCTAssertEqual(world.state.file?.schedule, stored, failure)
            XCTAssertEqual(world.state.activities, activities(stored), failure)
            XCTAssertEqual(world.state.store, s1, failure)
        }
    }
    func testSaveTreatsAnUnreadableStoredFileAsNoLayer() throws {
        let world = EverydayWorld()
        let (engine, _) = try onLayer(world)
        world.state.fileCorrupt = true
        let off = layer(enabled: false)
        try save(engine, world, off, [], at: t0)
        XCTAssertEqual(world.state.file?.schedule, off); XCTAssertTrue(world.state.activities.isEmpty); XCTAssertNil(world.state.store)
    }

    // MARK: Focus transitions

    func testBreakStartLiftsTheEverydayLayerAndRollbackKeepsIt() throws {
        let world = EverydayWorld()
        let (engine, _) = try onLayer(world)
        let id = try started(engine, world)
        try takeBreak(engine, world, id)
        XCTAssertEqual(phase(world), .onBreak); XCTAssertNil(world.state.store); XCTAssertFalse(world.state.focusShield)
        let rollback = EverydayWorld()
        let (rollbackEngine, _) = try onLayer(rollback)
        let other = try started(rollbackEngine, rollback)
        _ = try rollbackEngine.requestBreak(id: other, now: at(100))
        rollback.failSavePhases = [.onBreak]
        XCTAssertThrowsError(try rollbackEngine.startBreak(id: other, now: at(115), saveSelection: { try rollback.saveCopy(other) }))
        XCTAssertEqual(phase(rollback), .active); XCTAssertEqual(rollback.state.store, s1); XCTAssertTrue(rollback.state.focusShield)
    }
    func testStatusDuringABreakNamesTheBreakEndAsTheNextChange() throws {
        let world = EverydayWorld()
        let (engine, _) = try onLayer(world)
        let id = try started(engine, world)
        try takeBreak(engine, world, id)
        let status = try engine.everydayStatus(now: at(200), authorized: true)
        XCTAssertFalse(status.blocksNow)
        XCTAssertEqual(status.nextChange, at(295))
        XCTAssertEqual(status.nextChange, world.state.envelope.session?.breakEndsAt)
    }
    func testStatusDuringABreakThatEndsInAWindowNamesTheWindowEnd() throws {
        let world = EverydayWorld()
        let (engine, _) = try onLayer(world)
        // Started at 11:57; break 1 runs from 11:58:55 to 12:01:55, inside lunch.
        let start = clock(11, 57)
        let id = try engine.start(now: start, authorized: { true }, apply: { world.state.focusShield = true }, matches: { world.state.focusShield }).id
        let waiting = try engine.requestBreak(id: id, now: start.addingTimeInterval(100))
        try engine.startBreak(id: id, now: waiting.waitEndsAt!, saveSelection: { try world.saveCopy(id) })
        let breakEndsAt = try XCTUnwrap(world.state.envelope.session?.breakEndsAt)
        XCTAssertGreaterThan(breakEndsAt, clock(12, 0)); XCTAssertLessThan(breakEndsAt, clock(13, 0))
        for now in [clock(11, 59), clock(12, 0, 30)] {
            let status = try engine.everydayStatus(now: now, authorized: true)
            XCTAssertFalse(status.blocksNow, "\(now)")
            XCTAssertEqual(status.nextChange, clock(13, 0), "\(now)")
        }
    }
    func testReBlockAppliesBothLayersBeforeTheSaveOfBreakOver() throws {
        let world = EverydayWorld()
        let (engine, _) = try onLayer(world)
        let id = try started(engine, world)
        try takeBreak(engine, world, id)
        world.log = []
        try engine.reconcile(now: at(295), authorized: true)
        let save = try XCTUnwrap(world.log.firstIndex(of: "save:breakOver"))
        XCTAssertLessThan(try XCTUnwrap(world.log.firstIndex(of: "focus.restore")), save)
        XCTAssertLessThan(try XCTUnwrap(world.log.firstIndex(of: "everyday.apply")), save)
        XCTAssertEqual(world.state.store, s1); XCTAssertTrue(world.state.focusShield)
    }
    func testEarlyResumeRestoresBothLayersBeforeFocusResumes() throws {
        let world = EverydayWorld(); let (engine, _) = try onLayer(world)
        let id = try started(engine, world)
        try takeBreak(engine, world, id)
        world.log = []
        try engine.resume(id: id, now: at(150))
        XCTAssertEqual(phase(world), .active)
        XCTAssertEqual(world.state.store, s1); XCTAssertTrue(world.state.focusShield)
        let save = try XCTUnwrap(world.log.firstIndex(of: "save:active"))
        XCTAssertLessThan(try XCTUnwrap(world.log.firstIndex(of: "focus.restore")), save)
        XCTAssertLessThan(try XCTUnwrap(world.log.firstIndex(of: "everyday.apply")), save)
        XCTAssertEqual(world.state.envelope.session?.deadlineCredit, 50)
    }
    func testEarlyResumeEverydayRestoreFailureKeepsFocusPausedUntilRetry() throws {
        let world = EverydayWorld(); let (engine, _) = try onLayer(world)
        let id = try started(engine, world)
        try takeBreak(engine, world, id)
        world.storeMismatch = true
        XCTAssertThrowsError(try engine.resume(id: id, now: at(150)))
        XCTAssertEqual(phase(world), .onBreak)
        XCTAssertTrue(world.state.focusShield)
        world.storeMismatch = false
        try engine.resume(id: id, now: at(155))
        XCTAssertEqual(phase(world), .active)
        XCTAssertEqual(world.state.store, s1)
        XCTAssertEqual(world.state.envelope.session?.deadlineCredit, 55)
    }
    func testEverydayCallbackAfterBreakEndsAtBlocksAndReBlocksTheFocusLayer() throws {
        let world = EverydayWorld()
        let (engine, schedule) = try onLayer(world)
        let id = try started(engine, world)
        try takeBreak(engine, world, id)
        try engine.handleCallback(activityName: name(schedule.revision, "window.1"), kind: .didEnd, now: at(305), authorized: true)
        XCTAssertEqual(world.state.store, s1); XCTAssertEqual(phase(world), .breakOver); XCTAssertTrue(world.state.focusShield)
    }
    func testEverydayCallbackNeverChangesTheFocusPhaseOutsideALateBreak() throws {
        let setups: [(String, TimeInterval, (SessionControl, EverydayWorld, UUID) throws -> Void)] = [
            ("active", 50, { _, _, _ in }),
            ("waiting", 105, { engine, _, id in _ = try engine.requestBreak(id: id, now: self.at(100)) }),
            ("onBreak before breakEndsAt", 200, { engine, world, id in try self.takeBreak(engine, world, id) }),
            ("breakOver", 300, { engine, world, id in try self.takeBreak(engine, world, id); try engine.reconcile(now: self.at(295), authorized: true) }),
        ]
        for (phaseName, offset, setup) in setups {
            for storedRevision in [true, false] {
                for kind in [CallbackKind.didStart, .didEnd, .willEndWarning] {
                    for approved in [true, false] {
                        let world = EverydayWorld()
                        let (engine, schedule) = try onLayer(world)
                        let id = try started(engine, world)
                        try setup(engine, world, id)
                        let before = world.state.envelope.session
                        if !approved { world.state.focus[id] = nil }
                        world.log = []
                        let callback = name(storedRevision ? schedule.revision : UUID(), storedRevision ? "range" : "window.1")
                        try engine.handleCallback(activityName: callback, kind: kind, now: at(offset), authorized: approved)
                        let context = "\(phaseName) stored=\(storedRevision) \(kind) approved=\(approved)"
                        XCTAssertEqual(world.state.envelope.session, before, context)
                        for event in ["focus.register", "focus.stop", "focus.clear"] { XCTAssertFalse(world.log.contains(event), "\(event): \(context)") }
                    }
                }
            }
        }
    }
    func testEndDuringBreakAppliesTheEverydayLayerAfterTheFocusRelease() throws {
        let world = EverydayWorld()
        let (engine, schedule) = try onLayer(world)
        let id = try started(engine, world)
        try takeBreak(engine, world, id)
        world.state.activities.remove(Activity(revision: schedule.revision, part: .window(1)))
        world.log = []
        try engine.finish(id: id, reason: .earlyExit, now: at(200))
        let order = ["save:ending", "focus.clear", "focus.stop", "copy.remove", "everyday.apply", "save:terminal"].map { world.log.firstIndex(of: $0) }
        XCTAssertFalse(order.contains(nil), "\(world.log)")
        XCTAssertEqual(order.compactMap { $0 }, order.compactMap { $0 }.sorted(), "\(world.log)")
        let terminal = try XCTUnwrap(world.log.firstIndex(of: "save:terminal"))
        XCTAssertFalse(world.log[..<terminal].contains("everyday.register"))
        XCTAssertTrue(world.log[terminal...].contains("everyday.register"))
        XCTAssertEqual(world.state.store, s1); XCTAssertEqual(world.state.activities, activities(schedule))
    }
    func testFailedSaveOfEndingLeavesTheEarlierPhaseForTheEverydayStep() throws {
        // A failed save must not count as stored: the everyday step and the convergence use the phase that is on disk.
        for (failures, store) in [([SessionPhase.ending], s1 as Set<String>?), ([.ending, .terminal], nil)] {
            let world = EverydayWorld()
            let (engine, _) = try onLayer(world)
            let id = try started(engine, world)
            try takeBreak(engine, world, id)
            world.failSavePhases = failures; world.log = []
            XCTAssertThrowsError(try engine.finish(id: id, reason: .earlyExit, now: at(200)))
            if let terminal = world.log.firstIndex(of: "save:terminal") { XCTAssertFalse(world.log[..<terminal].contains("everyday.apply"), "\(failures)") }
            XCTAssertEqual(world.state.store, store, "\(failures)"); XCTAssertFalse(world.state.focusShield)
        }
    }
    func testEverydayFailureNeverStopsAFocusEnd() throws {
        for failure in ["unreadable", "registration", "mismatch"] {
            let world = EverydayWorld()
            let (engine, schedule) = try onLayer(world)
            let id = try started(engine, world)
            switch failure {
            case "unreadable": world.state.fileCorrupt = true
            case "registration": world.state.activities.remove(Activity(revision: schedule.revision, part: .range)); world.failEverydayParts = [.range]
            default: world.state.store = nil; world.storeMismatch = true
            }
            try engine.finish(id: id, reason: .earlyExit, now: at(200))
            XCTAssertFalse(world.state.focusShield, failure); XCTAssertEqual(phase(world), .terminal, failure); XCTAssertNil(world.state.focus[id], failure)
        }
    }
    func testControlReadFailureClearsBothStoresAndKeepsEverydayActivities() throws {
        let sections: [(String, (SessionControl) throws -> Void)] = [
            ("reconcile", { _ = try $0.reconcile(now: self.t0, authorized: true) }),
            ("snapshot", { _ = try $0.snapshot() }),
            ("status", { _ = try $0.everydayStatus(now: self.t0, authorized: true) }),
            ("callback", { try $0.handleCallback(activityName: "everyday.\(UUID().uuidString).range", kind: .didEnd, now: self.t0, authorized: true) }),
        ]
        for (name, run) in sections {
            let world = EverydayWorld()
            let (engine, schedule) = try onLayer(world)
            world.state.activities.remove(Activity(revision: schedule.revision, part: .window(1)))
            let kept = world.state.activities
            world.state.focusShield = true; world.failReads = true; world.log = []
            XCTAssertThrowsError(try run(engine), name)
            XCTAssertNil(world.state.store, name); XCTAssertFalse(world.state.focusShield, name)
            XCTAssertEqual(world.state.activities, kept, name)
            for event in ["file.read", "everyday.register", "everyday.stop", "everyday.apply"] { XCTAssertFalse(world.log.contains(event), "\(event): \(name)") }
        }
    }
    func testStartAndStartRollbackNeverWriteTheEverydayStore() throws {
        for rollback in [false, true] {
            let world = EverydayWorld()
            _ = try onLayer(world)
            let engine = engine(world)
            if rollback { world.failSavePhases = [.active] }
            world.log = []
            if rollback { XCTAssertThrowsError(try started(engine, world)) } else { _ = try started(engine, world) }
            XCTAssertFalse(world.log.contains("everyday.apply")); XCTAssertFalse(world.log.contains("everyday.clear"))
            XCTAssertEqual(world.state.store, s1)
        }
    }
    func testM2EnvelopeWithoutEverydayFileLoadsWithTheLayerOff() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID(), started = t0.timeIntervalSinceReferenceDate
        let json = """
        {"schemaVersion":2,"session":{"id":"\(id.uuidString)","startedAt":\(started),"expiresAt":\(started + 1500),"phase":"active","breaksTaken":0}}
        """
        try Data(json.utf8).write(to: directory.appendingPathComponent("control.json"))
        let world = EverydayWorld(); world.state.focus[id] = at(1500)
        let engine = SessionControl(store: SharedControlStore(directory: directory), monitoring: world, shield: world, breakSelection: world, everyday: LayerView(world), calendar: calendar)
        let running = try engine.reconcile(now: at(100), authorized: true)
        XCTAssertEqual(running.session?.id, id); XCTAssertEqual(running.session?.phase, .active)
        XCTAssertEqual(TimeRules.remaining(session: try XCTUnwrap(running.session), now: at(100)), 1400)
        let status = try engine.everydayStatus(now: at(100), authorized: true)
        XCTAssertNil(status.schedule); XCTAssertFalse(status.blocksNow); XCTAssertNil(status.issue)
        XCTAssertEqual(try engine.reconcile(now: at(1500), authorized: true).session?.reason, .expired)
        XCTAssertFalse(world.log.contains("everyday.register")); XCTAssertNil(world.state.store)
    }

    // MARK: Interruptions

    /// The spec tables "Stored states and side artifacts", after a section with access approved.
    private func assertEverydayTable(_ world: EverydayWorld, now: Date, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        guard !world.state.fileCorrupt else { XCTAssertNil(world.state.store, context, file: file, line: line); return }
        let schedule = world.state.file?.schedule
        let blocks = EverydayRules.blocks(schedule: schedule, session: world.state.envelope.session, authorized: true, now: now, calendar: calendar)
        XCTAssertEqual(world.state.store, blocks ? world.state.file?.selection : nil, "store: \(context)", file: file, line: line)
        let expected = schedule.map { $0.enabled ? activities($0) : [] } ?? []
        XCTAssertEqual(world.state.activities, expected, "activities: \(context)", file: file, line: line)
    }
    func testInterruptionAtEveryStepKeepsTheEverydayTable() throws {
        struct Scenario {
            let name: String
            let setup: (EverydayWorld) throws -> (SessionControl, UUID?)
            let run: (SessionControl, EverydayWorld, UUID?) throws -> Void
            let now: Date
            /// For a save inside the range: the store never falls below the earlier selection.
            var earlier: Set<String>?
        }
        let layered: (EverydayWorld) throws -> (SessionControl, UUID?) = { world in (try self.onLayer(world).0, nil) }
        let session: (EverydayWorld) throws -> (SessionControl, UUID?) = { world in
            let (engine, _) = try self.onLayer(world); return (engine, try self.started(engine, world))
        }
        let onBreak: (EverydayWorld) throws -> (SessionControl, UUID?) = { world in
            let (engine, id) = try session(world); try self.takeBreak(engine, world, id!); return (engine, id)
        }
        let scenarios = [
            Scenario(name: "stricter edit", setup: layered, run: { engine, world, _ in try self.save(engine, world, self.layer(windows: []), self.s2, at: self.t0) }, now: t0, earlier: s1),
            Scenario(name: "turn-off outside the range", setup: layered, run: { engine, world, _ in try self.save(engine, world, self.layer(enabled: false), self.s1, at: self.clock(19, 0)) }, now: clock(19, 0)),
            Scenario(name: "convergence", setup: { world in
                let earlier = self.layer(), stored = self.layer()
                world.state = EverydayState(file: StoredLayer(schedule: stored, selection: self.s1), activities: self.activities(earlier))
                return (self.engine(world), nil)
            }, run: { engine, _, _ in try engine.reconcile(now: self.t0, authorized: true) }, now: t0),
            Scenario(name: "start", setup: layered, run: { engine, world, _ in _ = try self.started(engine, world) }, now: t0),
            Scenario(name: "start rollback", setup: { world in let result = try layered(world); world.failSavePhases = [.active]; return result },
                     run: { engine, world, _ in _ = try self.started(engine, world) }, now: t0),
            Scenario(name: "break start", setup: { world in
                let (engine, id) = try session(world); _ = try engine.requestBreak(id: id!, now: self.at(100)); return (engine, id)
            }, run: { engine, world, id in try engine.startBreak(id: id!, now: self.at(115), saveSelection: { try world.saveCopy(id!) }) }, now: at(115)),
            Scenario(name: "re-block", setup: onBreak, run: { engine, _, _ in try engine.reconcile(now: self.at(295), authorized: true) }, now: at(295)),
            Scenario(name: "end", setup: session, run: { engine, _, id in try engine.finish(id: id!, reason: .earlyExit, now: self.at(200)) }, now: at(200)),
            Scenario(name: "end during a break", setup: onBreak, run: { engine, _, id in try engine.finish(id: id!, reason: .earlyExit, now: self.at(200)) }, now: at(200)),
            Scenario(name: "off for today", setup: layered, run: { engine, world, _ in try self.turnOff(engine, world, at: self.t0) }, now: t0),
            Scenario(name: "save while off for today", setup: { world in let result = try layered(world); try self.turnOff(result.0, world, at: self.t0); return result },
                     run: { engine, world, _ in try self.save(engine, world, self.layer(windows: []), self.s2, at: self.at(60)) }, now: at(60)),
        ]
        for scenario in scenarios {
            // Exit pass: a new process starts from each recorded state.
            let world = EverydayWorld(); let (engine, id) = try scenario.setup(world)
            world.recording = true; world.snapshots = [world.state]
            try? scenario.run(engine, world, id)
            XCTAssertGreaterThan(world.snapshots.count, 1, scenario.name)
            for (index, snapshot) in world.snapshots.enumerated() {
                let context = "\(scenario.name) exit \(index)"
                if let earlier = scenario.earlier { XCTAssertTrue(earlier.isSubset(of: snapshot.store ?? []), "never looser: \(context)") }
                let exited = EverydayWorld(snapshot)
                _ = try? self.engine(exited).reconcile(now: scenario.now, authorized: true)
                assertEverydayTable(exited, now: scenario.now, context)
            }
            // Throw pass: each throwable effect throws once, then reconcile runs.
            let counting = EverydayWorld(); let (countingEngine, countingID) = try scenario.setup(counting)
            let base = counting.effects
            try? scenario.run(countingEngine, counting, countingID)
            for offset in 0..<(counting.effects - base) {
                let thrown = EverydayWorld(); let (engine, id) = try scenario.setup(thrown)
                thrown.throwAtEffect = thrown.effects + offset
                try? scenario.run(engine, thrown, id)
                if let earlier = scenario.earlier { XCTAssertTrue(earlier.isSubset(of: thrown.state.store ?? []), "never looser: \(scenario.name) throw \(offset)") }
                _ = try? engine.reconcile(now: scenario.now, authorized: true)
                assertEverydayTable(thrown, now: scenario.now, "\(scenario.name) throw \(offset)")
            }
        }
    }
    // MARK: Off for today

    private func key(_ date: Date) -> String { EverydaySchedule.dayKey(of: date, calendar: calendar) }
    private func day(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second))!
    }
    /// The off-for-today section for the stored revision, unless another is given; the write keeps the stored selection.
    private func turnOff(_ engine: SessionControl, _ world: EverydayWorld, revision: UUID? = nil, at now: Date, access: Bool = true) throws {
        try engine.turnEverydayOffForToday(revision: revision ?? world.state.file?.schedule.revision ?? UUID(), now: now, authorized: { access },
                                           write: { try world.writeFile(StoredLayer(schedule: $0, selection: world.state.file?.selection ?? [])) })
    }
    private func refusal(_ engine: SessionControl, _ world: EverydayWorld, revision: UUID? = nil, at now: Date, access: Bool = true) -> Error? {
        do { try turnOff(engine, world, revision: revision, at: now, access: access); return nil } catch { return error }
    }

    func testOffForTodayWritesTodaysKeyKeepsTheRevisionAndActivitiesAndClearsTheStore() throws {
        let world = EverydayWorld()
        let (engine, schedule) = try onLayer(world)
        world.log = []
        try turnOff(engine, world, at: t0)
        var expected = schedule; expected.offDay = "2026-11-02"
        XCTAssertEqual(world.state.file?.schedule, expected, "same revision, schedule and selection, with today's key")
        XCTAssertEqual(world.state.file?.selection, s1)
        XCTAssertEqual(world.state.activities, activities(schedule), "the activities stay for tomorrow's range start")
        XCTAssertNil(world.state.store)
        // Steps 1 and 2 register and stop nothing; the convergence finds the revision complete.
        XCTAssertFalse(world.log.contains("everyday.register")); XCTAssertFalse(world.log.contains("everyday.stop"))
        XCTAssertLessThan(try XCTUnwrap(world.log.firstIndex(of: "file.write")), try XCTUnwrap(world.log.firstIndex(of: "everyday.clear")))
        let status = try engine.everydayStatus(now: at(60), authorized: true)
        XCTAssertTrue(status.offForToday); XCTAssertFalse(status.blocksNow); XCTAssertNil(status.issue)
        XCTAssertEqual(status.nextChange, day(3, 8))
        // Later edges today leave the store empty; the next day's range blocks again without the app.
        for time in [clock(12, 0), clock(13, 0), clock(17, 59, 59)] {
            try engine.handleCallback(activityName: name(schedule.revision, "range"), kind: .didStart, now: time, authorized: true)
            XCTAssertNil(world.state.store, "\(time)")
        }
        try engine.handleCallback(activityName: name(schedule.revision, "range"), kind: .didStart, now: day(3, 8), authorized: true)
        XCTAssertEqual(world.state.store, s1)
        let tomorrow = try engine.everydayStatus(now: day(3, 8), authorized: true)
        XCTAssertFalse(tomorrow.offForToday); XCTAssertTrue(tomorrow.blocksNow)
    }
    func testOffForTodayRefusesEachConditionInOrderAndWritesNothing() throws {
        // Each case: setup, the expected refusal; the file never changes.
        func check(_ name: String, at now: Date = t0, access: Bool = true, revision: ((EverydaySchedule?) -> UUID)? = nil,
                   setup: (EverydayWorld, SessionControl) throws -> Void, expect: (Error?) -> Bool) throws {
            let world = EverydayWorld()
            let (engine, _) = try onLayer(world)
            try setup(world, engine)
            let before = world.state.file
            world.log = []
            let error = refusal(engine, world, revision: revision?(world.state.file?.schedule), at: now, access: access)
            XCTAssertTrue(expect(error), "\(name): \(String(describing: error))")
            XCTAssertEqual(world.state.file, before, name); XCTAssertFalse(world.log.contains("file.write"), name)
        }
        let session: (EverydayWorld, SessionControl) throws -> Void = { world, engine in _ = try self.started(engine, world) }
        try check("unauthorized", access: false, setup: { _, _ in }) { $0 as? ControlIssue == .unauthorized }
        try check("unauthorized before busy", access: false, setup: session) { $0 as? ControlIssue == .unauthorized }
        try check("busy", setup: session) { $0 as? ControlIssue == .busy }
        try check("busy before unreadable", setup: { world, engine in try session(world, engine); world.state.fileCorrupt = true }) { $0 as? ControlIssue == .busy }
        try check("unreadable", setup: { world, _ in world.state.fileCorrupt = true }) { $0 as? EverydayOffRefusal == .unreadable }
        try check("no layer", setup: { world, _ in world.state.file = nil }) { $0 as? EverydayOffRefusal == .notOn }
        try check("layer off before revision", revision: { _ in UUID() }, setup: { world, _ in world.state.file?.schedule.enabled = false }) {
            $0 as? EverydayOffRefusal == .notOn
        }
        try check("revision", revision: { _ in UUID() }, setup: { _, _ in }) { $0 as? EverydayOffRefusal == .revisionChanged }
        try check("revision before range", at: clock(19, 0), revision: { _ in UUID() }, setup: { _, _ in }) { $0 as? EverydayOffRefusal == .revisionChanged }
        for time in [clock(7, 59, 59), clock(18, 0), clock(19, 0)] {
            try check("outside the range \(time)", at: time, setup: { _, _ in }) { $0 as? EverydayOffRefusal == .outsideRange }
        }
        try check("already off", setup: { world, engine in try self.turnOff(engine, world, at: self.clock(9, 0)) }) { $0 as? EverydayOffRefusal == .alreadyOff }
        try check("range before already off", at: clock(19, 0), setup: { world, engine in try self.turnOff(engine, world, at: self.clock(9, 0)) }) {
            $0 as? EverydayOffRefusal == .outsideRange
        }
        XCTAssertEqual(EverydayOffRefusal.allCases, [.unreadable, .notOn, .revisionChanged, .outsideRange, .alreadyOff])
    }
    func testOffForTodayRefusalConvergesAsEveryAppSection() throws {
        // A refusal for access stops every everyday activity and clears the store (M3 row "Access revoked").
        let world = EverydayWorld()
        let (engine, _) = try onLayer(world)
        XCTAssertNotNil(refusal(engine, world, at: t0, access: false))
        XCTAssertTrue(world.state.activities.isEmpty); XCTAssertNil(world.state.store)
        // Another refusal registers a missing activity of the stored revision and keeps the store by the schedule.
        let other = EverydayWorld()
        let (otherEngine, schedule) = try onLayer(other)
        other.state.activities.remove(Activity(revision: schedule.revision, part: .window(1)))
        XCTAssertNotNil(refusal(otherEngine, other, revision: UUID(), at: t0))
        XCTAssertEqual(other.state.activities, activities(schedule)); XCTAssertEqual(other.state.store, s1)
        // An unreadable `control.json` clears the store and runs no convergence.
        let unreadable = EverydayWorld()
        let (unreadableEngine, _) = try onLayer(unreadable)
        unreadable.failReads = true; unreadable.log = []
        XCTAssertNotNil(refusal(unreadableEngine, unreadable, at: t0))
        XCTAssertNil(unreadable.state.store); XCTAssertFalse(unreadable.log.contains("file.read"))
    }
    func testAFailedOffForTodayWriteKeepsTheLayerBlocking() throws {
        let world = EverydayWorld()
        let (engine, schedule) = try onLayer(world)
        world.failWrite = true
        XCTAssertThrowsError(try turnOff(engine, world, at: t0))
        XCTAssertEqual(world.state.file?.schedule, schedule); XCTAssertEqual(world.state.store, s1)
        world.failWrite = false
        try turnOff(engine, world, at: t0.addingTimeInterval(40))
        XCTAssertNil(world.state.store)
    }
    func testSaveKeepsTodaysOffDayDropsAnEarlierOneAndIgnoresAPassedOne() throws {
        let world = EverydayWorld()
        let (engine, _) = try onLayer(world)
        try turnOff(engine, world, at: t0)
        // A draft without `offDay`, saved while the layer is off for today, keeps today's key.
        try save(engine, world, layer(windows: []), s2, at: at(300))
        XCTAssertEqual(world.state.file?.schedule.offDay, "2026-11-02"); XCTAssertNil(world.state.store)
        // An `offDay` that the app passes is ignored.
        var passed = layer(windows: []); passed.offDay = "2026-12-24"
        try save(engine, world, passed, s2, at: at(600))
        XCTAssertEqual(world.state.file?.schedule.offDay, "2026-11-02")
        // On the next day, the first save removes the earlier key, also outside the range.
        try save(engine, world, layer(windows: []), s2, at: day(3, 7))
        XCTAssertNil(world.state.file?.schedule.offDay)
        // An app-passed key never turns a day off.
        var today = layer(windows: []); today.offDay = key(day(3, 7))
        try save(engine, world, today, s2, at: day(3, 7))
        XCTAssertNil(world.state.file?.schedule.offDay)
    }

    // MARK: Guards across sequences of accepted actions

    func testOffForTodayThenALooserEditIsRefusedUntilTheStoredRangeEnd() throws {
        let world = EverydayWorld()
        let (engine, stored) = try onLayer(world)
        try turnOff(engine, world, at: t0)
        let looser: [(EverydaySchedule, Set<String>, EverydayLockReason)] = [
            (layer(), ["site1"], .removesSelection), (layer(8 * 60, 17 * 60), s1, .rangeEndsEarlier),
            (layer(windows: [lunch, EverydayWindow(kind: .custom, start: 15 * 60, end: 15 * 60 + 30)]), s1, .unblocksTime), (layer(enabled: false), s1, .turnsOff),
        ]
        for (schedule, selection, reason) in looser {
            XCTAssertThrowsError(try save(engine, world, schedule, selection, at: at(300))) { XCTAssertEqual($0 as? EverydayLockReason, reason) }
        }
        // The lock still ends at the stored range end.
        for (schedule, selection, reason) in [looser[0], looser[3]] {
            XCTAssertThrowsError(try save(engine, world, schedule, selection, at: clock(17, 59, 59))) { XCTAssertEqual($0 as? EverydayLockReason, reason) }
        }
        var expected = stored; expected.offDay = "2026-11-02"
        XCTAssertEqual(world.state.file?.schedule, expected); XCTAssertEqual(world.state.file?.selection, s1)
    }
    func testOffForTodayThenAStricterEditBlocksFromTheNextDaysRange() throws {
        let world = EverydayWorld()
        let (engine, _) = try onLayer(world)
        try turnOff(engine, world, at: t0)
        try save(engine, world, layer(windows: []), s2, at: at(300))
        XCTAssertNil(world.state.store, "nothing blocks until today ends")
        try engine.reconcile(now: clock(12, 30), authorized: true)
        XCTAssertNil(world.state.store)
        try engine.reconcile(now: day(3, 8), authorized: true)
        XCTAssertEqual(world.state.store, s2)
    }
    func testOffForTodayThenALooserEditAfterTheRangeEndAndThenTheNextDay() throws {
        let world = EverydayWorld()
        let (engine, _) = try onLayer(world)
        try turnOff(engine, world, at: t0)
        try save(engine, world, layer(9 * 60, 17 * 60, windows: []), ["site1"], at: clock(19, 0))
        XCTAssertEqual(world.state.file?.schedule.offDay, "2026-11-02")
        try engine.reconcile(now: day(3, 8, 30), authorized: true)
        XCTAssertNil(world.state.store, "the new schedule starts at 09:00")
        try engine.reconcile(now: day(3, 9), authorized: true)
        XCTAssertEqual(world.state.store, ["site1"])
    }
    func testTurningTheLayerOffAndOnOutsideTheRangeKeepsItOffForToday() throws {
        let world = EverydayWorld()
        let (engine, _) = try onLayer(world)
        try turnOff(engine, world, at: t0)
        try save(engine, world, layer(enabled: false), s1, at: clock(19, 0))
        try save(engine, world, layer(6 * 60, 23 * 60), s1, at: clock(19, 5))
        XCTAssertEqual(world.state.file?.schedule.offDay, "2026-11-02")
        XCTAssertNil(world.state.store, "there is no way to turn it back on for today")
        XCTAssertTrue(try engine.everydayStatus(now: clock(19, 10), authorized: true).offForToday)
        XCTAssertEqual(refusal(engine, world, at: clock(19, 10)) as? EverydayOffRefusal, .alreadyOff)
    }
    func testOffForTodayOnDayDThenTheNextDayBlocksAndOffersTheActionAgain() throws {
        let world = EverydayWorld()
        let (engine, _) = try onLayer(world)
        try turnOff(engine, world, at: t0)
        try engine.reconcile(now: day(3, 10), authorized: true)
        XCTAssertEqual(world.state.store, s1)
        XCTAssertFalse(try engine.everydayStatus(now: day(3, 10), authorized: true).offForToday)
        XCTAssertThrowsError(try save(engine, world, layer(enabled: false), s1, at: day(3, 10))) { XCTAssertEqual($0 as? EverydayLockReason, .turnsOff) }
        try turnOff(engine, world, at: day(3, 10))
        XCTAssertEqual(world.state.file?.schedule.offDay, "2026-11-03"); XCTAssertNil(world.state.store)
    }
    func testASaveAfterTheFileBecameUnreadableWritesNoOffDay() throws {
        let world = EverydayWorld()
        let (engine, _) = try onLayer(world)
        try turnOff(engine, world, at: t0)
        world.state.fileCorrupt = true
        try save(engine, world, layer(), s1, at: at(300))
        XCTAssertNil(world.state.file?.schedule.offDay); XCTAssertEqual(world.state.store, s1, "the layer blocks again today")
        try turnOff(engine, world, at: at(600))
        XCTAssertNil(world.state.store, "the action can be used again today")
    }
    func testAStricterEditThenOffForTodayWritesTheNewRevision() throws {
        let world = EverydayWorld()
        let (engine, _) = try onLayer(world)
        let next = layer(windows: [])
        try save(engine, world, next, s2, at: t0)
        try turnOff(engine, world, at: at(60))
        XCTAssertEqual(world.state.file?.schedule.revision, next.revision); XCTAssertEqual(world.state.file?.selection, s2)
        XCTAssertEqual(world.state.activities, activities(next)); XCTAssertNil(world.state.store)
    }
    func testASaveOrTheRangeEndDuringTheWaitRefusesTheSection() throws {
        let world = EverydayWorld()
        let (engine, shown) = try onLayer(world)
        try save(engine, world, layer(windows: []), s1, at: at(10))
        XCTAssertEqual(refusal(engine, world, revision: shown.revision, at: at(30)) as? EverydayOffRefusal, .revisionChanged)
        XCTAssertEqual(world.state.store, s1)
        let other = EverydayWorld()
        let (otherEngine, _) = try onLayer(other)
        XCTAssertEqual(refusal(otherEngine, other, at: clock(18, 0, 10)) as? EverydayOffRefusal, .outsideRange)
    }
    func testASessionDuringTheWaitIsBusyAndASessionAfterTheActionKeepsTheLayerOff() throws {
        let world = EverydayWorld()
        let (engine, _) = try onLayer(world)
        let id = try started(engine, world)
        XCTAssertEqual(refusal(engine, world, at: at(30)) as? ControlIssue, .busy)
        try engine.finish(id: id, reason: .earlyExit, now: at(40))
        try engine.acknowledgeTerminal(id: id)
        try turnOff(engine, world, at: at(50))
        let later = EverydayWorld(world.state)
        let laterEngine = self.engine(later)
        // A session that starts after the action: its break, the re-block and the end all read the off day.
        let next = try laterEngine.start(now: t0, authorized: { true }, apply: { later.state.focusShield = true }, matches: { later.state.focusShield }).id
        try takeBreak(laterEngine, later, next)
        XCTAssertNil(later.state.store)
        try laterEngine.reconcile(now: at(295), authorized: true)
        XCTAssertEqual(phase(later), .breakOver); XCTAssertTrue(later.state.focusShield); XCTAssertNil(later.state.store)
        try laterEngine.finish(id: next, reason: .earlyExit, now: at(400))
        XCTAssertFalse(later.state.focusShield); XCTAssertNil(later.state.store)
    }
    func testAClockSetBackToTheOffDayTurnsTheLayerOffAgainUntilASave() throws {
        let world = EverydayWorld()
        let (engine, _) = try onLayer(world)
        try turnOff(engine, world, at: t0)
        try engine.reconcile(now: day(3, 10), authorized: true)
        XCTAssertEqual(world.state.store, s1)
        try engine.reconcile(now: clock(11, 0), authorized: true, clockChanged: true)
        XCTAssertNil(world.state.store, "off again for that local date")
        try save(engine, world, layer(), s1, at: day(3, 19))
        XCTAssertNil(world.state.file?.schedule.offDay)
    }
}
