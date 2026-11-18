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
    /// The `filterActivation` that started this session; set once in the save of `preparing`, `nil` for `manual` (2026-11-16 extension design).
    public var activation: UUID?
    /// The focus length at the start of a `focusFilter` session, the chunk of each rollover; `nil` for `manual` and earlier sessions.
    public var baseLength: TimeInterval?
    /// `true` from the App Intents extension's save of `active` until a section in the app container applies the focus shield (2026-11-16 shield amendment, decision 4).
    /// Valid only in `active`; `nil` means no pending shield.
    public var shieldPending: Bool?
    /// One week: the bound of a stored length and of the rollovers (spec decision 8). It equals `TodaySnapshot.maxFocusSeconds`, which the widget compiles without this file.
    public static let maxLength: TimeInterval = 7 * 86_400
    /// The spec rule "Length validation", shared by the store and the Live Activity projection.
    public var hasValidLength: Bool {
        guard length.isFinite else { return false }
        guard let baseLength else { return FocusLength.isAllowed(seconds: length) }
        guard baseLength.isFinite, FocusLength.isAllowed(seconds: baseLength), length <= Self.maxLength else { return false }
        if (phase == .ending || phase == .terminal) && reason == .expired { return length >= baseLength - 0.01 }
        let multiple = (length / baseLength).rounded()
        return multiple >= 1 && abs(multiple * baseLength - length) < 0.01
    }
    /// The open focused time (spec decision 5): `focused(at:)` without the cap at `length`, capped at the bound length
    /// (2026-11-18 single-interval amendment, decision 17), or at the one-week bound for a session without a base length.
    public func openFocused(at now: Date) -> TimeInterval {
        let openPause = pausedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return min(boundLength ?? Self.maxLength, max(0, now.timeIntervalSince(startedAt) - (pausedSeconds ?? 0) - openPause))
    }
    /// The longest focus interval that an open session registers, from `startedAt`: the longest interval that the 2026-11-18 probe accepted.
    public static let maxIntervalLength: TimeInterval = 192 * 3600
    /// The largest whole multiple of the base length within `maxLength`, the length that the catch-up reaches at the bound.
    public var boundLength: TimeInterval? {
        guard let baseLength, baseLength.isFinite, baseLength > 0 else { return nil }
        return (Self.maxLength / baseLength).rounded(.down) * baseLength
    }
    /// The stored-only rollover of an open session (2026-11-18 single-interval amendment, "the catch-up"): whole base lengths,
    /// only in `active`, only while the focus end is not after the deadline, never past the bound. The caller decides that the session is open.
    public func caughtUp(at now: Date, timing: BreakTiming) -> ControlSession {
        guard phase == .active, let base = baseLength, base > 0, focusEnd <= deadline(timing: timing) else { return self }
        var next = self
        while next.focusEnd <= now, next.length + base <= Self.maxLength { next.expiresAt = next.expiresAt.addingTimeInterval(base) }
        return next
    }
    /// The focus activity end of an open session in `active` (amendment, decision 5): the bound end, or the deadline when it comes first,
    /// capped at `startedAt + maxIntervalLength`. A catch-up keeps `focusEnd - deadline`, so the deadline comes first at every chunk or at none.
    public func openActiveEnd(timing: BreakTiming) -> Date {
        let deadline = deadline(timing: timing)
        let end = focusEnd <= deadline ? startedAt.addingTimeInterval((boundLength ?? length) + (pausedSeconds ?? 0)) : deadline
        return min(end, startedAt.addingTimeInterval(Self.maxIntervalLength))
    }
    public var activityName: String { ActivityNames.focus(id: id) }
    public func breakActivityName(index: Int) -> String { ActivityNames.focusBreak(id: id, index: index) }
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
/// `filterCallAt` is the arrival time of the newest filter call or activation-check clear that a section accepted (spec "Call order across processes").
struct ControlEnvelope: Codable {
    var schemaVersion = 2; var session: ControlSession?; var filterActivation: UUID?; var filterCallAt: Date?
    /// The session is open: filter-started, and the activation that started it is still the stored one.
    var sessionIsOpen: Bool {
        guard let session, session.isFilterStarted, let activation = session.activation else { return false }
        return activation == filterActivation
    }
    /// The envelope with the catch-up applied to an open session (2026-11-18 single-interval amendment, decision 9).
    func caughtUp(at now: Date, timing: BreakTiming) -> ControlEnvelope {
        guard sessionIsOpen, let session else { return self }
        var next = self; next.session = session.caughtUp(at: now, timing: timing)
        return next
    }
}
/// Why a Focus on call started no session.
enum FocusFilterRefusal: String, Codable { case access, selection, busy, history, error }
/// `stale`: an accepted call arrived later, so this one changed nothing of its own (2026-11-16 extension design).
enum FocusFilterStart: Equatable { case started(ControlSession), repeated, refused(FocusFilterRefusal), stale }
enum ControlIssue: Error { case unauthorized, busy, pendingHistory, verificationFailed, lockTimeout, io, unsupportedSchema, invalidState, breakUnavailable }
/// Why the off-for-today section wrote nothing, after the access and session checks, in the order that it checks them.
enum EverydayOffRefusal: Error, CaseIterable, Equatable {
    /// The everyday file cannot be read.
    case unreadable
    /// No layer is stored, or the stored layer is off.
    case notOn
    /// The stored revision is not the one that the waiting screen was shown for.
    case revisionChanged
    /// The local day of `now` is not one of the stored weekdays.
    case dayIsOff
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
    /// Whether another holder has the lock now: a probe that does not wait and does not keep the lock.
    func isLockBusy() -> Bool
}
extension ControlStore {
    func withExclusiveAccess<T>(_ body: (LockedControl) throws -> T) throws -> T { try withExclusiveAccess(timeout: nil, body) }
    var registrationMarkers: (any RegistrationMarkerStore)? { nil }
    /// A store without a shared lock is never busy, so its callbacks take the lock attempts of today.
    func isLockBusy() -> Bool { false }
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
/// The only definition of the focus, break and everyday `DeviceActivityName` raw values; strings, because `Shared/` has no Screen Time import.
/// Stored sessions, registered schedules and the Monitor's routing depend on these formats.
enum ActivityNames {
    static let focusPrefix = "focus."
    static let breakInfix = ".break."
    static let everydayPrefix = "everyday."
    static let rangeSuffix = ".range"
    static let windowInfix = ".window."
    /// `focus.<UUID>`
    static func focus(id: UUID) -> String { "\(focusPrefix)\(id.uuidString)" }
    /// `focus.<UUID>.break.<n>`
    static func focusBreak(id: UUID, index: Int) -> String { "\(focus(id: id))\(breakInfix)\(index)" }
    /// `everyday.<UUID>.range` or `everyday.<UUID>.window.<n>`
    static func everyday(revision: UUID, part: EverydayPart) -> String {
        switch part {
        case .range: "\(everydayPrefix)\(revision.uuidString)\(rangeSuffix)"
        case .window(let n): "\(everydayPrefix)\(revision.uuidString)\(windowInfix)\(n)"
        }
    }
}
/// Clears `focusSession` only; the everyday layer has its own store.
protocol ShieldClient {
    func clear()
    /// Whether the store holds a shield. A requirement, so that `any ShieldClient` reaches the conforming type's value.
    var hasShield: Bool { get }
}
extension ShieldClient {
    /// Clients without a readable store never trigger the repair's lift (2026-11-16 shield amendment, decision 11).
    var hasShield: Bool { false }
}
/// Which process an engine runs in (2026-11-16 shield amendment, decision 1).
enum ShieldRole {
    /// The app or the Monitor, which write every ManagedSettings store.
    /// `applyFocusSelection` applies the focus selection of the App Group and returns `true` only when the store matches it.
    case appContainer(applyFocusSelection: () -> Bool)
    /// The App Intents extension, whose ManagedSettings stores are in its own container: it never calls a store and writes no registration marker.
    case intentsExtension
}
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
    /// The stored layer is on and the local day of the read is not one of its weekdays. A day that is off is reported as such also when it is off for today.
    var dayIsOff = false
}
/// `notCleared`: the store keeps a shield while the layer does not block. `unchecked`: the app could not take the lock for the status, so it keeps the last status it read.
enum EverydayIssue: Equatable { case unreadable, registrationFailed, notApplied, notCleared, unchecked }
