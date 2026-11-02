import Foundation
import SwiftData

/// One engine, one selection repository and one `ModelContainer` per process, for the app's screens and the Focus filter (spec "One runtime per process").
/// Two containers on the same store could each import the same terminal session.
@MainActor final class FocusRuntimeHolder {
    private static let pause: (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    private let engine: SessionControl
    private let authorization: any AuthorizationProviding
    private let settings: FocusSettings
    private let make: () throws -> (FocusServices, ModelContainer)
    private var loaded: (services: FocusServices, container: ModelContainer)?
    private var handler: FocusFilterHandler?
    /// Set by the screens when the app's model exists; a background launch has none.
    var refreshScreens: (() -> Void)?
    /// `engine`, `authorization` and `settings` are the ones that `make` puts in the services; the off call uses them without `make`.
    /// `make` builds the services and the container; only a successful build is kept, so a failed load can be tried again.
    init(engine: SessionControl, authorization: any AuthorizationProviding, settings: FocusSettings, make: @escaping () throws -> (FocusServices, ModelContainer)) {
        self.engine = engine; self.authorization = authorization; self.settings = settings; self.make = make
    }
    func load() throws -> (FocusServices, ModelContainer) {
        if let loaded { return (loaded.services, loaded.container) }
        let (services, container) = try make()
        loaded = (services, container)
        return (services, container)
    }
    func filterHandler() throws -> FocusFilterHandler {
        if let handler { return handler }
        let (services, container) = try load()
        let history = SessionHistory(context: ModelContext(container), acknowledge: services.engine.acknowledgeTerminal)
        let created = FocusFilterHandler(services: services, history: history, refresh: { [weak self] in self?.refreshScreens?() }, pause: Self.pause)
        handler = created
        return created
    }
    /// The on call needs the selection and the history store, so it throws when they cannot load.
    /// The off call runs on the engine alone, as the error screen's end does, so a storage failure cannot keep a filter session running.
    func focusDidChange(startsSession: Bool) async throws {
        if startsSession { return try await filterHandler().focusDidChange(startsSession: true) }
        await FocusFilterHandler.end(engine: engine, authorization: authorization, settings: settings, now: Date.init, pause: Self.pause)
        refreshScreens?()
    }
}
