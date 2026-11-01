import Foundation
import FamilyControls
import SwiftData

@MainActor struct FocusRuntime {
    let recovery: StartupRecovery
    let hasAccess: () -> Bool
    let loadStorage: () throws -> (FocusServices, ModelContainer)
    static func real() throws -> FocusRuntime {
        let authorization = AuthorizationService(), shield = ScreenTimeShield()
        let systemMonitoring = ScreenTimeMonitoring()
        #if DEBUG
        let monitoring: any MonitoringClient
        let diagnosticMonitoring: DiagnosticMonitoring?
        if ProcessInfo.processInfo.arguments.contains("--screen-time-diagnostics") {
            let wrapped = DiagnosticMonitoring(base: systemMonitoring)
            diagnosticMonitoring = wrapped; monitoring = wrapped
        } else { diagnosticMonitoring = nil; monitoring = systemMonitoring }
        #else
        let monitoring = systemMonitoring
        #endif
        let group = try GroupConfiguration.directory()
        // The app and the Monitor re-block from the same frozen copy in the App Group.
        let breakSelection = BreakSelectionFile(directory: group, shield: shield)
        // The everyday file and its named store; the Monitor reads the same file.
        let everydayShield = ScreenTimeEverydayShield()
        let everyday = EverydayLayerFile(directory: group, shield: everydayShield)
        let engine = SessionControl(store: SharedControlStore(directory: group), monitoring: monitoring, shield: shield, breakSelection: breakSelection, everyday: everyday)
        #if DEBUG
        let diagnostics = diagnosticMonitoring.map { DeviceDiagnostics(monitoring: $0, engine: engine, hasAccess: authorization.hasAccessNow, everydayShield: everydayShield) }
        #endif
        return FocusRuntime(recovery: StartupRecovery(engine: engine), hasAccess: authorization.hasAccessNow, loadStorage: {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("PrivateSelection")
            var services = FocusServices(authorization: authorization, selection: try SelectionRepository(directory: directory), engine: engine, applySelection: shield.apply, matchesSelection: shield.matches)
            services.saveBreakSelection = { try breakSelection.save($0, id: $1) }
            services.everydaySelection = { (try? everyday.selection()) ?? nil }
            services.everydayContains = { try everyday.contains($0) }
            services.writeEveryday = { try everyday.write($0, selection: $1) }
            #if DEBUG
            services.diagnostics = diagnostics
            #endif
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
