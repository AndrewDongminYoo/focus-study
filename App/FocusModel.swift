import Foundation
import SwiftData
import FamilyControls
import Observation

@MainActor struct FocusServices {
    let authorization: any AuthorizationProviding
    let selection: any SelectionStoring
    let engine: SessionControl
    let applySelection: (FamilyActivitySelection) -> Void
    let matchesSelection: (FamilyActivitySelection) -> Bool
    var isFixture = false
    var settings = FocusSettings()
    /// Display-only notification, invoked after control/history work and outside every process lock.
    var activityDidChange: () -> Void = {}
    /// Writes the session-scoped selection copy for a break. Without one, no break can start, so the shield is never cleared.
    var saveBreakSelection: (FamilyActivitySelection, UUID) throws -> Void = { _, _ in throw ControlIssue.io }
    /// The stored everyday selection; an unreadable everyday file gives `nil`, because the layer then blocks nothing.
    var everydaySelection: () -> FamilyActivitySelection? = { nil }
    /// `true` when the new everyday selection holds every app and website of the stored one.
    var everydayContains: (FamilyActivitySelection) throws -> Bool = { _ in true }
    /// Writes `everyday-layer.json`; it runs inside the engine's save section.
    var writeEveryday: (EverydaySchedule, FamilyActivitySelection) throws -> Void = { _, _ in throw ControlIssue.io }
    /// Writes `everyday-layer.json` again with the stored selection and the schedule's `offDay`; it runs inside the engine's off-for-today section.
    var writeEverydayOffDay: (EverydaySchedule) throws -> Void = { _ in throw ControlIssue.io }
    #if DEBUG
    var diagnostics: DeviceDiagnostics?
    /// Opt-in timing of the complete synchronous start call; never carries selection or usage data.
    var didMeasureStart: ((TimeInterval) -> Void)?
    /// Opt-in timing of each accepted synchronous break transition call; never carries selection or usage data.
    var didMeasureBreak: ((BreakAction, TimeInterval) -> Void)?
    /// Opt-in timing of each session end, from the tap to the return of the engine call; never carries selection or usage data.
    var didMeasureEnd: ((TimeInterval) -> Void)?
    /// `--ui-testing ending-soon`: the focus seconds left when `start()` begins a session; the start time moves into the past.
    var fixtureFocusLeft: TimeInterval?
    /// `--break-delay`: seconds that the break feedback stays on screen before the transition runs; the main thread is not blocked.
    var fixtureBreakHold: TimeInterval = 0
    /// `--ui-testing history-failure`: wraps the app's history, so that every read of today's records fails.
    var fixtureHistory: ((any SessionHistoryProviding) -> any SessionHistoryProviding)?
    #endif

}
/// The four break transitions; the raw value names the action in the `BREAK_LATENCY` log.
enum BreakAction: String { case request, cancelWait, startBreak, resume }
/// A break transition reserved by the screen before its feedback has had a chance to appear.
/// `requestedAt` is the tick time of an automatic break start, which the engine checks against the wait end and its grace.
struct PendingBreak: Equatable { let id: UUID; let action: BreakAction; let requestedAt: Date }
enum StartBlocker: Equatable { case access, checking, error, selection }
enum OnboardingStep: Int, CaseIterable { case intro, permission, selection, length }
enum LaunchRoute: Equatable { case onboarding(OnboardingStep), timer }
@MainActor @Observable final class FocusModel {
    let services: FocusServices
    private let history: any SessionHistoryProviding
    private(set) var current: ControlSession?
    private(set) var records: [SessionRecord] = []
    private(set) var errorMessage: String?
    private(set) var isStarting = false
    private(set) var startRequestID: UUID?
    /// The recovery tap whose access request is in flight; leaving the foreground clears it.
    private var accessRecoveryID: UUID?
    /// A break transition that waits for its feedback frame; while it is set, every break action is refused.
    private(set) var pendingBreak: PendingBreak?
    private(set) var now = Date()
    /// The most recent session that reached its full length, until the person dismisses it.
    private(set) var completedSessionID: UUID?
    /// That session's own length; today's records can miss it (a session that crossed midnight, a history failure).
    private(set) var completedLength: TimeInterval?
    /// The everyday layer for the settings row and for the timer screen's everyday status row, which the idle screen and the completion card show.
    private(set) var everydayStatus: EverydayStatus?
    /// The session of a thrown `finish`, which can leave the stored phase behind its stopped activities; until one reconcile succeeds, `tick` runs one with no session.
    private var failedEndID: UUID?
    private static let endFailure = "종료 상태를 저장하지 못했어요. 다시 확인해 주세요."
    var access: AccessStatus { services.authorization.status }
    var isActive: Bool { current?.phase == .active }
    /// Focusing or paused for a break: the selection editor and the settings stay locked.
    var isInSession: Bool { isActive || current?.isPaused == true }
    private var timing: BreakTiming { services.engine.timing }
    var breaksLeft: Int { current?.breaksLeft ?? BreakTiming.maxBreaks }
    /// 0 to 1 while the waiting screen is open.
    var waitProgress: Double? {
        guard let s = current, s.phase == .waiting, let pausedAt = s.pausedAt, let waitEndsAt = s.waitEndsAt else { return nil }
        let total = waitEndsAt.timeIntervalSince(pausedAt)
        return total > 0 ? min(1, max(0, now.timeIntervalSince(pausedAt) / total)) : 1
    }
    var waitRemaining: Int? {
        guard let s = current, s.phase == .waiting, let waitEndsAt = s.waitEndsAt else { return nil }
        return Int(ceil(max(0, waitEndsAt.timeIntervalSince(now))))
    }
    var breakRemaining: Int? {
        guard let s = current, s.phase == .onBreak, let breakEndsAt = s.breakEndsAt else { return nil }
        return Int(ceil(max(0, breakEndsAt.timeIntervalSince(now))))
    }
    /// After the re-block: seconds until the last tap on "다시 집중하기" that can still complete before the deadline.
    var resumeRemaining: Int? {
        guard let s = current, s.phase == .breakOver else { return nil }
        let lastResume = s.deadline(timing: timing).addingTimeInterval(-(s.length - s.focused(at: now)))
        return Int(ceil(max(0, lastResume.timeIntervalSince(now))))
    }
    var counts: (apps: Int, websites: Int, categories: Int) { services.selection.counts }
    /// In `checking` the start control stays enabled: its tap is the access recovery (`recoverAccessAndStart`).
    var canStart: Bool { (access == .approved || access == .checking) && current == nil && !isStarting && errorMessage == nil && counts.apps + counts.websites > 0 }
    /// The first unmet start condition, in the order the person has to resolve them.
    var startBlocker: StartBlocker? {
        guard current == nil, !isStarting else { return nil }
        // A failed recovery tap sets the error, which disables the start control until "다시 확인하기".
        if access == .checking { return errorMessage == nil ? .checking : .error }
        if access != .approved { return .access }
        if errorMessage != nil { return .error }
        return counts.apps + counts.websites == 0 ? .selection : nil
    }
    var remaining: Int { current.map { TimeRules.remaining(session: $0, now: now) } ?? Int(services.settings.lengthSeconds) }
    /// Which screen launch shows: onboarding resumes at its first unfinished step; a finished person who lost access or selection returns to that step.
    /// The screens follow the session before access, so a session that is not `terminal` stays reachable in every access status.
    var route: LaunchRoute {
        if let current, current.phase != .terminal { return .timer }
        let hasSelection = counts.apps + counts.websites > 0
        if !services.settings.hasCompletedOnboarding {
            switch access {
            case .notRequested: return .onboarding(.intro)
            case .denied, .checking: return .onboarding(.permission)
            case .approved: return .onboarding(hasSelection ? .length : .selection)
            }
        }
        // `checking` is not a revocation: the timer screen shows its recovery start control.
        if access == .denied || access == .notRequested { return .onboarding(.permission) }
        return hasSelection ? .timer : .onboarding(.selection)
    }
    convenience init(services: FocusServices, context: ModelContext) {
        let history: any SessionHistoryProviding = SessionHistory(context: context, acknowledge: services.engine.acknowledgeTerminal)
        #if DEBUG
        if let wrap = services.fixtureHistory { self.init(services: services, history: wrap(history)); return }
        #endif
        self.init(services: services, history: history)
    }
    init(services: FocusServices, history: any SessionHistoryProviding) {
        self.services = services; self.history = history
    }
    func refresh(clockChanged: Bool = false) {
        defer { services.activityDidChange() }
        services.authorization.refresh(); now = Date()
        do {
            try services.engine.reconcile(now: now, authorized: services.authorization.accessState(), clockChanged: clockChanged)
            current = try services.engine.snapshot().session
        } catch {
            current = nil
            errorMessage = failedEndID != nil ? Self.endFailure : "상태를 확인하지 못했어요. 다시 확인해 주세요."
            return
        }
        let failedEnd = failedEndID; failedEndID = nil
        // The filter path imported an `.expired` session first: its card shows only on an idle screen, and this import's own card overrides it.
        if let pending = services.settings.takePendingCompletion(), current == nil || current?.phase == .terminal {
            completedSessionID = pending.id; completedLength = pending.length
        }
        do {
            if let terminal = current, terminal.phase == .terminal {
                try history.importTerminal(terminal)
                if terminal.reason == .expired { completedSessionID = terminal.id; completedLength = terminal.length }
                current = try services.engine.snapshot().session
            }
            // The card belongs to an idle screen: a session that started without `start()`, such as by a Focus, must not sit under it.
            if let current, current.phase != .terminal { completedSessionID = nil; completedLength = nil }
            records = try history.records(on: now, calendar: .current)
            errorMessage = nil
        } catch {
            // A history failure does not invalidate a confirmed control session or its early-exit action.
            errorMessage = "기록을 불러오지 못했어요. 다시 확인해 주세요. 진행 중인 세션은 종료할 수 있어요."
        }
        // The reconcile found nothing to repair (a lock timeout threw before the end's section), so the session still runs and the end stays reported.
        if let current, current.id == failedEnd, current.phase != .terminal { errorMessage = Self.endFailure }
        refreshEveryday()
    }
    /// Its own `do`/`catch`: a lock timeout against a Monitor everyday callback never changes `current` or `errorMessage`.
    func refreshEveryday() {
        do { everydayStatus = try services.engine.everydayStatus(now: Date(), authorized: services.authorization.accessState()) }
        catch {
            var kept = everydayStatus ?? EverydayStatus(schedule: nil, blocksNow: false, nextChange: nil, issue: nil)
            kept.issue = .unchecked; everydayStatus = kept
        }
    }

    func start() {
        guard canStart else { return }
        performStart()
    }
    /// The tap on the start control while access is `checking`: request access, then reserve the start only after the published value reads approved.
    /// The engine's start still requires `approved` inside the lock, so a request result alone never starts a session.
    /// Leaving the foreground during the request cancels the tap, so a start never waits for the return.
    func recoverAccessAndStart() async {
        guard access == .checking, canStart else { return }
        let recovery = UUID()
        accessRecoveryID = recovery; isStarting = true
        await services.authorization.requestIndividual()
        let wasCancelled = accessRecoveryID != recovery
        if !wasCancelled { accessRecoveryID = nil; isStarting = false }
        refresh()
        guard !wasCancelled else { return }
        guard access == .approved else {
            if access == .checking, errorMessage == nil { errorMessage = "스크린 타임 권한을 확인하지 못했어요. 다시 확인해 주세요." }
            return
        }
        requestStart()
    }
    /// Reserves the UI action before its feedback has had a chance to appear. No control operation runs here.
    @discardableResult func requestStart() -> UUID? {
        guard canStart else { return nil }
        let request = UUID()
        startRequestID = request; isStarting = true
        completedSessionID = nil; completedLength = nil
        return request
    }
    /// Called after the feedback view's frame boundary. Every control section remains synchronous.
    func performPendingStart(_ request: UUID) {
        guard startRequestID == request else { return }
        performStart()
    }
    func cancelPendingStart(_ request: UUID) {
        guard startRequestID == request else { return }
        startRequestID = nil; isStarting = false
    }
    private func performStart() {
        #if DEBUG
        let measurementStarted = services.didMeasureStart == nil ? nil : ProcessInfo.processInfo.systemUptime
        defer {
            if let measurementStarted { services.didMeasureStart?(ProcessInfo.processInfo.systemUptime - measurementStarted) }
        }
        #endif
        completedSessionID = nil; completedLength = nil
        isStarting = true; defer { startRequestID = nil; isStarting = false }
        refresh()
        guard errorMessage == nil, access == .approved, current == nil else { return }
        do {
            let counts = services.selection.counts
            try SelectionValidator.validate(appCount: counts.apps, webCount: counts.websites, categoryCount: counts.categories)
            let frozen = services.selection.selection
            let length = services.settings.lengthSeconds
            #if DEBUG
            let startedAt = Date().addingTimeInterval(-(services.fixtureFocusLeft.map { length - $0 } ?? 0))
            #else
            let startedAt = Date()
            #endif
            _ = try services.engine.start(now: startedAt, length: length, authorized: { self.services.authorization.accessState() }, apply: { self.services.applySelection(frozen) }, matches: { self.services.matchesSelection(frozen) })
            refresh()
        } catch {
            refresh()
            errorMessage = "집중 시간을 시작하지 못했어요. 다시 확인해 주세요."
        }
    }
    func end() {
        guard let id = current?.id else { return }
        #if DEBUG
        let measurementStarted = services.didMeasureEnd == nil ? nil : ProcessInfo.processInfo.systemUptime
        #endif
        let finished = Result { try services.engine.finish(id: id, reason: .earlyExit, now: Date()) }
        #if DEBUG
        // From the tap to the return of the engine call; the refresh after it is not part of the end.
        if let measurementStarted { services.didMeasureEnd?(ProcessInfo.processInfo.systemUptime - measurementStarted) }
        #endif
        do { try finished.get(); refresh() }
        catch {
            // The reconcile repairs the stored phase now; when it throws too, `refresh()` keeps the end message and the ticks try again.
            failedEndID = id; refresh()
        }
    }
    func dismissCompletion() { completedSessionID = nil; completedLength = nil }
    func completeOnboarding() { services.settings.hasCompletedOnboarding = true }
    /// `defersBreakStart`: the timer screen reserves the automatic break start, so its feedback can appear before the engine call.
    func tick(defersBreakStart: Bool = false) {
        now = Date()
        guard let current else {
            if failedEndID != nil { refresh() }
            return
        }
        switch current.phase {
        case .waiting:
            // A wait past its grace throws `breakUnavailable`, and the refresh then cancels it.
            if let waitEndsAt = current.waitEndsAt, now >= waitEndsAt {
                if defersBreakStart { requestBreakAction(.startBreak) }
                else if pendingBreak == nil { perform(.startBreak, at: now) }
            }
        case .onBreak:
            if now >= (current.breakEndsAt ?? now) || current.timedEnd(at: now, timing: timing) != nil { refresh() }
        case .active, .breakOver:
            if current.timedEnd(at: now, timing: timing) != nil { refresh() }
        case .preparing, .ending, .terminal:
            if now >= current.expiresAt { refresh() }
        }
    }
    func requestBreak() { if pendingBreak == nil { perform(.request, at: Date()) } }
    func cancelWait() { if pendingBreak == nil { perform(.cancelWait, at: Date()) } }
    func resume() { if pendingBreak == nil { perform(.resume, at: Date()) } }
    /// Reserves a break action before its feedback has had a chance to appear. No control operation runs here.
    @discardableResult func requestBreakAction(_ action: BreakAction) -> UUID? {
        guard pendingBreak == nil, startRequestID == nil, admits(action) else { return nil }
        let request = UUID()
        pendingBreak = PendingBreak(id: request, action: action, requestedAt: now)
        return request
    }
    /// Called after the feedback view's frame boundary. Every control section remains synchronous.
    func performPendingBreak(_ request: UUID) {
        guard let pending = pendingBreak, pending.id == request else { return }
        defer { pendingBreak = nil }
        perform(pending.action, at: pending.action == .startBreak ? pending.requestedAt : Date())
    }
    func cancelPendingBreak(_ request: UUID) {
        guard pendingBreak?.id == request else { return }
        pendingBreak = nil
    }
    /// The waiting screen is a step that the person must watch, so leaving the app cancels the wait.
    /// A pending break action is dropped first; a pending automatic break start then gives way to that cancel.
    func sceneDidLeaveForeground() {
        if let request = startRequestID { cancelPendingStart(request) }
        if accessRecoveryID != nil { accessRecoveryID = nil; isStarting = false }
        if let pending = pendingBreak { cancelPendingBreak(pending.id) }
        if current?.phase == .waiting { cancelWait() }
    }
    /// An `.inactive` overlay such as Control Center keeps the wait, but drops a reserved automatic break start.
    /// The start would otherwise run at its old tick time when the app returns, and the break would lose the time spent away.
    /// The next active tick reserves it again with its own time; past the grace, the stale-wait rule cancels the wait.
    func sceneDidBecomeInactive() {
        if let pending = pendingBreak, pending.action == .startBreak { cancelPendingBreak(pending.id) }
    }
    private func admits(_ action: BreakAction) -> Bool {
        guard let phase = current?.phase else { return false }
        switch action {
        case .request: return phase == .active && breaksLeft > 0
        case .cancelWait, .startBreak: return phase == .waiting
        case .resume: return phase == .onBreak || phase == .breakOver
        }
    }
    /// The unchanged synchronous break transition; `moment` is the engine time of an automatic break start.
    private func perform(_ action: BreakAction, at moment: Date) {
        guard let id = current?.id, admits(action) else { return }
        #if DEBUG
        let measurementStarted = services.didMeasureBreak == nil ? nil : ProcessInfo.processInfo.systemUptime
        defer {
            if let measurementStarted { services.didMeasureBreak?(action, ProcessInfo.processInfo.systemUptime - measurementStarted) }
        }
        #endif
        switch action {
        case .request:
            run({ _ = try services.engine.requestBreak(id: id, now: moment) }, failure: "쉬는 시간을 요청하지 못했어요. 다시 시도해 주세요.")
        case .cancelWait:
            run({ try services.engine.cancelWait(id: id, now: moment) }, failure: "집중으로 돌아가지 못했어요. 다시 시도해 주세요.")
        case .startBreak:
            let frozen = services.selection.selection
            run({ try services.engine.startBreak(id: id, now: moment, saveSelection: { try self.services.saveBreakSelection(frozen, id) }) },
                failure: "쉬는 시간을 시작하지 못했어요. 제한은 그대로예요. 다시 시도해 주세요.")
        case .resume:
            run({ try services.engine.resume(id: id, now: moment) }, failure: "집중을 다시 시작하지 못했어요. 다시 시도해 주세요.")
        }
    }
    /// A break action, then a refresh. A phase that changed in the meantime is not an error.
    private func run(_ action: () throws -> Void, failure: String) {
        do { try action(); refresh() }
        catch {
            refresh()
            if case ControlIssue.breakUnavailable = error { return }
            errorMessage = failure
        }
    }
    func saveSelection(_ selection: FamilyActivitySelection) throws {
        guard !isInSession, !isStarting else { throw ControlIssue.busy }
        try SelectionFeedback.validateUnion(selection, services.everydaySelection())
        try services.selection.save(selection)
    }
}
