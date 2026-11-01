import Foundation
import DeviceActivity
import FamilyControls

final class FocusMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) { super.intervalDidStart(for: activity); reconcile(activity, kind: .didStart) }
    override func intervalDidEnd(for activity: DeviceActivityName) { super.intervalDidEnd(for: activity); reconcile(activity, kind: .didEnd) }
    /// The warning of a break activity re-blocks at the end of the break, usually without the app.
    override func intervalWillEndWarning(for activity: DeviceActivityName) { super.intervalWillEndWarning(for: activity); reconcile(activity, kind: .willEndWarning) }
    private func reconcile(_ activity: DeviceActivityName, kind: CallbackKind) {
        let shield = ScreenTimeShield()
        do {
            let directory = try GroupConfiguration.directory()
            let engine = SessionControl(store: SharedControlStore(directory: directory), monitoring: ScreenTimeMonitoring(), shield: shield,
                                        breakSelection: BreakSelectionFile(directory: directory, shield: shield))
            try engine.handleCallbackRetryingLock(activityName: activity.rawValue, kind: kind, now: Date.init,
                                                  authorized: { ScreenTimeAccess.isApproved(AuthorizationCenter.shared.authorizationStatus) })
        } catch {
            // No sensitive logging; a lock timeout was already retried a few times, and other failures wait for a later lifecycle event or an app reconcile.
        }
    }
}
