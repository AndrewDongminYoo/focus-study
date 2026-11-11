#if DEBUG
import Foundation
import DeviceActivity
import FamilyControls
import Observation

/// A Screen Time operation timed under `--screen-time-diagnostics`; the raw value names it in the `SCREEN_TIME_TIMING` log.
enum ScreenTimeOperation: String {
    case applyShield = "apply_shield"
    case register
    case registerBreak = "register_break"
    case registerEveryday = "register_everyday"
    case stop
    case stopBreak = "stop_break"
    case stopEveryday = "stop_everyday"
}

/// Runs `body` and reports its duration on the monotonic uptime clock, also when `body` throws.
func measureScreenTime<T>(_ operation: ScreenTimeOperation, report: (ScreenTimeOperation, TimeInterval) -> Void, _ body: () throws -> T) rethrows -> T {
    let started = ProcessInfo.processInfo.systemUptime
    defer { report(operation, ProcessInfo.processInfo.systemUptime - started) }
    return try body()
}

/// Opt-in wrapper: the real registration happens before the injected one-shot error.
/// Each registration and stop reports the duration of the real `base` call only, through `didMeasure`.
@Observable final class DiagnosticMonitoring: MonitoringClient {
    private let base: any MonitoringClient
    private let didMeasure: (ScreenTimeOperation, TimeInterval) -> Void
    private(set) var isFailureArmed = false
    init(base: any MonitoringClient, didMeasure: @escaping (ScreenTimeOperation, TimeInterval) -> Void = { _, _ in }) {
        self.base = base; self.didMeasure = didMeasure
    }
    var registeredSessionIDs: [UUID] { base.registeredSessionIDs }
    func armFailure() { isFailureArmed = true }
    func register(id: UUID, start: Date, end: Date) throws {
        let fail = isFailureArmed
        isFailureArmed = false
        try measureScreenTime(.register, report: didMeasure) { try base.register(id: id, start: start, end: end) }
        if fail { throw ControlIssue.io }
    }
    func isRegistered(id: UUID) -> Bool { base.isRegistered(id: id) }
    func stop(id: UUID) { measureScreenTime(.stop, report: didMeasure) { base.stop(id: id) } }
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws {
        try measureScreenTime(.registerBreak, report: didMeasure) { try base.registerBreak(id: id, index: index, start: start, end: end, warning: warning) }
    }
    func isBreakRegistered(id: UUID, index: Int) -> Bool { base.isBreakRegistered(id: id, index: index) }
    var registeredBreaks: [(id: UUID, index: Int)] { base.registeredBreaks }
    func stopBreak(id: UUID, index: Int) { measureScreenTime(.stopBreak, report: didMeasure) { base.stopBreak(id: id, index: index) } }
    func registerEveryday(revision: UUID, part: EverydayPart, start: Int, end: Int) throws {
        try measureScreenTime(.registerEveryday, report: didMeasure) { try base.registerEveryday(revision: revision, part: part, start: start, end: end) }
    }
    var registeredEveryday: [(revision: UUID, part: EverydayPart)] { base.registeredEveryday }
    func stopEveryday(revision: UUID, part: EverydayPart) { measureScreenTime(.stopEveryday, report: didMeasure) { base.stopEveryday(revision: revision, part: part) } }
}

/// The two interval cases of the registration probe: one that contains now and one that starts later.
enum RegistrationProbeInterval: String, CaseIterable {
    case current, future
}

/// The probe's only access to `DeviceActivityCenter`, so that tests do not need Screen Time.
protocol RegistrationProbeCenter {
    func start(name: String, start: Date, end: Date) throws
    /// Stops the named activities only.
    func stop(names: [String])
}

final class SystemRegistrationProbeCenter: RegistrationProbeCenter {
    private let center = DeviceActivityCenter()
    /// The same non-repeating schedule as a focus registration.
    func start(name: String, start: Date, end: Date) throws {
        try center.startMonitoring(DeviceActivityName(name), during: ScreenTimeMonitoring.schedule(start: start, end: end, calendar: .current))
    }
    func stop(names: [String]) {
        // `stopMonitoring([])` would stop every activity, also the focus, break and everyday activities.
        guard !names.isEmpty else { return }
        center.stopMonitoring(names.map { DeviceActivityName($0) })
    }
}

/// Times throwaway `probe.<interval>.<n>` registrations, which no session, break or everyday name parser accepts.
/// It holds no process lock and never touches the control store or a shield.
struct RegistrationProbe {
    struct Sample: Equatable {
        let interval: RegistrationProbeInterval
        let n: Int
        let duration: TimeInterval
        let failed: Bool
    }
    static let runs = 3
    static let length: TimeInterval = 20 * 60
    static let futureLead: TimeInterval = 2 * 60
    let center: any RegistrationProbeCenter
    var now: () -> Date = Date.init
    var uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var log: (String) -> Void = { NSLog("%@", $0) }
    static func activityName(_ interval: RegistrationProbeInterval, _ n: Int) -> String { "probe.\(interval.rawValue).\(n)" }
    static var activityNames: [String] { (1...runs).flatMap { n in RegistrationProbeInterval.allCases.map { activityName($0, n) } } }
    /// Alternates `current` and `future` three times; each activity stops right after its registration, and all stop again at the end.
    func run() -> [Sample] {
        defer { center.stop(names: Self.activityNames) }
        var samples: [Sample] = []
        for n in 1...Self.runs {
            for interval in RegistrationProbeInterval.allCases {
                let name = Self.activityName(interval, n)
                let start = now().addingTimeInterval(interval == .future ? Self.futureLead : 0)
                let began = uptime()
                var failure: Error?
                do { try center.start(name: name, start: start, end: start.addingTimeInterval(Self.length)) } catch { failure = error }
                let duration = uptime() - began
                let ms = String(format: "%.3f", duration * 1000)
                if let failure {
                    log("SCREEN_TIME_PROBE interval=\(interval.rawValue) n=\(n) failed ms=\(ms) error=\(String(describing: failure))")
                } else {
                    log("SCREEN_TIME_PROBE interval=\(interval.rawValue) n=\(n) ms=\(ms)")
                }
                samples.append(Sample(interval: interval, n: n, duration: duration, failed: failure != nil))
                center.stop(names: [name])
            }
        }
        return samples
    }
}

@MainActor @Observable final class DeviceDiagnostics {
    let monitoring: DiagnosticMonitoring
    private let engine: SessionControl
    private let hasAccess: () -> AccessState
    private let everydayShield: ScreenTimeEverydayShield?
    private let probe: RegistrationProbe?
    private var savedActivity: String?
    private(set) var message: String?
    init(monitoring: DiagnosticMonitoring, engine: SessionControl, hasAccess: @escaping () -> AccessState, everydayShield: ScreenTimeEverydayShield? = nil,
         probe: RegistrationProbe? = nil) {
        self.monitoring = monitoring; self.engine = engine; self.hasAccess = hasAccess; self.everydayShield = everydayShield; self.probe = probe
    }
    var canApplyEveryday: Bool { everydayShield != nil }
    var canProbeRegistration: Bool { probe != nil }
    /// Compares the registration time of a current and a future interval, only while no session is stored or registered.
    /// The read never runs recovery, so a refusal changes nothing.
    func runRegistrationProbe() {
        guard let probe else { return }
        let stored: ControlSession?
        do { stored = try engine.activitySnapshot() } catch {
            message = "세션 상태를 읽지 못해 비교하지 않았습니다."
            return
        }
        guard stored == nil, monitoring.registeredSessionIDs.isEmpty else {
            message = "세션이 남아 있어 비교하지 않았습니다. 세션을 끝낸 뒤 다시 눌러 주세요."
            return
        }
        let samples = probe.run()
        let values = { (interval: RegistrationProbeInterval) in
            samples.filter { $0.interval == interval }.map { $0.failed ? "실패" : String(format: "%.1f", $0.duration * 1000) }.joined(separator: ", ")
        }
        message = "등록 시간(ms) current: \(values(.current)) / future: \(values(.future))"
    }
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
