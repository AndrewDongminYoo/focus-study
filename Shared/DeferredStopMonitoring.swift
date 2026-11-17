import Foundation

/// The App Intents extension's monitoring inside one lock section (2026-11-17 lock-order amendment, decisions 4 and 5).
/// A stop of a running interval returns only after the Monitor's callback for it returns, and that callback waits for the lock,
/// so the section records each focus stop and `flush()` makes them after the lock is released, in the order recorded.
/// Inside the section, an activity with a recorded stop reads as not registered.
/// A focus stop names a session that the section ended, which no process registers again. A break or everyday name can be registered again
/// by the app between the release and the flush, so the extension makes no such stop and leaves those activities to the app container
/// (reconciliation of decision 5).
final class DeferredStopMonitoring: MonitoringClient {
    private let base: any MonitoringClient
    /// The sessions whose focus and break activities `flush()` stops.
    private(set) var stops: [UUID] = []
    init(base: any MonitoringClient) { self.base = base }

    /// Makes every recorded stop, in order; called after the lock is released.
    func flush() {
        let pending = stops
        stops = []
        for id in pending { base.stop(id: id) }
    }
    /// `stop(id:)` also stops every break activity of the session.
    private func isStopped(_ id: UUID) -> Bool { stops.contains(id) }

    var registeredSessionIDs: [UUID] { base.registeredSessionIDs.filter { !isStopped($0) } }
    func register(id: UUID, start: Date, end: Date) throws {
        // A new registration of the same name must not be stopped by an earlier record of this section.
        stops.removeAll { $0 == id }
        try base.register(id: id, start: start, end: end)
    }
    func isRegistered(id: UUID) -> Bool { !isStopped(id) && base.isRegistered(id: id) }
    func stop(id: UUID) { if !stops.contains(id) { stops.append(id) } }
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws {
        try base.registerBreak(id: id, index: index, start: start, end: end, warning: warning)
    }
    func isBreakRegistered(id: UUID, index: Int) -> Bool { !isStopped(id) && base.isBreakRegistered(id: id, index: index) }
    var registeredBreaks: [(id: UUID, index: Int)] { base.registeredBreaks.filter { !isStopped($0.id) } }
    /// Not made: the app container's next section stops an orphaned break activity inside its own lock.
    func stopBreak(id: UUID, index: Int) {}
    func registerEveryday(revision: UUID, part: EverydayPart, start: Int, end: Int) throws {
        try base.registerEveryday(revision: revision, part: part, start: start, end: end)
    }
    var registeredEveryday: [(revision: UUID, part: EverydayPart)] { base.registeredEveryday }
    /// Not made: an extension section changes no everyday activity (decision 7).
    func stopEveryday(revision: UUID, part: EverydayPart) {}
}
