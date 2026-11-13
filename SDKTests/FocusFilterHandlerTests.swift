import XCTest
import FamilyControls
import SwiftData

/// Records every request, so that a test can prove that the filter path never asks for access.
@MainActor final class RecordingAuthorization: AuthorizationProviding {
    var status: AccessStatus = .approved
    private(set) var requests = 0
    func requestIndividual() async { requests += 1 }
    func refresh() {}
    /// `checking` and `notRequested` are `.notDetermined`, which the engine reads as `unknown`.
    func accessState() -> AccessState { status == .approved ? .approved : status == .denied ? .denied : .unknown }
}
@MainActor final class FilterTestHistory: SessionHistoryProviding {
    var failSave = false
    private(set) var imported: [UUID] = []
    let acknowledge: (UUID) throws -> Void
    init(acknowledge: @escaping (UUID) throws -> Void) { self.acknowledge = acknowledge }
    func importTerminal(_ session: ControlSession) throws {
        if failSave { throw ModelTestError.storage }
        if !imported.contains(session.id) { imported.append(session.id) }
        try acknowledge(session.id)
    }
    func records(on date: Date, calendar: Calendar) throws -> [SessionRecord] { [] }
    func streak(at date: Date, calendar: Calendar) throws -> Int { 0 }
}

@MainActor final class FocusFilterHandlerTests: XCTestCase {
    @MainActor private struct Rig {
        let handler: FocusFilterHandler
        let services: FocusServices
        let store: ModelTestStore
        let shield: ModelTestShield
        let history: FilterTestHistory
        let authorization: RecordingAuthorization
        let selection: ModelTestSelection
        let pauses: Box<[TimeInterval]>
        let refreshes: Box<Int>
        let applied: Box<[FamilyActivitySelection]>
        /// Runs inside the injected pause, so a test can send a second call while the first one waits to retry.
        let onPause: Box<(@MainActor () async -> Void)?>
        var engine: SessionControl { services.engine }
    }
    final class Box<T> { var value: T; init(_ value: T) { self.value = value } }
    private var authorizations: [RecordingAuthorization] = []
    override func tearDown() async throws {
        // No test of this file may request access through the filter path.
        for authorization in authorizations { XCTAssertEqual(authorization.requests, 0) }
        authorizations = []
    }
    private func rig(now: @escaping () -> Date = Date.init) -> Rig {
        let store = ModelTestStore(), shield = ModelTestShield(), authorization = RecordingAuthorization(), selection = ModelTestSelection()
        authorizations.append(authorization)
        let engine = SessionControl(store: store, monitoring: ModelTestMonitoring(), shield: shield, breakSelection: ModelTestBreakSelection(), everyday: ModelTestEverydayLayer())
        let applied = Box<[FamilyActivitySelection]>([])
        var services = FocusServices(authorization: authorization, selection: selection, engine: engine,
                                     applySelection: { applied.value.append($0); shield.applied = true }, matchesSelection: { _ in shield.applied }, isFixture: true)
        services.settings = FocusSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let history = FilterTestHistory(acknowledge: engine.acknowledgeTerminal)
        let pauses = Box<[TimeInterval]>([]), refreshes = Box(0), onPause = Box<(@MainActor () async -> Void)?>(nil)
        let handler = FocusFilterHandler(services: services, history: history, refresh: { refreshes.value += 1 }, now: now,
                                         pause: { pauses.value.append($0); await onPause.value?() })
        return Rig(handler: handler, services: services, store: store, shield: shield, history: history, authorization: authorization, selection: selection,
                   pauses: pauses, refreshes: refreshes, applied: applied, onPause: onPause)
    }
    private func stored(_ rig: Rig) -> ControlSession? { rig.store.envelope.session }

    func testOnCallImportsAPendingTerminalThenStarts() async throws {
        for expired in [true, false] {
            let rig = rig()
            let earlier = try rig.engine.start(now: Date().addingTimeInterval(expired ? -1500 : -60), authorized: { .approved }, apply: {}, matches: { true })
            if !expired { try rig.engine.finish(id: earlier.id, reason: .earlyExit, now: Date()) }
            await rig.handler.focusDidChange(startsSession: true)
            XCTAssertEqual(rig.history.imported, [earlier.id], "\(expired)")
            let session = try XCTUnwrap(stored(rig), "\(expired)")
            XCTAssertNotEqual(session.id, earlier.id); XCTAssertEqual(session.origin, .focusFilter); XCTAssertEqual(session.phase, .active)
            let pending = rig.services.settings.pendingCompletion
            XCTAssertEqual(pending?.id, expired ? earlier.id : nil, "\(expired)")
            if expired { XCTAssertEqual(pending?.length, 1500) }
            XCTAssertNil(rig.services.settings.lastFilterRefusal)
        }
    }
    func testFailedImportRefusesWithHistory() async throws {
        let rig = rig()
        let earlier = try rig.engine.start(now: Date().addingTimeInterval(-60), authorized: { .approved }, apply: {}, matches: { true })
        try rig.engine.finish(id: earlier.id, reason: .earlyExit, now: Date())
        rig.history.failSave = true
        await rig.handler.focusDidChange(startsSession: true)
        XCTAssertEqual(rig.services.settings.lastFilterRefusal?.reason, .history)
        XCTAssertEqual(stored(rig)?.id, earlier.id); XCTAssertEqual(stored(rig)?.phase, .terminal)
        XCTAssertTrue(rig.applied.value.isEmpty)
    }
    func testOnCallUsesTheFocusLengthAndTheFrozenSelection() async throws {
        let rig = rig()
        rig.services.settings.lengthMinutes = 40
        rig.selection.selection.applicationTokens = syntheticApps(0..<2); rig.selection.counts = (2, 0, 0)
        await rig.handler.focusDidChange(startsSession: true)
        let session = try XCTUnwrap(stored(rig))
        XCTAssertEqual(session.expiresAt.timeIntervalSince(session.startedAt), 2400)
        XCTAssertEqual(rig.applied.value.map(\.applicationTokens), [syntheticApps(0..<2)])
    }
    func testEmptyOrInvalidSelectionRefusesWithSelection() async throws {
        for counts in [(0, 0, 0), (51, 0, 0), (1, 0, 1)] {
            let rig = rig(); rig.selection.counts = counts
            await rig.handler.focusDidChange(startsSession: true)
            XCTAssertEqual(rig.services.settings.lastFilterRefusal?.reason, .selection, "\(counts)")
            XCTAssertNil(stored(rig), "\(counts)"); XCTAssertTrue(rig.applied.value.isEmpty, "\(counts)")
        }
    }
    func testRefusalIsStoredAndAStartClearsIt() async throws {
        let time = Date(timeIntervalSinceNow: -10)
        let rig = rig(now: { time })
        rig.selection.counts = (0, 0, 0)
        await rig.handler.focusDidChange(startsSession: true)
        XCTAssertEqual(rig.services.settings.lastFilterRefusal?.reason, .selection); XCTAssertEqual(rig.services.settings.lastFilterRefusal?.at, time)
        await rig.handler.focusDidChange(startsSession: false)
        rig.selection.counts = (1, 0, 0)
        await rig.handler.focusDidChange(startsSession: true)
        XCTAssertNil(rig.services.settings.lastFilterRefusal); XCTAssertEqual(stored(rig)?.origin, .focusFilter)
    }
    func testThrownErrorIsStoredAsError() async throws {
        let rig = rig(); rig.store.failRead = true
        await rig.handler.focusDidChange(startsSession: true)
        XCTAssertEqual(rig.services.settings.lastFilterRefusal?.reason, .error); XCTAssertTrue(rig.applied.value.isEmpty)
    }
    func testLockTimeoutIsRetriedFourTimesWithAFreshTime() async throws {
        let base = Date(timeIntervalSinceNow: -100)
        for timeouts in [4, 5] {
            var ticks = 0.0
            let rig = rig(now: { ticks += 1; return base.addingTimeInterval(ticks) })
            // The on call takes the lock for the reconcile (1), the snapshot (2), then the start section (3 and later).
            rig.store.lockTimeoutCalls = Set((3..<(3 + timeouts)).map { rig.store.calls + $0 })
            await rig.handler.focusDidChange(startsSession: true)
            XCTAssertEqual(rig.pauses.value, Array(repeating: FocusFilterHandler.retryPause, count: 4), "\(timeouts)")
            if timeouts == 4 {
                // The reconcile read time 1; the start attempts read times 2 to 6, and the fifth attempt started the session.
                XCTAssertEqual(stored(rig)?.startedAt, base.addingTimeInterval(6)); XCTAssertNil(rig.services.settings.lastFilterRefusal)
            } else {
                XCTAssertNil(stored(rig)); XCTAssertEqual(rig.services.settings.lastFilterRefusal?.reason, .error)
            }
        }
    }
    /// Sends `second` once during the first pause and lets the main actor run it, as a call from the system would arrive.
    private func sendDuringFirstPause(_ rig: Rig, _ second: @escaping @MainActor () async -> Void) -> Box<Task<Void, Never>?> {
        let sent = Box<Task<Void, Never>?>(nil)
        rig.onPause.value = {
            rig.onPause.value = nil
            sent.value = Task { await second() }
            for _ in 0..<50 { await Task.yield() }
        }
        return sent
    }
    func testOffCallDuringTheRetryPauseOfAnOnCallEndsTheSessionItStarts() async throws {
        let rig = rig()
        // The on call takes the lock for the reconcile (1), the snapshot (2), then the start section (3), which times out once.
        rig.store.lockTimeoutCalls = [rig.store.calls + 3]
        // The off call takes the path of `FocusRuntimeHolder`, which does not go through the handler instance.
        let off = sendDuringFirstPause(rig) {
            await FocusFilterHandler.end(engine: rig.engine, authorization: rig.authorization, settings: rig.services.settings, now: Date.init, pause: { _ in })
        }
        await rig.handler.focusDidChange(startsSession: true)
        await off.value?.value
        XCTAssertEqual(rig.pauses.value, [FocusFilterHandler.retryPause])
        let session = try XCTUnwrap(stored(rig))
        XCTAssertEqual(session.origin, .focusFilter); XCTAssertEqual(session.phase, .terminal); XCTAssertEqual(session.reason, .earlyExit)
        XCTAssertNil(rig.store.envelope.filterActivation); XCTAssertFalse(rig.shield.applied)
    }
    func testOnCallDuringTheRetryPauseOfAnOffCallStartsAfterTheEnd() async throws {
        let rig = rig()
        await rig.handler.focusDidChange(startsSession: true)
        let first = try XCTUnwrap(stored(rig))
        // The off call's end section is its first lock call, and it times out once.
        rig.store.lockTimeoutCalls = [rig.store.calls + 1]
        let on = sendDuringFirstPause(rig) { await rig.handler.focusDidChange(startsSession: true) }
        await rig.handler.focusDidChange(startsSession: false)
        await on.value?.value
        XCTAssertEqual(rig.pauses.value, [FocusFilterHandler.retryPause])
        XCTAssertEqual(rig.history.imported, [first.id])
        let session = try XCTUnwrap(stored(rig))
        XCTAssertNotEqual(session.id, first.id); XCTAssertEqual(session.origin, .focusFilter); XCTAssertEqual(session.phase, .active)
        XCTAssertNotNil(rig.store.envelope.filterActivation); XCTAssertTrue(rig.shield.applied)
    }
    /// The access-state design, "Gaps between steps": each attempt reads again, so a retry after a lock timeout uses the value read after the pause.
    func testOffCallRetryReadsTheAccessValueAgain() async throws {
        let rig = rig()
        await rig.handler.focusDidChange(startsSession: true)
        rig.authorization.status = .checking
        // The off call's end section is its first lock call, and it times out once; during the pause the value settles to `denied`.
        rig.store.lockTimeoutCalls = [rig.store.calls + 1]
        await FocusFilterHandler.end(engine: rig.engine, authorization: rig.authorization, settings: rig.services.settings, now: Date.init,
                                     pause: { _ in rig.authorization.status = .denied })
        let session = try XCTUnwrap(stored(rig))
        XCTAssertEqual(session.phase, .terminal); XCTAssertEqual(session.reason, .authorizationRevoked)
        XCTAssertFalse(rig.shield.applied)
    }
    func testOffCallEndsTheFilterSessionAndRefreshes() async throws {
        let rig = rig()
        await rig.handler.focusDidChange(startsSession: true)
        XCTAssertEqual(rig.refreshes.value, 1); XCTAssertTrue(rig.shield.applied)
        await rig.handler.focusDidChange(startsSession: false)
        XCTAssertEqual(stored(rig)?.phase, .terminal); XCTAssertEqual(stored(rig)?.reason, .earlyExit)
        XCTAssertNil(rig.store.envelope.filterActivation); XCTAssertFalse(rig.shield.applied)
        XCTAssertEqual(rig.refreshes.value, 2)
    }
    func testActivationCheckClearsOnlyOnOff() async throws {
        let rig = rig()
        await rig.handler.focusDidChange(startsSession: true)
        let marker = try XCTUnwrap(rig.store.envelope.filterActivation)
        for reading in [FocusFilterReading.on, .unknown] {
            await rig.handler.checkActivation(reading: { reading })
            XCTAssertEqual(rig.store.envelope.filterActivation, marker, "\(reading)")
        }
        // An off call and an on call between the read of the marker and the clear store a newer marker, which stays.
        var newer: UUID?
        await rig.handler.checkActivation(reading: {
            await rig.handler.focusDidChange(startsSession: false)
            await rig.handler.focusDidChange(startsSession: true)
            newer = rig.store.envelope.filterActivation
            return .off
        })
        XCTAssertNotNil(newer); XCTAssertNotEqual(newer, marker); XCTAssertEqual(rig.store.envelope.filterActivation, newer)
        let session = stored(rig)
        await rig.handler.checkActivation(reading: { .off })
        XCTAssertNil(rig.store.envelope.filterActivation); XCTAssertEqual(stored(rig), session)
    }
    /// Focus off while access is `checking`, such as with the app not running: the session ends as the person's end, never as revoked.
    func testOffCallWhileCheckingEndsWithoutRevocation() async throws {
        let rig = rig()
        await rig.handler.focusDidChange(startsSession: true)
        XCTAssertEqual(stored(rig)?.phase, .active)
        rig.authorization.status = .checking
        await rig.handler.focusDidChange(startsSession: false)
        XCTAssertEqual(stored(rig)?.phase, .terminal); XCTAssertEqual(stored(rig)?.reason, .earlyExit)
    }
    func testHandlerNeverRequestsAuthorization() async throws {
        for status in [AccessStatus.approved, .denied, .notRequested, .checking] {
            let rig = rig(); rig.authorization.status = status
            await rig.handler.focusDidChange(startsSession: true)
            await rig.handler.checkActivation(reading: { .off })
            await rig.handler.focusDidChange(startsSession: false)
            XCTAssertEqual(rig.authorization.requests, 0, "\(status)")
            if status != .approved { XCTAssertEqual(rig.services.settings.lastFilterRefusal?.reason, .access, "\(status)") }
        }
    }
    func testHandlerAndScreensShareOneRuntime() async throws {
        let rig = rig()
        let container = try ModelContainer(for: SessionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        var builds = 0, fail = true
        let holder = FocusRuntimeHolder(engine: rig.engine, authorization: rig.authorization, settings: rig.services.settings) {
            builds += 1
            if fail { fail = false; throw ModelTestError.storage }
            return (rig.services, container)
        }
        // A failed build is not kept, so the next load builds again.
        XCTAssertThrowsError(try holder.load())
        let (screens, screensContainer) = try holder.load()
        let handler = try holder.filterHandler()
        XCTAssertTrue(handler === (try holder.filterHandler()))
        XCTAssertEqual(builds, 2)
        XCTAssertTrue(screens.engine === handler.services.engine)
        XCTAssertTrue(screens.selection === handler.services.selection)
        XCTAssertTrue(screensContainer === (try holder.load().1))
        var refreshed = 0
        holder.refreshScreens = { refreshed += 1 }
        await handler.focusDidChange(startsSession: true)
        XCTAssertEqual(refreshed, 1); XCTAssertEqual(rig.store.envelope.session?.origin, .focusFilter)
    }
    func testOffCallEndsTheFilterSessionWhenTheStorageCannotLoad() async throws {
        let rig = rig()
        await rig.handler.focusDidChange(startsSession: true)
        XCTAssertEqual(stored(rig)?.origin, .focusFilter); XCTAssertTrue(rig.shield.applied)
        var builds = 0
        let holder = FocusRuntimeHolder(engine: rig.engine, authorization: rig.authorization, settings: rig.services.settings) {
            builds += 1; throw ModelTestError.storage
        }
        var refreshed = 0
        holder.refreshScreens = { refreshed += 1 }
        try await holder.focusDidChange(startsSession: false)
        XCTAssertEqual(builds, 0, "the off call must not need the selection or the SwiftData store")
        XCTAssertEqual(stored(rig)?.phase, .terminal); XCTAssertEqual(stored(rig)?.reason, .earlyExit)
        XCTAssertNil(rig.store.envelope.filterActivation); XCTAssertFalse(rig.shield.applied)
        XCTAssertEqual(refreshed, 1)
        // The on call still needs the storage, so it throws and `FocusRuntime` stores `error`.
        do { try await holder.focusDidChange(startsSession: true); XCTFail("the on call must throw") } catch {}
        XCTAssertEqual(builds, 1)
    }
}
