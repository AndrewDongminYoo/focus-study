#if DEBUG
import XCTest

@MainActor final class DeviceDiagnosticsTests: XCTestCase {
    func testInjectedFailureStopsRealBoundaryRegistrationAndDoesNotRepeat() throws {
        let base = DiagnosticMonitoringSpy(), shield = DiagnosticShieldSpy()
        let monitor = DiagnosticMonitoring(base: base)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = SessionControl(store: SharedControlStore(directory: directory), monitoring: monitor, shield: shield)
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
        let engine = SessionControl(store: SharedControlStore(directory: directory), monitoring: monitor, shield: shield)
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
}
private enum DiagnosticFailure: Error { case registration }
private final class DiagnosticMonitoringSpy: MonitoringClient {
    var shouldThrow = false
    var registered: [UUID] = [], stopped: [UUID] = []
    private var current = Set<UUID>()
    var registeredSessionIDs: [UUID] { Array(current) }
    func register(id: UUID, start: Date, end: Date) throws { if shouldThrow { throw DiagnosticFailure.registration }; registered.append(id); current.insert(id) }
    func isRegistered(id: UUID) -> Bool { current.contains(id) }
    func stop(id: UUID) { stopped.append(id); current.remove(id) }
}
private final class DiagnosticShieldSpy: ShieldClient {
    var clearCount = 0
    func clear() { clearCount += 1 }
}
#endif
