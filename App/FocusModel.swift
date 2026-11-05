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
    /// Writes the session-scoped selection copy for a break. Without one, no break can start, so the shield is never cleared.
    var saveBreakSelection: (FamilyActivitySelection, UUID) throws -> Void = { _, _ in throw ControlIssue.io }
    /// The stored everyday selection; an unreadable everyday file gives `nil`, because the layer then blocks nothing.
    var everydaySelection: () -> FamilyActivitySelection? = { nil }
    /// `true` when the new everyday selection holds every app and website of the stored one.
    var everydayContains: (FamilyActivitySelection) throws -> Bool = { _ in true }
    /// Writes `everyday-layer.json`; it runs inside the engine's save section.
    var writeEveryday: (EverydaySchedule, FamilyActivitySelection) throws -> Void = { _, _ in throw ControlIssue.io }
    #if DEBUG
    var diagnostics: DeviceDiagnostics?
    /// Opt-in timing of the complete synchronous start call; never carries selection or usage data.
    var didMeasureStart: ((TimeInterval) -> Void)?
    /// `--ui-testing ending-soon`: the focus seconds left when `start()` begins a session; the start time moves into the past.
    var fixtureFocusLeft: TimeInterval?
    #endif

}
enum StartBlocker: Equatable { case access, error, selection }
enum OnboardingStep: Int, CaseIterable { case intro, permission, selection, length }
enum LaunchRoute: Equatable { case onboarding(OnboardingStep), timer }
@MainActor @Observable final class FocusModel {
    let services: FocusServices
    private let history: any SessionHistoryProviding
    private(set) var current: ControlSession?
    private(set) var records: [SessionRecord] = []
    private(set) var errorMessage: String?
    private(set) var isStarting = false
    private(set) var now = Date()
    /// The most recent session that reached its full length, until the person dismisses it.
    private(set) var completedSessionID: UUID?
    /// That session's own length; today's records can miss it (a session that crossed midnight, a history failure).
    private(set) var completedLength: TimeInterval?
    /// The everyday layer for the settings row. The timer screen does not show it.
    private(set) var everydayStatus: EverydayStatus?
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
    var canStart: Bool { access == .approved && current == nil && !isStarting && errorMessage == nil && counts.apps + counts.websites > 0 }
    /// The first unmet start condition, in the order the person has to resolve them.
    var startBlocker: StartBlocker? {
        guard current == nil, !isStarting else { return nil }
        if access != .approved { return .access }
        if errorMessage != nil { return .error }
        return counts.apps + counts.websites == 0 ? .selection : nil
    }
    var remaining: Int { current.map { TimeRules.remaining(session: $0, now: now) } ?? Int(services.settings.lengthSeconds) }
    /// Which screen launch shows: onboarding resumes at its first unfinished step; a finished person who lost access or selection returns to that step.
    var route: LaunchRoute {
        let hasSelection = counts.apps + counts.websites > 0
        if !services.settings.hasCompletedOnboarding {
            switch access {
            case .notRequested: return .onboarding(.intro)
            case .denied: return .onboarding(.permission)
            case .approved: return .onboarding(hasSelection ? .length : .selection)
            }
        }
        if access != .approved { return .onboarding(.permission) }
        return hasSelection ? .timer : .onboarding(.selection)
    }
    convenience init(services: FocusServices, context: ModelContext) {
        self.init(services: services, history: SessionHistory(context: context, acknowledge: services.engine.acknowledgeTerminal))
    }
    init(services: FocusServices, history: any SessionHistoryProviding) {
        self.services = services; self.history = history
    }
    func refresh(clockChanged: Bool = false) {
        services.authorization.refresh(); now = Date()
        do {
            try services.engine.reconcile(now: now, authorized: access == .approved, clockChanged: clockChanged)
            current = try services.engine.snapshot().session
        } catch {
            current = nil
            errorMessage = "상태를 확인하지 못했어요. 다시 확인해 주세요."
            return
        }
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
        refreshEveryday()
    }
    /// Its own `do`/`catch`: a lock timeout against a Monitor everyday callback never changes `current` or `errorMessage`.
    func refreshEveryday() {
        do { everydayStatus = try services.engine.everydayStatus(now: Date(), authorized: access == .approved) }
        catch {
            var kept = everydayStatus ?? EverydayStatus(schedule: nil, blocksNow: false, nextChange: nil, issue: nil)
            kept.issue = .unchecked; everydayStatus = kept
        }
    }

    func start() {
        guard canStart else { return }
        #if DEBUG
        let measurementStarted = services.didMeasureStart == nil ? nil : ProcessInfo.processInfo.systemUptime
        defer {
            if let measurementStarted { services.didMeasureStart?(ProcessInfo.processInfo.systemUptime - measurementStarted) }
        }
        #endif
        completedSessionID = nil; completedLength = nil
        isStarting = true; defer { isStarting = false }
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
            _ = try services.engine.start(now: startedAt, length: length, authorized: { self.services.authorization.hasAccessNow() }, apply: { self.services.applySelection(frozen) }, matches: { self.services.matchesSelection(frozen) })
            refresh()
        } catch {
            refresh()
            errorMessage = "집중 시간을 시작하지 못했어요. 다시 확인해 주세요."
        }
    }
    func end() {
        guard let id = current?.id else { return }
        do { try services.engine.finish(id: id, reason: .earlyExit, now: Date()); refresh() }
        catch { current = nil; errorMessage = "종료 상태를 저장하지 못했어요. 다시 확인해 주세요." }
    }
    func dismissCompletion() { completedSessionID = nil; completedLength = nil }
    func completeOnboarding() { services.settings.hasCompletedOnboarding = true }
    func tick() {
        now = Date()
        guard let current else { return }
        switch current.phase {
        case .waiting:
            // A wait past its grace throws `breakUnavailable`, and the refresh then cancels it.
            if let waitEndsAt = current.waitEndsAt, now >= waitEndsAt { startBreak(current) }
        case .onBreak:
            if now >= (current.breakEndsAt ?? now) || current.timedEnd(at: now, timing: timing) != nil { refresh() }
        case .active, .breakOver:
            if current.timedEnd(at: now, timing: timing) != nil { refresh() }
        case .preparing, .ending, .terminal:
            if now >= current.expiresAt { refresh() }
        }
    }
    func requestBreak() {
        guard let id = current?.id, isActive, breaksLeft > 0 else { return }
        run({ _ = try services.engine.requestBreak(id: id, now: Date()) }, failure: "쉬는 시간을 요청하지 못했어요. 다시 시도해 주세요.")
    }
    func cancelWait() {
        guard let id = current?.id, current?.phase == .waiting else { return }
        run({ try services.engine.cancelWait(id: id, now: Date()) }, failure: "집중으로 돌아가지 못했어요. 다시 시도해 주세요.")
    }
    func resume() {
        guard let id = current?.id, current?.phase == .breakOver else { return }
        run({ try services.engine.resume(id: id, now: Date()) }, failure: "집중을 다시 시작하지 못했어요. 다시 시도해 주세요.")
    }
    /// The waiting screen is a step that the person must watch, so leaving the app cancels the wait.
    func sceneDidLeaveForeground() { if current?.phase == .waiting { cancelWait() } }
    private func startBreak(_ session: ControlSession) {
        let frozen = services.selection.selection, id = session.id
        run({ try services.engine.startBreak(id: id, now: now, saveSelection: { try self.services.saveBreakSelection(frozen, id) }) },
            failure: "쉬는 시간을 시작하지 못했어요. 제한은 그대로예요. 다시 시도해 주세요.")
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
