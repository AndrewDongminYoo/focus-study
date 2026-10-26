import Foundation
import FamilyControls
import SwiftData

@MainActor struct FocusRuntime {
    let recovery: StartupRecovery
    let hasAccess: () -> Bool
    let loadStorage: () throws -> (FocusServices, ModelContainer)
    static func real() throws -> FocusRuntime {
        let authorization = AuthorizationService(), shield = ScreenTimeShield()
        let engine = SessionControl(store: SharedControlStore(directory: try GroupConfiguration.directory()), monitoring: ScreenTimeMonitoring(), shield: shield)
        return FocusRuntime(recovery: StartupRecovery(engine: engine), hasAccess: authorization.hasAccessNow, loadStorage: {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("PrivateSelection")
            let services = FocusServices(authorization: authorization, selection: try SelectionRepository(directory: directory), engine: engine, applySelection: shield.apply, matchesSelection: shield.matches)
            let container = try ModelContainer(for: SessionRecord.self, configurations: ModelConfiguration(cloudKitDatabase: .none))
            return (services, container)
        })
    }
    func prepare() throws -> (FocusServices, ModelContainer) {
        var loaded: (FocusServices, ModelContainer)?
        try recovery.prepare(now: Date(), authorized: hasAccess()) { loaded = try loadStorage() }
        guard let loaded else { throw ControlIssue.io }
        return loaded
    }
}
