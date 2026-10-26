import Foundation

public enum SessionPhase: String, Codable { case preparing, active, ending, terminal }
public enum EndReason: String, Codable { case expired, earlyExit, authorizationRevoked, startFailed, recoveryInterrupted, clockChanged }
public struct ControlSession: Codable, Equatable {
    public var id: UUID
    public var startedAt: Date
    public var expiresAt: Date
    public var phase: SessionPhase = .preparing
    public var reason: EndReason?
    public var observedAt: Date?
    public var activityName: String { "focus.\(id.uuidString)" }
    public init(startedAt: Date, id: UUID = UUID()) {
        self.id = id; self.startedAt = startedAt; expiresAt = startedAt.addingTimeInterval(1500)
    }
    public var recordedEnd: Date? {
        guard let observedAt else { return nil }
        return max(startedAt, min(expiresAt, observedAt))
    }
}
struct ControlEnvelope: Codable { var schemaVersion = 1; var session: ControlSession? }
enum ControlIssue: Error { case unauthorized, busy, pendingHistory, verificationFailed, lockTimeout, io, unsupportedSchema, invalidState }
protocol LockedControl {
    func load() throws -> ControlEnvelope
    func save(_ envelope: ControlEnvelope) throws
}
protocol ControlStore {
    func withExclusiveAccess<T>(_ body: (LockedControl) throws -> T) throws -> T
}
protocol MonitoringClient {
    func register(id: UUID, start: Date, end: Date) throws
    func isRegistered(id: UUID) -> Bool
    func stop(id: UUID)
}
protocol ShieldClient { func clear() }
