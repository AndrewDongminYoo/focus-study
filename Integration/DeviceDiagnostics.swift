#if DEBUG
import Foundation
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
}

@MainActor @Observable final class DeviceDiagnostics {
    let monitoring: DiagnosticMonitoring
    private let engine: SessionControl
    private let hasAccess: () -> Bool
    private var savedActivity: String?
    private(set) var message: String?
    init(monitoring: DiagnosticMonitoring, engine: SessionControl, hasAccess: @escaping () -> Bool) {
        self.monitoring = monitoring; self.engine = engine; self.hasAccess = hasAccess
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
        try engine.handleCallback(activityName: savedActivity, now: Date(), authorized: hasAccess())
        message = "이전 세션 콜백을 전달했습니다. 현재 세션과 제한이 유지되는지 확인해 주세요."
    }
}
#endif
