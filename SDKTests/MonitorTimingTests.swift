#if DEBUG
import XCTest

final class MonitorTimingTests: XCTestCase {
    private var directory: URL!
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: directory) }
    private var flagURL: URL { directory.appendingPathComponent("monitor-timing.json") }

    // MARK: Flag

    func testFlagIsOffForAMissingUndecodableOrOtherVersionFile() throws {
        XCTAssertFalse(MonitorTimingFlag.isOn(directory: directory, now: now))
        try Data("{".utf8).write(to: flagURL)
        XCTAssertFalse(MonitorTimingFlag.isOn(directory: directory, now: now))
        try JSONEncoder().encode(["writtenAt": now.timeIntervalSinceReferenceDate]).write(to: flagURL)
        XCTAssertFalse(MonitorTimingFlag.isOn(directory: directory, now: now))
        try JSONEncoder().encode(MonitorTimingFlag(schemaVersion: 2, writtenAt: now)).write(to: flagURL)
        XCTAssertFalse(MonitorTimingFlag.isOn(directory: directory, now: now))
        try JSONEncoder().encode(MonitorTimingFlag(writtenAt: now)).write(to: flagURL)
        XCTAssertTrue(MonitorTimingFlag.isOn(directory: directory, now: now))
    }
    func testFlagIsOnOnlyFromAgeZeroToTwentyFourHours() {
        MonitorTimingFlag.set(true, directory: directory, now: now)
        let day: TimeInterval = 24 * 60 * 60
        XCTAssertFalse(MonitorTimingFlag.isOn(directory: directory, now: now.addingTimeInterval(-1)))
        XCTAssertTrue(MonitorTimingFlag.isOn(directory: directory, now: now))
        XCTAssertTrue(MonitorTimingFlag.isOn(directory: directory, now: now.addingTimeInterval(day)))
        XCTAssertFalse(MonitorTimingFlag.isOn(directory: directory, now: now.addingTimeInterval(day + 1)))
    }
    func testAppWritesTheFlagWithTheArgumentAndRemovesItWithout() throws {
        let group = directory.appendingPathComponent("SessionControl")
        var options: [Data.WritingOptions] = []
        MonitorTimingFlag.set(true, directory: group, now: now) { data, url, option in options.append(option); try data.write(to: url, options: option) }
        let url = group.appendingPathComponent("monitor-timing.json")
        let stored = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        XCTAssertEqual(stored?.keys.sorted(), ["schemaVersion", "writtenAt"])
        XCTAssertEqual(stored?["schemaVersion"] as? Int, 1)
        XCTAssertEqual(options, [SharedControlStore.fileWritingOptions])
        // Each launch with the argument writes the flag again.
        MonitorTimingFlag.set(true, directory: group, now: now.addingTimeInterval(60))
        XCTAssertFalse(MonitorTimingFlag.isOn(directory: group, now: now))
        XCTAssertTrue(MonitorTimingFlag.isOn(directory: group, now: now.addingTimeInterval(60)))
        MonitorTimingFlag.set(false, directory: group, now: now)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        // Removing a missing flag is the usual launch.
        MonitorTimingFlag.set(false, directory: group, now: now)
    }
    /// The call of `FocusRuntime.real()`, with the arguments of a launch. The call site itself runs only in the real runtime, which no SDK test builds.
    func testLaunchArgumentsDecideBetweenTheWriteAndTheRemoval() {
        let group = directory.appendingPathComponent("SessionControl")
        MonitorTimingFlag.set(launchArguments: ["FocusStudy", "--screen-time-diagnostics"], directory: group, now: now)
        XCTAssertTrue(MonitorTimingFlag.isOn(directory: group, now: now))
        // A background launch for the Focus filter has no launch arguments.
        MonitorTimingFlag.set(launchArguments: ["FocusStudy"], directory: group, now: now)
        XCTAssertFalse(FileManager.default.fileExists(atPath: group.appendingPathComponent("monitor-timing.json").path))
        MonitorTimingFlag.set(launchArguments: ["FocusStudy", "--ui-testing", "--break-timing", "short"], directory: group, now: now)
        XCTAssertFalse(MonitorTimingFlag.isOn(directory: group, now: now))
    }
    func testAFailedWriteOrRemovalDoesNotStopTheLaunch() {
        MonitorTimingFlag.set(true, directory: directory, now: now, writeData: { _, _, _ in throw ModelTestError.storage })
        XCTAssertFalse(MonitorTimingFlag.isOn(directory: directory, now: now))
        MonitorTimingFlag.set(true, directory: directory, now: now)
        MonitorTimingFlag.set(false, directory: directory, now: now, removeItem: { _ in throw ModelTestError.storage })
        // The flag that stayed goes stale.
        XCTAssertTrue(MonitorTimingFlag.isOn(directory: directory, now: now))
        XCTAssertFalse(MonitorTimingFlag.isOn(directory: directory, now: now.addingTimeInterval(24 * 60 * 60 + 1)))
    }

    // MARK: Activity kind

    func testActivityKindOfEachName() {
        let id = UUID().uuidString
        XCTAssertEqual(MonitorTimingActivity(activityName: "focus.\(id)"), .focus)
        XCTAssertEqual(MonitorTimingActivity(activityName: "focus.\(id).break.2"), .break)
        XCTAssertEqual(MonitorTimingActivity(activityName: "everyday.\(id).range"), .everyday)
        XCTAssertEqual(MonitorTimingActivity(activityName: "everyday.\(id).window.3"), .everyday)
        XCTAssertEqual(MonitorTimingActivity(activityName: "probe.current.1"), .other)
        XCTAssertEqual(MonitorTimingActivity(activityName: "focus.\(id).break.0"), .other)
        XCTAssertEqual(MonitorTimingActivity(activityName: "focus.\(id).other"), .other)
        XCTAssertEqual(MonitorTimingActivity(activityName: "everyday.\(id)"), .other)
        XCTAssertEqual([MonitorTimingActivity.focus, .break, .everyday, .other].map(\.rawValue), ["focus", "break", "everyday", "other"])
    }
    func testBeginLineNamesTheKindsAndNeverTheActivityName() {
        MonitorTimingFlag.set(true, directory: directory, now: now)
        let id = UUID().uuidString
        var lines: [String] = []
        let cases: [(String, CallbackKind, String)] = [
            ("focus.\(id)", .didStart, "kind=didStart activity=focus"), ("focus.\(id).break.1", .willEndWarning, "kind=willEndWarning activity=break"),
            ("everyday.\(id).window.1", .didEnd, "kind=didEnd activity=everyday"), ("probe.future.2", .didStart, "kind=didStart activity=other"),
        ]
        for (index, entry) in cases.enumerated() {
            XCTAssertNotNil(MonitorTimingRecorder.begin(directory: directory, activity: MonitorTimingActivity(activityName: entry.0), kind: entry.1, now: now, number: { index + 1 }) { lines.append($0) })
        }
        XCTAssertEqual(lines.map(Self.withoutTimes), cases.enumerated().map { "MONITOR_TIMING cb=\($0.offset + 1) \($0.element.2) step=begin flag_ms=#" })
        XCTAssertTrue(lines.allSatisfy { !$0.contains(id) && !$0.contains("probe") })
        // Every time has 3 decimals.
        XCTAssertTrue(lines.allSatisfy { $0.range(of: #"flag_ms=[0-9]+\.[0-9]{3}$"#, options: .regularExpression) != nil })
    }
    func testCallbackNumbersCountUpByOne() {
        let first = MonitorTimingRecorder.nextNumber()
        XCTAssertEqual(MonitorTimingRecorder.nextNumber(), first + 1)
    }

    // MARK: Line sequences

    func testCallbackThatRunsAtAttemptZero() throws {
        let fixture = TimingFixture.breakWarning(now: now)
        let lines = try fixture.runTimed(directory: directory, number: 7)
        let prefix = "MONITOR_TIMING cb=7 kind=willEndWarning activity=break"
        XCTAssertEqual(lines.map(\.text), [
            "\(prefix) step=begin flag_ms=#",
            "\(prefix) step=access ms=# state=approved",
            "\(prefix) step=lock attempt=0 wait_ms=# result=acquired",
            "\(prefix) step=call op=apply_shield ms=#",
            "\(prefix) step=call op=stop_break ms=#",
            "\(prefix) step=section hold_ms=#",
            "\(prefix) step=end total_ms=# result=ran",
        ])
        XCTAssertEqual(fixture.store.envelope.session?.phase, .breakOver)
        // No log call inside the lock: the lines of the section arrive after the store released it.
        XCTAssertTrue(lines.allSatisfy { !$0.insideLock })
        XCTAssertTrue(lines.allSatisfy { !$0.raw.contains(fixture.id.uuidString) })
    }
    func testCallbackThatFindsTheLockBusyAndSkips() throws {
        let fixture = TimingFixture.expiredFocus(now: now)
        fixture.store.busyCalls = [1]
        fixture.markers.marker = RegistrationMarker(activityName: fixture.activityName, uptime: fixture.markers.clock, validUntil: now.addingTimeInterval(60))
        let lines = try fixture.runTimed(directory: directory, number: 2)
        let prefix = "MONITOR_TIMING cb=2 kind=didEnd activity=focus"
        XCTAssertEqual(lines.map(\.text), [
            "\(prefix) step=begin flag_ms=#",
            "\(prefix) step=access ms=# state=approved",
            "\(prefix) step=lock attempt=0 wait_ms=# result=busy",
            "\(prefix) step=marker ms=# marker=register result=skip",
            "\(prefix) step=end total_ms=# result=skipped",
        ])
        XCTAssertEqual(fixture.store.envelope.session?.phase, .active)
        XCTAssertTrue(lines.allSatisfy { !$0.raw.contains(fixture.id.uuidString) })
    }
    func testCallbackThatSkipsOnTheEarlyCheckHasNoAccessLine() throws {
        let fixture = TimingFixture.expiredFocus(now: now)
        fixture.store.busyProbe = true
        fixture.markers.marker = RegistrationMarker(activityName: fixture.activityName, uptime: fixture.markers.clock, validUntil: now.addingTimeInterval(60))
        let lines = try fixture.runTimed(directory: directory, number: 8)
        let prefix = "MONITOR_TIMING cb=8 kind=didEnd activity=focus"
        XCTAssertEqual(lines.map(\.text), [
            "\(prefix) step=begin flag_ms=#",
            "\(prefix) step=lock attempt=probe wait_ms=# result=busy",
            "\(prefix) step=marker ms=# marker=register result=skip",
            "\(prefix) step=end total_ms=# result=skipped",
        ])
        XCTAssertEqual(fixture.accessReads, 0); XCTAssertEqual(fixture.store.calls, 0)
        XCTAssertEqual(fixture.store.envelope.session?.phase, .active)
    }
    func testBusyProbeWhoseMarkerDoesNotDecideContinuesWithAttemptZero() throws {
        let fixture = TimingFixture.expiredFocus(now: now)
        fixture.store.busyProbe = true
        let lines = try fixture.runTimed(directory: directory, number: 9)
        let prefix = "MONITOR_TIMING cb=9 kind=didEnd activity=focus"
        XCTAssertEqual(Array(lines.map(\.text).prefix(5)), [
            "\(prefix) step=begin flag_ms=#",
            "\(prefix) step=lock attempt=probe wait_ms=# result=busy",
            "\(prefix) step=marker ms=# marker=none result=continue",
            "\(prefix) step=access ms=# state=approved",
            "\(prefix) step=lock attempt=0 wait_ms=# result=acquired",
        ])
        XCTAssertEqual(lines.last?.text, "\(prefix) step=end total_ms=# result=ran")
        XCTAssertEqual(fixture.store.envelope.session?.reason, .expired)
    }
    func testCallbackThatRunsAfterABusyAttempt() throws {
        let fixture = TimingFixture.expiredFocus(now: now)
        fixture.store.busyCalls = [1]
        fixture.access = .unknown
        // A `stop` marker for another activity does not decide this callback.
        fixture.markers.marker = .stop(["focus.\(UUID().uuidString)"], uptime: fixture.markers.clock)
        let lines = try fixture.runTimed(directory: directory, number: 3)
        let prefix = "MONITOR_TIMING cb=3 kind=didEnd activity=focus"
        XCTAssertEqual(lines.map(\.text), [
            "\(prefix) step=begin flag_ms=#",
            "\(prefix) step=access ms=# state=unknown",
            "\(prefix) step=lock attempt=0 wait_ms=# result=busy",
            "\(prefix) step=marker ms=# marker=stop result=continue",
            "\(prefix) step=access ms=# state=unknown",
            "\(prefix) step=lock attempt=1 wait_ms=# result=acquired",
            "\(prefix) step=call op=clear_shield ms=#",
            "\(prefix) step=call op=stop ms=#",
            "\(prefix) step=section hold_ms=#",
            "\(prefix) step=end total_ms=# result=ran",
        ])
        XCTAssertEqual(fixture.store.envelope.session?.reason, .expired)
        XCTAssertTrue(lines.allSatisfy { !$0.insideLock })
    }
    func testCallbackWhoseRetriesRunOut() {
        let fixture = TimingFixture.expiredFocus(now: now)
        fixture.store.busyCalls = Set(1...6)
        var lines: [TimingLine] = []
        XCTAssertThrowsError(try fixture.runTimed(directory: directory, number: 4, into: &lines)) { XCTAssertEqual($0 as? ControlIssue, .lockTimeout) }
        let prefix = "MONITOR_TIMING cb=4 kind=didEnd activity=focus"
        let attempts = (0...5).flatMap { attempt in [
            "\(prefix) step=access ms=# state=approved",
            "\(prefix) step=lock attempt=\(attempt) wait_ms=# result=busy",
            "\(prefix) step=marker ms=# marker=none result=continue",
        ] }
        XCTAssertEqual(lines.map(\.text), ["\(prefix) step=begin flag_ms=#"] + attempts + ["\(prefix) step=end total_ms=# result=lock_timeout"])
    }
    func testAnotherThrowEndsWithError() {
        let fixture = TimingFixture.expiredFocus(now: now)
        fixture.store.failRead = true
        var lines: [TimingLine] = []
        XCTAssertThrowsError(try fixture.runTimed(directory: directory, number: 5, into: &lines))
        XCTAssertEqual(lines.last?.text, "MONITOR_TIMING cb=5 kind=didEnd activity=focus step=end total_ms=# result=error")
        // The read failure clears both stores inside the section.
        XCTAssertEqual(lines.map(\.text).filter { $0.contains("step=call") }.map { String($0.split(separator: " ")[5]) }, ["op=clear_shield", "op=clear_everyday", "op=stop"])
    }
    func testEverydayApplyHasItsOwnCallLine() throws {
        let fixture = TimingFixture.breakWarning(now: now)
        // A stored range around `now`, so the re-block applies the everyday layer too, and the convergence registers its activity.
        fixture.everyday.blocking = true
        let lines = try fixture.runTimed(directory: directory, number: 6)
        XCTAssertEqual(lines.map(\.text).filter { $0.contains("step=call") }.map { String($0.split(separator: " ")[5]) }, ["op=apply_shield", "op=apply_everyday", "op=stop_break", "op=register_everyday"])
    }

    // MARK: No behavior change

    func testWrappersChangeNoLockAttemptNoCallAndNoState() throws {
        let scenarios: [(String, () -> TimingFixture)] = [
            ("break warning", { .breakWarning(now: self.now) }),
            ("expired focus", { .expiredFocus(now: self.now) }),
            ("busy then run", { let fixture = TimingFixture.expiredFocus(now: self.now); fixture.store.busyCalls = [1, 2]; return fixture }),
            ("skip", {
                let fixture = TimingFixture.expiredFocus(now: self.now)
                fixture.store.busyCalls = [1]
                fixture.markers.marker = RegistrationMarker(activityName: fixture.activityName, uptime: fixture.markers.clock, validUntil: self.now.addingTimeInterval(60))
                return fixture
            }),
            ("early skip", {
                let fixture = TimingFixture.expiredFocus(now: self.now)
                fixture.store.busyProbe = true
                fixture.markers.marker = RegistrationMarker(activityName: fixture.activityName, uptime: fixture.markers.clock, validUntil: self.now.addingTimeInterval(60))
                return fixture
            }),
            ("busy probe then run", { let fixture = TimingFixture.expiredFocus(now: self.now); fixture.store.busyProbe = true; return fixture }),
            ("retries run out", { let fixture = TimingFixture.expiredFocus(now: self.now); fixture.store.busyCalls = Set(1...6); return fixture }),
            ("unreadable control file", { let fixture = TimingFixture.expiredFocus(now: self.now); fixture.store.failRead = true; return fixture }),
        ]
        for (name, make) in scenarios {
            let plain = make(), timed = make()
            let plainError = Result { try plain.runPlain() }.failure
            var lines: [TimingLine] = []
            let timedError = Result { try timed.runTimed(directory: directory, number: 1, into: &lines) }.failure
            XCTAssertEqual(plainError.map(String.init(describing:)), timedError.map(String.init(describing:)), name)
            XCTAssertEqual(plain.store.calls, timed.store.calls, name)
            XCTAssertEqual(plain.store.probes, timed.store.probes, name)
            XCTAssertEqual(plain.events.list, timed.events.list, name)
            if name == "early skip" {
                // The early skip returns on the probe, before any lock call.
                XCTAssertEqual(plain.store.calls, 0, name); XCTAssertEqual(plain.store.probes, 1, name)
            } else {
                XCTAssertFalse(plain.events.list.isEmpty && plain.store.calls == 0, name)
            }
            XCTAssertEqual(plain.store.envelope.session, timed.store.envelope.session, name)
            XCTAssertEqual(plain.accessReads, timed.accessReads, name)
            XCTAssertEqual(plain.sleeps, timed.sleeps, name)
            XCTAssertFalse(lines.isEmpty, name)
        }
    }
    func testWithoutAValidFlagTheCallbackBuildsNoRecorderAndEmitsNoLine() {
        var lines: [String] = [], numbers = 0
        let begin = { (now: Date) in
            MonitorTimingRecorder.begin(directory: self.directory, activity: .focus, kind: .didEnd, now: now,
                                        number: { numbers += 1; return numbers }) { lines.append($0) }
        }
        XCTAssertNil(begin(now))
        MonitorTimingFlag.set(true, directory: directory, now: now)
        XCTAssertNil(begin(now.addingTimeInterval(24 * 60 * 60 + 1)))
        XCTAssertNil(begin(now.addingTimeInterval(-1)))
        MonitorTimingFlag.set(false, directory: directory)
        XCTAssertNil(begin(now))
        XCTAssertTrue(lines.isEmpty)
        // `cb` counts timed callbacks only.
        XCTAssertEqual(numbers, 0)
    }

    /// Every time becomes `#`, so that a sequence compares as text.
    fileprivate static func withoutTimes(_ line: String) -> String {
        line.replacingOccurrences(of: #"ms=[0-9]+\.[0-9]{3}( |$)"#, with: "ms=#$1", options: .regularExpression)
    }
}

private struct TimingLine {
    let raw: String
    let insideLock: Bool
    var text: String { MonitorTimingTests.withoutTimes(raw) }
}
private extension Result {
    var failure: Failure? { if case .failure(let error) = self { return error }; return nil }
}
/// The call order of every fake client of one callback.
private final class TimingEvents { var list: [String] = [] }

/// One stored session and the fakes that a callback for it uses, with or without the timing wrappers.
private final class TimingFixture {
    let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let events = TimingEvents()
    let store = TimingTestStore(), markers = TimingTestMarkers()
    let monitoring: TimingTestMonitoring, shield: TimingTestShield, breakSelection: TimingTestBreakSelection, everyday: TimingTestEverydayLayer
    let activityName: String, kind: CallbackKind, now: Date
    var access = AccessState.approved
    private(set) var accessReads = 0, sleeps = 0

    private init(session: ControlSession, activityName: String, kind: CallbackKind, now: Date) {
        monitoring = TimingTestMonitoring(events: events); shield = TimingTestShield(events: events)
        breakSelection = TimingTestBreakSelection(events: events); everyday = TimingTestEverydayLayer(events: events, now: now)
        self.activityName = activityName; self.kind = kind; self.now = now
        store.envelope.session = session; store.markers = markers
        monitoring.ids = [session.id]
    }
    /// An `onBreak` session whose break activity delivers its warning: the section re-blocks.
    static func breakWarning(now: Date) -> TimingFixture {
        var session = ControlSession(startedAt: now.addingTimeInterval(-600), id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!)
        session.phase = .onBreak; session.breaksTaken = 1; session.pausedAt = now.addingTimeInterval(-200)
        session.breakEndsAt = now.addingTimeInterval(-10); session.deadlineCredit = 200
        let fixture = TimingFixture(session: session, activityName: session.breakActivityName(index: 1), kind: .willEndWarning, now: now)
        fixture.monitoring.breaks = [(session.id, 1)]; fixture.breakSelection.copies = [session.id]
        return fixture
    }
    /// An `active` session whose focus activity delivers its end: the section ends the session as `expired`.
    static func expiredFocus(now: Date) -> TimingFixture {
        var session = ControlSession(startedAt: now.addingTimeInterval(-1500), id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!)
        session.phase = .active
        return TimingFixture(session: session, activityName: session.activityName, kind: .didEnd, now: now)
    }
    private func read() -> AccessState { accessReads += 1; return access }
    /// The engine of today, as `FocusMonitor` builds it without a valid flag.
    func runPlain() throws {
        let engine = SessionControl(store: store, monitoring: monitoring, shield: shield, breakSelection: breakSelection, everyday: everyday)
        try engine.handleCallbackRetryingLock(activityName: activityName, kind: kind, now: { self.now }, authorized: read, sleep: { _ in self.sleeps += 1 })
    }
    @discardableResult func runTimed(directory: URL, number: Int) throws -> [TimingLine] {
        var lines: [TimingLine] = []
        try runTimed(directory: directory, number: number, into: &lines)
        return lines
    }
    /// The same callback as `FocusMonitor` runs with a valid flag; `lines` also gets the lines of a callback that throws.
    func runTimed(directory: URL, number: Int, into lines: inout [TimingLine]) throws {
        MonitorTimingFlag.set(true, directory: directory, now: now)
        var emitted: [TimingLine] = []
        defer { lines = emitted }
        let timing = try XCTUnwrap(MonitorTimingRecorder.begin(directory: directory, activity: MonitorTimingActivity(activityName: activityName), kind: kind, now: now, number: { number }) {
            emitted.append(TimingLine(raw: $0, insideLock: self.store.isLocked))
        })
        let engine = timing.engine(store: store, monitoring: monitoring, shield: shield, breakSelection: breakSelection, everyday: everyday)
        try timing.run {
            try engine.handleCallbackRetryingLock(activityName: activityName, kind: kind, now: { self.now }, authorized: { timing.access(self.read) },
                                                  sleep: { _ in self.sleeps += 1 })
        }
    }
}
private final class TimingTestStore: ControlStore, LockedControl {
    var envelope = ControlEnvelope(), failRead = false
    /// The numbers of the lock attempts that throw `lockTimeout` before their body runs.
    var busyCalls = Set<Int>()
    var markers: (any RegistrationMarkerStore)?
    var registrationMarkers: (any RegistrationMarkerStore)? { markers }
    /// The answer of the busy probe before the access read; the lock attempts keep `busyCalls`.
    var busyProbe = false
    private(set) var calls = 0, probes = 0, isLocked = false
    func isLockBusy() -> Bool { probes += 1; return busyProbe }
    func withExclusiveAccess<T>(timeout: TimeInterval?, _ body: (LockedControl) throws -> T) throws -> T {
        calls += 1
        if busyCalls.contains(calls) { throw ControlIssue.lockTimeout }
        isLocked = true
        defer { isLocked = false }
        return try body(self)
    }
    func load() throws -> ControlEnvelope { if failRead { throw ModelTestError.storage }; return envelope }
    func save(_ envelope: ControlEnvelope) throws { self.envelope = envelope }
}
private final class TimingTestMarkers: RegistrationMarkerStore {
    var marker: RegistrationMarker?
    let clock: TimeInterval = 100
    func read() -> RegistrationMarker? { marker }
    func write(_ marker: RegistrationMarker) throws {}
    func delete() throws {}
    func uptime() -> TimeInterval { clock }
}
private final class TimingTestMonitoring: MonitoringClient {
    private let events: TimingEvents
    var ids = Set<UUID>(), breaks: [(id: UUID, index: Int)] = []
    init(events: TimingEvents) { self.events = events }
    var registeredSessionIDs: [UUID] { events.list.append("registeredSessionIDs"); return Array(ids) }
    func register(id: UUID, start: Date, end: Date) throws { events.list.append("register"); ids.insert(id) }
    func isRegistered(id: UUID) -> Bool { events.list.append("isRegistered"); return ids.contains(id) }
    func stop(id: UUID) { events.list.append("stop"); ids.remove(id); breaks.removeAll { $0.id == id } }
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws { events.list.append("registerBreak"); breaks.append((id, index)) }
    func isBreakRegistered(id: UUID, index: Int) -> Bool { events.list.append("isBreakRegistered"); return breaks.contains { $0.id == id && $0.index == index } }
    var registeredBreaks: [(id: UUID, index: Int)] { events.list.append("registeredBreaks"); return breaks }
    func stopBreak(id: UUID, index: Int) { events.list.append("stopBreak \(index)"); breaks.removeAll { $0.id == id && $0.index == index } }
    func registerEveryday(revision: UUID, part: EverydayPart, start: Int, end: Int) throws { events.list.append("registerEveryday") }
    var registeredEveryday: [(revision: UUID, part: EverydayPart)] { events.list.append("registeredEveryday"); return [] }
    func stopEveryday(revision: UUID, part: EverydayPart) { events.list.append("stopEveryday") }
}
private final class TimingTestShield: ShieldClient {
    private let events: TimingEvents
    init(events: TimingEvents) { self.events = events }
    func clear() { events.list.append("clear") }
}
private final class TimingTestBreakSelection: BreakSelectionStore {
    private let events: TimingEvents
    var copies = Set<UUID>()
    init(events: TimingEvents) { self.events = events }
    func restoreShield(id: UUID) -> Bool { events.list.append("restoreShield"); return copies.contains(id) }
    func exists(id: UUID) -> Bool { events.list.append("exists"); return copies.contains(id) }
    func remove(id: UUID) { events.list.append("remove"); copies.remove(id) }
    func removeAll(except id: UUID?) { events.list.append("removeAll"); copies = copies.filter { $0 == id } }
}
private final class TimingTestEverydayLayer: EverydayLayerStore {
    private let events: TimingEvents
    private let now: Date
    /// A stored layer whose range holds `now`, with nothing applied yet.
    var blocking = false
    private var applied = false
    init(events: TimingEvents, now: Date) { self.events = events; self.now = now }
    func load() throws -> EverydaySchedule? {
        events.list.append("load")
        guard blocking else { return nil }
        // The engine reads the range in its own calendar, the current one.
        let minute = Calendar.current.component(.hour, from: now) * 60 + Calendar.current.component(.minute, from: now)
        return EverydaySchedule(revision: UUID(uuidString: "AAAAAAAA-2222-3333-4444-555555555555")!, enabled: true,
                                rangeStart: max(0, minute - 60), rangeEnd: min(EverydaySchedule.latestRangeEnd, minute + 60), windows: [])
    }
    func storeMatches() -> Bool { events.list.append("storeMatches"); return applied }
    func applyStored() -> Bool { events.list.append("applyStored"); applied = true; return true }
    var hasShield: Bool { events.list.append("hasShield"); return applied }
    func clearShield() { events.list.append("clearShield"); applied = false }
}
#endif
