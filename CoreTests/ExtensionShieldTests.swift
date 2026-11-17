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
/// Counts the stops, and the stops made while another file descriptor finds the shared lock busy.
private final class LockObservingMonitoring: MonitoringClient {
    let base: FakeMonitoring, store: SharedControlStore
    var stops = 0, stopsWhileLocked = 0
    init(base: FakeMonitoring, store: SharedControlStore) { self.base = base; self.store = store }
    private func observe() { stops += 1; if store.isLockBusy() { stopsWhileLocked += 1 } }
    var registeredSessionIDs: [UUID] { base.registeredSessionIDs }
    func register(id: UUID, start: Date, end: Date) throws { try base.register(id: id, start: start, end: end) }
    func isRegistered(id: UUID) -> Bool { base.isRegistered(id: id) }
    func stop(id: UUID) { observe(); base.stop(id: id) }
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws {
        try base.registerBreak(id: id, index: index, start: start, end: end, warning: warning)
    }
    func isBreakRegistered(id: UUID, index: Int) -> Bool { base.isBreakRegistered(id: id, index: index) }
    var registeredBreaks: [(id: UUID, index: Int)] { base.registeredBreaks }
    func stopBreak(id: UUID, index: Int) { observe(); base.stopBreak(id: id, index: index) }
    func registerEveryday(revision: UUID, part: EverydayPart, start: Int, end: Int) throws {
        try base.registerEveryday(revision: revision, part: part, start: start, end: end)
    }
    var registeredEveryday: [(revision: UUID, part: EverydayPart)] { base.registeredEveryday }
    func stopEveryday(revision: UUID, part: EverydayPart) { observe(); base.stopEveryday(revision: revision, part: part) }
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
    func testExtensionSectionChangesNoEverydayActivity() throws {
        let everyday = ContainerEveryday(forbidden: true)
        everyday.schedule = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 0, rangeEnd: 23 * 60 + 55, windows: [])
        let stale = UUID()
        try monitoring.registerEveryday(revision: stale, part: .range, start: 0, end: 60)
        let engine = extensionEngine(everyday: everyday)
        try filterOn(engine, at: t0)
        try engine.endFromFocusFilter(now: t0.addingTimeInterval(60), authorized: .denied)
        // Neither the missing revision is registered nor the stale one stopped, also after a `denied` read (2026-11-17 lock-order amendment, decision 7).
        XCTAssertEqual(monitoring.registeredEveryday.map(\.revision), [stale])
    }

    // MARK: Lock order (2026-11-17 lock-order amendment)

    func testExtensionStartDelaysOnlyTheFirstRegistration() throws {
        let session = try filterOn(extensionEngine(), at: t0)
        let interval = try XCTUnwrap(monitoring.intervals[session.id])
        XCTAssertEqual(interval.0, t0.addingTimeInterval(SessionControl.extensionStartDelay))
        XCTAssertEqual(interval.1, session.expiresAt)
        XCTAssertEqual(session.startedAt, t0, "focused time still starts at the call")
    }
    func testExtensionLateRolloverKeepsTheStartAndTheSession() throws {
        let engine = extensionEngine()
        let session = try filterOn(engine, at: t0)
        // A catch-up 20 minutes after a missed rollover of a 25-minute session.
        try engine.reconcile(now: session.expiresAt.addingTimeInterval(20 * 60), authorized: .unknown)
        let interval = try XCTUnwrap(monitoring.intervals[session.id])
        XCTAssertEqual(interval.0, t0)
        XCTAssertGreaterThanOrEqual(interval.1.timeIntervalSince(interval.0), 15 * 60)
        XCTAssertEqual(try stored()?.phase, .active)
        XCTAssertEqual(try stored()?.expiresAt, t0.addingTimeInterval(3000))
    }
    func testExtensionEndStopsAfterTheLockIsReleased() throws {
        let observing = LockObservingMonitoring(base: monitoring, store: store)
        let engine = SessionControl(store: store, monitoring: observing, shield: ContainerShield(forbidden: true), breakSelection: ContainerBreakSelection(forbidden: true),
                                    everyday: ContainerEveryday(forbidden: true), role: .intentsExtension)
        let session = try filterOn(engine, at: t0)
        try engine.endFromFocusFilter(now: t0.addingTimeInterval(60), authorized: .unknown)
        XCTAssertEqual(observing.stops, 1)
        XCTAssertEqual(observing.stopsWhileLocked, 0)
        XCTAssertFalse(monitoring.isRegistered(id: session.id))
        XCTAssertEqual(try stored()?.phase, .terminal)
    }
    func testExtensionRollbackStopsAfterTheLockAlsoWhenTheSectionThrew() throws {
        let observing = LockObservingMonitoring(base: monitoring, store: store)
        let engine = SessionControl(store: store, monitoring: observing, shield: ContainerShield(forbidden: true), breakSelection: ContainerBreakSelection(forbidden: true),
                                    everyday: ContainerEveryday(forbidden: true), role: .intentsExtension)
        monitoring.hideRegistration = true
        XCTAssertThrowsError(try engine.startFromFocusFilter(now: t0, length: 1500, authorized: { .unknown }, selectionReady: true, apply: {}, matches: { true }))
        XCTAssertEqual(observing.stops, 1)
        XCTAssertEqual(observing.stopsWhileLocked, 0)
        XCTAssertTrue(monitoring.intervals.isEmpty)
        XCTAssertEqual(try stored()?.reason, .startFailed)
    }
    func testAppSectionStillStopsInsideTheLock() throws {
        let observing = LockObservingMonitoring(base: monitoring, store: store)
        let app = SessionControl(store: store, monitoring: observing, shield: appShield, breakSelection: appCopies, everyday: appEveryday,
                                 role: .appContainer(applyFocusSelection: { true }))
        let session = try app.start(now: t0, authorized: { .approved }, apply: { self.appShield.on = true }, matches: { self.appShield.on })
        try app.finish(id: session.id, reason: .earlyExit, now: t0.addingTimeInterval(60))
        XCTAssertEqual(observing.stopsWhileLocked, observing.stops)
        XCTAssertGreaterThan(observing.stops, 0)
    }
    func testDeferredStopsReadAsNotRegisteredAndRunInOrder() throws {
        let a = UUID(), b = UUID(), revision = UUID()
        try monitoring.register(id: a, start: t0, end: t0.addingTimeInterval(1500))
        try monitoring.register(id: b, start: t0, end: t0.addingTimeInterval(1500))
        try monitoring.registerBreak(id: b, index: 1, start: t0, end: t0.addingTimeInterval(900), warning: 180)
        try monitoring.registerEveryday(revision: revision, part: .range, start: 0, end: 60)
        let deferred = DeferredStopMonitoring(base: monitoring)
        deferred.stop(id: a); deferred.stopBreak(id: b, index: 1); deferred.stopEveryday(revision: revision, part: .range)
        XCTAssertFalse(deferred.isRegistered(id: a)); XCTAssertTrue(deferred.isRegistered(id: b))
        XCTAssertFalse(deferred.isBreakRegistered(id: b, index: 1)); XCTAssertTrue(deferred.registeredEveryday.isEmpty)
        XCTAssertEqual(Set(deferred.registeredSessionIDs), [b])
        // Nothing is stopped before the flush.
        XCTAssertTrue(monitoring.isRegistered(id: a)); XCTAssertTrue(monitoring.isBreakRegistered(id: b, index: 1))
        // A new registration of a recorded name cancels its stop.
        try deferred.register(id: a, start: t0, end: t0.addingTimeInterval(3000))
        deferred.flush()
        XCTAssertTrue(monitoring.isRegistered(id: a)); XCTAssertTrue(monitoring.isRegistered(id: b))
        XCTAssertFalse(monitoring.isBreakRegistered(id: b, index: 1)); XCTAssertTrue(monitoring.registeredEveryday.isEmpty)
        XCTAssertEqual(deferred.stops, [])
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
