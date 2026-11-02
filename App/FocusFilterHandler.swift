import Foundation

/// What `FocusStudyFilter.current` says about the Focus, mapped so that the handler and its tests do not import `AppIntents`.
enum FocusFilterReading: Equatable { case on, off, unknown }

/// The work of a Focus filter call in the app process (spec "Filter start", "Filter end" and "Activation check").
/// It never requests a permission: it only reads the authorization status.
@MainActor final class FocusFilterHandler {
    /// Each filter call is the only trigger of its change, so a lock timeout is retried as the Monitor retries it.
    static let lockRetries = 4, retryPause: TimeInterval = 0.25
    let services: FocusServices
    private let history: any SessionHistoryProviding
    private let refresh: () -> Void
    private let now: () -> Date
    private let pause: (TimeInterval) async -> Void
    init(services: FocusServices, history: any SessionHistoryProviding, refresh: @escaping () -> Void, now: @escaping () -> Date = Date.init,
         pause: @escaping (TimeInterval) async -> Void) {
        self.services = services; self.history = history; self.refresh = refresh; self.now = now; self.pause = pause
    }
    private var settings: FocusSettings { services.settings }
    private var engine: SessionControl { services.engine }

    func focusDidChange(startsSession: Bool) async {
        await Self.serially {
            if startsSession { await self.start() } else { await self.end() }
            self.refresh()
        }
    }
    /// The last Focus call of the process. A call waits for it, so the calls run one at a time in the order they arrive.
    private static var lastCall: Task<Void, Never>?
    /// `@MainActor` does not stop a second call during the lock-retry pause: without this, an off call could run before an on call that is still retrying,
    /// and the on call would then start a shielded session while the Focus is off, which no later call ends.
    private static func serially(_ work: @escaping @MainActor () async -> Void) async {
        let previous = lastCall
        let call = Task { @MainActor in
            await previous?.value
            await work()
        }
        lastCall = call
        await call.value
    }
    /// Step 3 of the activation check clears only on `.off`; `notFound` maps to `.off` in `FocusStudyFilter.reading()`.
    func checkActivation(reading: () async -> FocusFilterReading) async {
        guard let marker = try? engine.snapshot().filterActivation else { return }
        let value = await reading()
        log("check \(value)")
        guard value == .off else { return }
        _ = try? await retryingLock { try self.engine.clearFilterActivation(matching: marker, now: self.now()) }
    }

    private func start() async {
        // Step 1: the inputs, read outside the lock.
        services.authorization.refresh()
        let length = settings.lengthSeconds, counts = services.selection.counts, frozen = services.selection.selection
        let selectionReady = (try? SelectionValidator.validate(appCount: counts.apps, webCount: counts.websites, categoryCount: counts.categories)) != nil
        // Step 2: a failure here does not stop step 3, which refuses with `history` while a terminal session stays.
        await importPendingTerminal()
        // Steps 3 and 4.
        do {
            let result = try await retryingLock {
                try self.engine.startFromFocusFilter(now: self.now(), length: length, authorized: { self.services.authorization.hasAccessNow() }, selectionReady: selectionReady,
                                                     apply: { self.services.applySelection(frozen) }, matches: { self.services.matchesSelection(frozen) })
            }
            switch result {
            case .started: settings.clearFilterRefusal(); log("on started")
            case .repeated: log("on repeated")
            case .refused(let reason): settings.recordFilterRefusal(reason, at: now()); log("on refused \(reason)")
            }
        } catch {
            settings.recordFilterRefusal(.error, at: now()); log("on error")
        }
    }
    private func end() async {
        await Self.performEnd(engine: engine, authorization: services.authorization, settings: settings, now: now, pause: pause)
    }
    /// The off call needs only the engine and the access status, so a failed selection or SwiftData load cannot keep a filter session running.
    /// It waits for the earlier Focus calls of the process, as `focusDidChange` does.
    static func end(engine: SessionControl, authorization: any AuthorizationProviding, settings: FocusSettings, now: @escaping () -> Date,
                    pause: @escaping (TimeInterval) async -> Void) async {
        await serially { await performEnd(engine: engine, authorization: authorization, settings: settings, now: now, pause: pause) }
    }
    private static func performEnd(engine: SessionControl, authorization: any AuthorizationProviding, settings: FocusSettings, now: @escaping () -> Date,
                                   pause: (TimeInterval) async -> Void) async {
        authorization.refresh()
        do {
            try await retryingLock(pause: pause) { try engine.endFromFocusFilter(now: now(), authorized: authorization.status == .approved) }
            log("off done", settings: settings, at: now())
        } catch { log("off error", settings: settings, at: now()) }
    }
    /// The first part of `FocusModel.refresh()`: reconcile, snapshot and the import of a terminal session.
    private func importPendingTerminal() async {
        do {
            let access = services.authorization.status == .approved
            try await retryingLock { _ = try self.engine.reconcile(now: self.now(), authorized: access) }
            guard let terminal = try await retryingLock({ try self.engine.snapshot().session }), terminal.phase == .terminal else { return }
            // A repeated import finds the saved record and only acknowledges it.
            try await retryingLock { try self.history.importTerminal(terminal) }
            if terminal.reason == .expired { settings.recordPendingCompletion(id: terminal.id, length: terminal.length) }
        } catch {}
    }
    /// The store throws `lockTimeout` before a section runs, so a failed attempt changed nothing. The pause runs outside the lock.
    private func retryingLock<T>(_ body: () throws -> T) async throws -> T { try await Self.retryingLock(pause: pause, body) }
    private static func retryingLock<T>(pause: (TimeInterval) async -> Void, _ body: () throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do { return try body() }
            catch ControlIssue.lockTimeout where attempt < lockRetries { attempt += 1; await pause(retryPause) }
        }
    }
    private func log(_ result: String) { Self.log(result, settings: settings, at: now()) }
    private static func log(_ result: String, settings: FocusSettings, at time: Date) {
        #if DEBUG
        settings.appendFilterCall("\(ISO8601DateFormatter().string(from: time)) \(result)")
        #endif
    }
}
