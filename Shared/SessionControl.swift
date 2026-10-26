import Foundation

/// Synchronous critical sections span read, identity check, system effects and durable writes.
final class SessionControl {
    private let store: any ControlStore
    private let monitoring: any MonitoringClient
    private let shield: any ShieldClient
    init(store: any ControlStore, monitoring: any MonitoringClient, shield: any ShieldClient) {
        self.store = store; self.monitoring = monitoring; self.shield = shield
    }
    func start(now: Date, authorized: () -> Bool, apply: () -> Void, matches: () -> Bool) throws -> ControlSession {
        try store.withExclusiveAccess { locked in
            var envelope = try read(locked)
            guard authorized() else { throw ControlIssue.unauthorized }
            if let prior = envelope.session {
                throw prior.phase == .terminal ? ControlIssue.pendingHistory : ControlIssue.busy
            }
            var session = ControlSession(startedAt: now)
            do {
                envelope.session = session
                try locked.save(envelope)
                try monitoring.register(id: session.id, start: session.startedAt, end: session.expiresAt)
                guard monitoring.isRegistered(id: session.id), authorized() else { throw ControlIssue.verificationFailed }
                apply()
                guard matches(), authorized() else { throw ControlIssue.verificationFailed }
                session.phase = .active; envelope.session = session
                try locked.save(envelope)
                return session
            } catch {
                // Keep the lock until rollback completes: a newer session cannot be cleared here.
                shield.clear(); monitoring.stop(id: session.id)
                session.phase = .terminal; session.reason = .startFailed; session.observedAt = now
                envelope.session = session
                try? locked.save(envelope)
                throw error
            }
        }
    }
    func snapshot() throws -> ControlEnvelope { try store.withExclusiveAccess { try read($0) } }
    func finish(id: UUID, reason: EndReason, now: Date) throws {
        try store.withExclusiveAccess { locked in
            var envelope = try read(locked)
            guard let current = envelope.session, current.id == id, current.phase != .terminal else { return }
            try end(&envelope, locked: locked, reason: reason, now: now)
        }
    }
    func acknowledgeTerminal(id: UUID) throws {
        try store.withExclusiveAccess { locked in
            var envelope = try read(locked)
            guard envelope.session?.id == id, envelope.session?.phase == .terminal else { return }
            envelope.session = nil; try locked.save(envelope)
        }
    }
    @discardableResult
    func reconcile(now: Date, authorized: Bool, clockChanged: Bool = false) throws -> ControlEnvelope {
        try store.withExclusiveAccess { locked in
            var envelope = try read(locked)
            try reconcile(&envelope, locked: locked, now: now, authorized: authorized, clockChanged: clockChanged)
            return envelope
        }
    }
    func handleCallback(activityName: String, now: Date, authorized: Bool) throws {
        try store.withExclusiveAccess { locked in
            var envelope = try read(locked)
            guard envelope.session?.activityName == activityName else { return }
            try reconcile(&envelope, locked: locked, now: now, authorized: authorized, clockChanged: false)
        }
    }
    private func read(_ locked: LockedControl) throws -> ControlEnvelope {
        do { return try locked.load() }
        catch {
            shield.clear()
            // Metadata is unavailable. Stop only this app's UUID-namespaced registrations.
            // Their absence lets a later process detect cleanup instead of trusting stale active metadata.
            for id in monitoring.registeredSessionIDs { monitoring.stop(id: id) }
            throw error
        }
    }
    private func reconcile(_ envelope: inout ControlEnvelope, locked: LockedControl, now: Date, authorized: Bool, clockChanged: Bool) throws {
        guard let s = envelope.session, s.phase != .terminal else { return }
        if s.phase == .ending { try end(&envelope, locked: locked, reason: s.reason ?? .recoveryInterrupted, now: s.observedAt ?? now) }
        else if !authorized { try end(&envelope, locked: locked, reason: .authorizationRevoked, now: now) }
        else if s.phase == .preparing { try end(&envelope, locked: locked, reason: .recoveryInterrupted, now: now) }
        else if clockChanged { try end(&envelope, locked: locked, reason: .clockChanged, now: now) }
        else if !monitoring.isRegistered(id: s.id) { try end(&envelope, locked: locked, reason: .recoveryInterrupted, now: now) }
        else if now >= s.expiresAt { try end(&envelope, locked: locked, reason: .expired, now: now) }
    }
    private func end(_ envelope: inout ControlEnvelope, locked: LockedControl, reason: EndReason, now: Date) throws {
        guard var session = envelope.session else { return }
        session.phase = .ending; session.reason = reason; session.observedAt = now
        envelope.session = session
        // A disk failure must not prevent releasing our own restrictions.
        var writeError: Error?
        do { try locked.save(envelope) } catch { writeError = error }
        shield.clear(); monitoring.stop(id: session.id)
        session.phase = .terminal; envelope.session = session
        try locked.save(envelope)
        if let writeError { throw writeError }
    }
}
