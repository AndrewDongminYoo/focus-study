import Foundation
import SwiftData

/// The extension's side of `FocusStudyFilter.perform()`: one engine, one selection repository and one `ModelContainer` for the process,
/// on the App Group state that the app and the Monitor use under the same `control.lock` (2026-11-16 extension design, decisions 9 and 10).
@MainActor enum FocusFilterEntry {
    private static let pause: (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    private static var engine: SessionControl?
    private static var history: SessionHistory?
    private static let authorization = AuthorizationService()
    private static let settings = FocusSettings.app()

    static func didChange(startsSession: Bool, calledAt: Date) async {
        do {
            if startsSession { try await makeHandler().focusDidChange(startsSession: true, calledAt: calledAt); return }
            // The off call needs only the engine and the access status, as in the app, so a failed selection or SwiftData load cannot keep a session running.
            await FocusFilterHandler.end(engine: try loadEngine(), authorization: authorization, settings: settings, now: Date.init, pause: pause, calledAt: calledAt)
        } catch {
            // The App Group is unreadable, for example before the first unlock after a restart; the stored refusal tells the settings sheet.
            if startsSession { settings.recordFilterRefusal(.error, at: Date()) }
        }
    }
    private static func loadEngine() throws -> SessionControl {
        if let engine { return engine }
        let group = try GroupConfiguration.directory(), shield = ScreenTimeShield()
        // This process's ManagedSettings stores are in its own container, so the engine never calls them (2026-11-16 shield amendment, decision 1).
        let created = SessionControl(store: SharedControlStore(directory: group), monitoring: ScreenTimeMonitoring(), shield: shield,
                                     breakSelection: BreakSelectionFile(directory: group, shield: shield),
                                     everyday: EverydayLayerFile(directory: group, shield: ScreenTimeEverydayShield()), role: .intentsExtension)
        engine = created
        return created
    }
    private static func loadHistory(engine: SessionControl) throws -> SessionHistory {
        if let history { return history }
        let container = try ModelContainer(for: SessionRecord.self, configurations: ModelConfiguration(cloudKitDatabase: .none))
        let created = SessionHistory(context: ModelContext(container), acknowledge: engine.acknowledgeTerminal)
        history = created
        return created
    }
    /// A new handler for each on call, with the selection and the shared settings read again: the process can outlive a call,
    /// and the person can change the selection or the focus length in the app, or the app can finish the migration, between two calls.
    /// The engine and the history store stay one per process.
    private static func makeHandler() throws -> FocusFilterHandler {
        let engine = try loadEngine(), shield = ScreenTimeShield()
        settings.reloadShared()
        // No private selection exists in the extension's container: the app migrates it (decision 17).
        let selection = try SelectionRepository(directory: GroupConfiguration.container().appendingPathComponent("FocusSelection", isDirectory: true))
        var services = FocusServices(authorization: authorization, selection: selection, engine: engine, applySelection: shield.apply, matchesSelection: shield.matches)
        services.settings = settings
        // The app stays the only writer of the today snapshot (decision 26), and no screen of this process refreshes.
        return FocusFilterHandler(services: services, history: try loadHistory(engine: engine), refresh: {}, pause: pause, writesTodaySnapshot: false)
    }
}
