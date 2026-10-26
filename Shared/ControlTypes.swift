import Foundation

enum SessionPhase: String, Codable { case preparing, active, ending, terminal }
enum EndReason: String, Codable { case expired, earlyExit, authorizationRevoked, startFailed, recoveryInterrupted, clockChanged }
struct ControlSession: Codable, Equatable {
    var id: UUID
    var startedAt: Date
    var expiresAt: Date
    var phase: SessionPhase = .preparing
    var reason: EndReason?
    var observedAt: Date?
    var activityName: String { "focus.\(id.uuidString)" }
    init(startedAt: Date, id: UUID = UUID()) {
        self.id = id; self.startedAt = startedAt; expiresAt = startedAt.addingTimeInterval(1500)
    }
    var recordedEnd: Date? {
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
