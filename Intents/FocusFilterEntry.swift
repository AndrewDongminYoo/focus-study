import Foundation
import SwiftData

/// The extension's side of `FocusStudyFilter.perform()`: one engine, one selection repository and one `ModelContainer` for the process,
/// on the App Group state that the app and the Monitor use under the same `control.lock` (2026-11-16 extension design, decisions 9 and 10).
@MainActor enum FocusFilterEntry {
    private static let pause: (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    private static var engine: SessionControl?
    private static var handler: FocusFilterHandler?
    private static let authorization = AuthorizationService()
    private static let settings = FocusSettings.app()

    static func didChange(startsSession: Bool, calledAt: Date) async {
        do {
            if startsSession { try await loadHandler().focusDidChange(startsSession: true, calledAt: calledAt); return }
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
        let created = SessionControl(store: SharedControlStore(directory: group), monitoring: ScreenTimeMonitoring(), shield: shield,
                                     breakSelection: BreakSelectionFile(directory: group, shield: shield),
                                     everyday: EverydayLayerFile(directory: group, shield: ScreenTimeEverydayShield()))
        engine = created
        return created
    }
    private static func loadHandler() throws -> FocusFilterHandler {
        if let handler { return handler }
        let engine = try loadEngine(), shield = ScreenTimeShield()
        // No private selection exists in the extension's container: the app migrates it (decision 17).
        let selection = try SelectionRepository(directory: GroupConfiguration.container().appendingPathComponent("FocusSelection", isDirectory: true))
        var services = FocusServices(authorization: authorization, selection: selection, engine: engine, applySelection: shield.apply, matchesSelection: shield.matches)
        services.settings = settings
        let container = try ModelContainer(for: SessionRecord.self, configurations: ModelConfiguration(cloudKitDatabase: .none))
        let history = SessionHistory(context: ModelContext(container), acknowledge: engine.acknowledgeTerminal)
        // The app stays the only writer of the today snapshot (decision 26), and no screen of this process refreshes.
        let created = FocusFilterHandler(services: services, history: history, refresh: {}, pause: pause, writesTodaySnapshot: false)
        handler = created
        return created
    }
}
