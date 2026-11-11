import Foundation

public enum SessionPhase: String, Codable { case preparing, active, waiting, onBreak, breakOver, ending, terminal }
public enum EndReason: String, Codable { case expired, earlyExit, authorizationRevoked, startFailed, recoveryInterrupted, clockChanged, deadlineMissed }
/// Who started the session. Only a `focusFilter` session ends when its Focus turns off.
public enum SessionOrigin: String, Codable { case manual, focusFilter }
/// The access value that a lock section uses (the 2026-11-11 access-state design). It is an input to a section and is never stored.
/// Only `denied` is an observation of revocation; `unknown` (no value yet, or a value that this code does not know) runs a section as with access, except that an action that needs access refuses.
public enum AccessState: Equatable, Sendable { case approved, denied, unknown }
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
    /// Set once in the save of `preparing`. A missing value (an M3 or earlier session) means `manual`.
    public var origin: SessionOrigin?
    public var isFilterStarted: Bool { origin == .focusFilter }
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
/// `filterActivation` is the Focus activation that the filter path has seen; the next off call clears it. It outlives the session.
struct ControlEnvelope: Codable { var schemaVersion = 2; var session: ControlSession?; var filterActivation: UUID? }
/// Why a Focus on call started no session.
enum FocusFilterRefusal: String, Codable { case access, selection, busy, history, error }
enum FocusFilterStart: Equatable { case started(ControlSession), repeated, refused(FocusFilterRefusal) }
enum ControlIssue: Error { case unauthorized, busy, pendingHistory, verificationFailed, lockTimeout, io, unsupportedSchema, invalidState, breakUnavailable }
/// Why the off-for-today section wrote nothing, after the access and session checks, in the order that it checks them.
enum EverydayOffRefusal: Error, CaseIterable, Equatable {
    /// The everyday file cannot be read.
    case unreadable
    /// No layer is stored, or the stored layer is off.
    case notOn
    /// The stored revision is not the one that the waiting screen was shown for.
    case revisionChanged
    /// `now` is outside the stored range.
    case outsideRange
    /// The stored `offDay` is already today's key.
    case alreadyOff
}
enum CallbackKind { case didStart, didEnd, willEndWarning }
protocol LockedControl {
    func load() throws -> ControlEnvelope
    func save(_ envelope: ControlEnvelope) throws
}
protocol ControlStore {
    /// `timeout` `nil` waits for the store's own lock timeout; `0` makes one lock attempt that does not wait.
    func withExclusiveAccess<T>(timeout: TimeInterval?, _ body: (LockedControl) throws -> T) throws -> T
    /// The registration marker next to the control state, or `nil` for a store without one.
    var registrationMarkers: (any RegistrationMarkerStore)? { get }
}
extension ControlStore {
    func withExclusiveAccess<T>(_ body: (LockedControl) throws -> T) throws -> T { try withExclusiveAccess(timeout: nil, body) }
    var registrationMarkers: (any RegistrationMarkerStore)? { nil }
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
    /// A repeating activity `everyday.<revision>.range` or `everyday.<revision>.window.<n>`; times are minutes after midnight.
    func registerEveryday(revision: UUID, part: EverydayPart, start: Int, end: Int) throws
    var registeredEveryday: [(revision: UUID, part: EverydayPart)] { get }
    /// Stops one named everyday activity. It never stops all activities.
    func stopEveryday(revision: UUID, part: EverydayPart)
}
enum EverydayPart: Hashable { case range, window(Int) }
/// Clears `focusSession` only; the everyday layer has its own store.
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
/// The everyday file and the `everydayLayer` store. Only the schedule part reaches `Shared/`.
protocol EverydayLayerStore {
    /// `nil` when no layer is set up; throws for an unreadable or invalid file.
    func load() throws -> EverydaySchedule?
    func storeMatches() -> Bool
    /// Applies the stored selection and returns `true` only when the store matches it.
    func applyStored() -> Bool
    var hasShield: Bool { get }
    func clearShield()
}
struct EverydayStatus: Equatable {
    var schedule: EverydaySchedule?
    var blocksNow: Bool
    var nextChange: Date?
    var issue: EverydayIssue?
    /// The stored layer is on and off for the local day of the read.
    var offForToday = false
}
/// `notCleared`: the store keeps a shield while the layer does not block. `unchecked`: the app could not take the lock for the status, so it keeps the last status it read.
enum EverydayIssue: Equatable { case unreadable, registrationFailed, notApplied, notCleared, unchecked }
