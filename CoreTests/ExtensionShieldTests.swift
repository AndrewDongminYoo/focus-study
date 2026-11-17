import XCTest
@testable import FocusCore

/// The focus store of one container. In the extension role every call fails the test (2026-11-16 shield amendment, decision 1).
private final class ContainerShield: ShieldClient {
    let forbidden: Bool
    var on = false, clears = 0
    init(forbidden: Bool) { self.forbidden = forbidden }
    func clear() { if forbidden { XCTFail("shield.clear in the extension") }; on = false; clears += 1 }
    var hasShield: Bool { if forbidden { XCTFail("shield.hasShield in the extension") }; return on }
}
/// The everyday file and store; in the extension role every store call fails the test, and `load` stays allowed (decision 10).
private final class ContainerEveryday: EverydayLayerStore {
    let forbidden: Bool
    var schedule: EverydaySchedule?, on = false
    init(forbidden: Bool) { self.forbidden = forbidden }
    private func check(_ call: String) { if forbidden { XCTFail("everyday.\(call) in the extension") } }
    func load() throws -> EverydaySchedule? { schedule }
    func storeMatches() -> Bool { check("storeMatches"); return on }
    func applyStored() -> Bool { check("applyStored"); on = true; return true }
    var hasShield: Bool { check("hasShield"); return on }
    func clearShield() { check("clearShield"); on = false }
}
/// Break copies; in the extension role a restore fails the test, and the file calls stay allowed.
private final class ContainerBreakSelection: BreakSelectionStore {
    let forbidden: Bool
    var copies = Set<UUID>()
    init(forbidden: Bool) { self.forbidden = forbidden }
    func restoreShield(id: UUID) -> Bool { if forbidden { XCTFail("restoreShield in the extension") }; return copies.contains(id) }
    func exists(id: UUID) -> Bool { copies.contains(id) }
    func remove(id: UUID) { copies.remove(id) }
    func removeAll(except id: UUID?) { copies = copies.filter { $0 == id } }
}
private final class CountingMarkers: RegistrationMarkerStore {
    var writes = 0
    func read() -> RegistrationMarker? { nil }
    func write(_ marker: RegistrationMarker) throws { writes += 1 }
    func delete() throws {}
    func uptime() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}

final class ExtensionShieldTests: XCTestCase {
    private var directory: URL!
    private let monitoring = FakeMonitoring()
    private let markers = CountingMarkers()
    private var store: SharedControlStore!
    /// The process container's focus store, shared by the app and the Monitor.
    private let appShield = ContainerShield(forbidden: false)
    private let appEveryday = ContainerEveryday(forbidden: false)
    private let appCopies = ContainerBreakSelection(forbidden: false)
    private var groupSelectionApplies = true
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = SharedControlStore(directory: directory, markers: markers)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    /// An engine of the App Intents extension, with stores that fail the test when called.
    private func extensionEngine(everyday: ContainerEveryday = ContainerEveryday(forbidden: true),
                                 copies: ContainerBreakSelection = ContainerBreakSelection(forbidden: true)) -> SessionControl {
        SessionControl(store: store, monitoring: monitoring, shield: ContainerShield(forbidden: true), breakSelection: copies, everyday: everyday, role: .intentsExtension)
    }
    /// An engine of the app or the Monitor; its group selection apply turns the app container's shield on.
    private func appEngine() -> SessionControl {
        SessionControl(store: store, monitoring: monitoring, shield: appShield, breakSelection: appCopies, everyday: appEveryday,
                       role: .appContainer(applyFocusSelection: { [self] in
                           guard groupSelectionApplies else { appShield.on = true; return false }
                           appShield.on = true; return true
                       }))
    }
    @discardableResult
    private func filterOn(_ engine: SessionControl, at now: Date) throws -> ControlSession {
        let result = try engine.startFromFocusFilter(now: now, length: 1500, authorized: { .unknown }, selectionReady: true,
                                                     apply: { XCTFail("apply in the extension") }, matches: { XCTFail("matches in the extension"); return false })
        guard case .started(let session) = result else { XCTFail("not started: \(result)"); throw FixtureFailure.injected }
        return session
    }
    private func stored() throws -> ControlSession? { try store.withExclusiveAccess { try $0.load().session } }

    // MARK: Extension sections

    func testExtensionStartSavesAPendingShieldWithoutStoreCallsOrMarkers() throws {
        let session = try filterOn(extensionEngine(), at: t0)
        XCTAssertEqual(session.phase, .active); XCTAssertEqual(session.shieldPending, true)
        XCTAssertEqual(try stored()?.shieldPending, true)
        XCTAssertTrue(monitoring.isRegistered(id: session.id))
        XCTAssertEqual(markers.writes, 0, "an extension section writes no marker (decision 9)")
    }
    func testExtensionFocusOffEndsAPendingSessionWithoutStoreCallsAndTheStoreReloads() throws {
        let engine = extensionEngine()
        let session = try filterOn(engine, at: t0)
        XCTAssertTrue(try engine.endFromFocusFilter(now: t0.addingTimeInterval(60), authorized: .unknown))
        let ended = try XCTUnwrap(stored())
        XCTAssertEqual(ended.phase, .terminal); XCTAssertEqual(ended.reason, .earlyExit); XCTAssertNil(ended.shieldPending)
        XCTAssertFalse(monitoring.isRegistered(id: session.id))
        XCTAssertEqual(markers.writes, 0)
    }
    func testExtensionFailedRegistrationRollsBackWithoutStoreCalls() throws {
        monitoring.failRegistration = true
        XCTAssertThrowsError(try extensionEngine().startFromFocusFilter(now: t0, length: 1500, authorized: { .unknown }, selectionReady: true, apply: {}, matches: { true }))
        let ended = try XCTUnwrap(stored())
        XCTAssertEqual(ended.reason, .startFailed); XCTAssertNil(ended.shieldPending)
    }
    func testExtensionReconcileLeavesALateBreakForTheAppContainer() throws {
        let copies = ContainerBreakSelection(forbidden: true)
        var session = ControlSession(startedAt: t0); session.phase = .onBreak; session.breaksTaken = 1
        session.pausedAt = t0.addingTimeInterval(100); session.breakEndsAt = t0.addingTimeInterval(280); session.deadlineCredit = 195
        try store.withExclusiveAccess { try $0.save(ControlEnvelope(session: session)) }
        try monitoring.register(id: session.id, start: t0, end: t0.addingTimeInterval(2100))
        try monitoring.registerBreak(id: session.id, index: 1, start: t0.addingTimeInterval(100), end: t0.addingTimeInterval(1000), warning: 180)
        copies.copies = [session.id]
        try extensionEngine(copies: copies).reconcile(now: t0.addingTimeInterval(300), authorized: .unknown)
        XCTAssertEqual(try stored()?.phase, .onBreak, "the extension cannot re-block, so it never commits breakOver")
    }
    func testExtensionConvergenceRegistersEverydayActivitiesWithoutStoreCalls() throws {
        let everyday = ContainerEveryday(forbidden: true)
        everyday.schedule = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 0, rangeEnd: 23 * 60 + 55, windows: [])
        try filterOn(extensionEngine(everyday: everyday), at: t0)
        XCTAssertEqual(monitoring.registeredEveryday.map(\.revision), [everyday.schedule!.revision])
    }

    // MARK: Sections in the app container

    func testMonitorStartCallbackShieldsAPendingSession() throws {
        let session = try filterOn(extensionEngine(), at: t0)
        try appEngine().handleCallback(activityName: session.activityName, kind: .didStart, now: t0.addingTimeInterval(1), authorized: .unknown)
        XCTAssertTrue(appShield.on); XCTAssertNil(try stored()?.shieldPending); XCTAssertEqual(try stored()?.phase, .active)
    }
    func testMonitorStartCallbackEndsAsStartFailedWhenTheSelectionDoesNotMatch() throws {
        groupSelectionApplies = false
        let session = try filterOn(extensionEngine(), at: t0)
        try appEngine().handleCallback(activityName: session.activityName, kind: .didStart, now: t0.addingTimeInterval(1), authorized: .unknown)
        let ended = try XCTUnwrap(stored())
        XCTAssertEqual(ended.phase, .terminal); XCTAssertEqual(ended.reason, .startFailed); XCTAssertNil(ended.shieldPending)
        XCTAssertFalse(appShield.on, "the rollback lifts what the apply wrote")
        XCTAssertFalse(monitoring.isRegistered(id: session.id))
    }
    func testMonitorEndCallbackLiftsTheShieldOfAnEndedSession() throws {
        let engine = extensionEngine(), app = appEngine()
        let session = try filterOn(engine, at: t0)
        try app.handleCallback(activityName: session.activityName, kind: .didStart, now: t0.addingTimeInterval(1), authorized: .unknown)
        try engine.endFromFocusFilter(now: t0.addingTimeInterval(60), authorized: .unknown)
        XCTAssertTrue(appShield.on, "the extension cannot lift it")
        try app.handleCallback(activityName: session.activityName, kind: .didEnd, now: t0.addingTimeInterval(61), authorized: .unknown)
        XCTAssertFalse(appShield.on)
    }
    func testLateEndCallbackOfAnEarlierSessionKeepsTheShieldOfARunningOne() throws {
        let engine = extensionEngine(), app = appEngine()
        let first = try filterOn(engine, at: t0)
        try engine.endFromFocusFilter(now: t0.addingTimeInterval(60), authorized: .unknown)
        // The app imports the terminal session; a manual session then runs with its own shield.
        try app.acknowledgeTerminal(id: first.id)
        _ = try app.start(now: t0.addingTimeInterval(70), authorized: { .approved }, apply: { self.appShield.on = true }, matches: { self.appShield.on })
        try app.handleCallback(activityName: first.activityName, kind: .didEnd, now: t0.addingTimeInterval(80), authorized: .unknown)
        XCTAssertTrue(appShield.on)
    }
    func testAppReconcileRepairsALostStartCallback() throws {
        try filterOn(extensionEngine(), at: t0)
        try appEngine().reconcile(now: t0.addingTimeInterval(30), authorized: .unknown)
        XCTAssertTrue(appShield.on); XCTAssertNil(try stored()?.shieldPending)
    }
    func testAppReconcileRepairsALostEndCallback() throws {
        appShield.on = true
        try appEngine().reconcile(now: t0, authorized: .unknown)
        XCTAssertFalse(appShield.on)
        appShield.on = true
        let terminal = { () -> ControlSession in
            var s = ControlSession(startedAt: self.t0); s.phase = .terminal; s.reason = .earlyExit; s.observedAt = self.t0.addingTimeInterval(60); return s
        }()
        try store.withExclusiveAccess { try $0.save(ControlEnvelope(session: terminal)) }
        try appEngine().reconcile(now: t0.addingTimeInterval(70), authorized: .unknown)
        XCTAssertFalse(appShield.on)
    }
    func testAManualSessionKeepsItsShieldThroughTheRepair() throws {
        let app = appEngine()
        _ = try app.start(now: t0, authorized: { .approved }, apply: { self.appShield.on = true }, matches: { self.appShield.on })
        try app.reconcile(now: t0.addingTimeInterval(30), authorized: .unknown)
        XCTAssertTrue(appShield.on); XCTAssertEqual(appShield.clears, 0)
    }
    func testRepairDoesNotShieldAPendingSessionWhoseFailedEndStoppedIt() throws {
        let memory = MemoryControlStore(), shield = ContainerShield(forbidden: false)
        var session = ControlSession(startedAt: t0); session.phase = .active; session.shieldPending = true; session.origin = .focusFilter
        memory.envelope = ControlEnvelope(session: session)
        try monitoring.register(id: session.id, start: t0, end: t0.addingTimeInterval(1500))
        let app = SessionControl(store: memory, monitoring: monitoring, shield: shield, breakSelection: appCopies, everyday: appEveryday,
                                 role: .appContainer(applyFocusSelection: { shield.on = true; return true }))
        memory.failAllWrites = true
        XCTAssertThrowsError(try app.finish(id: session.id, reason: .earlyExit, now: t0.addingTimeInterval(60)))
        XCTAssertFalse(monitoring.isRegistered(id: session.id))
        XCTAssertFalse(shield.on, "no callback is left to lift a shield that the repair applies after the cleanup")
    }
    func testRepairDoesNotShieldAPendingSessionThatAReadFailureStopped() throws {
        let memory = MemoryControlStore(), shield = ContainerShield(forbidden: false)
        var session = ControlSession(startedAt: t0); session.phase = .active; session.shieldPending = true; session.origin = .focusFilter
        memory.envelope = ControlEnvelope(session: session)
        try monitoring.register(id: session.id, start: t0, end: t0.addingTimeInterval(1500))
        let app = SessionControl(store: memory, monitoring: monitoring, shield: shield, breakSelection: appCopies, everyday: appEveryday,
                                 role: .appContainer(applyFocusSelection: { shield.on = true; return true }))
        // The read-failure cleanup stops the session's monitoring and leaves the pending session on disk.
        memory.failRead = true
        XCTAssertThrowsError(try app.reconcile(now: t0.addingTimeInterval(30), authorized: .unknown))
        memory.failRead = false
        // An everyday edge returns before the reconcile of an `active` session; the repair must not shield it without its callbacks.
        try app.handleCallback(activityName: ActivityNames.everyday(revision: UUID(), part: .range), kind: .didStart, now: t0.addingTimeInterval(40), authorized: .unknown)
        XCTAssertFalse(monitoring.isRegistered(id: session.id))
        XCTAssertFalse(shield.on, "no callback is left to lift a shield that the repair applies after the cleanup")
        // The next reconcile ends the session, as for any session whose registration is gone.
        try app.reconcile(now: t0.addingTimeInterval(50), authorized: .unknown)
        XCTAssertEqual(memory.envelope.session?.reason, .recoveryInterrupted); XCTAssertNil(memory.envelope.session?.shieldPending)
    }
    func testBreakRequestOfAPendingSessionWaitsForTheRepair() throws {
        let session = try filterOn(extensionEngine(), at: t0)
        let app = appEngine()
        XCTAssertThrowsError(try app.requestBreak(id: session.id, now: t0.addingTimeInterval(30))) { XCTAssertEqual($0 as? ControlIssue, .breakUnavailable) }
        XCTAssertTrue(appShield.on, "the section that refused also shielded the session")
        XCTAssertEqual(try app.requestBreak(id: session.id, now: t0.addingTimeInterval(31)).phase, .waiting)
        XCTAssertEqual(try stored()?.phase, .waiting)
    }

    // MARK: Stored values

    func testStoreRejectsAPendingShieldOutsideActive() throws {
        var session = ControlSession(startedAt: t0); session.phase = .waiting; session.pausedAt = t0.addingTimeInterval(100); session.waitEndsAt = t0.addingTimeInterval(115)
        session.shieldPending = true
        try store.withExclusiveAccess { try $0.save(ControlEnvelope(session: session)) }
        XCTAssertThrowsError(try stored()) { XCTAssertEqual($0 as? ControlIssue, .invalidState) }
        session.phase = .active; session.pausedAt = nil; session.waitEndsAt = nil
        try store.withExclusiveAccess { try $0.save(ControlEnvelope(session: session)) }
        XCTAssertEqual(try stored()?.shieldPending, true)
    }
}
