import Foundation
import DeviceActivity
import FamilyControls

final class FocusMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) { super.intervalDidStart(for: activity); reconcile(activity) }
    override func intervalDidEnd(for activity: DeviceActivityName) { super.intervalDidEnd(for: activity); reconcile(activity) }
    private func reconcile(_ activity: DeviceActivityName) {
        let shield = ScreenTimeShield()
        do {
            let engine = SessionControl(store: SharedControlStore(directory: try GroupConfiguration.directory()), monitoring: ScreenTimeMonitoring(), shield: shield)
            try engine.handleCallback(activityName: activity.rawValue, now: Date(), authorized: ScreenTimeAccess.isApproved(AuthorizationCenter.shared.authorizationStatus))
        } catch {
            // No sensitive logging; lock failures retry on a later lifecycle event.
        }
    }
}
