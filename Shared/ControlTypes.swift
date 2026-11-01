import Foundation

public enum SessionPhase: String, Codable { case preparing, active, waiting, onBreak, breakOver, ending, terminal }
public enum EndReason: String, Codable { case expired, earlyExit, authorizationRevoked, startFailed, recoveryInterrupted, clockChanged, deadlineMissed }
public struct ControlSession: Codable, Equatable {
    public var id: UUID
    public var startedAt: Date
    /// `startedAt` + the focus length. Breaks never move it.
    public var expiresAt: Date
    public var phase: SessionPhase = .preparing
    public var reason: EndReason?
    public var observedAt: Date?
    // Break fields are optional so that a schema version 1 session decodes without them.
    public var breaksTaken: Int?
    public var pausedSeconds: TimeInterval?
    public var pausedAt: Date?
    public var deadlineCredit: TimeInterval?
    public var waitEndsAt: Date?
    public var breakEndsAt: Date?
    public var activityName: String { "focus.\(id.uuidString)" }
    public func breakActivityName(index: Int) -> String { "\(activityName).break.\(index)" }
    public init(startedAt: Date, length: TimeInterval = 1500, id: UUID = UUID()) {
        self.id = id; self.startedAt = startedAt; expiresAt = startedAt.addingTimeInterval(length)
    }
    public var length: TimeInterval { expiresAt.timeIntervalSince(startedAt) }
    public var recordedEnd: Date? {
        guard let observedAt else { return nil }
        return max(startedAt, min(expiresAt, observedAt))
    }
    public var breaksLeft: Int { BreakTiming.maxBreaks - (breaksTaken ?? 0) }
    public var isPaused: Bool { phase == .waiting || phase == .onBreak || phase == .breakOver }
    /// Focus time so far; the open pause does not count.
    public func focused(at now: Date) -> TimeInterval {
        let openPause = pausedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return min(length, max(0, now.timeIntervalSince(startedAt) - (pausedSeconds ?? 0) - openPause))
    }
    /// The completion time while `active`.
    public var focusEnd: Date { expiresAt.addingTimeInterval(pausedSeconds ?? 0) }
    public func deadline(timing: BreakTiming) -> Date { expiresAt.addingTimeInterval((deadlineCredit ?? 0) + timing.slack) }
    /// The end that time alone causes. It compares timestamps, so a late check gets the same reason as a timely one.
    public func timedEnd(at now: Date, timing: BreakTiming) -> EndReason? {
        let deadline = deadline(timing: timing)
        switch phase {
        case .active:
            guard now >= min(focusEnd, deadline) else { return nil }
            return focusEnd <= deadline ? .expired : .deadlineMissed
        case .onBreak, .breakOver: return now >= deadline ? .deadlineMissed : nil
        default: return nil
        }
    }
}
struct ControlEnvelope: Codable { var schemaVersion = 2; var session: ControlSession? }
enum ControlIssue: Error { case unauthorized, busy, pendingHistory, verificationFailed, lockTimeout, io, unsupportedSchema, invalidState, breakUnavailable }
enum CallbackKind { case didStart, didEnd, willEndWarning }
protocol LockedControl {
    func load() throws -> ControlEnvelope
    func save(_ envelope: ControlEnvelope) throws
}
protocol ControlStore {
    func withExclusiveAccess<T>(_ body: (LockedControl) throws -> T) throws -> T
}
protocol MonitoringClient {
    var registeredSessionIDs: [UUID] { get }
    /// Overwrites an existing schedule of the same session.
    func register(id: UUID, start: Date, end: Date) throws
    func isRegistered(id: UUID) -> Bool
    /// Stops the focus activity and every break activity of the session.
    func stop(id: UUID)
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws
    func isBreakRegistered(id: UUID, index: Int) -> Bool
    var registeredBreaks: [(id: UUID, index: Int)] { get }
    func stopBreak(id: UUID, index: Int)
}
protocol ShieldClient { func clear() }
/// The session-scoped selection copy that lets the Monitor re-block without the app.
protocol BreakSelectionStore {
    /// Applies the copy and returns `true` only when the store matches it.
    func restoreShield(id: UUID) -> Bool
    func exists(id: UUID) -> Bool
    func remove(id: UUID)
    /// `nil` deletes every copy.
    func removeAll(except id: UUID?)
}
