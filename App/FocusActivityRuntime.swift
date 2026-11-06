import Foundation
import UIKit

@MainActor enum FocusActivityRuntime {
    private static let attemptedKey = "focusActivityAttemptedSession"
    static func hook(engine: SessionControl, defaults: UserDefaults = .standard) -> () -> Void {
        let display = coordinator(engine: engine, defaults: defaults, client: SystemFocusActivityClient(),
                                  canStart: { UIApplication.shared.applicationState == .active })
        return { Task { await display.synchronize() } }
    }
    /// The marker is display-only and app-private. It never authorizes a session or a restriction.
    static func coordinator(engine: SessionControl, defaults: UserDefaults, client: any FocusActivityClient,
                            canStart: @escaping () -> Bool) -> FocusActivityCoordinator {
        FocusActivityCoordinator(client: client, snapshot: engine.activitySnapshot, timing: engine.timing,
                                 canStart: canStart, hasAttempted: { defaults.string(forKey: attemptedKey) == $0.uuidString },
                                 markAttempted: { defaults.set($0.uuidString, forKey: attemptedKey) })
    }
}
