import Foundation
public enum TimeRules {
    public static func remaining(expiresAt: Date, now: Date) -> Int { Int(ceil(max(0, min(1500, expiresAt.timeIntervalSince(now))))) }
    public static func today(now: Date, calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: now)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!)
    }
}
