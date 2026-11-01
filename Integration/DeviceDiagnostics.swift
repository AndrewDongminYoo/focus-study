#if DEBUG
import Foundation
import FamilyControls
import Observation

/// Opt-in wrapper: the real registration happens before the injected one-shot error.
@Observable final class DiagnosticMonitoring: MonitoringClient {
    private let base: any MonitoringClient
    private(set) var isFailureArmed = false
    init(base: any MonitoringClient) { self.base = base }
    var registeredSessionIDs: [UUID] { base.registeredSessionIDs }
    func armFailure() { isFailureArmed = true }
    func register(id: UUID, start: Date, end: Date) throws {
        let fail = isFailureArmed
        isFailureArmed = false
        try base.register(id: id, start: start, end: end)
        if fail { throw ControlIssue.io }
    }
    func isRegistered(id: UUID) -> Bool { base.isRegistered(id: id) }
    func stop(id: UUID) { base.stop(id: id) }
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws {
        try base.registerBreak(id: id, index: index, start: start, end: end, warning: warning)
    }
    func isBreakRegistered(id: UUID, index: Int) -> Bool { base.isBreakRegistered(id: id, index: index) }
    var registeredBreaks: [(id: UUID, index: Int)] { base.registeredBreaks }
    func stopBreak(id: UUID, index: Int) { base.stopBreak(id: id, index: index) }
    func registerEveryday(revision: UUID, part: EverydayPart, start: Int, end: Int) throws {
        try base.registerEveryday(revision: revision, part: part, start: start, end: end)
    }
    var registeredEveryday: [(revision: UUID, part: EverydayPart)] { base.registeredEveryday }
    func stopEveryday(revision: UUID, part: EverydayPart) { base.stopEveryday(revision: revision, part: part) }
}

@MainActor @Observable final class DeviceDiagnostics {
    let monitoring: DiagnosticMonitoring
    private let engine: SessionControl
    private let hasAccess: () -> Bool
    private let everydayShield: ScreenTimeEverydayShield?
    private var savedActivity: String?
    private(set) var message: String?
    init(monitoring: DiagnosticMonitoring, engine: SessionControl, hasAccess: @escaping () -> Bool, everydayShield: ScreenTimeEverydayShield? = nil) {
        self.monitoring = monitoring; self.engine = engine; self.hasAccess = hasAccess; self.everydayShield = everydayShield
    }
    var canApplyEveryday: Bool { everydayShield != nil }
    /// Device step 9 of the M3 spec: applies a chosen selection to `everydayLayer` without the union check.
    /// The next lock section converges the store to the stored everyday file again.
    func applyEverydayWithoutUnionCheck(_ selection: FamilyActivitySelection) {
        guard let everydayShield else { return }
        everydayShield.apply(selection)
        message = everydayShield.matches(selection)
            ? "매일 제한 store에 선택을 합집합 검사 없이 적용했습니다. 실제로 제한된 앱을 기록해 주세요."
            : "매일 제한 store가 선택과 일치하지 않습니다. 결과를 기록해 주세요."
    }
    func armRegistrationFailure() {
        monitoring.armFailure()
        message = "다음 시작에서 시스템 등록 후 실패를 주입합니다."
    }
    func capture(_ session: ControlSession) {
        guard session.phase == .active else { return }
        savedActivity = session.activityName
        message = "현재 세션 콜백을 저장했습니다. 세션을 종료하고 새 세션을 시작한 뒤 전달해 주세요."
    }
    func canReplay(current: ControlSession?) -> Bool {
        guard let savedActivity, let current, current.phase == .active else { return false }
        return savedActivity != current.activityName
    }
    func replay(current: ControlSession?) throws {
        guard canReplay(current: current), let savedActivity else { throw ControlIssue.invalidState }
        // A stale focus activity delivers `.didEnd`; its name belongs to an earlier session, so nothing is registered for it.
        try engine.handleCallback(activityName: savedActivity, kind: .didEnd, now: Date(), authorized: hasAccess())
        message = "이전 세션 콜백을 전달했습니다. 현재 세션과 제한이 유지되는지 확인해 주세요."
    }
}
#endif
