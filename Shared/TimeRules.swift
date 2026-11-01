import Foundation
public enum TimeRules {
    /// Remaining focus time, rounded up to whole seconds; it stops while the session is paused.
    public static func remaining(session: ControlSession, now: Date) -> Int {
        Int(ceil(max(0, session.length - session.focused(at: now))))
    }
    public static func today(now: Date, calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: now)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!)
    }
}
