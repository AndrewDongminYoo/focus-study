import XCTest
import FamilyControls
import ManagedSettings
import SwiftData

@MainActor final class FocusModelTests: XCTestCase {
    private func fixture(defaults: UserDefaults = UserDefaults(suiteName: UUID().uuidString)!) -> (FocusModel, ModelTestHistory, ModelTestStore, ModelTestShield, SessionControl) {
        let store = ModelTestStore(), shield = ModelTestShield(), monitoring = ModelTestMonitoring()
        let (model, history, _) = makeModel(store: store, monitoring: monitoring, shield: shield, defaults: defaults, timing: .standard)
        return (model, history, store, shield, model.services.engine)
    }
    private func makeModel(store: ModelTestStore, monitoring: ModelTestMonitoring, shield: ModelTestShield, defaults: UserDefaults, timing: BreakTiming) -> (FocusModel, ModelTestHistory, ModelTestBreakSelection) {
        let copies = ModelTestBreakSelection(); copies.onRestore = { shield.applied = true }
        let engine = SessionControl(store: store, monitoring: monitoring, shield: shield, breakSelection: copies, everyday: ModelTestEverydayLayer(), timing: timing)
        var services = FocusServices(authorization: ModelTestAuthorization(), selection: ModelTestSelection(), engine: engine, applySelection: { _ in shield.applied = true }, matchesSelection: { _ in shield.applied }, isFixture: true)
        services.settings = FocusSettings(defaults: defaults)
        services.saveBreakSelection = { selection, id in copies.saved.append((selection, id)); copies.copies.insert(id) }
        let history = ModelTestHistory(acknowledge: engine.acknowledgeTerminal)
        return (FocusModel(services: services, history: history), history, copies)
    }
    /// Waits of 0 seconds and a 50-millisecond break, so that the model's own clock drives every phase.
    private func breakFixture(slack: TimeInterval = 600) -> (FocusModel, ModelTestBreakSelection, ModelTestShield) {
        let shield = ModelTestShield()
        let (model, _, copies) = makeModel(store: ModelTestStore(), monitoring: ModelTestMonitoring(), shield: shield, defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                           timing: BreakTiming(waits: [0, 0, 0], breakLength: 0.05, slack: slack, staleWaitGrace: 5))
        model.completeOnboarding(); model.start()
        XCTAssertTrue(model.isActive)
        return (model, copies, shield)
    }
    /// One break from the request to the re-block.
    private func takeBreak(_ model: FocusModel) {
        model.requestBreak(); XCTAssertEqual(model.current?.phase, .waiting)
        model.tick(); XCTAssertEqual(model.current?.phase, .onBreak)
        usleep(80_000); model.tick(); XCTAssertEqual(model.current?.phase, .breakOver)
    }
    private func doubles(_ model: FocusModel) -> (ModelTestAuthorization, ModelTestSelection) {
        (model.services.authorization as! ModelTestAuthorization, model.services.selection as! ModelTestSelection)
    }
    func testRouteForNewUserFollowsOnboardingOrder() {
        let (model, _, _, _, _) = fixture(); let (access, selection) = doubles(model)
        access.status = .notRequested; selection.counts = (0, 0, 0)
        XCTAssertEqual(model.route, .onboarding(.intro))
        access.status = .denied; XCTAssertEqual(model.route, .onboarding(.permission))
        access.status = .approved; XCTAssertEqual(model.route, .onboarding(.selection))
        selection.counts = (1, 0, 0); XCTAssertEqual(model.route, .onboarding(.length))
        model.completeOnboarding(); XCTAssertEqual(model.route, .timer)
    }
    func testRelaunchAfterSelectionResumesAtLengthStep() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let (first, _, _, _, _) = fixture(defaults: defaults)
        first.services.settings.migrateIfNeeded(hasSelection: false)
        XCTAssertEqual(first.route, .onboarding(.length))
        let (relaunched, _, _, _, _) = fixture(defaults: defaults)
        relaunched.services.settings.migrateIfNeeded(hasSelection: true)
        XCTAssertEqual(relaunched.route, .onboarding(.length))
    }
    func testExistingSelectionMigratesEvenWhenFirstAccessReadIsNotApproved() {
        let (model, _, _, _, _) = fixture(); let (access, selection) = doubles(model)
        access.status = .denied; selection.counts = (1, 0, 0)
        model.services.settings.migrateIfNeeded(hasSelection: true)
        access.status = .approved
        XCTAssertEqual(model.route, .timer)
    }
    func testRevokedAccessAfterCompletionShowsPermissionThenTimer() throws {
        let (model, _, _, shield, engine) = fixture(); let (access, _) = doubles(model)
        model.completeOnboarding()
        _ = try engine.start(now: Date(), authorized: { true }, apply: { shield.applied = true }, matches: { true })
        model.refresh(); XCTAssertTrue(model.isActive)
        access.status = .denied; model.refresh()
        XCTAssertFalse(model.isActive); XCTAssertFalse(shield.applied)
        XCTAssertEqual(model.route, .onboarding(.permission))
        access.status = .approved; XCTAssertEqual(model.route, .timer)
    }
    func testStartUsesConfiguredLength() {
        let (model, _, _, _, _) = fixture(); model.services.settings.lengthMinutes = 40; model.completeOnboarding()
        XCTAssertEqual(model.remaining, 2400)
        model.start(); XCTAssertEqual(model.current?.length, 2400)
    }
    func testPendingStartReservesAdmissionUntilPerformed() throws {
        let (model, _, _, shield, engine) = fixture()
        let request = try XCTUnwrap(model.requestStart())
        XCTAssertTrue(model.isStarting); XCTAssertFalse(model.canStart)
        XCTAssertNil(model.current); XCTAssertNil(try engine.snapshot().session)
        XCTAssertNil(model.requestStart()); model.start()
        XCTAssertNil(try engine.snapshot().session); XCTAssertFalse(shield.applied)
        XCTAssertThrowsError(try model.saveSelection(FamilyActivitySelection()))
        model.performPendingStart(request)
        XCTAssertTrue(model.isActive); XCTAssertTrue(shield.applied)
        XCTAssertFalse(model.isStarting); XCTAssertNil(model.startRequestID)
        let id = model.current?.id
        model.performPendingStart(request)
        XCTAssertEqual(model.current?.id, id)
    }
    func testCancelledStartRejectsStalePerformAndCancel() throws {
        let (model, _, _, _, engine) = fixture()
        let old = try XCTUnwrap(model.requestStart())
        model.cancelPendingStart(old)
        XCTAssertFalse(model.isStarting); XCTAssertTrue(model.canStart)
        let current = try XCTUnwrap(model.requestStart())
        model.cancelPendingStart(old); model.performPendingStart(old)
        XCTAssertEqual(model.startRequestID, current); XCTAssertTrue(model.isStarting)
        XCTAssertNil(try engine.snapshot().session)
        model.performPendingStart(current)
        XCTAssertTrue(model.isActive); XCTAssertFalse(model.isStarting)
    }
    func testLeavingForegroundCancelsPendingStart() throws {
        let (model, _, _, _, engine) = fixture()
        let request = try XCTUnwrap(model.requestStart())
        model.sceneDidLeaveForeground(); model.performPendingStart(request)
        XCTAssertFalse(model.isStarting); XCTAssertNil(try engine.snapshot().session)
    }
    func testPendingStartRechecksRevokedAccessAndSelection() throws {
        for revokeAccess in [true, false] {
            let (model, _, _, shield, engine) = fixture()
            let request = try XCTUnwrap(model.requestStart())
            let (authorization, selection) = doubles(model)
            if revokeAccess { authorization.status = .denied }
            else { selection.counts = (0, 0, 0) }
            model.performPendingStart(request)
            XCTAssertFalse(model.isStarting); XCTAssertNil(model.current)
            XCTAssertNil(try engine.snapshot().session); XCTAssertFalse(shield.applied)
        }
    }
    func testPendingStartDoesNotReplaceAnotherSession() throws {
        let (model, _, _, shield, engine) = fixture()
        let request = try XCTUnwrap(model.requestStart())
        let existing = try engine.start(now: Date(), authorized: { true }, apply: { shield.applied = true }, matches: { true })
        model.performPendingStart(request)
        XCTAssertFalse(model.isStarting); XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.current?.id, existing.id)
        XCTAssertEqual(try engine.snapshot().session?.id, existing.id)
    }
    func testPendingStartDoesNotReplaceAFocusFilterSession() throws {
        let (model, _, _, shield, engine) = fixture()
        let request = try XCTUnwrap(model.requestStart())
        _ = try engine.startFromFocusFilter(now: Date(), length: 1500, authorized: { true }, selectionReady: true,
                                           apply: { shield.applied = true }, matches: { true })
        let existing = try XCTUnwrap(try engine.snapshot().session)
        XCTAssertEqual(existing.origin, .focusFilter)
        model.performPendingStart(request)
        XCTAssertFalse(model.isStarting); XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.current?.id, existing.id)
        XCTAssertEqual(try engine.snapshot().session?.origin, .focusFilter)
    }
    func testPendingStartReleasesAdmissionAfterRefreshFailure() throws {
        let (model, _, store, shield, _) = fixture()
        let request = try XCTUnwrap(model.requestStart())
        store.failRead = true; model.performPendingStart(request)
        XCTAssertFalse(model.isStarting); XCTAssertNil(model.startRequestID)
        XCTAssertNotNil(model.errorMessage); XCTAssertFalse(shield.applied)
    }
    func testPendingStartReleasesAdmissionAfterSelectionValidationFailure() throws {
        let (model, _, _, shield, _) = fixture()
        let monitoring = model.services.engine
        // A selection validation failure exercises the start body's catch and final refresh.
        let request = try XCTUnwrap(model.requestStart())
        let (_, selection) = doubles(model); selection.counts = (51, 0, 0)
        model.performPendingStart(request)
        XCTAssertFalse(model.isStarting); XCTAssertNil(model.startRequestID)
        XCTAssertNotNil(model.errorMessage); XCTAssertFalse(shield.applied)
        XCTAssertNil(try monitoring.snapshot().session)
    }
    func testPendingStartReleasesAdmissionAfterRegistrationFailure() throws {
        let store = ModelTestStore(), monitoring = ModelTestMonitoring(), shield = ModelTestShield()
        monitoring.failRegistration = true
        let (model, _, _) = makeModel(store: store, monitoring: monitoring, shield: shield,
                                    defaults: UserDefaults(suiteName: UUID().uuidString)!, timing: .standard)
        let request = try XCTUnwrap(model.requestStart())
        model.performPendingStart(request)
        XCTAssertFalse(model.isStarting); XCTAssertNil(model.startRequestID)
        XCTAssertNotNil(model.errorMessage); XCTAssertFalse(shield.applied)
        XCTAssertTrue(monitoring.ids.isEmpty)
        XCTAssertNil(try model.services.engine.snapshot().session)
    }
    func testStartMeasurementRunsAfterSuccessfulRefresh() {
        let (original, history, _, _, _) = fixture()
        var services = original.services
        var samples: [TimeInterval] = []
        weak var measuredModel: FocusModel?
        services.didMeasureStart = { duration in
            samples.append(duration)
            XCTAssertEqual(measuredModel?.isActive, true)
        }
        let model = FocusModel(services: services, history: history)
        measuredModel = model
        model.start()
        XCTAssertEqual(samples.count, 1)
        if let duration = samples.first { XCTAssertGreaterThan(duration, 0) }
    }
    func testStartMeasurementIncludesRefreshFailureButSkipsRejectedTap() {
        let (original, history, store, _, _) = fixture()
        var services = original.services
        var samples: [TimeInterval] = []
        services.didMeasureStart = { samples.append($0) }
        let model = FocusModel(services: services, history: history)
        store.failRead = true
        model.start()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(samples.count, 1)
        model.start()
        XCTAssertEqual(samples.count, 1)
    }
    func testChangingLengthDuringSessionKeepsRunningSession() {
        let (model, _, _, _, _) = fixture(); model.completeOnboarding()
        model.start(); let end = model.current?.expiresAt
        model.services.settings.lengthMinutes = 50; model.refresh()
        XCTAssertEqual(model.current?.expiresAt, end); XCTAssertEqual(model.current?.length, 1500)
    }
    func testHistoryFetchFailurePreservesActiveControlsAndCanEndRestrictions() throws {
        let (model, history, _, shield, engine) = fixture()
        let session = try engine.start(now: Date(), authorized: { true }, apply: { shield.applied = true }, matches: { true })
        history.failFetch = true
        model.refresh()
        XCTAssertEqual(model.current?.id, session.id)
        XCTAssertTrue(model.isActive); XCTAssertNotNil(model.errorMessage)
        model.end()
        XCTAssertFalse(shield.applied)
        XCTAssertNil(try engine.snapshot().session)
    }
    /// The history sheet's "다시 확인하기" calls `refresh()`: a read that succeeds after a failed one clears the history error and loads today's records.
    func testHistoryRetryClearsTheErrorAndLoadsRecordsAfterAFailedRead() throws {
        let (base, _, _, _, _) = fixture()
        let container = try ModelContainer(for: SessionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let stored = SessionHistory(context: ModelContext(container), acknowledge: { _ in })
        var ended = ControlSession(startedAt: Date())
        ended.phase = .terminal; ended.reason = .earlyExit; ended.observedAt = ended.startedAt
        try stored.importTerminal(ended)
        let model = FocusModel(services: base.services, history: FirstReadFailingHistory(base: stored))
        model.refresh()
        XCTAssertEqual(model.errorMessage, "기록을 불러오지 못했어요. 다시 확인해 주세요. 진행 중인 세션은 종료할 수 있어요.")
        XCTAssertTrue(model.records.isEmpty)
        model.refresh()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.records.map(\.id), [ended.id])
    }
    func testControlReadFailureStillInvalidatesPreviouslyConfirmedSession() throws {
        let (model, _, store, shield, engine) = fixture()
        _ = try engine.start(now: Date(), authorized: { true }, apply: { shield.applied = true }, matches: { true })
        model.refresh(); XCTAssertTrue(model.isActive)
        store.failRead = true
        model.refresh()
        XCTAssertNil(model.current); XCTAssertFalse(model.isActive); XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(shield.applied)
    }
    func testOnlyAFullSessionIsMarkedCompletedUntilDismissed() throws {
        let (model, _, _, shield, engine) = fixture()
        let session = try engine.start(now: Date().addingTimeInterval(-1500), authorized: { true }, apply: { shield.applied = true }, matches: { true })
        model.refresh()
        XCTAssertEqual(model.completedSessionID, session.id); XCTAssertNil(model.current)
        model.dismissCompletion()
        XCTAssertNil(model.completedSessionID)
        model.start(); XCTAssertTrue(model.isActive)
        model.end()
        XCTAssertNil(model.completedSessionID)
    }
    func testCompletionKeepsTheSessionsOwnLengthAfterTheSettingChanges() throws {
        let (model, _, _, shield, engine) = fixture()
        _ = try engine.start(now: Date().addingTimeInterval(-2400), length: 2400, authorized: { true }, apply: { shield.applied = true }, matches: { true })
        model.services.settings.lengthMinutes = 25
        model.refresh()
        XCTAssertEqual(model.completedLength, 2400)
        model.dismissCompletion(); XCTAssertNil(model.completedLength)
    }
    func testStartBlockerNamesTheFirstUnmetCondition() throws {
        let (model, history, _, shield, engine) = fixture()
        let selection = try XCTUnwrap(model.services.selection as? ModelTestSelection)
        model.refresh(); XCTAssertNil(model.startBlocker)
        selection.counts = (0, 0, 0)
        XCTAssertEqual(model.startBlocker, .selection)
        history.failFetch = true; model.refresh()
        XCTAssertEqual(model.startBlocker, .error)
        history.failFetch = false; selection.counts = (1, 0, 0); model.refresh()
        _ = try engine.start(now: Date(), authorized: { true }, apply: { shield.applied = true }, matches: { true })
        model.refresh(); XCTAssertNil(model.startBlocker)
    }
    func testRequestBreakPausesRemaining() throws {
        let (model, _, store, shield, engine) = fixture()
        let session = try engine.start(now: Date().addingTimeInterval(-300), authorized: { true }, apply: { shield.applied = true }, matches: { true })
        model.refresh(); XCTAssertEqual(model.remaining, 1200)
        model.requestBreak()
        XCTAssertEqual(store.envelope.session?.phase, .waiting); XCTAssertTrue(model.isInSession); XCTAssertFalse(model.isActive)
        let paused = model.remaining
        usleep(1_100_000); model.tick()
        XCTAssertEqual(model.remaining, paused); XCTAssertEqual(model.current?.id, session.id)
        XCTAssertNotNil(model.waitProgress); XCTAssertTrue(shield.applied)
    }
    func testLeavingForegroundCancelsWaitAndKeepsBreaksLeft() {
        let (model, copies, shield) = breakFixture()
        model.requestBreak(); XCTAssertEqual(model.current?.phase, .waiting)
        model.sceneDidLeaveForeground()
        XCTAssertEqual(model.current?.phase, .active); XCTAssertEqual(model.breaksLeft, 3)
        XCTAssertTrue(copies.saved.isEmpty); XCTAssertTrue(shield.applied)
    }
    func testTickStartsBreakAfterWaitWithFrozenSelection() {
        let (model, copies, shield) = breakFixture()
        let id = model.current?.id
        model.requestBreak(); model.tick()
        XCTAssertEqual(model.current?.phase, .onBreak); XCTAssertEqual(model.current?.breaksTaken, 1)
        XCTAssertEqual(copies.saved.map(\.1), [id].compactMap { $0 })
        XCTAssertEqual(copies.saved.first?.0.applicationTokens, model.services.selection.selection.applicationTokens)
        XCTAssertEqual(copies.saved.first?.0.webDomainTokens, model.services.selection.selection.webDomainTokens)
        XCTAssertFalse(shield.applied); XCTAssertNotNil(model.breakRemaining)
    }
    func testSelectionIsLockedDuringBreakAndAfterReBlock() {
        let (model, _, _) = breakFixture()
        model.requestBreak(); model.tick()
        XCTAssertEqual(model.current?.phase, .onBreak); XCTAssertTrue(model.isInSession)
        XCTAssertThrowsError(try model.saveSelection(FamilyActivitySelection()))
        usleep(80_000); model.tick()
        XCTAssertEqual(model.current?.phase, .breakOver); XCTAssertTrue(model.isInSession)
        XCTAssertThrowsError(try model.saveSelection(FamilyActivitySelection()))
    }
    func testResumeContinuesCountdownFromPausedValue() {
        let (model, _, shield) = breakFixture()
        takeBreak(model)
        XCTAssertTrue(shield.applied)
        let paused = model.remaining
        model.resume()
        XCTAssertEqual(model.current?.phase, .active)
        XCTAssertLessThanOrEqual(abs(model.remaining - paused), 1)
    }
    func testResumeDuringBreakRestoresRestrictionsAndPreservesRemainingFocus() {
        let shield = ModelTestShield()
        let (model, _, _) = makeModel(store: ModelTestStore(), monitoring: ModelTestMonitoring(), shield: shield,
                                    defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                    timing: BreakTiming(waits: [0, 0, 0], breakLength: 180, slack: 600, staleWaitGrace: 5))
        model.start(); model.requestBreak(); model.tick()
        XCTAssertEqual(model.current?.phase, .onBreak)
        XCTAssertFalse(shield.applied)
        let remaining = model.remaining
        model.resume()
        XCTAssertEqual(model.current?.phase, .active)
        XCTAssertTrue(shield.applied)
        XCTAssertEqual(model.breaksLeft, 2)
        XCTAssertLessThanOrEqual(abs(model.remaining - remaining), 1)
    }
    func testResumeRemainingReachesZeroWhenSessionCanNoLongerComplete() {
        let (roomy, _, _) = breakFixture()
        takeBreak(roomy)
        XCTAssertGreaterThan(roomy.resumeRemaining ?? 0, 590)
        let (late, _, _) = breakFixture(slack: 0)
        takeBreak(late)
        XCTAssertEqual(late.resumeRemaining, 0)
    }
    func testFocusSelectionSaveRefusesAUnionOver50() throws {
        let (model, _, _, _, _) = fixture()
        let (_, selection) = doubles(model)
        var everyday = FamilyActivitySelection(); everyday.applicationTokens = syntheticApps(0..<49)
        var services = model.services; services.everydaySelection = { everyday }
        let guarded = FocusModel(services: services, history: ModelTestHistory(acknowledge: services.engine.acknowledgeTerminal))
        var draft = FamilyActivitySelection(); draft.applicationTokens = syntheticApps(100..<102)
        XCTAssertThrowsError(try guarded.saveSelection(draft)) { XCTAssertEqual($0 as? SelectionUnionLimit, SelectionUnionLimit(issue: .tooManyApps)) }
        XCTAssertEqual(selection.saves, 0)
        everyday.applicationTokens = syntheticApps(0..<50); draft.applicationTokens = syntheticApps(0..<50)
        try guarded.saveSelection(draft)
        XCTAssertEqual(selection.saves, 1)
    }
    func testEverydayStatusFailureLeavesTheSessionAndErrorUnchanged() throws {
        let (model, _, store, _, _) = fixture()
        model.completeOnboarding(); model.start()
        let session = try XCTUnwrap(model.current); XCTAssertEqual(session.phase, .active)
        // `refresh()` takes the lock for the reconcile, the snapshot and then the everyday status.
        store.lockTimeoutCalls = [store.calls + 3]
        model.refresh()
        XCTAssertEqual(model.current, session); XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.everydayStatus?.issue, .unchecked)
        model.refresh()
        XCTAssertNil(model.everydayStatus?.issue)
    }
    /// A filter handler on the model's own services and history, as one runtime per process gives it.
    private func filterHandler(_ model: FocusModel, history: ModelTestHistory, refresh: @escaping () -> Void, now: @escaping () -> Date = Date.init) -> FocusFilterHandler {
        FocusFilterHandler(services: model.services, history: history, refresh: refresh, now: now, pause: { _ in })
    }
    func testFilterChangeRefreshesTheModel() async throws {
        let (model, history, _, shield, engine) = fixture()
        let earlier = try engine.start(now: Date().addingTimeInterval(-1500), authorized: { true }, apply: { shield.applied = true }, matches: { true })
        model.refresh(); XCTAssertEqual(model.completedSessionID, earlier.id)
        await filterHandler(model, history: history, refresh: { model.refresh() }).focusDidChange(startsSession: true)
        XCTAssertEqual(model.current?.origin, .focusFilter); XCTAssertEqual(model.current?.phase, .active)
        XCTAssertNil(model.completedSessionID); XCTAssertNil(model.completedLength)
    }
    func testFilterImportOfAnExpiredSessionKeepsTheCard() async throws {
        for starts in [false, true] {
            let (model, history, _, shield, engine) = fixture()
            let (_, selection) = doubles(model)
            let earlier = try engine.start(now: Date().addingTimeInterval(-1500), authorized: { true }, apply: { shield.applied = true }, matches: { true })
            if !starts { selection.counts = (0, 0, 0) }
            await filterHandler(model, history: history, refresh: { model.refresh() }).focusDidChange(startsSession: true)
            XCTAssertEqual(model.services.settings.lastFilterRefusal?.reason, starts ? nil : .selection, "\(starts)")
            XCTAssertEqual(model.completedSessionID, starts ? nil : earlier.id, "\(starts)")
            if !starts { XCTAssertEqual(model.completedLength, 1500) }
            XCTAssertNil(model.services.settings.pendingCompletion, "\(starts)")
        }
    }
    func testExpiredCardSurvivesRefreshesWithoutASession() throws {
        let (model, _, _, shield, engine) = fixture()
        let earlier = try engine.start(now: Date().addingTimeInterval(-1500), authorized: { true }, apply: { shield.applied = true }, matches: { true })
        model.refresh(); model.refresh()
        XCTAssertNil(model.current); XCTAssertEqual(model.completedSessionID, earlier.id); XCTAssertEqual(model.completedLength, 1500)
    }
    func testNewerExpiredSessionOverridesThePendingCard() async throws {
        let (model, history, _, shield, engine) = fixture()
        let s1 = try engine.start(now: Date().addingTimeInterval(-4000), authorized: { true }, apply: { shield.applied = true }, matches: { true })
        // The filter path starts S2 long enough ago that it is past its focus end at the off call.
        model.services.settings.lengthMinutes = 30
        var clock = Date().addingTimeInterval(-1900)
        let handler = filterHandler(model, history: history, refresh: {}, now: { clock })
        await handler.focusDidChange(startsSession: true)
        XCTAssertEqual(model.services.settings.pendingCompletion?.id, s1.id)
        let s2 = try XCTUnwrap(try engine.snapshot().session)
        XCTAssertEqual(s2.origin, .focusFilter); XCTAssertEqual(s2.length, 1800)
        clock = Date()
        await handler.focusDidChange(startsSession: false)
        XCTAssertEqual(try engine.snapshot().session?.reason, .expired)
        model.refresh()
        XCTAssertEqual(model.completedSessionID, s2.id); XCTAssertEqual(model.completedLength, 1800)
        XCTAssertNil(model.services.settings.pendingCompletion)
    }
    func testNoBreakActionAfterThirdBreak() {
        let (model, _, _) = breakFixture()
        for _ in 0..<3 { takeBreak(model); model.resume() }
        XCTAssertEqual(model.breaksLeft, 0); XCTAssertEqual(model.current?.phase, .active)
        let before = model.current
        model.requestBreak()
        XCTAssertEqual(model.current, before); XCTAssertNil(model.errorMessage)
    }
    /// A break fixture whose model reports every accepted break transition.
    private func measuredBreakFixture(store: ModelTestStore = ModelTestStore()) -> (FocusModel, ModelTestBreakSelection, () -> [BreakAction]) {
        let (original, history, copies) = makeModel(store: store, monitoring: ModelTestMonitoring(), shield: ModelTestShield(), defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                                    timing: BreakTiming(waits: [0, 0, 0], breakLength: 0.05, slack: 600, staleWaitGrace: 5))
        var services = original.services
        var measured: [BreakAction] = []
        services.didMeasureBreak = { action, duration in measured.append(action); XCTAssertGreaterThan(duration, 0) }
        let model = FocusModel(services: services, history: history)
        model.completeOnboarding(); model.start()
        XCTAssertTrue(model.isActive)
        return (model, copies, { measured })
    }
    func testPendingBreakRequestIsReservedBeforeTheEngineRuns() throws {
        let store = ModelTestStore()
        let (model, _, _) = measuredBreakFixture(store: store)
        let request = try XCTUnwrap(model.requestBreakAction(.request))
        XCTAssertEqual(model.pendingBreak?.action, .request)
        XCTAssertEqual(store.envelope.session?.phase, .active); XCTAssertEqual(model.current?.phase, .active)
        model.performPendingBreak(request)
        XCTAssertEqual(store.envelope.session?.phase, .waiting); XCTAssertNil(model.pendingBreak)
        // The view's teardown cancels the request it already performed; that late call changes nothing.
        model.cancelPendingBreak(request); model.performPendingBreak(request)
        XCTAssertEqual(model.current?.phase, .waiting); XCTAssertNil(model.pendingBreak)
    }
    func testSecondBreakTapWhilePendingIsIgnored() throws {
        let (model, _, measured) = measuredBreakFixture()
        let request = try XCTUnwrap(model.requestBreakAction(.request))
        XCTAssertNil(model.requestBreakAction(.request))
        model.requestBreak()
        XCTAssertEqual(model.current?.phase, .active); XCTAssertTrue(measured().isEmpty)
        model.performPendingBreak(request)
        XCTAssertEqual(model.current?.phase, .waiting); XCTAssertEqual(measured(), [.request])
        let cancel = try XCTUnwrap(model.requestBreakAction(.cancelWait))
        model.cancelWait(); XCTAssertNil(model.requestBreakAction(.cancelWait))
        XCTAssertEqual(model.current?.phase, .waiting)
        model.performPendingBreak(cancel)
        XCTAssertEqual(model.current?.phase, .active); XCTAssertEqual(model.breaksLeft, 3)
        XCTAssertEqual(measured(), [.request, .cancelWait])
    }
    func testPendingBreakClearsOnFailureWithTheSameMessage() throws {
        let store = ModelTestStore()
        let (model, _, measured) = measuredBreakFixture(store: store)
        store.failSavePhase = .waiting
        let request = try XCTUnwrap(model.requestBreakAction(.request))
        model.performPendingBreak(request)
        XCTAssertNil(model.pendingBreak); XCTAssertEqual(model.current?.phase, .active)
        XCTAssertEqual(model.errorMessage, "쉬는 시간을 요청하지 못했어요. 다시 시도해 주세요.")
        XCTAssertEqual(measured(), [.request])
    }
    func testLeavingForegroundCancelsAPendingBreakRequest() throws {
        let (model, copies, measured) = measuredBreakFixture()
        let request = try XCTUnwrap(model.requestBreakAction(.request))
        model.sceneDidLeaveForeground()
        XCTAssertNil(model.pendingBreak)
        model.performPendingBreak(request)
        XCTAssertEqual(model.current?.phase, .active); XCTAssertEqual(model.breaksLeft, 3)
        XCTAssertTrue(measured().isEmpty); XCTAssertTrue(copies.saved.isEmpty)
    }
    func testDeferredTickReservesTheAutomaticBreakStartOnce() throws {
        let (model, copies, measured) = measuredBreakFixture()
        model.requestBreak(); XCTAssertEqual(model.current?.phase, .waiting)
        model.tick(defersBreakStart: true)
        let pending = try XCTUnwrap(model.pendingBreak)
        XCTAssertEqual(pending.action, .startBreak); XCTAssertEqual(model.current?.phase, .waiting)
        model.tick(defersBreakStart: true); model.tick()
        XCTAssertEqual(model.pendingBreak, pending); XCTAssertEqual(model.current?.phase, .waiting)
        XCTAssertTrue(copies.saved.isEmpty)
        model.performPendingBreak(pending.id)
        XCTAssertEqual(model.current?.phase, .onBreak); XCTAssertNil(model.pendingBreak)
        let resume = try XCTUnwrap(model.requestBreakAction(.resume))
        model.performPendingBreak(resume)
        XCTAssertEqual(model.current?.phase, .active)
        XCTAssertEqual(measured(), [.request, .startBreak, .resume])
    }
    func testLeavingForegroundDuringAPendingBreakStartCancelsTheWait() throws {
        let (model, copies, measured) = measuredBreakFixture()
        model.requestBreak(); model.tick(defersBreakStart: true)
        let pending = try XCTUnwrap(model.pendingBreak)
        model.sceneDidLeaveForeground()
        model.performPendingBreak(pending.id)
        XCTAssertEqual(model.current?.phase, .active); XCTAssertEqual(model.breaksLeft, 3)
        XCTAssertTrue(copies.saved.isEmpty); XCTAssertNil(model.pendingBreak)
        XCTAssertEqual(measured(), [.request, .cancelWait])
    }
    func testInactiveSceneDropsAPendingBreakStartAndKeepsTheWait() throws {
        let (model, copies, measured) = measuredBreakFixture()
        model.requestBreak(); model.tick(defersBreakStart: true)
        let stale = try XCTUnwrap(model.pendingBreak)
        // An overlay such as Control Center keeps the wait, but a reservation made before it must not start the break at its old tick time.
        model.sceneDidBecomeInactive()
        XCTAssertNil(model.pendingBreak); XCTAssertEqual(model.current?.phase, .waiting)
        model.performPendingBreak(stale.id)
        XCTAssertEqual(model.current?.phase, .waiting); XCTAssertTrue(copies.saved.isEmpty)
        // Back in the foreground, the next tick reserves the start again with its own time.
        model.tick(defersBreakStart: true)
        let fresh = try XCTUnwrap(model.pendingBreak)
        XCTAssertNotEqual(fresh.id, stale.id); XCTAssertGreaterThan(fresh.requestedAt, stale.requestedAt)
        model.performPendingBreak(fresh.id)
        XCTAssertEqual(model.current?.phase, .onBreak)
        XCTAssertEqual(measured(), [.request, .startBreak])
    }
    func testInactiveSceneKeepsAPendingTappedAction() throws {
        let (model, _, measured) = measuredBreakFixture()
        let request = try XCTUnwrap(model.requestBreakAction(.request))
        model.sceneDidBecomeInactive()
        XCTAssertEqual(model.pendingBreak?.id, request)
        model.performPendingBreak(request)
        XCTAssertEqual(model.current?.phase, .waiting); XCTAssertEqual(measured(), [.request])
    }
    func testBreakMeasurementSkipsRejectedTaps() throws {
        let (model, _, measured) = measuredBreakFixture()
        model.cancelWait(); model.resume()
        XCTAssertNil(model.requestBreakAction(.cancelWait)); XCTAssertNil(model.requestBreakAction(.resume))
        XCTAssertNil(model.requestBreakAction(.startBreak))
        XCTAssertTrue(measured().isEmpty)
        let cancelled = try XCTUnwrap(model.requestBreakAction(.request))
        model.cancelPendingBreak(cancelled)
        model.requestBreak(); XCTAssertEqual(model.current?.phase, .waiting)
        model.performPendingBreak(cancelled); model.requestBreak()
        XCTAssertEqual(measured(), [.request])
    }
}
final class ModelTestBreakSelection: BreakSelectionStore {
    var copies = Set<UUID>(), saved: [(FamilyActivitySelection, UUID)] = []
    var onRestore: () -> Void = {}
    func restoreShield(id: UUID) -> Bool { guard copies.contains(id) else { return false }; onRestore(); return true }
    func exists(id: UUID) -> Bool { copies.contains(id) }
    func remove(id: UUID) { copies.remove(id) }
    func removeAll(except id: UUID?) { copies = copies.filter { $0 == id } }
}
enum ModelTestError: Error { case storage }
final class ModelTestStore: ControlStore, LockedControl {
    var envelope = ControlEnvelope(), failRead = false
    var failSavePhase: SessionPhase?
    /// The numbers of the lock sections that throw `lockTimeout` before their body runs.
    var lockTimeoutCalls = Set<Int>()
    private(set) var calls = 0
    func withExclusiveAccess<T>(timeout: TimeInterval?, _ body: (LockedControl) throws -> T) throws -> T {
        calls += 1
        if lockTimeoutCalls.contains(calls) { throw ControlIssue.lockTimeout }
        return try body(self)
    }
    func load() throws -> ControlEnvelope { if failRead { throw ModelTestError.storage }; return envelope }
    func save(_ envelope: ControlEnvelope) throws {
        if let failSavePhase, envelope.session?.phase == failSavePhase { throw ModelTestError.storage }
        self.envelope = envelope
    }
}
final class ModelTestMonitoring: MonitoringClient {
    var failRegistration = false
    var ids = Set<UUID>(); var registeredSessionIDs: [UUID] { Array(ids) }
    func register(id: UUID, start: Date, end: Date) throws {
        if failRegistration { throw ModelTestError.storage }
        ids.insert(id)
    }
    func isRegistered(id: UUID) -> Bool { ids.contains(id) }
    func stop(id: UUID) { ids.remove(id); breaks.removeAll { $0.id == id } }
    var breaks: [(id: UUID, index: Int)] = []
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws { breaks.append((id, index)) }
    func isBreakRegistered(id: UUID, index: Int) -> Bool { breaks.contains { $0.id == id && $0.index == index } }
    var registeredBreaks: [(id: UUID, index: Int)] { breaks }
    func stopBreak(id: UUID, index: Int) { breaks.removeAll { $0.id == id && $0.index == index } }
    var everyday: [(revision: UUID, part: EverydayPart)] = []
    func registerEveryday(revision: UUID, part: EverydayPart, start: Int, end: Int) throws { everyday.append((revision, part)) }
    var registeredEveryday: [(revision: UUID, part: EverydayPart)] { everyday }
    func stopEveryday(revision: UUID, part: EverydayPart) { everyday.removeAll { $0.revision == revision && $0.part == part } }
}
/// The everyday file and store in memory.
final class ModelTestEverydayLayer: EverydayLayerStore {
    var schedule: EverydaySchedule?, selection = FamilyActivitySelection(), shieldOn = false, unreadable = false
    private(set) var writes = 0
    func load() throws -> EverydaySchedule? { if unreadable { throw ModelTestError.storage }; return schedule }
    func storeMatches() -> Bool { shieldOn }
    func applyStored() -> Bool { shieldOn = true; return true }
    var hasShield: Bool { shieldOn }
    func clearShield() { shieldOn = false }
    func contains(_ new: FamilyActivitySelection) -> Bool {
        selection.applicationTokens.isSubset(of: new.applicationTokens) && selection.webDomainTokens.isSubset(of: new.webDomainTokens)
    }
    func write(_ schedule: EverydaySchedule, _ selection: FamilyActivitySelection) { self.schedule = schedule; self.selection = selection; unreadable = false; writes += 1 }
    /// The off-for-today write keeps the selection.
    func writeOffDay(_ schedule: EverydaySchedule) { self.schedule = schedule; writes += 1 }
}
/// Synthetic Codable tokens for count tests, never Screen Time calls.
func syntheticApps(_ range: Range<Int>) -> Set<ApplicationToken> {
    Set(range.map { try! JSONDecoder().decode(ApplicationToken.self, from: JSONEncoder().encode(["data": Data([UInt8($0 / 256), UInt8($0 % 256), 9])])) })
}
final class ModelTestShield: ShieldClient {
    var applied = false
    func clear() { applied = false }
}
@MainActor final class ModelTestHistory: SessionHistoryProviding {
    var failFetch = false
    let acknowledge: (UUID) throws -> Void
    init(acknowledge: @escaping (UUID) throws -> Void) { self.acknowledge = acknowledge }
    func importTerminal(_ session: ControlSession) throws { try acknowledge(session.id) }
    func records(on date: Date, calendar: Calendar) throws -> [SessionRecord] { if failFetch { throw ModelTestError.storage }; return [] }
}
/// Fails the first read of today's records, then reads the wrapped history.
@MainActor final class FirstReadFailingHistory: SessionHistoryProviding {
    private let base: any SessionHistoryProviding
    private var failed = false
    init(base: any SessionHistoryProviding) { self.base = base }
    func importTerminal(_ session: ControlSession) throws { try base.importTerminal(session) }
    func records(on date: Date, calendar: Calendar) throws -> [SessionRecord] {
        if !failed { failed = true; throw ModelTestError.storage }
        return try base.records(on: date, calendar: calendar)
    }
}
@MainActor final class ModelTestAuthorization: AuthorizationProviding {
    var status: AccessStatus = .approved
    func requestIndividual() async {}
    func refresh() {}
    func hasAccessNow() -> Bool { status == .approved }
}
@MainActor final class ModelTestSelection: SelectionStoring {
    var selection = FamilyActivitySelection()
    var counts: (apps: Int, websites: Int, categories: Int) = (1, 0, 0)
    private(set) var saves = 0
    func save(_ selection: FamilyActivitySelection) throws { saves += 1 }
}
