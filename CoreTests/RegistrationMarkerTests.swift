import XCTest
import Darwin
@testable import FocusCore

/// A marker in memory with a settable uptime clock.
private final class MemoryMarkers: RegistrationMarkerStore {
    var marker: RegistrationMarker?, now: TimeInterval = 1000, failWrite = false, failDelete = false
    private(set) var writes = 0, deletes = 0
    func read() -> RegistrationMarker? { marker }
    func write(_ marker: RegistrationMarker) throws { writes += 1; if failWrite { throw FixtureFailure.injected }; self.marker = marker }
    func delete() throws { deletes += 1; if failDelete { throw FixtureFailure.injected }; marker = nil }
    func uptime() -> TimeInterval { now }
}
/// A control store in memory that logs the timeout of each lock attempt and throws the queued lock failures, one per attempt.
private final class MarkerControlStore: ControlStore, LockedControl {
    var envelope = ControlEnvelope(), lockFailures: [Error] = [], failRead = false
    let markers = MemoryMarkers()
    var registrationMarkers: (any RegistrationMarkerStore)? { markers }
    private(set) var timeouts: [TimeInterval?] = []
    /// Runs before a queued lock failure is thrown, with the number of the attempt (0 first).
    var beforeFailure: ((Int) -> Void)?
    func withExclusiveAccess<T>(timeout: TimeInterval?, _ body: (LockedControl) throws -> T) throws -> T {
        timeouts.append(timeout)
        if !lockFailures.isEmpty { beforeFailure?(timeouts.count - 1); throw lockFailures.removeFirst() }
        return try body(self)
    }
    func load() throws -> ControlEnvelope { if failRead { throw FixtureFailure.injected }; return envelope }
    func save(_ envelope: ControlEnvelope) throws { self.envelope = envelope }
}
/// Records the marker that it can read during each registration and stop call.
private final class MarkerSpyMonitoring: MonitoringClient {
    let base = FakeMonitoring(), markers: any RegistrationMarkerStore
    var failRegistration = false
    /// Runs inside each everyday stop call, while the engine's marker for that call exists.
    var onStopEveryday: ((UUID, EverydayPart) -> Void)?
    /// Every registration and stop call, in order.
    private(set) var calls: [(call: String, marker: RegistrationMarker?)] = []
    /// The registration calls only.
    var seen: [(call: String, marker: RegistrationMarker?)] { calls.filter { $0.call.hasPrefix("register") } }
    /// The stop calls only.
    var stops: [(call: String, marker: RegistrationMarker?)] { calls.filter { $0.call.hasPrefix("stop") } }
    init(markers: any RegistrationMarkerStore) { self.markers = markers }
    func register(id: UUID, start: Date, end: Date) throws {
        calls.append(("register", markers.read()))
        if failRegistration { throw FixtureFailure.injected }
        try base.register(id: id, start: start, end: end)
    }
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws {
        calls.append(("registerBreak", markers.read())); try base.registerBreak(id: id, index: index, start: start, end: end, warning: warning)
    }
    func registerEveryday(revision: UUID, part: EverydayPart, start: Int, end: Int) throws {
        calls.append(("registerEveryday", markers.read())); try base.registerEveryday(revision: revision, part: part, start: start, end: end)
    }
    var registeredSessionIDs: [UUID] { base.registeredSessionIDs }
    func isRegistered(id: UUID) -> Bool { base.isRegistered(id: id) }
    func stop(id: UUID) { calls.append(("stop", markers.read())); base.stop(id: id) }
    func isBreakRegistered(id: UUID, index: Int) -> Bool { base.isBreakRegistered(id: id, index: index) }
    var registeredBreaks: [(id: UUID, index: Int)] { base.registeredBreaks }
    func stopBreak(id: UUID, index: Int) { calls.append(("stopBreak", markers.read())); base.stopBreak(id: id, index: index) }
    var registeredEveryday: [(revision: UUID, part: EverydayPart)] { base.registeredEveryday }
    func stopEveryday(revision: UUID, part: EverydayPart) {
        calls.append(("stopEveryday", markers.read())); onStopEveryday?(revision, part); base.stopEveryday(revision: revision, part: part)
    }
}

final class RegistrationMarkerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }
    private let utc: Calendar = { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!; return calendar }()
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }
    private var markerURL: URL { directory.appendingPathComponent(RegistrationMarker.fileName) }

    private func world() -> (SessionControl, MarkerControlStore, MarkerSpyMonitoring, FakeEverydayStore) {
        let store = MarkerControlStore(), monitor = MarkerSpyMonitoring(markers: store.markers), everyday = FakeEverydayStore()
        return (SessionControl(store: store, monitoring: monitor, shield: FakeShield(), breakSelection: FakeBreakSelection(), everyday: everyday, calendar: utc), store, monitor, everyday)
    }
    /// A 1500-second session that started at `t0`.
    private func started() throws -> (SessionControl, MarkerControlStore, MarkerSpyMonitoring, ControlSession) {
        let (engine, store, monitor, _) = world()
        let session = try engine.start(now: t0, authorized: { .approved }, apply: {}, matches: { true })
        return (engine, store, monitor, session)
    }

    // MARK: The marker file

    func testMarkerFileRoundTrips() throws {
        let file = RegistrationMarkerFile(directory: directory)
        let marker = RegistrationMarker(activityName: "focus.\(UUID().uuidString)", uptime: 1234.5, validUntil: at(1500))
        try file.write(marker)
        XCTAssertEqual(file.read(), marker)
        XCTAssertEqual(file.read()?.schemaVersion, 2); XCTAssertEqual(file.read()?.call, .register)
        let stop = RegistrationMarker.stop(["focus.\(UUID().uuidString)", "everyday.\(UUID().uuidString).range"], uptime: 1234.5)
        try file.write(stop)
        XCTAssertEqual(file.read(), stop)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: markerURL)) as? [String: Any])
        XCTAssertEqual(object["call"] as? String, "stop"); XCTAssertEqual(object["activityNames"] as? [String], stop.activityNames)
        XCTAssertNil(object["validUntil"], "a stop marker has no time bound")
        try file.delete()
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
        // Deleting a missing file succeeds.
        XCTAssertNoThrow(try file.delete())
    }
    func testMissingUnreadableUndecodableAndUnknownVersionCountAsNoMarker() throws {
        let file = RegistrationMarkerFile(directory: directory)
        XCTAssertNil(file.read(), "missing")
        try Data("not json".utf8).write(to: markerURL)
        XCTAssertNil(file.read(), "undecodable")
        // The version 1 shape of the registration marker design.
        try Data(#"{"schemaVersion":1,"activityName":"focus.x","uptime":1,"validUntil":0}"#.utf8).write(to: markerURL)
        XCTAssertNil(file.read(), "version 1")
        let encoded = try JSONEncoder().encode(RegistrationMarker(activityName: "focus.x", uptime: 1, validUntil: t0))
        let valid = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        try JSONSerialization.data(withJSONObject: valid).write(to: markerURL)
        XCTAssertNotNil(file.read(), "the control case decodes")
        let changes: [(String, (inout [String: Any]) -> Void)] = [
            ("version 1 with the version 2 fields", { $0["schemaVersion"] = 1 }),
            ("unknown schemaVersion", { $0["schemaVersion"] = 3 }),
            ("a register marker without validUntil", { $0.removeValue(forKey: "validUntil") }),
            ("unknown call", { $0["call"] = "pause" }),
            ("empty activityNames", { $0["activityNames"] = [String]() }),
            ("empty activityNames of a stop", { $0["call"] = "stop"; $0.removeValue(forKey: "validUntil"); $0["activityNames"] = [String]() })
        ]
        for (label, change) in changes {
            var object = valid; change(&object)
            try JSONSerialization.data(withJSONObject: object).write(to: markerURL)
            XCTAssertNil(file.read(), label)
        }
        try FileManager.default.removeItem(at: markerURL)
        try FileManager.default.createDirectory(at: markerURL, withIntermediateDirectories: true)
        XCTAssertNil(file.read(), "unreadable")
    }
    func testFreshnessBounds() {
        let marker = RegistrationMarker(activityName: "focus.x", uptime: 1000, validUntil: t0)
        XCTAssertFalse(marker.isFresh(atUptime: 1000 - 0.001), "a negative age is a marker from before a restart")
        XCTAssertTrue(marker.isFresh(atUptime: 1000))
        XCTAssertTrue(marker.isFresh(atUptime: 1010))
        XCTAssertFalse(marker.isFresh(atUptime: 1010.001))
        let markers = MemoryMarkers(); markers.marker = marker
        markers.now = 1010; XCTAssertEqual(markers.freshMarker(), marker)
        markers.now = 1010.001; XCTAssertNil(markers.freshMarker())
    }

    // MARK: The skip rule

    func testSkipRuleChecksNameKindAndValidUntil() {
        let name = "focus.\(UUID().uuidString)"
        let marker = RegistrationMarker(activityName: name, uptime: 1000, validUntil: at(1500))
        XCTAssertTrue(marker.decides(activityName: name, kind: .didStart, now: at(1499)))
        XCTAssertTrue(marker.decides(activityName: name, kind: .didEnd, now: at(1499.999)))
        XCTAssertFalse(marker.decides(activityName: name, kind: .didEnd, now: at(1500)), "a focus end at validUntil")
        XCTAssertFalse(marker.decides(activityName: name + ".break.1", kind: .didStart, now: at(1)), "another name")
        XCTAssertFalse(marker.decides(activityName: name, kind: .willEndWarning, now: at(1)), "a warning never skips")
        let everyday = "everyday.\(UUID().uuidString).range"
        let nextMinute = RegistrationMarker(activityName: everyday, uptime: 1000, validUntil: at(60))
        XCTAssertFalse(nextMinute.decides(activityName: everyday, kind: .didStart, now: at(60)), "an everyday edge at the next minute")
        let withoutBound = RegistrationMarker(call: .register, activityNames: [name], uptime: 1000, validUntil: nil)
        XCTAssertFalse(withoutBound.decides(activityName: name, kind: .didEnd, now: at(1)), "a register marker without validUntil is no marker")
    }
    func testStopMarkerSkipsOnlyTheDidEndOfAListedNameWithNoTimeBound() {
        let focus = "focus.\(UUID().uuidString)", breakTwo = focus + ".break.2"
        let marker = RegistrationMarker.stop([focus, breakTwo], uptime: 1000)
        XCTAssertTrue(marker.decides(activityName: focus, kind: .didEnd, now: at(1)))
        XCTAssertTrue(marker.decides(activityName: breakTwo, kind: .didEnd, now: .distantFuture), "no time condition")
        XCTAssertFalse(marker.decides(activityName: focus, kind: .didStart, now: at(1)), "a stop causes no didStart")
        XCTAssertFalse(marker.decides(activityName: breakTwo, kind: .willEndWarning, now: at(1)), "a warning never skips")
        XCTAssertFalse(marker.decides(activityName: focus + ".break.3", kind: .didEnd, now: at(1)), "a name that is not listed")
        XCTAssertFalse(RegistrationMarker.stop([], uptime: 1000).decides(activityName: focus, kind: .didEnd, now: at(1)))
    }

    // MARK: The retry

    func testMatchAtAttemptZeroReturnsWithoutPauseOrSection() throws {
        let (engine, store, _, session) = try started()
        store.markers.marker = RegistrationMarker(activityName: session.activityName, uptime: 1000, validUntil: at(2000))
        store.lockFailures = [ControlIssue.lockTimeout]
        let before = store.envelope.session; var pauses: [TimeInterval] = [], reads = 0
        // The section would end the session at its focus end.
        try engine.handleCallbackRetryingLock(activityName: session.activityName, kind: .didEnd, now: { reads += 1; return self.at(1500) }, authorized: { .approved }, sleep: { pauses.append($0) })
        XCTAssertTrue(pauses.isEmpty); XCTAssertEqual(reads, 1)
        XCTAssertEqual(store.timeouts.suffix(1), [0]); XCTAssertEqual(store.envelope.session, before)
    }
    func testCallbackThatDoesNotMatchKeepsTheBoundedRetry() throws {
        let cases: [(String, (ControlSession) -> RegistrationMarker?, CallbackKind)] = [
            ("another name", { RegistrationMarker(activityName: $0.breakActivityName(index: 1), uptime: 1000, validUntil: self.at(2000)) }, .didEnd),
            ("a warning", { RegistrationMarker(activityName: $0.activityName, uptime: 1000, validUntil: self.at(2000)) }, .willEndWarning),
            ("now at validUntil", { RegistrationMarker(activityName: $0.activityName, uptime: 1000, validUntil: self.at(1500)) }, .didEnd),
            ("a stale marker", { RegistrationMarker(activityName: $0.activityName, uptime: 989.999, validUntil: self.at(2000)) }, .didEnd),
            ("no marker", { _ in nil }, .didEnd)
        ]
        for (label, marker, kind) in cases {
            let (engine, store, _, session) = try started()
            store.markers.marker = marker(session)
            let before = store.envelope.session, firstLockCall = store.timeouts.count
            store.lockFailures = Array(repeating: ControlIssue.lockTimeout, count: 6)
            var pauses: [TimeInterval] = []
            XCTAssertThrowsError(try engine.handleCallbackRetryingLock(activityName: session.activityName, kind: kind, now: { self.at(1500) }, authorized: { .approved }, sleep: { pauses.append($0) }), label) {
                XCTAssertEqual($0 as? ControlIssue, .lockTimeout, label)
            }
            XCTAssertEqual(pauses, Array(repeating: 0.25, count: 4), label)
            XCTAssertEqual(Array(store.timeouts.dropFirst(firstLockCall)), [0, nil, nil, nil, nil, nil], label)
            XCTAssertEqual(store.envelope.session, before, label)
        }
    }
    func testMarkerThatAppearsAfterALaterTimeoutEndsTheCallback() throws {
        let (engine, store, _, session) = try started()
        let firstLockCall = store.timeouts.count
        store.lockFailures = Array(repeating: ControlIssue.lockTimeout, count: 6)
        // The holder registers this name only during the second retry.
        store.beforeFailure = { attempt in
            if attempt == firstLockCall + 2 { store.markers.marker = RegistrationMarker(activityName: session.activityName, uptime: 1000, validUntil: self.at(2000)) }
        }
        let before = store.envelope.session; var pauses: [TimeInterval] = []
        try engine.handleCallbackRetryingLock(activityName: session.activityName, kind: .didEnd, now: { self.at(1500) }, authorized: { .approved }, sleep: { pauses.append($0) })
        XCTAssertEqual(pauses, [0.25]); XCTAssertEqual(store.timeouts.count - firstLockCall, 3)
        XCTAssertEqual(store.lockFailures.count, 3); XCTAssertEqual(store.envelope.session, before)
    }
    func testCallbackThatGetsTheLockRunsItsSection() throws {
        let (engine, store, _, session) = try started()
        // A marker without a busy lock is a leftover, so the callback runs.
        store.markers.marker = RegistrationMarker(activityName: session.activityName, uptime: 1000, validUntil: at(2000))
        var pauses: [TimeInterval] = []
        try engine.handleCallbackRetryingLock(activityName: session.activityName, kind: .didEnd, now: { self.at(1500) }, authorized: { .approved }, sleep: { pauses.append($0) })
        XCTAssertTrue(pauses.isEmpty); XCTAssertEqual(store.timeouts.last, 0)
        XCTAssertEqual(store.envelope.session?.phase, .terminal); XCTAssertEqual(store.envelope.session?.reason, .expired)
    }

    // MARK: Writing and deleting around each registration

    func testStartWritesTheFocusMarkerDuringItsCallAndDeletesIt() throws {
        let (_, store, monitor, session) = try started()
        XCTAssertEqual(monitor.seen.count, 1)
        XCTAssertEqual(monitor.seen.first?.marker, RegistrationMarker(activityName: session.activityName, uptime: 1000, validUntil: session.expiresAt))
        XCTAssertNil(store.markers.marker)
    }
    func testBreakStartMarksTheBreakUntilItsWarningAndTheOverwriteUntilTheDeadline() throws {
        let (engine, store, monitor, session) = try started()
        _ = try engine.requestBreak(id: session.id, now: at(100))
        XCTAssertEqual(monitor.seen.last?.marker?.activityNames, [session.activityName])
        try engine.startBreak(id: session.id, now: at(115), saveSelection: {})
        let breakMarker = try XCTUnwrap(monitor.seen.first { $0.call == "registerBreak" }?.marker)
        XCTAssertEqual(breakMarker.activityNames, [session.breakActivityName(index: 1)])
        XCTAssertEqual(breakMarker.validUntil, at(115 + BreakTiming.standard.breakLength))
        let stored = try XCTUnwrap(store.envelope.session)
        XCTAssertEqual(stored.phase, .onBreak)
        XCTAssertEqual(monitor.seen.last?.call, "register")
        XCTAssertEqual(monitor.seen.last?.marker, RegistrationMarker(activityName: session.activityName, uptime: 1000, validUntil: stored.deadline(timing: .standard)))
        XCTAssertNil(store.markers.marker)
    }
    func testEverydayRegistrationsAreValidUntilTheNextWholeMinuteOfTheSectionTime() throws {
        let (engine, store, monitor, everyday) = world()
        let now = utc.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 10, minute: 30, second: 15))!.addingTimeInterval(0.5)
        let schedule = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 0, rangeEnd: 23 * 60 + 55, windows: [EverydayWindow(kind: .lunch, start: 13 * 60, end: 14 * 60)])
        try engine.saveEveryday(schedule, now: now, authorized: { .approved }, containsStoredSelection: { true }, write: { everyday.schedule = $0 })
        let markers = monitor.seen.filter { $0.call == "registerEveryday" }.map(\.marker)
        XCTAssertEqual(markers.map { $0?.activityNames.first }, ["everyday.\(schedule.revision.uuidString).range", "everyday.\(schedule.revision.uuidString).window.1"])
        let nextMinute = utc.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 10, minute: 31))!
        XCTAssertEqual(markers.map { $0?.validUntil }, [nextMinute, nextMinute])
        XCTAssertNil(store.markers.marker)
    }
    /// The convergence at the end of a section registers through the section's marker wrapper, in an app section and in a Monitor `didEnd` section.
    func testConvergenceRegistersAMissingEverydayPartUnderItsMarker() throws {
        let now = utc.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 10, minute: 30, second: 15))!
        let nextMinute = utc.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 10, minute: 31))!
        let sections: [(String, (SessionControl, EverydaySchedule) throws -> Void)] = [
            ("reconcile", { engine, _ in _ = try engine.reconcile(now: now, authorized: .approved) }),
            ("didEnd callback", { engine, schedule in
                try engine.handleCallback(activityName: "everyday.\(schedule.revision.uuidString).window.1", kind: .didEnd, now: now, authorized: .approved)
            })
        ]
        for (label, run) in sections {
            let (engine, store, monitor, everyday) = world()
            let schedule = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 0, rangeEnd: 23 * 60 + 55, windows: [EverydayWindow(kind: .lunch, start: 13 * 60, end: 14 * 60)])
            // The stored revision has no registered part, so the convergence registers both.
            everyday.schedule = schedule
            try run(engine, schedule)
            let calls = monitor.seen.filter { $0.call == "registerEveryday" }
            XCTAssertEqual(calls.map { $0.marker?.activityNames.first }, ["everyday.\(schedule.revision.uuidString).range", "everyday.\(schedule.revision.uuidString).window.1"], label)
            XCTAssertEqual(calls.map { $0.marker?.validUntil }, [nextMinute, nextMinute], label)
            XCTAssertNil(store.markers.marker, label)
        }
    }
    func testMarkerIsDeletedAfterARegistrationThatThrows() throws {
        let (engine, store, monitor, _) = world()
        monitor.failRegistration = true
        XCTAssertThrowsError(try engine.start(now: t0, authorized: { .approved }, apply: {}, matches: { true }))
        XCTAssertNotNil(monitor.seen.first?.marker)
        XCTAssertNil(store.markers.marker); XCTAssertEqual(store.envelope.session?.reason, .startFailed)
    }
    func testMarkerWriteThatThrowsDoesNotStopTheRegistration() throws {
        let (engine, store, monitor, _) = world()
        store.markers.failWrite = true
        let session = try engine.start(now: t0, authorized: { .approved }, apply: {}, matches: { true })
        XCTAssertEqual(store.markers.writes, 1); XCTAssertNil(monitor.seen.first?.marker)
        XCTAssertEqual(store.envelope.session?.phase, .active); XCTAssertTrue(monitor.isRegistered(id: session.id))
    }
    func testMarkerDeleteThatThrowsDoesNotFailTheSection() throws {
        let (engine, store, _, _) = world()
        store.markers.failDelete = true
        let session = try engine.start(now: t0, authorized: { .approved }, apply: {}, matches: { true })
        XCTAssertEqual(store.envelope.session?.id, session.id); XCTAssertEqual(store.envelope.session?.phase, .active)
        XCTAssertEqual(store.markers.marker?.activityNames, [session.activityName], "a leftover for the next lock holder")
    }

    // MARK: Writing and deleting around each stop

    /// A session on break 1, with the selection copy that a re-block restores.
    private func onBreak() throws -> (SessionControl, MarkerControlStore, MarkerSpyMonitoring, FakeEverydayStore, ControlSession) {
        let store = MarkerControlStore(), monitor = MarkerSpyMonitoring(markers: store.markers), everyday = FakeEverydayStore(), copies = FakeBreakSelection()
        let engine = SessionControl(store: store, monitoring: monitor, shield: FakeShield(), breakSelection: copies, everyday: everyday, calendar: utc)
        let session = try engine.start(now: t0, authorized: { .approved }, apply: {}, matches: { true })
        _ = try engine.requestBreak(id: session.id, now: at(100))
        try engine.startBreak(id: session.id, now: at(115), saveSelection: { copies.copies.insert(session.id) })
        XCTAssertEqual(store.envelope.session?.phase, .onBreak)
        return (engine, store, monitor, everyday, session)
    }
    func testSessionEndStopsUnderAMarkerWithEveryNameOfTheSession() throws {
        let (engine, store, monitor, _, session) = try onBreak()
        try engine.finish(id: session.id, reason: .earlyExit, now: at(200))
        let stop = try XCTUnwrap(monitor.stops.last { $0.call == "stop" })
        XCTAssertEqual(stop.marker?.call, .stop); XCTAssertNil(stop.marker?.validUntil)
        XCTAssertEqual(stop.marker?.activityNames, [session.activityName] + (1...BreakTiming.maxBreaks).map(session.breakActivityName))
        XCTAssertNil(store.markers.marker); XCTAssertEqual(store.envelope.session?.phase, .terminal)
    }
    func testStopNamesListRegisteredBreaksOfTheSessionOnce() {
        let id = UUID(), other = UUID()
        let names = MarkedMonitoring.stopActivityNames(id: id, registeredBreaks: [(id, 2), (other, 1), (id, 5)])
        XCTAssertEqual(names, [MarkedMonitoring.focusActivityName(id: id)] + [2, 5, 1, 3].map { MarkedMonitoring.breakActivityName(id: id, index: $0) })
    }
    func testResumeWithAnEarlyReturnMarksTheOverwriteTheStopAndTheOverwrite() throws {
        let (engine, store, monitor, _, session) = try onBreak()
        let before = monitor.calls.count
        try engine.resume(id: session.id, now: at(200))
        let calls = Array(monitor.calls.dropFirst(before))
        XCTAssertEqual(calls.map(\.call), ["register", "stopBreak", "register"])
        XCTAssertEqual(calls.map { $0.marker?.call }, [.register, .stop, .register])
        XCTAssertEqual(calls.map { $0.marker?.activityNames }, [[session.activityName], [session.breakActivityName(index: 1)], [session.activityName]])
        XCTAssertNil(store.markers.marker); XCTAssertEqual(store.envelope.session?.phase, .active)
    }
    func testEverydayStopsMarkTheStoppedPart() throws {
        let (engine, store, monitor, everyday) = world()
        let first = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 0, rangeEnd: 23 * 60 + 55, windows: [EverydayWindow(kind: .lunch, start: 13 * 60, end: 14 * 60)])
        try engine.saveEveryday(first, now: t0, authorized: { .approved }, containsStoredSelection: { true }, write: { everyday.schedule = $0 })
        var second = first; second.revision = UUID()
        try engine.saveEveryday(second, now: t0, authorized: { .approved }, containsStoredSelection: { true }, write: { everyday.schedule = $0 })
        XCTAssertEqual(monitor.stops.map(\.call), ["stopEveryday", "stopEveryday"])
        XCTAssertEqual(monitor.stops.map { $0.marker?.call }, [.stop, .stop])
        XCTAssertEqual(Set(monitor.stops.compactMap { $0.marker?.activityNames }), [[MarkedMonitoring.everydayActivityName(revision: first.revision, part: .range)],
                                                                                [MarkedMonitoring.everydayActivityName(revision: first.revision, part: .window(1))]])
        XCTAssertNil(store.markers.marker)
    }
    func testStopMarkerWriteThatThrowsDoesNotStopTheStop() throws {
        let (engine, store, monitor, session) = try started()
        store.markers.failWrite = true
        try engine.finish(id: session.id, reason: .earlyExit, now: at(10))
        XCTAssertEqual(monitor.stops.map(\.call), ["stop"]); XCTAssertNil(monitor.stops.first?.marker)
        XCTAssertFalse(monitor.isRegistered(id: session.id)); XCTAssertEqual(store.envelope.session?.phase, .terminal)
    }
    /// `snapshot()` and `everydayStatus` hold the lock without `section`; their read-failure stops are marked too.
    func testReadFailureStopsOfLockHoldersOutsideSectionsAreMarked() throws {
        let holders: [(String, (SessionControl) throws -> Void)] = [
            ("snapshot", { _ = try $0.snapshot() }),
            ("everydayStatus", { _ = try $0.everydayStatus(now: self.at(200), authorized: .approved) })
        ]
        for (label, holder) in holders {
            let (engine, store, monitor, _, session) = try onBreak()
            // A stop of a session also stops its breaks, so only an orphaned break of another session is left for `stopBreak`.
            let orphan = UUID()
            try monitor.base.registerBreak(id: orphan, index: 2, start: t0, end: at(900), warning: 720)
            store.failRead = true
            XCTAssertThrowsError(try holder(engine), label)
            XCTAssertEqual(monitor.stops.map(\.call), ["stop", "stopBreak"], label)
            XCTAssertEqual(monitor.stops.map { $0.marker?.call }, [.stop, .stop], label)
            XCTAssertEqual(monitor.stops.first?.marker?.activityNames, [session.activityName] + (1...BreakTiming.maxBreaks).map(session.breakActivityName), label)
            XCTAssertEqual(monitor.stops.last?.marker?.activityNames, [MarkedMonitoring.breakActivityName(id: orphan, index: 2)], label)
            XCTAssertFalse(monitor.isRegistered(id: session.id), label); XCTAssertNil(store.markers.marker, label)
        }
    }

    // MARK: Work that becomes due during a stop

    /// A section in break 1 stops an earlier everyday revision; the break ends during that stop.
    /// Returns the result of the everyday `didEnd` that arrived during the stop and whether it paused.
    private func breakEndsDuringAnEverydayStop() throws -> (SessionControl, MarkerControlStore, ControlSession, skipped: Bool) {
        let (engine, store, monitor, everyday, session) = try onBreak()
        let earlier = UUID(), stored = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 0, rangeEnd: 23 * 60 + 55, windows: [])
        everyday.schedule = stored
        try monitor.base.registerEveryday(revision: earlier, part: .range, start: 0, end: 23 * 60 + 55)
        try monitor.base.registerEveryday(revision: stored.revision, part: .range, start: 0, end: 23 * 60 + 55)
        let breakEnd = try XCTUnwrap(store.envelope.session?.breakEndsAt)
        var skipped = false
        monitor.onStopEveryday = { revision, _ in
            guard revision == earlier else { return }
            // The earlier range's didEnd, after the break end: the lock is busy, and the holder's stop marker lists that name.
            // Every attempt finds the lock busy, as while a real holder runs.
            store.lockFailures = Array(repeating: ControlIssue.lockTimeout, count: 6)
            var pauses: [TimeInterval] = []
            skipped = (try? engine.handleCallbackRetryingLock(activityName: "everyday.\(earlier.uuidString).range", kind: .didEnd, now: { breakEnd.addingTimeInterval(1) },
                                                              authorized: { .approved }, sleep: { pauses.append($0) })) != nil && pauses.isEmpty && store.lockFailures.count == 5
            store.lockFailures = []
        }
        try engine.reconcile(now: breakEnd.addingTimeInterval(-1), authorized: .approved)
        XCTAssertEqual(monitor.registeredEveryday.map(\.revision), [stored.revision])
        XCTAssertEqual(store.envelope.session?.phase, .onBreak, "the skipped didEnd did not re-block")
        XCTAssertNil(store.markers.marker)
        return (engine, store, session, skipped)
    }
    func testBreakEndDuringAnEverydayStopSkipsTheEverydayEndAndTheWarningReBlocks() throws {
        let (engine, store, session, skipped) = try breakEndsDuringAnEverydayStop()
        XCTAssertTrue(skipped)
        let breakEnd = try XCTUnwrap(store.envelope.session?.breakEndsAt)
        // The warning is not listed, so it took the bounded retry and gets the lock after the section.
        try engine.handleCallbackRetryingLock(activityName: session.breakActivityName(index: 1), kind: .willEndWarning, now: { breakEnd.addingTimeInterval(1) }, authorized: { .approved }, sleep: { _ in })
        XCTAssertEqual(store.envelope.session?.phase, .breakOver)
    }
    func testWarningThatGivesUpAfterAnEverydayStopLeavesTheReBlockToTheBreakEnd() throws {
        let (engine, store, session, skipped) = try breakEndsDuringAnEverydayStop()
        XCTAssertTrue(skipped)
        let breakEnd = try XCTUnwrap(store.envelope.session?.breakEndsAt)
        store.lockFailures = Array(repeating: ControlIssue.lockTimeout, count: 6)
        XCTAssertThrowsError(try engine.handleCallbackRetryingLock(activityName: session.breakActivityName(index: 1), kind: .willEndWarning, now: { breakEnd.addingTimeInterval(1) },
                                                                   authorized: { .approved }, sleep: { _ in })) { XCTAssertEqual($0 as? ControlIssue, .lockTimeout) }
        XCTAssertEqual(store.envelope.session?.phase, .onBreak)
        // No app reconcile: the break activity's didEnd at +15 min is the last backstop.
        let breakStart = breakEnd.addingTimeInterval(-BreakTiming.standard.breakLength)
        try engine.handleCallbackRetryingLock(activityName: session.breakActivityName(index: 1), kind: .didEnd, now: { breakStart.addingTimeInterval(BreakTiming.breakActivityLength) },
                                              authorized: { .approved }, sleep: { _ in })
        XCTAssertEqual(store.envelope.session?.phase, .breakOver)
    }

    // MARK: Delete on lock take

    private func sharedEngine(_ store: SharedControlStore) -> SessionControl {
        SessionControl(store: store, monitoring: FakeMonitoring(), shield: FakeShield(), breakSelection: FakeBreakSelection(), everyday: FakeEverydayStore(), calendar: utc)
    }
    private func writeLeftover() throws {
        try RegistrationMarkerFile(directory: directory).write(RegistrationMarker(activityName: "focus.\(UUID().uuidString)", uptime: ProcessInfo.processInfo.systemUptime, validUntil: .distantFuture))
    }
    func testEveryLockHolderDeletesALeftover() throws {
        let engine = sharedEngine(SharedControlStore(directory: directory))
        let holders: [(String, () throws -> Void)] = [
            ("snapshot", { _ = try engine.snapshot() }),
            ("activitySnapshot", { _ = try engine.activitySnapshot() }),
            ("everydayStatus", { _ = try engine.everydayStatus(now: self.t0, authorized: .approved) }),
            ("reconcile", { try engine.reconcile(now: self.t0, authorized: .approved) }),
            ("callback", { try engine.handleCallback(activityName: "focus.\(UUID().uuidString)", kind: .didEnd, now: self.t0, authorized: .approved) })
        ]
        for (label, holder) in holders {
            try writeLeftover()
            XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path), label)
            try holder()
            XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path), label)
        }
    }
    func testZeroTimeoutMakesOneAttemptAndLeavesTheHoldersMarker() throws {
        let store = SharedControlStore(directory: directory)
        try store.withExclusiveAccess { _ in }
        let fd = open(directory.appendingPathComponent("control.lock").path, O_RDWR)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        try writeLeftover()
        var entered = false
        let begin = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try store.withExclusiveAccess(timeout: 0) { _ in entered = true }) { XCTAssertEqual($0 as? ControlIssue, .lockTimeout) }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - begin, 0.1)
        XCTAssertFalse(entered)
        XCTAssertNotNil(store.registrationMarkers?.read(), "only a lock holder deletes the marker")
        flock(fd, LOCK_UN)
        try store.withExclusiveAccess(timeout: 0) { _ in entered = true }
        XCTAssertTrue(entered); XCTAssertNil(store.registrationMarkers?.read())
    }
}
