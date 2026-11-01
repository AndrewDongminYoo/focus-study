import Foundation

/// Synchronous critical sections span read, cleanup, identity check, system effects and durable writes.
final class SessionControl {
    private let store: any ControlStore
    private let monitoring: any MonitoringClient
    private let shield: any ShieldClient
    private let breakSelection: any BreakSelectionStore
    let timing: BreakTiming
    /// Counts focus activity registrations, so that a callback section knows whether it already registered one.
    private var focusRegistrations = 0
    init(store: any ControlStore, monitoring: any MonitoringClient, shield: any ShieldClient, breakSelection: any BreakSelectionStore, timing: BreakTiming = .standard) {
        self.store = store; self.monitoring = monitoring; self.shield = shield; self.breakSelection = breakSelection; self.timing = timing
    }
    func start(now: Date, length: TimeInterval = 1500, authorized: () -> Bool, apply: () -> Void, matches: () -> Bool) throws -> ControlSession {
        try store.withExclusiveAccess { locked in
            var envelope = try read(locked)
            try cleanup(&envelope, locked: locked, now: now)
            guard authorized() else { throw ControlIssue.unauthorized }
            if let prior = envelope.session {
                throw prior.phase == .terminal ? ControlIssue.pendingHistory : ControlIssue.busy
            }
            var session = ControlSession(startedAt: now, length: length)
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
            // The person's end must still lift the restrictions when the cleanup cannot save.
            var cleanupError: Error?
            do { try cleanup(&envelope, locked: locked, now: now) } catch { cleanupError = error }
            guard let current = envelope.session, current.id == id, current.phase != .terminal else {
                if let cleanupError { throw cleanupError }
                return
            }
            try end(&envelope, locked: locked, reason: reason, now: now)
        }
    }
    func acknowledgeTerminal(id: UUID) throws {
        try store.withExclusiveAccess { locked in
            var envelope = try read(locked)
            try cleanup(&envelope, locked: locked, now: Date())
            guard envelope.session?.id == id, envelope.session?.phase == .terminal else { return }
            envelope.session = nil; try locked.save(envelope)
        }
    }
    @discardableResult
    func reconcile(now: Date, authorized: Bool, clockChanged: Bool = false) throws -> ControlEnvelope {
        try store.withExclusiveAccess { locked in
            var envelope = try read(locked)
            try cleanup(&envelope, locked: locked, now: now)
            try reconcile(&envelope, locked: locked, now: now, authorized: authorized, clockChanged: clockChanged)
            return envelope
        }
    }
    func handleCallback(activityName: String, kind: CallbackKind, now: Date, authorized: Bool) throws {
        try store.withExclusiveAccess { locked in
            var envelope = try read(locked)
            let registrationsBefore = focusRegistrations
            // The cleanup depends only on the envelope and the time, and an orphaned break activity is often the only caller.
            try cleanup(&envelope, locked: locked, now: now)
            guard let session = envelope.session else { return }
            let breaks = session.breaksTaken ?? 0
            let isFocus = activityName == session.activityName
            let isCurrentBreak = breaks > 0 && activityName == session.breakActivityName(index: breaks)
            // A late callback of an earlier break or an earlier session cannot re-block, clear or end this one.
            guard isFocus || isCurrentBreak else { return }
            // An early re-block is the safe direction for the 5-minute limit, so the warning does not check `breakEndsAt`.
            try reconcile(&envelope, locked: locked, now: now, authorized: authorized, clockChanged: false, reBlockEarly: isCurrentBreak && kind == .willEndWarning)
            // Callback with nothing due: a process exit between an overwrite and its save left an end of another phase registered.
            guard isFocus, kind == .didEnd, focusRegistrations == registrationsBefore,
                  let after = envelope.session, after.id == session.id, after.phase != .ending, after.phase != .terminal else { return }
            try registerStoredEnd(&envelope, locked: locked, now: now)
        }
    }

    // MARK: Break transitions

    /// Transition 1: `active` → `waiting`. The restrictions stay on, and the focus timer stops.
    func requestBreak(id: UUID, now: Date) throws -> ControlSession {
        try store.withExclusiveAccess { locked in
            var envelope = try read(locked)
            try cleanup(&envelope, locked: locked, now: now)
            guard var session = envelope.session, session.id == id, session.phase == .active, session.breaksLeft > 0,
                  session.timedEnd(at: now, timing: timing) == nil else { throw ControlIssue.breakUnavailable }
            let breaks = session.breaksTaken ?? 0
            session.phase = .waiting; session.pausedAt = now
            session.waitEndsAt = now.addingTimeInterval(timing.waits[min(breaks, timing.waits.count - 1)])
            try overwriteAndSave(&envelope, to: session, locked: locked, now: now)
            return session
        }
    }
    /// Transition 2, started by the person.
    func cancelWait(id: UUID, now: Date) throws {
        try store.withExclusiveAccess { locked in
            var envelope = try read(locked)
            try cleanup(&envelope, locked: locked, now: now)
            guard envelope.session?.id == id, envelope.session?.phase == .waiting else { return }
            try closeWait(&envelope, locked: locked, now: now)
        }
    }
    /// Transition 3: `waiting` → `onBreak`. The shield is cleared only after `onBreak` is saved.
    func startBreak(id: UUID, now: Date, saveSelection: () throws -> Void) throws {
        try store.withExclusiveAccess { locked in
            var envelope = try read(locked)
            try cleanup(&envelope, locked: locked, now: now)
            guard var session = envelope.session, session.id == id, session.phase == .waiting,
                  let pausedAt = session.pausedAt, let waitEndsAt = session.waitEndsAt,
                  now >= waitEndsAt, now < waitEndsAt.addingTimeInterval(timing.staleWaitGrace) else { throw ControlIssue.breakUnavailable }
            let index = (session.breaksTaken ?? 0) + 1
            do {
                try saveSelection()
                try monitoring.registerBreak(id: id, index: index, start: now, end: now.addingTimeInterval(BreakTiming.breakActivityLength), warning: timing.breakWarning)
                session.breaksTaken = index
                session.deadlineCredit = (session.deadlineCredit ?? 0) + max(0, now.timeIntervalSince(pausedAt)) + timing.breakLength
                session.breakEndsAt = now.addingTimeInterval(timing.breakLength); session.waitEndsAt = nil; session.phase = .onBreak
                try registerFocus(session, end: session.deadline(timing: timing))
                var updated = envelope; updated.session = session
                try locked.save(updated); envelope = updated
            } catch {
                // The shield is still on, so no restriction gap opens.
                // The copy goes last: in `waiting` it is the sign of an interrupted break start.
                monitoring.stopBreak(id: id, index: index)
                try? closeWait(&envelope, locked: locked, now: now)
                breakSelection.remove(id: id)
                throw error
            }
            shield.clear()
        }
    }
    /// Transition 5: `breakOver` → `active`, when the person taps "다시 집중하기".
    func resume(id: UUID, now: Date) throws {
        try store.withExclusiveAccess { locked in
            var envelope = try read(locked)
            try cleanup(&envelope, locked: locked, now: now)
            guard var session = envelope.session, session.id == id, session.phase == .breakOver, let pausedAt = session.pausedAt else { return }
            if now >= session.deadline(timing: timing) { try end(&envelope, locked: locked, reason: .deadlineMissed, now: now); return }
            session.pausedSeconds = (session.pausedSeconds ?? 0) + max(0, now.timeIntervalSince(pausedAt))
            session.pausedAt = nil; session.phase = .active
            // A focus end after the deadline cannot complete; the session then ends at the deadline.
            try overwriteAndSave(&envelope, to: session, locked: locked, now: now)
        }
    }

    // MARK: Lock-section steps

    private func read(_ locked: LockedControl) throws -> ControlEnvelope {
        do { return try locked.load() }
        catch {
            shield.clear()
            // Metadata is unavailable. Stop only this app's UUID-namespaced registrations.
            // Their absence lets a later process detect cleanup instead of trusting stale active metadata.
            for id in Set(monitoring.registeredSessionIDs) { monitoring.stop(id: id) }
            for registered in monitoring.registeredBreaks { monitoring.stopBreak(id: registered.id, index: registered.index) }
            breakSelection.removeAll(except: nil)
            throw error
        }
    }
    /// Break artifacts may exist only for a stored `onBreak` session, whatever process exit or thrown error came before.
    private func cleanup(_ envelope: inout ControlEnvelope, locked: LockedControl, now: Date) throws {
        if let session = envelope.session, session.phase == .waiting, let waitEndsAt = session.waitEndsAt, breakSelection.exists(id: session.id) {
            // An earlier section stopped inside a break start, so the registered end can be the deadline.
            if now >= waitEndsAt.addingTimeInterval(timing.staleWaitGrace) { try closeWait(&envelope, locked: locked, now: now) }
            else { try registerStoredEnd(&envelope, locked: locked, now: now) }
        }
        let allowed = envelope.session.flatMap { $0.phase == .onBreak ? (id: $0.id, index: $0.breaksTaken ?? 0) : nil }
        for registered in monitoring.registeredBreaks where !(registered.id == allowed?.id && registered.index == allowed?.index) {
            monitoring.stopBreak(id: registered.id, index: registered.index)
        }
        // The copy goes last, because in `waiting` it is the only sign that the end must be registered again.
        breakSelection.removeAll(except: allowed?.id)
    }
    private func reconcile(_ envelope: inout ControlEnvelope, locked: LockedControl, now: Date, authorized: Bool, clockChanged: Bool, reBlockEarly: Bool = false) throws {
        guard let s = envelope.session, s.phase != .terminal else { return }
        if s.phase == .ending { try end(&envelope, locked: locked, reason: s.reason ?? .recoveryInterrupted, now: s.observedAt ?? now); return }
        if !authorized { try end(&envelope, locked: locked, reason: .authorizationRevoked, now: now); return }
        if s.phase == .preparing { try end(&envelope, locked: locked, reason: .recoveryInterrupted, now: now); return }
        if clockChanged { try end(&envelope, locked: locked, reason: .clockChanged, now: now); return }
        if !monitoring.isRegistered(id: s.id) { try end(&envelope, locked: locked, reason: .recoveryInterrupted, now: now); return }
        // The app was not there to start the break, so the wait is cancelled as of its end plus the grace.
        if s.phase == .waiting, let waitEndsAt = s.waitEndsAt, now >= waitEndsAt.addingTimeInterval(timing.staleWaitGrace) {
            try closeWait(&envelope, locked: locked, now: now)
        }
        guard let current = envelope.session, current.phase != .waiting else { return }
        if let reason = current.timedEnd(at: now, timing: timing) { try end(&envelope, locked: locked, reason: reason, now: now); return }
        if current.phase == .onBreak, reBlockEarly || now >= (current.breakEndsAt ?? .distantPast) { try reBlock(&envelope, locked: locked, now: now) }
    }
    /// Transition 2: `waiting` → `active`. The paused time up to `waitEndsAt` + grace is added to the pause and to the deadline.
    private func closeWait(_ envelope: inout ControlEnvelope, locked: LockedControl, now: Date) throws {
        guard var session = envelope.session, session.phase == .waiting, let pausedAt = session.pausedAt, let waitEndsAt = session.waitEndsAt else { return }
        let paused = max(0, min(now, waitEndsAt.addingTimeInterval(timing.staleWaitGrace)).timeIntervalSince(pausedAt))
        session.pausedSeconds = (session.pausedSeconds ?? 0) + paused
        session.deadlineCredit = (session.deadlineCredit ?? 0) + paused
        session.pausedAt = nil; session.waitEndsAt = nil; session.phase = .active
        try overwriteAndSave(&envelope, to: session, locked: locked, now: now)
    }
    /// Transition 4: `onBreak` → `breakOver`. A break without an end must not happen.
    private func reBlock(_ envelope: inout ControlEnvelope, locked: LockedControl, now: Date) throws {
        guard var session = envelope.session, session.phase == .onBreak else { return }
        if let reason = session.timedEnd(at: now, timing: timing) { try end(&envelope, locked: locked, reason: reason, now: now); return }
        guard breakSelection.restoreShield(id: session.id) else { try end(&envelope, locked: locked, reason: .recoveryInterrupted, now: now); return }
        session.phase = .breakOver
        var updated = envelope; updated.session = session
        // A failed save leaves `onBreak` with the shield on, and the next reconcile re-blocks again.
        try locked.save(updated); envelope = updated
        monitoring.stopBreak(id: session.id, index: session.breaksTaken ?? 0)
        breakSelection.remove(id: session.id)
    }
    /// Transition 6, in the order of the 2026-10-26 design plus the break artifacts.
    private func end(_ envelope: inout ControlEnvelope, locked: LockedControl, reason: EndReason, now: Date) throws {
        guard var session = envelope.session else { return }
        session.phase = .ending; session.reason = reason; session.observedAt = now
        envelope.session = session
        // A disk failure must not prevent releasing our own restrictions.
        var writeError: Error?
        do { try locked.save(envelope) } catch { writeError = error }
        shield.clear(); monitoring.stop(id: session.id)
        breakSelection.remove(id: session.id)
        session.phase = .terminal; envelope.session = session
        try locked.save(envelope)
        if let writeError { throw writeError }
    }

    // MARK: Focus activity end

    /// The next time the stored session must change without the app (spec "Monitoring activities").
    private func focusActivityEnd(_ session: ControlSession) -> Date? {
        let deadline = session.deadline(timing: timing)
        switch session.phase {
        case .active: return min(session.focusEnd, deadline)
        case .waiting:
            guard let pausedAt = session.pausedAt, let waitEndsAt = session.waitEndsAt else { return nil }
            // The `active` end after a stale-wait cancel, which adds the same time to the pause and to the deadline.
            return min(session.focusEnd, deadline).addingTimeInterval(max(0, waitEndsAt.addingTimeInterval(timing.staleWaitGrace).timeIntervalSince(pausedAt)))
        case .onBreak, .breakOver: return deadline
        case .preparing, .ending, .terminal: return nil
        }
    }
    private func registerFocus(_ session: ControlSession, end: Date) throws {
        // The interval always starts at `startedAt`, so it is at least the focus length.
        try monitoring.register(id: session.id, start: session.startedAt, end: end)
        focusRegistrations += 1
    }
    /// Registers the end that the stored phase needs. A session without a callback at its next change must not keep the restrictions on.
    private func registerStoredEnd(_ envelope: inout ControlEnvelope, locked: LockedControl, now: Date) throws {
        guard let session = envelope.session, let end = focusActivityEnd(session) else { return }
        if end > now, (try? registerFocus(session, end: end)) != nil { return }
        try self.end(&envelope, locked: locked, reason: .recoveryInterrupted, now: now)
    }
    /// Transitions 1, 2 and 5 overwrite the focus activity end before they save.
    /// After a failure, the registered end must match the stored phase again, or the session ends.
    private func overwriteAndSave(_ envelope: inout ControlEnvelope, to next: ControlSession, locked: LockedControl, now: Date) throws {
        var updated = envelope; updated.session = next
        do {
            if let end = focusActivityEnd(next) { try registerFocus(next, end: end) }
            try locked.save(updated)
            envelope = updated
        } catch {
            try registerStoredEnd(&envelope, locked: locked, now: now)
            throw error
        }
    }
}
