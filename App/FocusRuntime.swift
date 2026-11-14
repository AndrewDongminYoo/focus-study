import Foundation
import FamilyControls
import SwiftData
import WidgetKit
import os

@MainActor struct FocusRuntime {
    let recovery: StartupRecovery
    /// The main-queue access read of launch recovery; a cold launch reads `unknown` until the published value settles.
    let accessState: () -> AccessState
    /// The services and the `ModelContainer`, built once for the screens and the Focus filter.
    let holder: FocusRuntimeHolder
    private static var current: FocusRuntime?
    /// The runtime of this process. The screens and the Focus filter both start here; with `--ui-testing` it is the fixture runtime.
    /// A background launch for the filter has no launch arguments, so it builds the real runtime.
    static func process() throws -> FocusRuntime {
        if let current { return current }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let built = arguments.contains("--ui-testing") ? try fixture(arguments: arguments) : try real()
        #else
        let built = try real()
        #endif
        current = built
        return built
    }
    /// `FocusStudyFilter.perform()` delegates here.
    static func focusFilterDidChange(startsSession: Bool) async {
        do { try await process().holder.focusDidChange(startsSession: startsSession) }
        catch { if startsSession { FocusSettings().recordFilterRefusal(.error, at: Date()) } }
    }
    /// The activation check on launch and foreground. A fixture runtime never reads a real Focus.
    func checkActivation() async {
        defer { holder.notifyActivity() }
        guard let handler = try? holder.filterHandler(), let (services, _) = try? holder.load() else { return }
        await handler.checkActivation(reading: services.isFixture ? { .unknown } : FocusStudyFilter.reading)
    }
    static func real() throws -> FocusRuntime {
        let authorization = AuthorizationService(), shield = ScreenTimeShield()
        let systemMonitoring = ScreenTimeMonitoring()
        #if DEBUG
        let monitoring: any MonitoringClient
        let diagnosticMonitoring: DiagnosticMonitoring?
        // A unified-log `Logger`, so that `log collect` on the device keeps these lines next to the Monitor's `MONITOR_TIMING` lines; `NSLog` lines were not in the archives of 2026-11-14.
        let timingLog = Logger(subsystem: "kr.donminzzi.focusStudy", category: "timing")
        let logTiming: (ScreenTimeOperation, TimeInterval) -> Void = { operation, duration in
            timingLog.log("SCREEN_TIME_TIMING op=\(operation.rawValue, privacy: .public) ms=\(String(format: "%.3f", duration * 1000), privacy: .public)")
        }
        if ProcessInfo.processInfo.arguments.contains("--screen-time-diagnostics") {
            let wrapped = DiagnosticMonitoring(base: systemMonitoring, didMeasure: logTiming)
            diagnosticMonitoring = wrapped; monitoring = wrapped
        } else { diagnosticMonitoring = nil; monitoring = systemMonitoring }
        #else
        let monitoring = systemMonitoring
        #endif
        let group = try GroupConfiguration.directory()
        #if DEBUG
        // The Monitor gets no launch arguments, so this flag file turns its timing lines on; every launch of the real runtime without the argument removes it.
        MonitorTimingFlag.set(launchArguments: ProcessInfo.processInfo.arguments, directory: group)
        #endif
        // The app and the Monitor re-block from the same frozen copy in the App Group.
        let breakSelection = BreakSelectionFile(directory: group, shield: shield)
        // The everyday file and its named store; the Monitor reads the same file.
        let everydayShield = ScreenTimeEverydayShield()
        let everyday = EverydayLayerFile(directory: group, shield: everydayShield)
        let engine = SessionControl(store: SharedControlStore(directory: group), monitoring: monitoring, shield: shield, breakSelection: breakSelection, everyday: everyday)
        let activityDidChange = FocusActivityRuntime.hook(engine: engine)
        #if DEBUG
        let diagnostics = diagnosticMonitoring.map {
            DeviceDiagnostics(monitoring: $0, engine: engine, hasAccess: authorization.accessState, everydayShield: everydayShield,
                              probe: RegistrationProbe(center: SystemRegistrationProbeCenter()))
        }
        #endif
        // One settings object for the screens and the filter, so that a refusal recorded by the filter updates the guide that is shown.
        let settings = FocusSettings()
        // One writer per process, so its first write check asks for one reload; `group` is `SessionControl/` inside the container.
        let todaySnapshot = TodaySnapshotWriter(container: group.deletingLastPathComponent()) { WidgetCenter.shared.reloadTimelines(ofKind: TodaySnapshot.widgetKind) }
        return FocusRuntime(recovery: StartupRecovery(engine: engine), accessState: authorization.accessState, holder: FocusRuntimeHolder(engine: engine, authorization: authorization, settings: settings, activityDidChange: activityDidChange) {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("PrivateSelection")
            #if DEBUG
            let applySelection: (FamilyActivitySelection) -> Void = diagnostics == nil ? shield.apply : { selection in measureScreenTime(.applyShield, report: logTiming) { shield.apply(selection) } }
            #else
            let applySelection: (FamilyActivitySelection) -> Void = shield.apply
            #endif
            var services = FocusServices(authorization: authorization, selection: try SelectionRepository(directory: directory), engine: engine, applySelection: applySelection, matchesSelection: shield.matches)
            services.settings = settings
            services.activityDidChange = activityDidChange
            services.saveBreakSelection = { try breakSelection.save($0, id: $1) }
            services.everydaySelection = { (try? everyday.selection()) ?? nil }
            services.everydayContains = { try everyday.contains($0) }
            services.writeEveryday = { try everyday.write($0, selection: $1) }
            services.writeEverydayOffDay = { try everyday.writeOffDay($0) }
            services.writeTodaySnapshot = { try todaySnapshot.write($0) }
            #if DEBUG
            services.diagnostics = diagnostics
            if diagnostics != nil {
                services.didMeasureStart = { duration in timingLog.log("START_LATENCY total_ms=\(String(format: "%.3f", duration * 1000), privacy: .public)") }
                services.didMeasureBreak = { action, duration in
                    timingLog.log("BREAK_LATENCY action=\(action.rawValue, privacy: .public) total_ms=\(String(format: "%.3f", duration * 1000), privacy: .public)")
                }
                services.didMeasureEnd = { duration in timingLog.log("END_LATENCY total_ms=\(String(format: "%.3f", duration * 1000), privacy: .public)") }
            }
            #endif
            let container = try ModelContainer(for: SessionRecord.self, configurations: ModelConfiguration(cloudKitDatabase: .none))
            return (services, container)
        })
    }
    func prepare() throws -> (FocusServices, ModelContainer) {
        defer { holder.notifyActivity() }
        var loaded: (FocusServices, ModelContainer)?
        try recovery.prepare(now: Date(), authorized: accessState()) { loaded = try holder.load() }
        guard let loaded else { throw ControlIssue.io }
        return loaded
    }
}
