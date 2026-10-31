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
    #if DEBUG
    var diagnostics: DeviceDiagnostics?
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
    var access: AccessStatus { services.authorization.status }
    var isActive: Bool { current?.phase == .active }
    var counts: (apps: Int, websites: Int, categories: Int) { services.selection.counts }
    var canStart: Bool { access == .approved && current == nil && !isStarting && errorMessage == nil && counts.apps + counts.websites > 0 }
    /// The first unmet start condition, in the order the person has to resolve them.
    var startBlocker: StartBlocker? {
        guard current == nil, !isStarting else { return nil }
        if access != .approved { return .access }
        if errorMessage != nil { return .error }
        return counts.apps + counts.websites == 0 ? .selection : nil
    }
    var remaining: Int { current.map { TimeRules.remaining(startedAt: $0.startedAt, expiresAt: $0.expiresAt, now: now) } ?? Int(services.settings.lengthSeconds) }
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
        do {
            if let terminal = current, terminal.phase == .terminal {
                try history.importTerminal(terminal)
                if terminal.reason == .expired { completedSessionID = terminal.id }
                current = try services.engine.snapshot().session
            }
            records = try history.records(on: now, calendar: .current)
            errorMessage = nil
        } catch {
            // A history failure does not invalidate a confirmed control session or its early-exit action.
            errorMessage = "기록을 불러오지 못했어요. 다시 확인해 주세요. 진행 중인 세션은 종료할 수 있어요."
        }
    }

    func start() {
        guard canStart else { return }
        completedSessionID = nil
        isStarting = true; defer { isStarting = false }
        refresh()
        guard errorMessage == nil, access == .approved, current == nil else { return }
        do {
            let counts = services.selection.counts
            try SelectionValidator.validate(appCount: counts.apps, webCount: counts.websites, categoryCount: counts.categories)
            let frozen = services.selection.selection
            _ = try services.engine.start(now: Date(), length: services.settings.lengthSeconds, authorized: { self.services.authorization.hasAccessNow() }, apply: { self.services.applySelection(frozen) }, matches: { self.services.matchesSelection(frozen) })
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
    func dismissCompletion() { completedSessionID = nil }
    func completeOnboarding() { services.settings.hasCompletedOnboarding = true }
    func tick() {
        now = Date()
        if let current, now >= current.expiresAt { refresh() }
    }
    func saveSelection(_ selection: FamilyActivitySelection) throws {
        guard !isActive, !isStarting else { throw ControlIssue.busy }
        try services.selection.save(selection)
    }
}
