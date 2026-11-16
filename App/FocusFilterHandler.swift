import Foundation

/// What `FocusStudyFilter.current` says about the Focus, mapped so that the handler and its tests do not import `AppIntents`.
enum FocusFilterReading: Equatable { case on, off, unknown }

/// A data-free Darwin notification after a filter call that changed the stored state, so a running app refreshes its screens
/// when another process, such as the App Intents extension, ran the call (2026-11-16 extension design, decision 21).
enum ControlChangeNotification {
    static let name = "kr.donminzzi.focusStudy.control-changed"
    static func post() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }
    /// Keeps the observer registered until the returned object is released.
    final class Observation {
        let action: @MainActor () -> Void
        init(_ action: @escaping @MainActor () -> Void) {
            self.action = action
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
                guard let observer else { return }
                let observation = Unmanaged<Observation>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { MainActor.assumeIsolated { observation.action() } }
            }, ControlChangeNotification.name as CFString, nil, .deliverImmediately)
        }
        deinit { CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque()) }
    }
}

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
    private let postChange: () -> Void
    /// Only the app writes the today snapshot (2026-11-16 extension design, decision 26); the extension passes `false`.
    private let writesTodaySnapshot: Bool
    init(services: FocusServices, history: any SessionHistoryProviding, refresh: @escaping () -> Void, now: @escaping () -> Date = Date.init,
         pause: @escaping (TimeInterval) async -> Void, postChange: @escaping () -> Void = ControlChangeNotification.post, writesTodaySnapshot: Bool = true) {
        self.services = services; self.history = history; self.refresh = refresh; self.now = now; self.pause = pause
        self.postChange = postChange; self.writesTodaySnapshot = writesTodaySnapshot
    }
    private var settings: FocusSettings { services.settings }
    private var engine: SessionControl { services.engine }

    /// `calledAt` is the arrival time that `perform()` takes before any lock attempt (spec "Call order across processes"); `nil` takes the time here.
    func focusDidChange(startsSession: Bool, calledAt: Date? = nil) async {
        let arrival = calledAt ?? now()
        await Self.serially {
            let changed = startsSession ? await self.start(calledAt: arrival) : await self.end(calledAt: arrival)
            if changed { self.postChange() }
            self.refresh()
            if startsSession, self.writesTodaySnapshot { self.writeTodaySnapshot() }
        }
    }
    /// The last part of step 5 of the on call: today's records through the handler's own history, for a background launch with no model.
    /// It runs after the start section and the record of step 4, so it changes no result of the call; a failed read or write writes nothing.
    private func writeTodaySnapshot() {
        let date = now()
        guard let records = try? history.records(on: date, calendar: .current) else { return }
        try? services.writeTodaySnapshot(TodaySnapshot(records: records, now: date, calendar: .current))
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
        // The time before the read, so an on call that arrived before the check is stale after it (spec "Call order across processes", step 4).
        let checkedAt = now()
        let value = await reading()
        log("check \(value)")
        guard value == .off else { return }
        _ = try? await retryingLock { try self.engine.clearFilterActivation(matching: marker, now: checkedAt) }
    }

    /// Returns whether the call changed the stored state.
    private func start(calledAt: Date) async -> Bool {
        // Step 1: the inputs, read outside the lock.
        services.authorization.refresh()
        let length = settings.lengthSeconds, counts = services.selection.counts, frozen = services.selection.selection
        let selectionReady = (try? SelectionValidator.validate(appCount: counts.apps, webCount: counts.websites, categoryCount: counts.categories)) != nil
        // A selection with no stored length is a damaged migration: never start with a length the person did not choose (2026-11-16 extension design, decision 16).
        // The engine orders this refusal like any other, so a stale call cannot record it.
        let inputRefusal: FocusFilterRefusal? = counts.apps + counts.websites > 0 && !settings.hasStoredLength ? .error : nil
        // Step 2: a failure here does not stop step 3, which refuses with `history` while a terminal session stays.
        await importPendingTerminal()
        // Steps 3 and 4.
        do {
            let result = try await retryingLock {
                try self.engine.startFromFocusFilter(now: self.now(), length: length, authorized: { self.services.authorization.accessState() }, selectionReady: selectionReady,
                                                     apply: { self.services.applySelection(frozen) }, matches: { self.services.matchesSelection(frozen) }, calledAt: calledAt,
                                                     inputRefusal: inputRefusal)
            }
            switch result {
            case .started: settings.clearFilterRefusal(); log("on started"); return true
            case .repeated: log("on repeated"); return false
            case .refused(let reason): settings.recordFilterRefusal(reason, at: now()); log("on refused \(reason)"); return true
            // A call that arrived before an accepted one stores no refusal: it describes a Focus state that is already gone.
            case .stale: log("on stale"); return false
            }
        } catch {
            settings.recordFilterRefusal(.error, at: now()); log("on error"); return false
        }
    }
    private func end(calledAt: Date) async -> Bool {
        await Self.performEnd(engine: engine, authorization: services.authorization, settings: settings, now: now, pause: pause, calledAt: calledAt)
    }
    /// The off call needs only the engine and the access status, so a failed selection or SwiftData load cannot keep a filter session running.
    /// It waits for the earlier Focus calls of the process, as `focusDidChange` does.
    static func end(engine: SessionControl, authorization: any AuthorizationProviding, settings: FocusSettings, now: @escaping () -> Date,
                    pause: @escaping (TimeInterval) async -> Void, calledAt: Date? = nil, postChange: @escaping () -> Void = ControlChangeNotification.post) async {
        let arrival = calledAt ?? now()
        await serially {
            if await performEnd(engine: engine, authorization: authorization, settings: settings, now: now, pause: pause, calledAt: arrival) { postChange() }
        }
    }
    /// Returns whether the call was accepted; a stale call changes nothing of its own.
    private static func performEnd(engine: SessionControl, authorization: any AuthorizationProviding, settings: FocusSettings, now: @escaping () -> Date,
                                   pause: (TimeInterval) async -> Void, calledAt: Date) async -> Bool {
        authorization.refresh()
        do {
            // Each attempt reads the access value again, so a retry after a lock timeout uses the value after the pause.
            let accepted = try await retryingLock(pause: pause) { try engine.endFromFocusFilter(now: now(), authorized: authorization.accessState(), calledAt: calledAt) }
            log(accepted ? "off done" : "off stale", settings: settings, at: now())
            return accepted
        } catch { log("off error", settings: settings, at: now()); return false }
    }
    /// The first part of `FocusModel.refresh()`: reconcile, snapshot and the import of a terminal session.
    private func importPendingTerminal() async {
        do {
            let access = services.authorization.accessState()
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
