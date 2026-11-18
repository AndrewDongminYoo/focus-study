import Foundation

struct FocusActivityProjection: Equatable {
    var sessionID: UUID
    var content: FocusActivityContent
    /// `session` is the display copy of `SessionControl.activitySnapshot`, whose `activation` is set only while the session is open.
    static func make(session stored: ControlSession?, now: Date, timing: BreakTiming) -> FocusActivityProjection? {
        guard let stored else { return nil }
        // No callback runs at a chunk end, so the projection applies the pure catch-up itself (2026-11-18 single-interval amendment, decision 13).
        let open = isOpen(stored)
        let session = open ? stored.caughtUp(at: now, timing: timing) : stored
        guard now.timeIntervalSince1970.isFinite, session.startedAt.timeIntervalSince1970.isFinite,
              session.expiresAt.timeIntervalSince1970.isFinite, now >= session.startedAt,
              session.hasValidLength,
              (session.pausedSeconds ?? 0).isFinite, (session.pausedSeconds ?? 0) >= 0,
              (session.deadlineCredit ?? 0).isFinite, (session.deadlineCredit ?? 0) >= 0 else { return nil }
        if session.isPaused {
            guard let pausedAt = session.pausedAt, pausedAt.timeIntervalSince1970.isFinite, pausedAt <= now else { return nil }
        }
        let deadline = session.deadline(timing: timing)
        guard deadline.timeIntervalSince1970.isFinite, session.focusEnd.timeIntervalSince1970.isFinite,
              session.timedEnd(at: now, timing: timing) == nil else { return nil }
        let phase: FocusActivityContent.Phase
        let target: Date?
        switch session.phase {
        case .active:
            phase = Self.countsUp(session, now: now) ? .openFocus : .focus
            // A chunk end is never a target: after the base length the target is the registered end, the next time a callback can change the session.
            target = phase == .openFocus ? session.openActiveEnd(timing: timing) : min(session.focusEnd, deadline)
        case .waiting: phase = .waiting; target = nil
        case .onBreak:
            guard let end = session.breakEndsAt, end.timeIntervalSince1970.isFinite else { return nil }
            phase = .onBreak; target = min(end, deadline)
        case .breakOver:
            phase = .breakOver
            target = deadline.addingTimeInterval(-(session.length - session.focused(at: now)))
        case .preparing, .ending, .terminal: return nil
        }
        return FocusActivityProjection(sessionID: session.id, content: FocusActivityContent(
            phase: phase, checkedAt: now, targetAt: target, deadline: deadline,
            focusRemaining: TimeRules.remaining(session: session, now: now), focusEnd: phase == .focus ? session.focusEnd : nil,
            // An open `.focus` also carries the count-up start, which its card shows once it is stale at the base length (amendment, decision 14).
            focusStart: phase == .openFocus || (phase == .focus && open) ? now.addingTimeInterval(-session.openFocused(at: now)) : nil))
    }
    /// The envelope's open value, carried by the display copy's `activation`.
    static func isOpen(_ session: ControlSession) -> Bool { session.isFilterStarted && session.activation != nil && session.baseLength != nil }
    /// The rule of the timer screen (`FocusModel.openElapsed`): a filter session with an activation that reached its base length.
    static func countsUp(_ session: ControlSession, now: Date) -> Bool {
        guard session.activation != nil, let base = session.baseLength else { return false }
        return session.openFocused(at: now) >= base
    }
}
