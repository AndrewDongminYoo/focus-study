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
    var envelope = ControlEnvelope(), lockFailures: [Error] = []
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
    func load() throws -> ControlEnvelope { envelope }
    func save(_ envelope: ControlEnvelope) throws { self.envelope = envelope }
}
/// Records the marker that it can read during each registration call.
private final class MarkerSpyMonitoring: MonitoringClient {
    let base = FakeMonitoring(), markers: any RegistrationMarkerStore
    var failRegistration = false
    private(set) var seen: [(call: String, marker: RegistrationMarker?)] = []
    init(markers: any RegistrationMarkerStore) { self.markers = markers }
    func register(id: UUID, start: Date, end: Date) throws {
        seen.append(("register", markers.read()))
        if failRegistration { throw FixtureFailure.injected }
        try base.register(id: id, start: start, end: end)
    }
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws {
        seen.append(("registerBreak", markers.read())); try base.registerBreak(id: id, index: index, start: start, end: end, warning: warning)
    }
    func registerEveryday(revision: UUID, part: EverydayPart, start: Int, end: Int) throws {
        seen.append(("registerEveryday", markers.read())); try base.registerEveryday(revision: revision, part: part, start: start, end: end)
    }
    var registeredSessionIDs: [UUID] { base.registeredSessionIDs }
    func isRegistered(id: UUID) -> Bool { base.isRegistered(id: id) }
    func stop(id: UUID) { base.stop(id: id) }
    func isBreakRegistered(id: UUID, index: Int) -> Bool { base.isBreakRegistered(id: id, index: index) }
    var registeredBreaks: [(id: UUID, index: Int)] { base.registeredBreaks }
    func stopBreak(id: UUID, index: Int) { base.stopBreak(id: id, index: index) }
    var registeredEveryday: [(revision: UUID, part: EverydayPart)] { base.registeredEveryday }
    func stopEveryday(revision: UUID, part: EverydayPart) { base.stopEveryday(revision: revision, part: part) }
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
        let session = try engine.start(now: t0, authorized: { true }, apply: {}, matches: { true })
        return (engine, store, monitor, session)
    }

    // MARK: The marker file

    func testMarkerFileRoundTrips() throws {
        let file = RegistrationMarkerFile(directory: directory)
        let marker = RegistrationMarker(activityName: "focus.\(UUID().uuidString)", uptime: 1234.5, validUntil: at(1500))
        try file.write(marker)
        XCTAssertEqual(file.read(), marker)
        XCTAssertEqual(file.read()?.schemaVersion, 1)
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
        let encoded = try JSONEncoder().encode(RegistrationMarker(activityName: "focus.x", uptime: 1, validUntil: t0))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["schemaVersion"] = 2
        try JSONSerialization.data(withJSONObject: object).write(to: markerURL)
        XCTAssertNil(file.read(), "unknown schemaVersion")
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
    }

    // MARK: The retry

    func testMatchAtAttemptZeroReturnsWithoutPauseOrSection() throws {
        let (engine, store, _, session) = try started()
        store.markers.marker = RegistrationMarker(activityName: session.activityName, uptime: 1000, validUntil: at(2000))
        store.lockFailures = [ControlIssue.lockTimeout]
        let before = store.envelope.session; var pauses: [TimeInterval] = [], reads = 0
        // The section would end the session at its focus end.
        try engine.handleCallbackRetryingLock(activityName: session.activityName, kind: .didEnd, now: { reads += 1; return self.at(1500) }, authorized: { true }, sleep: { pauses.append($0) })
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
            XCTAssertThrowsError(try engine.handleCallbackRetryingLock(activityName: session.activityName, kind: kind, now: { self.at(1500) }, authorized: { true }, sleep: { pauses.append($0) }), label) {
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
        try engine.handleCallbackRetryingLock(activityName: session.activityName, kind: .didEnd, now: { self.at(1500) }, authorized: { true }, sleep: { pauses.append($0) })
        XCTAssertEqual(pauses, [0.25]); XCTAssertEqual(store.timeouts.count - firstLockCall, 3)
        XCTAssertEqual(store.lockFailures.count, 3); XCTAssertEqual(store.envelope.session, before)
    }
    func testCallbackThatGetsTheLockRunsItsSection() throws {
        let (engine, store, _, session) = try started()
        // A marker without a busy lock is a leftover, so the callback runs.
        store.markers.marker = RegistrationMarker(activityName: session.activityName, uptime: 1000, validUntil: at(2000))
        var pauses: [TimeInterval] = []
        try engine.handleCallbackRetryingLock(activityName: session.activityName, kind: .didEnd, now: { self.at(1500) }, authorized: { true }, sleep: { pauses.append($0) })
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
        XCTAssertEqual(monitor.seen.last?.marker?.activityName, session.activityName)
        try engine.startBreak(id: session.id, now: at(115), saveSelection: {})
        let breakMarker = try XCTUnwrap(monitor.seen.first { $0.call == "registerBreak" }?.marker)
        XCTAssertEqual(breakMarker.activityName, session.breakActivityName(index: 1))
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
        try engine.saveEveryday(schedule, now: now, authorized: { true }, containsStoredSelection: { true }, write: { everyday.schedule = $0 })
        let markers = monitor.seen.filter { $0.call == "registerEveryday" }.map(\.marker)
        XCTAssertEqual(markers.map { $0?.activityName }, ["everyday.\(schedule.revision.uuidString).range", "everyday.\(schedule.revision.uuidString).window.1"])
        let nextMinute = utc.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 10, minute: 31))!
        XCTAssertEqual(markers.map { $0?.validUntil }, [nextMinute, nextMinute])
        XCTAssertNil(store.markers.marker)
    }
    /// The convergence at the end of a section registers through the section's marker wrapper, in an app section and in a Monitor `didEnd` section.
    func testConvergenceRegistersAMissingEverydayPartUnderItsMarker() throws {
        let now = utc.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 10, minute: 30, second: 15))!
        let nextMinute = utc.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 10, minute: 31))!
        let sections: [(String, (SessionControl, EverydaySchedule) throws -> Void)] = [
            ("reconcile", { engine, _ in _ = try engine.reconcile(now: now, authorized: true) }),
            ("didEnd callback", { engine, schedule in
                try engine.handleCallback(activityName: "everyday.\(schedule.revision.uuidString).window.1", kind: .didEnd, now: now, authorized: true)
            })
        ]
        for (label, run) in sections {
            let (engine, store, monitor, everyday) = world()
            let schedule = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 0, rangeEnd: 23 * 60 + 55, windows: [EverydayWindow(kind: .lunch, start: 13 * 60, end: 14 * 60)])
            // The stored revision has no registered part, so the convergence registers both.
            everyday.schedule = schedule
            try run(engine, schedule)
            let calls = monitor.seen.filter { $0.call == "registerEveryday" }
            XCTAssertEqual(calls.map { $0.marker?.activityName }, ["everyday.\(schedule.revision.uuidString).range", "everyday.\(schedule.revision.uuidString).window.1"], label)
            XCTAssertEqual(calls.map { $0.marker?.validUntil }, [nextMinute, nextMinute], label)
            XCTAssertNil(store.markers.marker, label)
        }
    }
    func testMarkerIsDeletedAfterARegistrationThatThrows() throws {
        let (engine, store, monitor, _) = world()
        monitor.failRegistration = true
        XCTAssertThrowsError(try engine.start(now: t0, authorized: { true }, apply: {}, matches: { true }))
        XCTAssertNotNil(monitor.seen.first?.marker)
        XCTAssertNil(store.markers.marker); XCTAssertEqual(store.envelope.session?.reason, .startFailed)
    }
    func testMarkerWriteThatThrowsDoesNotStopTheRegistration() throws {
        let (engine, store, monitor, _) = world()
        store.markers.failWrite = true
        let session = try engine.start(now: t0, authorized: { true }, apply: {}, matches: { true })
        XCTAssertEqual(store.markers.writes, 1); XCTAssertNil(monitor.seen.first?.marker)
        XCTAssertEqual(store.envelope.session?.phase, .active); XCTAssertTrue(monitor.isRegistered(id: session.id))
    }
    func testMarkerDeleteThatThrowsDoesNotFailTheSection() throws {
        let (engine, store, _, _) = world()
        store.markers.failDelete = true
        let session = try engine.start(now: t0, authorized: { true }, apply: {}, matches: { true })
        XCTAssertEqual(store.envelope.session?.id, session.id); XCTAssertEqual(store.envelope.session?.phase, .active)
        XCTAssertEqual(store.markers.marker?.activityName, session.activityName, "a leftover for the next lock holder")
    }
    func testStopsWriteNoMarker() throws {
        let (engine, store, _, session) = try started()
        let writes = store.markers.writes
        try engine.finish(id: session.id, reason: .earlyExit, now: at(10))
        XCTAssertEqual(store.markers.writes, writes)
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
            ("everydayStatus", { _ = try engine.everydayStatus(now: self.t0, authorized: true) }),
            ("reconcile", { try engine.reconcile(now: self.t0, authorized: true) }),
            ("callback", { try engine.handleCallback(activityName: "focus.\(UUID().uuidString)", kind: .didEnd, now: self.t0, authorized: true) })
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
