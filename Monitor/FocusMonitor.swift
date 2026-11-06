import Foundation
import DeviceActivity
import FamilyControls

final class FocusMonitor: DeviceActivityMonitor {
    @MainActor private static var activityCoordinator: FocusActivityCoordinator?
    override func intervalDidStart(for activity: DeviceActivityName) { super.intervalDidStart(for: activity); reconcile(activity, kind: .didStart) }
    override func intervalDidEnd(for activity: DeviceActivityName) { super.intervalDidEnd(for: activity); reconcile(activity, kind: .didEnd) }
    /// The warning of a break activity re-blocks at the end of the break, usually without the app.
    override func intervalWillEndWarning(for activity: DeviceActivityName) { super.intervalWillEndWarning(for: activity); reconcile(activity, kind: .willEndWarning) }
    private func reconcile(_ activity: DeviceActivityName, kind: CallbackKind) {
        let shield = ScreenTimeShield()
        do {
            let directory = try GroupConfiguration.directory()
            // Every name reaches the engine: the everyday convergence depends only on the stored files and the time.
            let engine = SessionControl(store: SharedControlStore(directory: directory), monitoring: ScreenTimeMonitoring(), shield: shield,
                                        breakSelection: BreakSelectionFile(directory: directory, shield: shield),
                                        everyday: EverydayLayerFile(directory: directory, shield: ScreenTimeEverydayShield()))
            // The callback's process lock has been released before this task reads/publishes.
            defer { Self.synchronizeActivity(engine: engine) }
            try engine.handleCallbackRetryingLock(activityName: activity.rawValue, kind: kind, now: Date.init,
                                                  authorized: { ScreenTimeAccess.isApproved(AuthorizationCenter.shared.authorizationStatus) })
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
