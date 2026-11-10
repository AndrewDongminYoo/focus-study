#if DEBUG
import XCTest

@MainActor final class DeviceDiagnosticsTests: XCTestCase {
    func testInjectedFailureStopsRealBoundaryRegistrationAndDoesNotRepeat() throws {
        let base = DiagnosticMonitoringSpy(), shield = DiagnosticShieldSpy()
        let monitor = DiagnosticMonitoring(base: base)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = SessionControl(store: SharedControlStore(directory: directory), monitoring: monitor, shield: shield, breakSelection: DiagnosticBreakSelectionSpy(), everyday: ModelTestEverydayLayer())
        let diagnostics = DeviceDiagnostics(monitoring: monitor, engine: engine, hasAccess: { true })
        diagnostics.armRegistrationFailure()
        var applied = false
        XCTAssertThrowsError(try engine.start(now: Date(), authorized: { true }, apply: { applied = true }, matches: { true }))
        XCTAssertEqual(base.registered.count, 1)
        XCTAssertEqual(base.stopped, base.registered)
        XCTAssertTrue(base.registeredSessionIDs.isEmpty)
        XCTAssertFalse(applied)
        XCTAssertGreaterThan(shield.clearCount, 0)
        let failed = try XCTUnwrap(engine.snapshot().session)
        XCTAssertEqual(failed.phase, .terminal)
        XCTAssertEqual(failed.reason, .startFailed)
        try engine.acknowledgeTerminal(id: failed.id)
        let next = try engine.start(now: Date(), authorized: { true }, apply: {}, matches: { true })
        XCTAssertTrue(base.isRegistered(id: next.id))
        XCTAssertEqual(next.phase, .active)
    }
    func testSystemRegistrationErrorIsPreservedAndConsumesInjection() throws {
        let base = DiagnosticMonitoringSpy()
        let failing = DiagnosticMonitoring(base: base)
        base.shouldThrow = true
        failing.armFailure()
        XCTAssertThrowsError(try failing.register(id: UUID(), start: Date(), end: Date().addingTimeInterval(1500))) { error in
            XCTAssertTrue(error is DiagnosticFailure)
        }
        XCTAssertFalse(failing.isFailureArmed)
        base.shouldThrow = false
        try failing.register(id: UUID(), start: Date(), end: Date().addingTimeInterval(1500))
        XCTAssertEqual(base.registeredSessionIDs.count, 1)
    }
    func testSavedCallbackCannotClearNextSessionAndRejectsCurrentSession() throws {
        let base = DiagnosticMonitoringSpy(), shield = DiagnosticShieldSpy()
        let monitor = DiagnosticMonitoring(base: base)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = SessionControl(store: SharedControlStore(directory: directory), monitoring: monitor, shield: shield, breakSelection: DiagnosticBreakSelectionSpy(), everyday: ModelTestEverydayLayer())
        let diagnostics = DeviceDiagnostics(monitoring: monitor, engine: engine, hasAccess: { false })
        let first = try engine.start(now: Date(), authorized: { true }, apply: {}, matches: { true })
        diagnostics.capture(first)
        XCTAssertFalse(diagnostics.canReplay(current: first))
        XCTAssertThrowsError(try diagnostics.replay(current: first))
        try engine.finish(id: first.id, reason: .earlyExit, now: Date())
        try engine.acknowledgeTerminal(id: first.id)
        let next = try engine.start(now: Date(), authorized: { true }, apply: {}, matches: { true })
        let clears = shield.clearCount, stops = base.stopped
        XCTAssertTrue(diagnostics.canReplay(current: next))
        try diagnostics.replay(current: next)
        XCTAssertEqual(try engine.snapshot().session?.id, next.id)
        XCTAssertEqual(try engine.snapshot().session?.phase, .active)
        XCTAssertEqual(shield.clearCount, clears)
        XCTAssertEqual(base.stopped, stops)
        XCTAssertTrue(base.isRegistered(id: next.id))
    }
    func testDiagnosticMonitoringForwardsBreakRegistration() throws {
        let base = DiagnosticMonitoringSpy(), monitor = DiagnosticMonitoring(base: base), id = UUID()
        try monitor.registerBreak(id: id, index: 2, start: Date(), end: Date().addingTimeInterval(900), warning: 720)
        XCTAssertTrue(monitor.isBreakRegistered(id: id, index: 2)); XCTAssertEqual(base.breaks.first?.warning, 720)
        XCTAssertEqual(monitor.registeredBreaks.map(\.index), [2])
        monitor.stopBreak(id: id, index: 2)
        XCTAssertFalse(base.isBreakRegistered(id: id, index: 2))
    }
    func testDiagnosticMonitoringForwardsEverydayRegistration() throws {
        let base = DiagnosticMonitoringSpy(), monitor = DiagnosticMonitoring(base: base), revision = UUID()
        try monitor.registerEveryday(revision: revision, part: .window(2), start: 720, end: 780)
        XCTAssertEqual(base.everyday.first?.start, 720); XCTAssertEqual(base.everyday.first?.end, 780)
        XCTAssertEqual(monitor.registeredEveryday.map(\.part), [.window(2)]); XCTAssertEqual(monitor.registeredEveryday.first?.revision, revision)
        monitor.stopEveryday(revision: revision, part: .window(2))
        XCTAssertTrue(base.everyday.isEmpty)
    }
    func testEachRegistrationReportsOneTimingWithItsOperation() throws {
        let base = DiagnosticMonitoringSpy()
        var measured: [(ScreenTimeOperation, TimeInterval)] = []
        let monitor = DiagnosticMonitoring(base: base) { measured.append(($0, $1)) }
        try monitor.register(id: UUID(), start: Date(), end: Date().addingTimeInterval(1500))
        XCTAssertEqual(measured.map(\.0), [.register])
        try monitor.registerBreak(id: UUID(), index: 0, start: Date(), end: Date().addingTimeInterval(180), warning: 120)
        XCTAssertEqual(measured.map(\.0), [.register, .registerBreak])
        try monitor.registerEveryday(revision: UUID(), part: .window(0), start: 600, end: 660)
        XCTAssertEqual(measured.map(\.0), [.register, .registerBreak, .registerEveryday])
        XCTAssertTrue(measured.allSatisfy { $0.1 >= 0 })
        XCTAssertEqual(measured.map(\.0.rawValue), ["register", "register_break", "register_everyday"])
    }
    func testArmedFailureRegistersThenThrowsAndStillReportsTiming() throws {
        let base = DiagnosticMonitoringSpy()
        var measured: [ScreenTimeOperation] = []
        let monitor = DiagnosticMonitoring(base: base) { operation, _ in measured.append(operation) }
        monitor.armFailure()
        XCTAssertThrowsError(try monitor.register(id: UUID(), start: Date(), end: Date().addingTimeInterval(1500))) { error in
            XCTAssertEqual(error as? ControlIssue, .io)
        }
        XCTAssertEqual(base.registered.count, 1)
        XCTAssertEqual(measured, [.register])
    }
    func testBaseRegistrationErrorPropagatesAndReportsTiming() {
        let base = DiagnosticMonitoringSpy()
        base.shouldThrow = true
        var measured: [ScreenTimeOperation] = []
        let monitor = DiagnosticMonitoring(base: base) { operation, _ in measured.append(operation) }
        XCTAssertThrowsError(try monitor.register(id: UUID(), start: Date(), end: Date().addingTimeInterval(1500))) { error in
            XCTAssertTrue(error is DiagnosticFailure)
        }
        XCTAssertTrue(base.registered.isEmpty)
        XCTAssertEqual(measured, [.register])
    }
    func testMeasuredShieldApplyRunsOnceAndReportsApplyShield() {
        var applied = 0
        var measured: [ScreenTimeOperation] = []
        measureScreenTime(.applyShield, report: { operation, _ in measured.append(operation) }) { applied += 1 }
        XCTAssertEqual(applied, 1)
        XCTAssertEqual(measured, [.applyShield])
        XCTAssertEqual(ScreenTimeOperation.applyShield.rawValue, "apply_shield")
    }
    func testRegistrationProbeAlternatesIntervalsAndTimesSixRegistrations() {
        let center = ProbeCenterSpy(), now = Date(timeIntervalSince1970: 1_800_000_000)
        var clock: TimeInterval = 100, lines: [String] = []
        // Each registration takes 1 ms longer than the one before it.
        center.onStart = { clock += 0.001 * Double(center.started.count + 1) }
        let probe = RegistrationProbe(center: center, now: { now }, uptime: { clock }, log: { lines.append($0) })
        let samples = probe.run()
        let order = ["probe.current.1", "probe.future.1", "probe.current.2", "probe.future.2", "probe.current.3", "probe.future.3"]
        XCTAssertEqual(center.started.map(\.name), order)
        XCTAssertEqual(samples.map(\.interval), [.current, .future, .current, .future, .current, .future])
        XCTAssertEqual(samples.map(\.n), [1, 1, 2, 2, 3, 3])
        XCTAssertFalse(samples.contains { $0.failed })
        for (index, duration) in samples.map(\.duration).enumerated() { XCTAssertEqual(duration, 0.001 * Double(index + 1), accuracy: 1e-9) }
        for registration in center.started where registration.name.hasPrefix("probe.current.") {
            XCTAssertEqual(registration.start, now); XCTAssertEqual(registration.end, now.addingTimeInterval(20 * 60))
        }
        for registration in center.started where registration.name.hasPrefix("probe.future.") {
            XCTAssertEqual(registration.start, now.addingTimeInterval(2 * 60)); XCTAssertEqual(registration.end, now.addingTimeInterval(22 * 60))
        }
        // Each activity stops right after its own registration, and all six stop again at the end.
        XCTAssertEqual(center.events, order.flatMap { ["start \($0)", "stop \($0)"] } + ["stop \(order.joined(separator: ","))"])
        XCTAssertEqual(lines.first, "SCREEN_TIME_PROBE interval=current n=1 ms=1.000")
        XCTAssertEqual(lines.last, "SCREEN_TIME_PROBE interval=future n=3 ms=6.000")
        XCTAssertEqual(lines.count, 6)
    }
    func testRegistrationProbeStopsEveryActivityWhenOneRegistrationThrows() {
        let center = ProbeCenterSpy()
        center.failing = "probe.current.2"
        var lines: [String] = []
        let samples = RegistrationProbe(center: center, log: { lines.append($0) }).run()
        XCTAssertEqual(samples.count, 6)
        XCTAssertEqual(samples.filter(\.failed).map { RegistrationProbe.activityName($0.interval, $0.n) }, ["probe.current.2"])
        XCTAssertTrue(lines[2].hasPrefix("SCREEN_TIME_PROBE interval=current n=2 failed ms="))
        XCTAssertTrue(lines[2].contains("error="))
        XCTAssertEqual(center.stops.dropLast().flatMap { $0 }, RegistrationProbe.activityNames)
        XCTAssertEqual(center.stops.last, RegistrationProbe.activityNames)
        XCTAssertFalse(center.stops.contains { $0.isEmpty })
    }
    func testRegistrationProbeRefusesWhileASessionIsStoredOrRegistered() throws {
        let base = DiagnosticMonitoringSpy(), shield = DiagnosticShieldSpy(), center = ProbeCenterSpy()
        let monitor = DiagnosticMonitoring(base: base)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = SessionControl(store: SharedControlStore(directory: directory), monitoring: monitor, shield: shield, breakSelection: DiagnosticBreakSelectionSpy(), everyday: ModelTestEverydayLayer())
        let diagnostics = DeviceDiagnostics(monitoring: monitor, engine: engine, hasAccess: { true }, probe: RegistrationProbe(center: center, log: { _ in }))
        XCTAssertTrue(diagnostics.canProbeRegistration)
        let session = try engine.start(now: Date(), authorized: { true }, apply: {}, matches: { true })
        diagnostics.runRegistrationProbe()
        XCTAssertTrue(center.events.isEmpty)
        XCTAssertEqual(diagnostics.message, "세션이 남아 있어 비교하지 않았습니다. 세션을 끝낸 뒤 다시 눌러 주세요.")
        // A terminal session that is not acknowledged is still stored.
        try engine.finish(id: session.id, reason: .earlyExit, now: Date())
        diagnostics.runRegistrationProbe()
        XCTAssertTrue(center.events.isEmpty)
        try engine.acknowledgeTerminal(id: session.id)
        // A registered focus activity without a stored session also refuses.
        try base.register(id: UUID(), start: Date(), end: Date().addingTimeInterval(1500))
        diagnostics.runRegistrationProbe()
        XCTAssertTrue(center.events.isEmpty)
        base.stop(id: base.registered[1])
        let shieldsBefore = shield.clearCount, stopsBefore = base.stopped
        diagnostics.runRegistrationProbe()
        XCTAssertEqual(center.started.count, 6)
        XCTAssertTrue(diagnostics.message?.hasPrefix("등록 시간(ms) current: ") == true)
        XCTAssertNil(try engine.snapshot().session)
        XCTAssertEqual(shield.clearCount, shieldsBefore)
        XCTAssertEqual(base.stopped, stopsBefore)
        XCTAssertFalse(DeviceDiagnostics(monitoring: monitor, engine: engine, hasAccess: { true }).canProbeRegistration)
    }
    func testProbeActivityCallbackNeitherEndsSessionNorChangesShield() throws {
        let base = DiagnosticMonitoringSpy(), shield = DiagnosticShieldSpy()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = SessionControl(store: SharedControlStore(directory: directory), monitoring: base, shield: shield, breakSelection: DiagnosticBreakSelectionSpy(), everyday: ModelTestEverydayLayer())
        let session = try engine.start(now: Date(), authorized: { true }, apply: {}, matches: { true })
        let clears = shield.clearCount, stops = base.stopped
        for name in RegistrationProbe.activityNames {
            for kind in [CallbackKind.didStart, .willEndWarning, .didEnd] {
                try engine.handleCallback(activityName: name, kind: kind, now: Date(), authorized: true)
            }
        }
        XCTAssertEqual(try engine.snapshot().session?.id, session.id)
        XCTAssertEqual(try engine.snapshot().session?.phase, .active)
        XCTAssertEqual(shield.clearCount, clears)
        XCTAssertEqual(base.stopped, stops)
        XCTAssertTrue(base.isRegistered(id: session.id))
    }
}
private final class ProbeCenterSpy: RegistrationProbeCenter {
    var failing: String?
    var onStart: () -> Void = {}
    var started: [(name: String, start: Date, end: Date)] = []
    var stops: [[String]] = []
    var events: [String] = []
    func start(name: String, start: Date, end: Date) throws {
        events.append("start \(name)")
        onStart()
        if name == failing { throw DiagnosticFailure.registration }
        started.append((name, start, end))
    }
    func stop(names: [String]) { events.append("stop \(names.joined(separator: ","))"); stops.append(names) }
}
private enum DiagnosticFailure: Error { case registration }
private final class DiagnosticMonitoringSpy: MonitoringClient {
    var shouldThrow = false
    var registered: [UUID] = [], stopped: [UUID] = []
    private var current = Set<UUID>()
    var registeredSessionIDs: [UUID] { Array(current) }
    func register(id: UUID, start: Date, end: Date) throws { if shouldThrow { throw DiagnosticFailure.registration }; registered.append(id); current.insert(id) }
    func isRegistered(id: UUID) -> Bool { current.contains(id) }
    func stop(id: UUID) { stopped.append(id); current.remove(id); breaks.removeAll { $0.id == id } }
    var breaks: [(id: UUID, index: Int, warning: TimeInterval)] = []
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws { breaks.append((id, index, warning)) }
    func isBreakRegistered(id: UUID, index: Int) -> Bool { breaks.contains { $0.id == id && $0.index == index } }
    var registeredBreaks: [(id: UUID, index: Int)] { breaks.map { (id: $0.id, index: $0.index) } }
    func stopBreak(id: UUID, index: Int) { breaks.removeAll { $0.id == id && $0.index == index } }
    var everyday: [(revision: UUID, part: EverydayPart, start: Int, end: Int)] = []
    func registerEveryday(revision: UUID, part: EverydayPart, start: Int, end: Int) throws { everyday.append((revision, part, start, end)) }
    var registeredEveryday: [(revision: UUID, part: EverydayPart)] { everyday.map { (revision: $0.revision, part: $0.part) } }
    func stopEveryday(revision: UUID, part: EverydayPart) { everyday.removeAll { $0.revision == revision && $0.part == part } }
}
private final class DiagnosticBreakSelectionSpy: BreakSelectionStore {
    func restoreShield(id: UUID) -> Bool { false }
    func exists(id: UUID) -> Bool { false }
    func remove(id: UUID) {}
    func removeAll(except id: UUID?) {}
}
private final class DiagnosticShieldSpy: ShieldClient {
    var clearCount = 0
    func clear() { clearCount += 1 }
}
#endif
