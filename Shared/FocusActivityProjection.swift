import Foundation

struct FocusActivityProjection: Equatable {
    var sessionID: UUID
    var content: FocusActivityContent
    static func make(session: ControlSession?, now: Date, timing: BreakTiming) -> FocusActivityProjection? {
        guard let session else { return nil }
        guard now.timeIntervalSince1970.isFinite, session.startedAt.timeIntervalSince1970.isFinite,
              session.expiresAt.timeIntervalSince1970.isFinite, now >= session.startedAt,
              FocusLength.isAllowed(seconds: session.length),
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
        case .active: phase = .focus; target = min(session.focusEnd, deadline)
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
            focusRemaining: TimeRules.remaining(session: session, now: now), focusEnd: phase == .focus ? session.focusEnd : nil))
    }
}
