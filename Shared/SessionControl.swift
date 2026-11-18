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
    /// The focus activity whose `intervalDidEnd` runs the current section; a registration of that activity there does not survive the callback
    /// (2026-11-18 single-interval amendment, decision 12).
    private var ownEndActivity: String?
    /// Set by the Focus off section: `end` clears the marker in its save of `ending` (2026-11-18 single-interval amendment, decision 16).
    private var clearsMarkerOnEnd = false
    /// `nil` in the App Intents extension, which never calls a ManagedSettings store (2026-11-16 shield amendment, decision 1).
    private let applyFocusSelection: (() -> Bool)?
    private var writesShields: Bool { applyFocusSelection != nil }
    /// Every process constructor passes `role`; the default serves the host tests, whose engines have no App Group selection.
    init(store: any ControlStore, monitoring: any MonitoringClient, shield: any ShieldClient, breakSelection: any BreakSelectionStore,
         everyday: any EverydayLayerStore, timing: BreakTiming = .standard, calendar: Calendar = .autoupdatingCurrent,
         role: ShieldRole = .appContainer(applyFocusSelection: { false })) {
        self.store = store; self.baseMonitoring = monitoring; self.shield = shield; self.breakSelection = breakSelection
        self.everyday = everyday; self.timing = timing; self.calendar = calendar
        switch role {
        case .appContainer(let apply): applyFocusSelection = apply
        case .intentsExtension: applyFocusSelection = nil
        }
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
    /// `calledAt` is the arrival time of the call (2026-11-16 extension design, "Call order across processes"); `nil` skips the order check.
    /// `inputRefusal` is a refusal that the caller found in its inputs outside the lock, such as a missing focus length; it is ordered and marked like any refusal.
    func startFromFocusFilter(now: Date, length: TimeInterval, authorized: () -> AccessState, selectionReady: Bool, apply: () -> Void, matches: () -> Bool,
                              calledAt: Date? = nil, inputRefusal: FocusFilterRefusal? = nil) throws -> FocusFilterStart {
        try section(now: now) { locked in
            var envelope = try read(locked)
            try cleanup(&envelope, locked: locked, now: now)
            // A call that arrived before an accepted one makes no change of its own.
            if Self.isStale(calledAt, envelope) { return .stale }
            if let calledAt { envelope.filterCallAt = calledAt }
            // A repeated call of the same activation makes no change of its own; it stores only its arrival time.
            guard envelope.filterActivation == nil else { try saveCallTime(envelope, locked: locked); return .repeated }
            envelope.filterActivation = UUID()
            locked.access = authorized()
            let refusal: FocusFilterRefusal?
            // Only `denied` refuses: a fresh extension process usually reads `unknown` (2026-11-16 extension design, decision 20).
            if locked.access == .denied { refusal = .access }
            else if let inputRefusal { refusal = inputRefusal }
            else if !selectionReady { refusal = .selection }
            else if let prior = envelope.session { refusal = prior.phase == .terminal ? .history : .busy }
            else { refusal = nil }
            if let refusal { try locked.save(envelope); return .refused(refusal) }
            // The save of `preparing` writes the marker; the rollback keeps it, so the activation is used.
            // The two access reads inside `begin` also accept `unknown`; the registration and shield checks still prove the restrictions.
            let notDenied: () -> AccessState = { authorized() == .denied ? .denied : .approved }
            return .started(try begin(&envelope, locked: locked, now: now, length: length, origin: .focusFilter, activation: envelope.filterActivation,
                                      authorized: notDenied, apply: apply, matches: matches))
        }
    }
    /// The spec "Filter end". The Focus-off rule ends only a `focusFilter` session; a manual one ends only for the reasons of any reconcile.
    /// Returns `false` for a stale call, which changes nothing of its own.
    @discardableResult
    func endFromFocusFilter(now: Date, authorized: AccessState, calledAt: Date? = nil) throws -> Bool {
        try section(now: now, access: authorized) { locked in
            var envelope = try read(locked)
            // Turning the Focus off is the person's end, so it must still lift the restrictions of a filter-started session when the cleanup or the reconcile cannot save (#53).
            var caught: Error?
            do { try cleanup(&envelope, locked: locked, now: now) } catch { caught = error }
            if Self.isStale(calledAt, envelope) {
                if let caught { throw caught }
                return false
            }
            if let calledAt { envelope.filterCallAt = calledAt }
            // Openness is decided before the marker is cleared and kept for the rest of the section (2026-11-16 extension design, "Filter end").
            let wasOpen = envelope.sessionIsOpen
            // Saves before the save of `ending` keep the stored marker, so a process exit there is a lost off call that the activation check repairs;
            // the save of `ending`, or the save at the end of this section, carries the cleared marker (2026-11-18 single-interval amendment, decision 16).
            clearsMarkerOnEnd = true
            defer { clearsMarkerOnEnd = false }
            if caught == nil {
                do { try reconcile(&envelope, locked: locked, now: now, authorized: authorized, clockChanged: false, finalizingOpen: wasOpen) } catch { caught = error }
            }
            // An `end` inside the cleanup or the reconcile sets `terminal` in memory before its last save, so its own error never causes a second end.
            if let session = envelope.session, session.phase != .terminal, session.isFilterStarted {
                if wasOpen {
                    try endOpen(&envelope, locked: locked, now: now, authorized: authorized)
                } else {
                    // The reconcile order after a caught error: access `denied`, then the timed end, else the person's end. `unknown` is not a revocation.
                    let reason: EndReason = caught == nil ? .earlyExit : authorized == .denied ? .authorizationRevoked : session.timedEnd(at: now, timing: timing) ?? .earlyExit
                    try end(&envelope, locked: locked, reason: reason, now: now)
                }
            } else if let caught { throw caught }
            if var stored = locked.stored, stored.filterActivation != nil || (calledAt != nil && stored.filterCallAt != calledAt) {
                stored.filterActivation = nil
                if let calledAt { stored.filterCallAt = calledAt }
                try locked.save(stored)
            }
            return true
        }
    }
    /// The spec "Activation check", step 3: clears the marker only while it is still the one that the caller read.
    /// It never starts a session; it ends a session that was open for that marker, as a Focus off would (2026-11-16 extension design).
    /// `now` is the time of the section, which the end of an open session and the everyday convergence use; `calledAt` is the time before the read of the Focus,
    /// which only the call order uses (spec "Call order across processes", step 4). Without `calledAt`, `now` serves both.
    func clearFilterActivation(matching id: UUID, now: Date, calledAt: Date? = nil) throws {
        try section(now: now) { locked in
            var envelope = try read(locked)
            try cleanup(&envelope, locked: locked, now: now)
            guard envelope.filterActivation == id else { return }
            let wasOpen = envelope.sessionIsOpen
            // The time of the check makes an on call that arrived before it stale (spec "Call order across processes", step 4).
            let checkedAt = calledAt ?? now
            envelope.filterActivation = nil; envelope.filterCallAt = max(envelope.filterCallAt ?? checkedAt, checkedAt)
            if wasOpen, let session = envelope.session, Self.isRunning(session.phase) {
                try endOpen(&envelope, locked: locked, now: now, authorized: .unknown)
            } else {
                try locked.save(envelope)
            }
        }
    }
    func snapshot() throws -> ControlEnvelope { try holding { try read($0) } }
    /// Optional display reads never invoke recovery, even when metadata is unavailable.
    /// The display copy keeps `activation` only while the session is open, so the projection reads the envelope's open value from it
    /// (2026-11-18 single-interval amendment, decision 13).
    func activitySnapshot() throws -> ControlSession? {
        try store.withExclusiveAccess { locked in
            let envelope = try locked.load()
            guard var session = envelope.session else { return nil }
            if !envelope.sessionIsOpen { session.activation = nil }
            return session
        }
    }
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
            // "집중 종료" of an open session counts when the base length was reached (2026-11-16 extension design, "Manual end"); the marker stays.
            if reason == .earlyExit, envelope.sessionIsOpen, Self.isRunning(current.phase) {
                try endOpen(&envelope, locked: locked, now: endedAt ?? now, authorized: .unknown); return
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
            let stored = envelope.session
            let ownEnd = kind == .didEnd && stored.map { activityName == $0.activityName } == true
            if ownEnd { ownEndActivity = activityName }
            defer { ownEndActivity = nil }
            // The cleanup depends only on the envelope and the time, and an orphaned break activity is often the only caller.
            // In the focus activity's own end no later callback comes, so a failed cleanup save does not stop the section (amendment, decision 9).
            do { try cleanup(&envelope, locked: locked, now: now) } catch { if !ownEnd { throw error } }
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
            // In its own end a failed save of the reconcile, such as a re-block at the 192 h cap, must not skip the end below (amendment, decision 9).
            var reconcileError: Error?
            do { try reconcile(&envelope, locked: locked, now: now, authorized: authorized, clockChanged: false, reBlockEarly: isCurrentBreak && kind == .willEndWarning) }
            catch { if !ownEnd { throw error }; reconcileError = error }
            // Callback with nothing due: the registered interval has ended, and the system deletes it after this callback, so a session
            // that is still running has no callback at its next change and ends (2026-11-18 single-interval amendment, decision 12).
            guard ownEnd, let after = envelope.session, after.id == session.id, after.phase != .ending, after.phase != .terminal else {
                if let reconcileError { throw reconcileError }
                return
            }
            try endWithoutCallback(&envelope, locked: locked, now: now)
        }
    }
    /// A Monitor callback is often the only trigger of its timed change, so a lock timeout retries with a fresh time before the callback returns.
    /// The store throws `lockTimeout` before the section runs, so a failed attempt changed nothing. Worst case with the defaults: attempt 0, then 5 lock waits of 0.25 s and 4 pauses of 0.25 s, about 2.25 s.
    /// After every `lockTimeout`, a fresh marker of the lock holder that decides this callback ends the callback: the holder's section decides that activity.
    /// A `register` marker decides `didStart` and `didEnd` before its `validUntil`; a `stop` marker decides only `didEnd`.
    /// Before attempt 0, a busy probe and a deciding marker end the callback with no access read and no lock attempt.
    func handleCallbackRetryingLock(activityName: String, kind: CallbackKind, now: () -> Date, authorized: () -> AccessState, retries: Int = 4, pause: TimeInterval = 0.25,
                                    sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) throws {
        let first = now()
        // The early check (#119): while a holder has the lock and its fresh marker decides this callback, return before the access read, which can take a main-queue hop of about 0.2 s.
        // The holder can release the lock between the probe and the marker read. That is the race of a `lockTimeout` followed by the marker read below:
        // a holder deletes its marker before it releases the lock, so a marker that is read then is that holder's, whose section decides this activity, or a leftover that the next lock holder deletes.
        if store.isLockBusy(), holderDecides(activityName: activityName, kind: kind, now: first) { return }
        // Attempt 0: one lock call that does not wait, with no pause after it.
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
    /// Read only after a busy probe or a `lockTimeout`: a marker without a busy lock is a leftover, and the callback must then run.
    private func holderDecides(activityName: String, kind: CallbackKind, now: Date) -> Bool {
        store.registrationMarkers?.freshMarker()?.decides(activityName: activityName, kind: kind, now: now) == true
    }

    // MARK: Break transitions

    /// Transition 1: `active` → `waiting`. The restrictions stay on, and the focus timer stops.
    func requestBreak(id: UUID, now: Date) throws -> ControlSession {
        try section(now: now) { locked in
            var envelope = try read(locked)
            try cleanup(&envelope, locked: locked, now: now)
            // A session whose shield is pending cannot carry the flag into `waiting`; the repair at the end of this section shields it, so a second request can start the break.
            guard var session = envelope.session, session.id == id, session.phase == .active, session.breaksLeft > 0, session.shieldPending == nil,
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
                if let end = focusActivityEnd(session, open: envelope.sessionIsOpen) { _ = try registerFocus(session, end: end, now: now) }
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
            if writesShields { shield.clear() }
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
            // The extension leaves this cleanup to the app container: its stores are not the app's (2026-11-16 shield amendment, decision 1),
            // and a stop made after its lock could remove a registration that the app makes for the same running session in between
            // (2026-11-17 lock-order amendment, reconciliation of decision 5).
            guard writesShields else { throw error }
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
    private func begin(_ envelope: inout ControlEnvelope, locked: LockedControl, now: Date, length: TimeInterval, origin: SessionOrigin, activation: UUID? = nil,
                       authorized: () -> AccessState, apply: () -> Void, matches: () -> Bool) throws -> ControlSession {
        var session = ControlSession(startedAt: now, length: length)
        session.origin = origin
        if origin == .focusFilter { session.activation = activation; session.baseLength = length }
        do {
            envelope.session = session
            try locked.save(envelope)
            // In the extension, the interval begins after the section has released the lock, so `startMonitoring` does not wait for the Monitor's callback;
            // `startedAt` stays the call time (2026-11-17 lock-order amendment, decision 1). Later registrations of the session keep `startedAt`.
            let intervalStart = writesShields ? session.startedAt : now.addingTimeInterval(Self.extensionStartDelay)
            // An open session registers its one interval to the bound end (2026-11-18 single-interval amendment, decisions 1 and 8).
            let intervalEnd = envelope.sessionIsOpen ? session.openActiveEnd(timing: timing) : session.expiresAt
            try monitoring.register(id: session.id, start: intervalStart, end: intervalEnd)
            guard monitoring.isRegistered(id: session.id), authorized() == .approved else { throw ControlIssue.verificationFailed }
            if writesShields {
                apply()
                guard matches(), authorized() == .approved else { throw ControlIssue.verificationFailed }
            } else {
                // The Monitor applies and verifies the shield in `intervalDidStart` of this activity (2026-11-16 shield amendment, decisions 4 and 5).
                session.shieldPending = true
            }
            session.phase = .active; envelope.session = session
            try locked.save(envelope)
            return session
        } catch {
            // Keep the lock until rollback completes: a newer session cannot be cleared here.
            if writesShields { shield.clear() }
            monitoring.stop(id: session.id)
            session.phase = .terminal; session.reason = .startFailed; session.observedAt = now; session.shieldPending = nil
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
        try catchUp(&envelope, locked: locked, now: now)
    }
    /// The stored-only rollover of an open session (2026-11-18 single-interval amendment, decisions 9 and 10). It registers nothing.
    /// The envelope changes before the save, so a section that continues after a failed save works on the caught-up session.
    private func catchUp(_ envelope: inout ControlEnvelope, locked: LockedControl, now: Date) throws {
        let next = envelope.caughtUp(at: now, timing: timing)
        guard next.session != envelope.session else { return }
        envelope = next
        do { try locked.save(envelope) }
        // In the focus activity's own end no later callback comes, so the section continues in memory (amendment, decision 9).
        catch { if ownEndActivity == nil { throw error } }
    }
    /// `finalizingOpen`: the Focus-off section of a session that was open; it neither rolls over nor ends with the timed `.expired`, and its own end follows.
    private func reconcile(_ envelope: inout ControlEnvelope, locked: LockedControl, now: Date, authorized: AccessState, clockChanged: Bool, reBlockEarly: Bool = false,
                           finalizingOpen: Bool = false) throws {
        guard let s = envelope.session, s.phase != .terminal else { return }
        let open = finalizingOpen || envelope.sessionIsOpen
        if s.phase == .ending { try end(&envelope, locked: locked, reason: s.reason ?? .recoveryInterrupted, now: s.observedAt ?? now); return }
        // Step 2. Only a `denied` read is a revocation; `unknown` skips this step and runs every other one.
        if authorized == .denied { try end(&envelope, locked: locked, reason: .authorizationRevoked, now: now); return }
        if s.phase == .preparing { try end(&envelope, locked: locked, reason: .recoveryInterrupted, now: now); return }
        if clockChanged { try end(&envelope, locked: locked, reason: .clockChanged, now: now); return }
        // Also for an open session: a missing registration can be the read-failure cleanup, which cleared the shield, so a rollover must not continue it.
        if !monitoring.isRegistered(id: s.id) { try end(&envelope, locked: locked, reason: .recoveryInterrupted, now: now); return }
        // The app was not there to start the break, so the wait is cancelled as of its end plus the grace.
        if s.phase == .waiting, let waitEndsAt = s.waitEndsAt, now >= waitEndsAt.addingTimeInterval(timing.staleWaitGrace) {
            try closeWait(&envelope, locked: locked, now: now)
        }
        guard envelope.session.map({ $0.phase != .waiting }) == true else { return }
        // A stale-wait cancel can run long after the wait and return an open session to `active` with a focus end of an old chunk (amendment, decision 10).
        if open, !finalizingOpen { try catchUp(&envelope, locked: locked, now: now) }
        guard let current = envelope.session else { return }
        if let reason = current.timedEnd(at: now, timing: timing), !(finalizingOpen && reason == .expired) {
            try end(&envelope, locked: locked, reason: reason, now: now); return
        }
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
    /// The extension skips it: its restore would apply the copy in its own container and commit `breakOver` with no shield in force.
    /// The break activity's warning or the app re-blocks instead (2026-11-16 shield amendment, decision 1).
    private func reBlock(_ envelope: inout ControlEnvelope, locked: LockedControl, now: Date, endingEarly: Bool = false) throws {
        guard writesShields, var session = envelope.session, session.phase == .onBreak else { return }
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
        // A stored `ending` keeps the reason and the time it was saved with, so a retry cannot pair a measured length with another reason.
        if session.phase != .ending { session.reason = reason; session.observedAt = now }
        // The store accepts a pending shield only in `active`.
        session.phase = .ending; session.shieldPending = nil
        envelope.session = session
        if clearsMarkerOnEnd { envelope.filterActivation = nil }
        // A disk failure must not prevent releasing our own restrictions.
        var writeError: Error?
        do { try locked.save(envelope) } catch { writeError = error }
        // In the extension, the Monitor's `intervalDidEnd` of the stopped activity lifts the shield (2026-11-16 shield amendment, decision 8).
        if writesShields { shield.clear() }
        monitoring.stop(id: session.id)
        breakSelection.remove(id: session.id)
        // Convergence steps 1 and 3 only, after the focus release: the everyday layer blocks again by its schedule, also after a break.
        // The registrations wait for the end of the section, so this step cannot delay the focus part.
        // `now` can be a recorded end time, so the blocking rule uses the wall clock of the section.
        if let tracked = locked as? TrackedControl, let stored = tracked.stored { convergeStore(stored, access: tracked.access, now: tracked.now) }
        session.phase = .terminal; envelope.session = session
        try locked.save(envelope)
        if let writeError { throw writeError }
    }

    // MARK: Open sessions (2026-11-16 Focus filter extension design)

    /// A call is stale when an accepted call arrived later. Equal times keep the lock order, and a missing time on either side makes no call stale.
    static func isStale(_ calledAt: Date?, _ envelope: ControlEnvelope) -> Bool {
        guard let calledAt, let stored = envelope.filterCallAt else { return false }
        return stored > calledAt
    }
    /// The save of an accepted call that changes nothing else.
    private func saveCallTime(_ envelope: ControlEnvelope, locked: TrackedControl) throws {
        // `stored` is the envelope of the last load or save of this section, so the save keeps whatever the cleanup saved.
        guard var stored = locked.stored, stored.filterCallAt != envelope.filterCallAt else { return }
        stored.filterCallAt = envelope.filterCallAt
        try locked.save(stored)
    }

    static func isRunning(_ phase: SessionPhase) -> Bool { [.active, .waiting, .onBreak, .breakOver].contains(phase) }
    /// The end of a session that was open, with the reason order of decision 4: `denied`, the deadline, the base length reached, else the person's end.
    /// Every end of an open session converges here, so the missing-registration rule of the reconcile holds on each path:
    /// the read-failure cleanup cleared the shield and stopped monitoring, so that time is never counted.
    private func endOpen(_ envelope: inout ControlEnvelope, locked: LockedControl, now: Date, authorized: AccessState) throws {
        guard var session = envelope.session else { return }
        if authorized == .denied { try end(&envelope, locked: locked, reason: .authorizationRevoked, now: now); return }
        if !monitoring.isRegistered(id: session.id) { try end(&envelope, locked: locked, reason: .recoveryInterrupted, now: now); return }
        if session.timedEnd(at: now, timing: timing) == .deadlineMissed { try end(&envelope, locked: locked, reason: .deadlineMissed, now: now); return }
        let focused = session.openFocused(at: now)
        guard let base = session.baseLength, focused >= base else { try end(&envelope, locked: locked, reason: .earlyExit, now: now); return }
        session.expiresAt = session.startedAt.addingTimeInterval(focused)
        envelope.session = session
        try end(&envelope, locked: locked, reason: .expired, now: now)
    }

    // MARK: Focus activity end

    /// The next time the stored session must change without the app (spec "Monitoring activities").
    /// An open session registers its focus interval once, to the bound end (2026-11-18 single-interval amendment, decision 5).
    private func focusActivityEnd(_ session: ControlSession, open: Bool) -> Date? {
        let deadline = session.deadline(timing: timing)
        let activeEnd = open ? session.openActiveEnd(timing: timing) : min(session.focusEnd, deadline)
        let end: Date
        switch session.phase {
        case .active: end = activeEnd
        case .waiting:
            guard let pausedAt = session.pausedAt, let waitEndsAt = session.waitEndsAt else { return nil }
            // The `active` end after a stale-wait cancel, which adds the same time to the pause and to the deadline.
            end = activeEnd.addingTimeInterval(max(0, waitEndsAt.addingTimeInterval(timing.staleWaitGrace).timeIntervalSince(pausedAt)))
        case .onBreak, .breakOver: end = deadline
        case .preparing, .ending, .terminal: return nil
        }
        // Repeated wait cancels can grow the pauses without a bound, so an open session's end stays within the probed interval (amendment, "Bounds").
        return open ? min(end, session.startedAt.addingTimeInterval(ControlSession.maxIntervalLength)) : end
    }
    private enum FocusRegistration { case made, skipped }
    /// Inside its own end, a registration of the focus activity does not survive the callback (amendment, decision 12):
    /// one whose end is not after `now` is skipped, because the same section ends the session at that end; any other counts as failed.
    private func registerFocus(_ session: ControlSession, end: Date, now: Date) throws -> FocusRegistration {
        if ownEndActivity == session.activityName {
            guard end > now else { return .skipped }
            throw ControlIssue.verificationFailed
        }
        // The interval always starts at `startedAt`, so it is at least the focus length.
        try monitoring.register(id: session.id, start: session.startedAt, end: end)
        return .made
    }
    /// Registers the end that the stored phase needs. A session without a callback at its next change must not keep the restrictions on.
    /// A restored end that is not after `now` ends the session (M2 step 2); this is not the skip of decision 12.
    private func registerStoredEnd(_ envelope: inout ControlEnvelope, locked: LockedControl, now: Date) throws {
        guard let session = envelope.session, let end = focusActivityEnd(session, open: envelope.sessionIsOpen) else { return }
        if end > now, (try? registerFocus(session, end: end, now: now)) == .made { return }
        if ownEndActivity != nil { try endWithoutCallback(&envelope, locked: locked, now: now) }
        else { try self.end(&envelope, locked: locked, reason: .recoveryInterrupted, now: now) }
    }
    /// Transitions 1, 2 and 5 overwrite the focus activity end before they save.
    /// After a failure, the registered end must match the stored phase again, or the session ends.
    /// After a skipped registration nothing was registered, so a failed save continues on the new session in memory (amendment, decision 12).
    private func overwriteAndSave(_ envelope: inout ControlEnvelope, to next: ControlSession, locked: LockedControl, now: Date) throws {
        var updated = envelope; updated.session = next
        var registration: FocusRegistration?
        do {
            if let end = focusActivityEnd(next, open: updated.sessionIsOpen) { registration = try registerFocus(next, end: end, now: now) }
            try locked.save(updated)
            envelope = updated
        } catch {
            if registration == .skipped { envelope = updated; return }
            try registerStoredEnd(&envelope, locked: locked, now: now)
            throw error
        }
    }
    /// The end of a session whose focus interval ended with the session still running (amendment, decision 12): an open session that reached
    /// its base length counts, with the open focused time; every other session ends as `.recoveryInterrupted`.
    /// The time is the registered end when the callback came late, so a late callback at the 192 h cap records no time after the cap.
    private func endWithoutCallback(_ envelope: inout ControlEnvelope, locked: LockedControl, now: Date) throws {
        guard var session = envelope.session else { return }
        let open = envelope.sessionIsOpen
        let endedAt = min(now, focusActivityEnd(session, open: open) ?? now)
        let focused = session.openFocused(at: endedAt)
        if open, let base = session.baseLength, focused >= base {
            session.expiresAt = session.startedAt.addingTimeInterval(focused)
            envelope.session = session
            try end(&envelope, locked: locked, reason: .expired, now: endedAt)
            return
        }
        try end(&envelope, locked: locked, reason: .recoveryInterrupted, now: endedAt)
    }

    // MARK: Everyday convergence

    /// The activities of a layer that is on: the range, then windows 1-3.
    static func everydayActivities(_ schedule: EverydaySchedule) -> [(part: EverydayPart, start: Int, end: Int)] {
        [(.range, schedule.rangeStart, schedule.rangeEnd)] + schedule.windows.enumerated().map { (.window($0.offset + 1), $0.element.start, $0.element.end) }
    }
    /// A lock holder that does not run through `section`: its read-failure stops go through a marker wrapper without a section time.
    private func holding<T>(_ body: (LockedControl) throws -> T) throws -> T {
        let deferred = deferredStops()
        // Runs after `withExclusiveAccess` returned or threw, so after the lock is released.
        defer { deferred?.flush() }
        return try store.withExclusiveAccess { locked in
            sectionMonitoring = deferred ?? markerStore.map { MarkedMonitoring(base: baseMonitoring, markers: $0) }
            defer { sectionMonitoring = nil }
            return try body(locked)
        }
    }
    /// Engine mutation sections end with everyday convergence, also when their focus part threw.
    /// When the read of `control.json` threw, the section has no envelope, and no convergence step runs.
    private func section<T>(now: Date, access: AccessState = .unknown, mayRegister: Bool = true, lockTimeout: TimeInterval? = nil, _ body: (TrackedControl) throws -> T) throws -> T {
        let deferred = deferredStops()
        // Runs after `withExclusiveAccess` returned or threw, so after the lock is released.
        defer { deferred?.flush() }
        return try store.withExclusiveAccess(timeout: lockTimeout) { base in
            let locked = TrackedControl(base, access: access, now: now)
            // Set after the lock is held. This reset runs after the convergence below, so the convergence registers through the wrapper too.
            sectionMonitoring = deferred ?? markerStore.map { MarkedMonitoring(base: baseMonitoring, markers: $0, now: now, calendar: calendar) }
            defer { sectionMonitoring = nil }
            defer { if let stored = locked.stored { converge(stored, access: locked.access, mayRegister: mayRegister, now: now) } }
            // Declared after the convergence, so it runs before it, also when the body threw.
            defer { repairShield(locked) }
            return try body(locked)
        }
    }
    /// An extension section writes no marker: it cannot decide a shield, so a Monitor callback must wait for its lock (2026-11-16 shield amendment, decision 9).
    private var markerStore: (any RegistrationMarkerStore)? { writesShields ? store.registrationMarkers : nil }
    /// The extension's stops wait until its lock is released, so the Monitor's callback for each stop can take the lock (2026-11-17 lock-order amendment, decisions 4 to 6).
    private func deferredStops() -> DeferredStopMonitoring? { writesShields ? nil : DeferredStopMonitoring(base: baseMonitoring) }
    /// The delay of the first focus registration of an extension start (2026-11-17 lock-order amendment, decision 1).
    static let extensionStartDelay: TimeInterval = 5
    /// Decision 11 of the 2026-11-16 shield amendment, after the section's own steps: it recovers a lost `intervalDidStart` or `intervalDidEnd` of the Monitor.
    /// With no running session stored, the focus shield is lifted; this is also decision 8, for a callback of an ended or removed session.
    /// A callback of another running session changes nothing.
    /// A pending shield is applied only while the session's focus activity is registered: an end whose saves failed, or the read-failure cleanup of an earlier
    /// section, stopped it, and a shield without its callbacks would stay until the app runs. The reconcile of a later section ends that session instead.
    private func repairShield(_ locked: TrackedControl) {
        guard let applyFocusSelection, var envelope = locked.stored else { return }
        if var session = envelope.session, session.phase == .active, session.shieldPending == true {
            guard monitoring.isRegistered(id: session.id) else { return }
            if applyFocusSelection() {
                session.shieldPending = nil; envelope.session = session
                // A failed save keeps the flag with the shield on; the next section applies and saves again.
                try? locked.save(envelope)
            } else {
                // As the M1 rollback: `end` lifts what the apply wrote.
                try? end(&envelope, locked: locked, reason: .startFailed, now: locked.now)
            }
        } else if !(envelope.session.map { Self.isRunning($0.phase) } ?? false), shield.hasShield {
            shield.clear()
        }
    }
    /// The spec "Everyday convergence". It never throws, so it can never stop a focus step.
    private func converge(_ envelope: ControlEnvelope, access: AccessState, mayRegister: Bool, now: Date) {
        // An extension section changes no everyday activity and no store: a registration whose range has begun would wait for the Monitor's callback,
        // and the next section in the app container converges the layer (2026-11-17 lock-order amendment, decision 7).
        guard writesShields else { return }
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
        guard writesShields else { return }
        let schedule: EverydaySchedule?
        do { schedule = try everyday.load() } catch { everyday.clearShield(); return }
        setEverydayStore(schedule, envelope: envelope, access: access, now: now)
    }
    private func setEverydayStore(_ schedule: EverydaySchedule?, envelope: ControlEnvelope, access: AccessState, now: Date) {
        guard writesShields else { return }
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
