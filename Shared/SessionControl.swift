import Foundation

/// Synchronous critical sections span read, cleanup, identity check, system effects and durable writes.
final class SessionControl {
    private let store: any ControlStore
    private let baseMonitoring: any MonitoringClient
    /// The marker wrapper of the lock section that is running, set only while the section holds the lock.
    private var sectionMonitoring: (any MonitoringClient)?
    /// Every registration and every stop inside a lock section goes through the section's marker wrapper.
    private var monitoring: any MonitoringClient { sectionMonitoring ?? baseMonitoring }
    private let shield: any ShieldClient
    private let breakSelection: any BreakSelectionStore
    private let everyday: any EverydayLayerStore
    let timing: BreakTiming
    /// The wall clock of the everyday layer. `autoupdatingCurrent` follows a time zone change in a long-lived app engine.
    let calendar: Calendar
    /// Counts focus activity registrations, so that a callback section knows whether it already registered one.
    private var focusRegistrations = 0
    init(store: any ControlStore, monitoring: any MonitoringClient, shield: any ShieldClient, breakSelection: any BreakSelectionStore,
         everyday: any EverydayLayerStore, timing: BreakTiming = .standard, calendar: Calendar = .autoupdatingCurrent) {
        self.store = store; self.baseMonitoring = monitoring; self.shield = shield; self.breakSelection = breakSelection
        self.everyday = everyday; self.timing = timing; self.calendar = calendar
    }
    func start(now: Date, length: TimeInterval = 1500, authorized: () -> AccessState, apply: () -> Void, matches: () -> Bool) throws -> ControlSession {
        try section(now: now) { locked in
            var envelope = try read(locked)
            try cleanup(&envelope, locked: locked, now: now)
            locked.access = authorized()
            guard locked.access == .approved else { throw ControlIssue.unauthorized }
            if let prior = envelope.session {
                throw prior.phase == .terminal ? ControlIssue.pendingHistory : ControlIssue.busy
            }
            return try begin(&envelope, locked: locked, now: now, length: length, origin: .manual, authorized: authorized, apply: apply, matches: matches)
        }
    }

    // MARK: Focus filter

    /// The spec "Filter start", step 3. One activation starts at most one session: a refusal also stores the marker.
    func startFromFocusFilter(now: Date, length: TimeInterval, authorized: () -> AccessState, selectionReady: Bool, apply: () -> Void, matches: () -> Bool) throws -> FocusFilterStart {
        try section(now: now) { locked in
            var envelope = try read(locked)
            try cleanup(&envelope, locked: locked, now: now)
            // A repeated call of the same activation makes no change of its own.
            guard envelope.filterActivation == nil else { return .repeated }
            envelope.filterActivation = UUID()
            locked.access = authorized()
            let refusal: FocusFilterRefusal?
            if locked.access != .approved { refusal = .access }
            else if !selectionReady { refusal = .selection }
            else if let prior = envelope.session { refusal = prior.phase == .terminal ? .history : .busy }
            else { refusal = nil }
            if let refusal { try locked.save(envelope); return .refused(refusal) }
            // The save of `preparing` writes the marker; the rollback keeps it, so the activation is used.
            return .started(try begin(&envelope, locked: locked, now: now, length: length, origin: .focusFilter, authorized: authorized, apply: apply, matches: matches))
        }
    }
    /// The spec "Filter end". The Focus-off rule ends only a `focusFilter` session; a manual one ends only for the reasons of any reconcile.
    func endFromFocusFilter(now: Date, authorized: AccessState) throws {
        try section(now: now, access: authorized) { locked in
            var envelope = try read(locked)
            // Turning the Focus off is the person's end, so it must still lift the restrictions of a filter-started session when the cleanup or the reconcile cannot save (#53).
            var caught: Error?
            do { try cleanup(&envelope, locked: locked, now: now) } catch { caught = error }
            // Every later save of this section writes the cleared marker.
            envelope.filterActivation = nil
            if caught == nil {
                do { try reconcile(&envelope, locked: locked, now: now, authorized: authorized, clockChanged: false) } catch { caught = error }
            }
            // An `end` inside the cleanup or the reconcile sets `terminal` in memory before its last save, so its own error never causes a second end.
            if let session = envelope.session, session.phase != .terminal, session.isFilterStarted {
                // The reconcile order after a caught error: access `denied`, then the timed end, else the person's end. `unknown` is not a revocation.
                let reason: EndReason = caught == nil ? .earlyExit : authorized == .denied ? .authorizationRevoked : session.timedEnd(at: now, timing: timing) ?? .earlyExit
                try end(&envelope, locked: locked, reason: reason, now: now)
            } else if let caught { throw caught }
            if var stored = locked.stored, stored.filterActivation != nil {
                stored.filterActivation = nil; try locked.save(stored)
            }
        }
    }
    /// The spec "Activation check", step 3: clears the marker only while it is still the one that the caller read. It never starts or ends a session.
    func clearFilterActivation(matching id: UUID, now: Date) throws {
        try section(now: now) { locked in
            var envelope = try read(locked)
            try cleanup(&envelope, locked: locked, now: now)
            guard envelope.filterActivation == id else { return }
            envelope.filterActivation = nil; try locked.save(envelope)
        }
    }
    func snapshot() throws -> ControlEnvelope { try holding { try read($0) } }
    /// Optional display reads never invoke recovery, even when metadata is unavailable.
    func activitySnapshot() throws -> ControlSession? { try store.withExclusiveAccess { try $0.load().session } }
    /// `now` is the wall clock of the section and of its everyday convergence; `endedAt`, when given, is the recorded end time of the session.
    func finish(id: UUID, reason: EndReason, now: Date, endedAt: Date? = nil) throws {
        try section(now: now) { locked in
            var envelope = try read(locked)
            // The person's end must still lift the restrictions when the cleanup cannot save.
            var cleanupError: Error?
            do { try cleanup(&envelope, locked: locked, now: now) } catch { cleanupError = error }
            guard let current = envelope.session, current.id == id, current.phase != .terminal else {
                if let cleanupError { throw cleanupError }
                return
            }
            try end(&envelope, locked: locked, reason: reason, now: endedAt ?? now)
        }
    }
    func acknowledgeTerminal(id: UUID) throws {
        let now = Date()
        try section(now: now) { locked in
            var envelope = try read(locked)
            try cleanup(&envelope, locked: locked, now: now)
            guard envelope.session?.id == id, envelope.session?.phase == .terminal else { return }
            envelope.session = nil; try locked.save(envelope)
        }
    }
    @discardableResult
    func reconcile(now: Date, authorized: AccessState, clockChanged: Bool = false) throws -> ControlEnvelope {
        try section(now: now, access: authorized) { locked in
            var envelope = try read(locked)
            try cleanup(&envelope, locked: locked, now: now)
            try reconcile(&envelope, locked: locked, now: now, authorized: authorized, clockChanged: clockChanged)
            return envelope
        }
    }
    /// `lockTimeout` `0` is the attempt of `handleCallbackRetryingLock` that does not wait; `nil` waits for the store's own timeout.
    func handleCallback(activityName: String, kind: CallbackKind, now: Date, authorized: AccessState, lockTimeout: TimeInterval? = nil) throws {
        // A section that `intervalDidStart(for:)` started never registers an everyday activity, so a registration cannot loop through its own callback.
        try section(now: now, access: authorized, mayRegister: kind != .didStart, lockTimeout: lockTimeout) { locked in
            var envelope = try read(locked)
            let registrationsBefore = focusRegistrations
            // The cleanup depends only on the envelope and the time, and an orphaned break activity is often the only caller.
            try cleanup(&envelope, locked: locked, now: now)
            guard let session = envelope.session else { return }
            if activityName.hasPrefix(ActivityNames.everydayPrefix) {
                // An everyday edge reaches the M2 reconcile only in a late break, where the focus shield is already off.
                // In every other phase the M2 callback identity rule holds, so it cannot end the session on access or center state.
                guard session.phase == .onBreak, now >= (session.breakEndsAt ?? .distantFuture) else { return }
                try reconcile(&envelope, locked: locked, now: now, authorized: authorized, clockChanged: false)
                return
            }
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
    /// A Monitor callback is often the only trigger of its timed change, so a lock timeout retries with a fresh time before the callback returns.
    /// The store throws `lockTimeout` before the section runs, so a failed attempt changed nothing. Worst case with the defaults: attempt 0, then 5 lock waits of 0.25 s and 4 pauses of 0.25 s, about 2.25 s.
    /// After every `lockTimeout`, a fresh marker of the lock holder that decides this callback ends the callback: the holder's section decides that activity.
    /// A `register` marker decides `didStart` and `didEnd` before its `validUntil`; a `stop` marker decides only `didEnd`.
    func handleCallbackRetryingLock(activityName: String, kind: CallbackKind, now: () -> Date, authorized: () -> AccessState, retries: Int = 4, pause: TimeInterval = 0.25,
                                    sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) throws {
        // Attempt 0: one lock call that does not wait, with no pause after it.
        let first = now()
        do { return try handleCallback(activityName: activityName, kind: kind, now: first, authorized: authorized(), lockTimeout: 0) }
        catch ControlIssue.lockTimeout { if holderDecides(activityName: activityName, kind: kind, now: first) { return } }
        var attempt = 0
        while true {
            let time = now()
            do { return try handleCallback(activityName: activityName, kind: kind, now: time, authorized: authorized()) }
            catch ControlIssue.lockTimeout {
                if holderDecides(activityName: activityName, kind: kind, now: time) { return }
                guard attempt < retries else { throw ControlIssue.lockTimeout }
                attempt += 1; sleep(pause)
            }
        }
    }
    /// Read only after a `lockTimeout`: a marker without a busy lock is a leftover, and the callback must then run.
    private func holderDecides(activityName: String, kind: CallbackKind, now: Date) -> Bool {
        store.registrationMarkers?.freshMarker()?.decides(activityName: activityName, kind: kind, now: now) == true
    }

    // MARK: Break transitions

    /// Transition 1: `active` → `waiting`. The restrictions stay on, and the focus timer stops.
    func requestBreak(id: UUID, now: Date) throws -> ControlSession {
        try section(now: now) { locked in
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
        try section(now: now) { locked in
            var envelope = try read(locked)
            try cleanup(&envelope, locked: locked, now: now)
            guard envelope.session?.id == id, envelope.session?.phase == .waiting else { return }
            try closeWait(&envelope, locked: locked, now: now)
        }
    }
    /// Transition 3: `waiting` → `onBreak`. The shield is cleared only after `onBreak` is saved.
    func startBreak(id: UUID, now: Date, saveSelection: () throws -> Void) throws {
        try section(now: now) { locked in
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
    /// An early return first commits the re-block, then transition 5 resumes focus.
    func resume(id: UUID, now: Date) throws {
        try section(now: now) { locked in
            var envelope = try read(locked)
            try cleanup(&envelope, locked: locked, now: now)
            guard envelope.session?.id == id else { return }
            if envelope.session?.phase == .onBreak { try reBlock(&envelope, locked: locked, now: now, endingEarly: true) }
            guard var session = envelope.session, session.id == id, session.phase == .breakOver, let pausedAt = session.pausedAt else { return }
            if now >= session.deadline(timing: timing) { try end(&envelope, locked: locked, reason: .deadlineMissed, now: now); return }
            session.pausedSeconds = (session.pausedSeconds ?? 0) + max(0, now.timeIntervalSince(pausedAt))
            session.pausedAt = nil; session.phase = .active
            // A focus end after the deadline cannot complete; the session then ends at the deadline.
            try overwriteAndSave(&envelope, to: session, locked: locked, now: now)
        }
    }

    // MARK: Everyday layer

    /// Turn on, edit or turn off, in the order of the spec "Save": check, register, write (the commit point), stop the other revisions, converge.
    /// `write` gets the schedule to store: the new schedule with the `offDay` that the section sets, never one that the app passes.
    func saveEveryday(_ schedule: EverydaySchedule, now: Date, authorized: () -> AccessState, containsStoredSelection: () throws -> Bool,
                      write: (EverydaySchedule) throws -> Void) throws {
        try section(now: now) { locked in
            var envelope = try read(locked)
            try cleanup(&envelope, locked: locked, now: now)
            // A refusal for access registers and writes nothing; after a `denied` read the convergence of this section then stops every everyday activity.
            locked.access = authorized()
            guard locked.access == .approved else { throw ControlIssue.unauthorized }
            if let session = envelope.session, session.phase != .terminal { throw ControlIssue.busy }
            guard schedule.isValid else { throw ControlIssue.invalidState }
            // An unreadable file counts as no stored layer, so that the person can set the layer up again.
            let stored = try? everyday.load()
            if let stored, stored.isLocked(at: now, calendar: calendar) {
                // The new range keeps `now` and ends no earlier, so the lock lasts until at least the stored range end after every accepted edit.
                // The conditions compare with the stored schedule without its off day, and the first one that fails names the refusal.
                if let reason = schedule.lockReason(against: stored, at: now, calendar: calendar) { throw reason }
                guard try containsStoredSelection() else { throw EverydayLockReason.removesSelection }
            }
            // An accepted edit never turns the layer back on for today, and an off day of an earlier date goes away.
            var written = schedule
            written.offDay = stored?.isOff(at: now, calendar: calendar) == true ? stored?.offDay : nil
            let activities = schedule.enabled ? Self.everydayActivities(schedule) : []
            do {
                for activity in activities { try monitoring.registerEveryday(revision: schedule.revision, part: activity.part, start: activity.start, end: activity.end) }
                try write(written)
            } catch {
                // The stored file and the store stay as they were; a registration that threw may still exist, so every new name is stopped.
                for activity in activities { monitoring.stopEveryday(revision: schedule.revision, part: activity.part) }
                throw error
            }
            for registered in monitoring.registeredEveryday where registered.revision != schedule.revision {
                monitoring.stopEveryday(revision: registered.revision, part: registered.part)
            }
            // Step 5 is the convergence at the end of this section, against the new file.
        }
    }
    /// The spec "The off-for-today section": check, write the stored file again with today's `offDay` (the commit point), converge.
    /// `revision` is the stored revision that the waiting screen was shown for; `write` replaces the file with the same revision, schedule and tokens.
    func turnEverydayOffForToday(revision: UUID, now: Date, authorized: () -> AccessState, write: (EverydaySchedule) throws -> Void) throws {
        try section(now: now) { locked in
            var envelope = try read(locked)
            try cleanup(&envelope, locked: locked, now: now)
            // A refusal for access writes nothing; after a `denied` read the convergence of this section then stops every everyday activity.
            locked.access = authorized()
            guard locked.access == .approved else { throw ControlIssue.unauthorized }
            // A Focus filter can start a session during the wait.
            if let session = envelope.session, session.phase != .terminal { throw ControlIssue.busy }
            let stored: EverydaySchedule?
            do { stored = try everyday.load() } catch { throw EverydayOffRefusal.unreadable }
            guard var schedule = stored, schedule.enabled else { throw EverydayOffRefusal.notOn }
            guard schedule.revision == revision else { throw EverydayOffRefusal.revisionChanged }
            // The app offers the action only on a day that is on; a time zone or clock change during the wait can reach this.
            guard schedule.applies(on: now, calendar: calendar) else { throw EverydayOffRefusal.dayIsOff }
            guard schedule.isInsideRange(at: now, calendar: calendar) else { throw EverydayOffRefusal.outsideRange }
            guard !schedule.isOff(at: now, calendar: calendar) else { throw EverydayOffRefusal.alreadyOff }
            schedule.offDay = EverydaySchedule.dayKey(of: now, calendar: calendar)
            try write(schedule)
            // The convergence at the end of this section finds the revision registered and clears the store.
        }
    }
    /// No convergence step; unreadable control metadata still invokes the recovery reader.
    /// `unknown` access reads as approved here, so that the settings show no access issue until a `denied` read.
    func everydayStatus(now: Date, authorized: AccessState) throws -> EverydayStatus {
        try holding { locked in
            let envelope = try read(locked)
            let schedule: EverydaySchedule?
            do { schedule = try everyday.load() } catch { return EverydayStatus(schedule: nil, blocksNow: false, nextChange: nil, issue: .unreadable) }
            let blocksNow = EverydayRules.blocks(schedule: schedule, session: envelope.session, authorized: authorized, now: now, calendar: calendar)
            var issue: EverydayIssue?
            if authorized != .denied, let schedule, schedule.enabled {
                let present = Set(monitoring.registeredEveryday.filter { $0.revision == schedule.revision }.map(\.part))
                if !Self.everydayActivities(schedule).allSatisfy({ present.contains($0.part) }) { issue = .registrationFailed }
            }
            if issue == nil, blocksNow, !everyday.storeMatches() { issue = .notApplied }
            // A window-start or range-end callback that came late or never came leaves the store applied.
            // Without access the shield is not in force, and the app's next lock section clears it.
            if issue == nil, authorized != .denied, !blocksNow, everyday.hasShield { issue = .notCleared }
            let nextChange = EverydayRules.nextChange(schedule: schedule, session: envelope.session, authorized: authorized, now: now, calendar: calendar)
            let offForToday = schedule.map { $0.enabled && $0.isOff(at: now, calendar: calendar) } ?? false
            let dayIsOff = schedule.map { $0.enabled && !$0.applies(on: now, calendar: calendar) } ?? false
            return EverydayStatus(schedule: schedule, blocksNow: blocksNow, nextChange: nextChange, issue: issue, offForToday: offForToday, dayIsOff: dayIsOff)
        }
    }

    // MARK: Lock-section steps

    private func read(_ locked: LockedControl) throws -> ControlEnvelope {
        do { return try locked.load() }
        catch {
            shield.clear()
            // No envelope, so no everyday convergence step runs: an empty envelope would apply the everyday shield again.
            // The everyday activities stay, so that a later callback can apply the layer when `control.json` is readable.
            everyday.clearShield()
            // Metadata is unavailable. Stop only this app's UUID-namespaced registrations.
            // Their absence lets a later process detect cleanup instead of trusting stale active metadata.
            for id in Set(monitoring.registeredSessionIDs) { monitoring.stop(id: id) }
            for registered in monitoring.registeredBreaks { monitoring.stopBreak(id: registered.id, index: registered.index) }
            breakSelection.removeAll(except: nil)
            throw error
        }
    }
    /// The M1 start steps after the start checks: save `preparing`, register, verify, apply, verify, save `active`, or the rollback.
    private func begin(_ envelope: inout ControlEnvelope, locked: LockedControl, now: Date, length: TimeInterval, origin: SessionOrigin,
                       authorized: () -> AccessState, apply: () -> Void, matches: () -> Bool) throws -> ControlSession {
        var session = ControlSession(startedAt: now, length: length)
        session.origin = origin
        do {
            envelope.session = session
            try locked.save(envelope)
            try monitoring.register(id: session.id, start: session.startedAt, end: session.expiresAt)
            guard monitoring.isRegistered(id: session.id), authorized() == .approved else { throw ControlIssue.verificationFailed }
            apply()
            guard matches(), authorized() == .approved else { throw ControlIssue.verificationFailed }
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
    private func reconcile(_ envelope: inout ControlEnvelope, locked: LockedControl, now: Date, authorized: AccessState, clockChanged: Bool, reBlockEarly: Bool = false) throws {
        guard let s = envelope.session, s.phase != .terminal else { return }
        if s.phase == .ending { try end(&envelope, locked: locked, reason: s.reason ?? .recoveryInterrupted, now: s.observedAt ?? now); return }
        // Step 2. Only a `denied` read is a revocation; `unknown` skips this step and runs every other one.
        if authorized == .denied { try end(&envelope, locked: locked, reason: .authorizationRevoked, now: now); return }
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
    private func reBlock(_ envelope: inout ControlEnvelope, locked: LockedControl, now: Date, endingEarly: Bool = false) throws {
        guard var session = envelope.session, session.phase == .onBreak else { return }
        if let reason = session.timedEnd(at: now, timing: timing) { try end(&envelope, locked: locked, reason: reason, now: now); return }
        guard breakSelection.restoreShield(id: session.id) else { try end(&envelope, locked: locked, reason: .recoveryInterrupted, now: now); return }
        // Both layers come back before the save of `breakOver`: the blocking rule without its break line. A failure here changes no M2 step.
        if let schedule = try? everyday.load(), EverydayRules.blocks(schedule: schedule, session: nil, authorized: .unknown, now: now, calendar: calendar),
           !everyday.storeMatches() {
            let applied = everyday.applyStored()
            if endingEarly && !applied { throw ControlIssue.verificationFailed }
        }
        session.phase = .breakOver
        if endingEarly, let breakEndsAt = session.breakEndsAt, now < breakEndsAt {
            session.deadlineCredit = max(0, (session.deadlineCredit ?? 0) - breakEndsAt.timeIntervalSince(now))
            session.breakEndsAt = now
            // The shortened deadline needs its callback before the recovery point is committed.
            try overwriteAndSave(&envelope, to: session, locked: locked, now: now)
        } else {
            var updated = envelope; updated.session = session
            // A failed save leaves `onBreak` with the shield on, and the next reconcile re-blocks again.
            try locked.save(updated); envelope = updated
        }
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
        // Convergence steps 1 and 3 only, after the focus release: the everyday layer blocks again by its schedule, also after a break.
        // The registrations wait for the end of the section, so this step cannot delay the focus part.
        // `now` can be a recorded end time, so the blocking rule uses the wall clock of the section.
        if let tracked = locked as? TrackedControl, let stored = tracked.stored { convergeStore(stored, access: tracked.access, now: tracked.now) }
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

    // MARK: Everyday convergence

    /// The activities of a layer that is on: the range, then windows 1-3.
    static func everydayActivities(_ schedule: EverydaySchedule) -> [(part: EverydayPart, start: Int, end: Int)] {
        [(.range, schedule.rangeStart, schedule.rangeEnd)] + schedule.windows.enumerated().map { (.window($0.offset + 1), $0.element.start, $0.element.end) }
    }
    /// A lock holder that does not run through `section`: its read-failure stops go through a marker wrapper without a section time.
    private func holding<T>(_ body: (LockedControl) throws -> T) throws -> T {
        try store.withExclusiveAccess { locked in
            sectionMonitoring = store.registrationMarkers.map { MarkedMonitoring(base: baseMonitoring, markers: $0) }
            defer { sectionMonitoring = nil }
            return try body(locked)
        }
    }
    /// Engine mutation sections end with everyday convergence, also when their focus part threw.
    /// When the read of `control.json` threw, the section has no envelope, and no convergence step runs.
    private func section<T>(now: Date, access: AccessState = .unknown, mayRegister: Bool = true, lockTimeout: TimeInterval? = nil, _ body: (TrackedControl) throws -> T) throws -> T {
        try store.withExclusiveAccess(timeout: lockTimeout) { base in
            let locked = TrackedControl(base, access: access, now: now)
            // Set after the lock is held. This reset runs after the convergence below, so the convergence registers through the wrapper too.
            sectionMonitoring = store.registrationMarkers.map { MarkedMonitoring(base: baseMonitoring, markers: $0, now: now, calendar: calendar) }
            defer { sectionMonitoring = nil }
            defer { if let stored = locked.stored { converge(stored, access: locked.access, mayRegister: mayRegister, now: now) } }
            return try body(locked)
        }
    }
    /// The spec "Everyday convergence". It never throws, so it can never stop a focus step.
    private func converge(_ envelope: ControlEnvelope, access: AccessState, mayRegister: Bool, now: Date) {
        // Step 1.
        let schedule: EverydaySchedule?
        do { schedule = try everyday.load() } catch { everyday.clearShield(); return }
        // Step 2. Every stop names its activity: an empty list would stop the focus and break activities too.
        let expected = schedule.map { $0.enabled ? Self.everydayActivities($0) : [] } ?? []
        if access == .denied {
            for registered in monitoring.registeredEveryday { monitoring.stopEveryday(revision: registered.revision, part: registered.part) }
        } else {
            var complete = true
            if let schedule {
                let present = Set(monitoring.registeredEveryday.filter { $0.revision == schedule.revision }.map(\.part))
                for activity in expected where !present.contains(activity.part) {
                    guard mayRegister, (try? monitoring.registerEveryday(revision: schedule.revision, part: activity.part, start: activity.start, end: activity.end)) != nil else {
                        complete = false; continue
                    }
                }
            }
            // The earlier revision stays until the stored one is complete, because it is the only source of callbacks until then.
            if complete {
                let kept = Set(expected.map(\.part))
                for registered in monitoring.registeredEveryday where !(registered.revision == schedule?.revision && kept.contains(registered.part)) {
                    monitoring.stopEveryday(revision: registered.revision, part: registered.part)
                }
            }
        }
        // Step 3.
        setEverydayStore(schedule, envelope: envelope, access: access, now: now)
    }
    /// Convergence steps 1 and 3, for the end of a session.
    private func convergeStore(_ envelope: ControlEnvelope, access: AccessState, now: Date) {
        let schedule: EverydaySchedule?
        do { schedule = try everyday.load() } catch { everyday.clearShield(); return }
        setEverydayStore(schedule, envelope: envelope, access: access, now: now)
    }
    private func setEverydayStore(_ schedule: EverydaySchedule?, envelope: ControlEnvelope, access: AccessState, now: Date) {
        if EverydayRules.blocks(schedule: schedule, session: envelope.session, authorized: access, now: now, calendar: calendar) {
            // A store that still does not match keeps what was applied; the status reports it.
            if !everyday.storeMatches() { _ = everyday.applyStored() }
        } else if everyday.hasShield { everyday.clearShield() }
    }
}
/// Remembers the envelope that the section loaded or saved last, so that the convergence never evaluates an envelope whose save failed.
private final class TrackedControl: LockedControl {
    private let base: LockedControl
    private(set) var stored: ControlEnvelope?
    /// The access value of the section; `unknown` when it does not know one.
    var access: AccessState
    /// The wall clock of the section, which the everyday blocking rule uses also where a step ends a session at a recorded time.
    let now: Date
    init(_ base: LockedControl, access: AccessState, now: Date) { self.base = base; self.access = access; self.now = now }
    func load() throws -> ControlEnvelope { let envelope = try base.load(); stored = envelope; return envelope }
    func save(_ envelope: ControlEnvelope) throws { try base.save(envelope); stored = envelope }
}
