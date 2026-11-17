import Foundation

/// The App Intents extension's monitoring inside one lock section (2026-11-17 lock-order amendment, decisions 4 and 5).
/// A stop of a running interval returns only after the Monitor's callback for it returns, and that callback waits for the lock,
/// so the section records each stop and `flush()` makes them after the lock is released, in the order recorded.
/// Inside the section, an activity with a recorded stop reads as not registered.
final class DeferredStopMonitoring: MonitoringClient {
    enum Stop: Equatable { case focus(UUID), focusBreak(UUID, Int), everyday(UUID, EverydayPart) }
    private let base: any MonitoringClient
    private(set) var stops: [Stop] = []
    init(base: any MonitoringClient) { self.base = base }

    /// Makes every recorded stop, in order; called after the lock is released.
    func flush() {
        let pending = stops
        stops = []
        for stop in pending {
            switch stop {
            case .focus(let id): base.stop(id: id)
            case .focusBreak(let id, let index): base.stopBreak(id: id, index: index)
            case .everyday(let revision, let part): base.stopEveryday(revision: revision, part: part)
            }
        }
    }
    private func record(_ stop: Stop) { if !stops.contains(stop) { stops.append(stop) } }
    /// `stop(id:)` also stops every break activity of the session.
    private func isStopped(_ id: UUID) -> Bool { stops.contains(.focus(id)) }

    var registeredSessionIDs: [UUID] { base.registeredSessionIDs.filter { !isStopped($0) } }
    func register(id: UUID, start: Date, end: Date) throws {
        // A new registration of the same name must not be stopped by an earlier record of this section.
        stops.removeAll { $0 == .focus(id) }
        try base.register(id: id, start: start, end: end)
    }
    func isRegistered(id: UUID) -> Bool { !isStopped(id) && base.isRegistered(id: id) }
    func stop(id: UUID) { record(.focus(id)) }
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws {
        stops.removeAll { $0 == .focusBreak(id, index) }
        try base.registerBreak(id: id, index: index, start: start, end: end, warning: warning)
    }
    func isBreakRegistered(id: UUID, index: Int) -> Bool {
        !isStopped(id) && !stops.contains(.focusBreak(id, index)) && base.isBreakRegistered(id: id, index: index)
    }
    var registeredBreaks: [(id: UUID, index: Int)] {
        base.registeredBreaks.filter { !isStopped($0.id) && !stops.contains(.focusBreak($0.id, $0.index)) }
    }
    func stopBreak(id: UUID, index: Int) { record(.focusBreak(id, index)) }
    func registerEveryday(revision: UUID, part: EverydayPart, start: Int, end: Int) throws {
        stops.removeAll { $0 == .everyday(revision, part) }
        try base.registerEveryday(revision: revision, part: part, start: start, end: end)
    }
    var registeredEveryday: [(revision: UUID, part: EverydayPart)] {
        base.registeredEveryday.filter { !stops.contains(.everyday($0.revision, $0.part)) }
    }
    func stopEveryday(revision: UUID, part: EverydayPart) { record(.everyday(revision, part)) }
}
