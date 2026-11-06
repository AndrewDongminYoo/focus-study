import ActivityKit
import Foundation

@MainActor final class SystemFocusActivityClient: FocusActivityClient {
    var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    var activities: [FocusActivityHandle] {
        Activity<FocusActivityAttributes>.activities.map {
            FocusActivityHandle(id: $0.id, sessionID: $0.attributes.sessionID, isLive: $0.activityState == .active || $0.activityState == .stale)
        }
    }
    func request(_ projection: FocusActivityProjection) throws {
        do {
            _ = try Activity.request(attributes: FocusActivityAttributes(sessionID: projection.sessionID),
                                     content: ActivityContent(state: projection.content, staleDate: projection.content.staleAt), pushType: nil)
            log("request succeeded")
        } catch {
            log("request failed code=\((error as NSError).code)")
            throw error
        }
    }
    func update(_ activity: FocusActivityHandle, content: FocusActivityContent) async {
        guard let current = find(activity) else { return }
        await current.update(ActivityContent(state: content, staleDate: content.staleAt))
        log("update \(content.phase.rawValue)")
    }
    func end(_ activity: FocusActivityHandle) async {
        guard let current = find(activity) else { return }
        await current.end(nil, dismissalPolicy: .immediate)
        log("end")
    }
    private func find(_ activity: FocusActivityHandle) -> Activity<FocusActivityAttributes>? {
        Activity<FocusActivityAttributes>.activities.first { $0.id == activity.id && $0.attributes.sessionID == activity.sessionID }
    }
    private func log(_ message: String) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--live-activity-probe") { NSLog("LIVE_ACTIVITY_PROBE %@", message) }
        #endif
    }
}
