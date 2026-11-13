import Foundation
import DeviceActivity
import FamilyControls
#if DEBUG
import os
#endif

final class FocusMonitor: DeviceActivityMonitor {
    @MainActor private static var activityCoordinator: FocusActivityCoordinator?
    #if DEBUG
    /// The notice level, so that the device keeps the lines and `log show` prints them without `--info`.
    private static let timingLog = Logger(subsystem: "kr.donminzzi.focusStudy.monitor", category: "timing")
    #endif
    override func intervalDidStart(for activity: DeviceActivityName) { super.intervalDidStart(for: activity); reconcile(activity, kind: .didStart) }
    override func intervalDidEnd(for activity: DeviceActivityName) { super.intervalDidEnd(for: activity); reconcile(activity, kind: .didEnd) }
    /// The warning of a break activity re-blocks at the end of the break, usually without the app.
    override func intervalWillEndWarning(for activity: DeviceActivityName) { super.intervalWillEndWarning(for: activity); reconcile(activity, kind: .willEndWarning) }
    private func reconcile(_ activity: DeviceActivityName, kind: CallbackKind) {
        let shield = ScreenTimeShield()
        do {
            let directory = try GroupConfiguration.directory()
            let store = SharedControlStore(directory: directory), monitoring = ScreenTimeMonitoring()
            let breakSelection = BreakSelectionFile(directory: directory, shield: shield)
            let everyday = EverydayLayerFile(directory: directory, shield: ScreenTimeEverydayShield())
            // Every name reaches the engine: the everyday convergence depends only on the stored files and the time.
            let engine = SessionControl(store: store, monitoring: monitoring, shield: shield, breakSelection: breakSelection, everyday: everyday)
            // The callback's process lock has been released before this task reads/publishes.
            defer { Self.synchronizeActivity(engine: engine) }
            #if DEBUG
            // With a valid flag, a second engine with the timing wrappers handles the callback; the Live Activity read above keeps the plain engine and is not timed.
            // The recorder gets a fixed activity kind and never the name, so the one public string of a line holds fixed values and numbers only.
            if let timing = MonitorTimingRecorder.begin(directory: directory, activity: MonitorTimingActivity(activityName: activity.rawValue), kind: kind,
                                                        emit: { line in Self.timingLog.notice("\(line, privacy: .public)") }) {
                let timed = timing.engine(store: store, monitoring: monitoring, shield: shield, breakSelection: breakSelection, everyday: everyday)
                try timing.run {
                    try timed.handleCallbackRetryingLock(activityName: activity.rawValue, kind: kind, now: Date.init,
                                                         authorized: { timing.access { ScreenTimeAccess.current() } })
                }
                return
            }
            #endif
            try engine.handleCallbackRetryingLock(activityName: activity.rawValue, kind: kind, now: Date.init,
                                                  authorized: { ScreenTimeAccess.current() })
        } catch {
            // No sensitive logging; a lock timeout was already retried a few times, and other failures wait for a later lifecycle event or an app reconcile.
        }
    }
    private static func synchronizeActivity(engine: SessionControl) {
        Task { @MainActor in
            if activityCoordinator == nil {
                activityCoordinator = FocusActivityCoordinator(client: SystemFocusActivityClient(), snapshot: engine.activitySnapshot,
                                                               timing: engine.timing, canStart: { false }, hasAttempted: { _ in true }, markAttempted: { _ in })
            }
            await activityCoordinator?.synchronize()
        }
    }
}
