import Foundation

/// The label of an unblocked window. `custom` is a window that the person names by time only.
public enum EverydayWindowKind: String, Codable, CaseIterable { case lunch, toSchool, fromSchool, custom }
/// An unblocked window, in minutes after midnight, half-open (`[start, end)`).
public struct EverydayWindow: Codable, Equatable {
    public var kind: EverydayWindowKind
    public var start: Int
    public var end: Int
    public init(kind: EverydayWindowKind, start: Int, end: Int) { self.kind = kind; self.start = start; self.end = end }
}
/// The schedule part of `everyday-layer.json`. The tokens are encoded in `Integration/` only.
public struct EverydaySchedule: Codable, Equatable {
    public static let grid = 5
    public static let latestRangeEnd = 23 * 60 + 55
    public static let minimumRange = 60
    public static let maxWindows = 3
    public static let windowLengths = 15...120
    public var revision: UUID
    public var enabled: Bool
    public var rangeStart: Int
    public var rangeEnd: Int
    public var windows: [EverydayWindow]
    public init(revision: UUID, enabled: Bool, rangeStart: Int, rangeEnd: Int, windows: [EverydayWindow]) {
        self.revision = revision; self.enabled = enabled; self.rangeStart = rangeStart; self.rangeEnd = rangeEnd; self.windows = windows
    }
    /// A new layer: off, 08:00-18:00, no windows.
    public static let standard = EverydaySchedule(revision: UUID(), enabled: false, rangeStart: 8 * 60, rangeEnd: 18 * 60, windows: [])
    /// The suggested time of a template, and `nil` for `custom`.
    public static func template(_ kind: EverydayWindowKind) -> EverydayWindow? {
        switch kind {
        case .lunch: EverydayWindow(kind: .lunch, start: 12 * 60, end: 13 * 60)
        case .toSchool: EverydayWindow(kind: .toSchool, start: 8 * 60, end: 8 * 60 + 30)
        case .fromSchool: EverydayWindow(kind: .fromSchool, start: 16 * 60, end: 16 * 60 + 30)
        case .custom: nil
        }
    }

    // MARK: Rules

    /// Every rule of the spec section "Times".
    public var isValid: Bool {
        let times = [rangeStart, rangeEnd] + windows.flatMap { [$0.start, $0.end] }
        guard times.allSatisfy({ $0 % Self.grid == 0 }), rangeStart >= 0, rangeEnd <= Self.latestRangeEnd,
              rangeEnd - rangeStart >= Self.minimumRange, windows.count <= Self.maxWindows else { return false }
        let sorted = windows.sorted { $0.start < $1.start }
        for (index, window) in sorted.enumerated() {
            guard Self.windowLengths.contains(window.end - window.start), window.start >= rangeStart, window.end <= rangeEnd else { return false }
            if index > 0, sorted[index - 1].end > window.start { return false }
        }
        // Windows inside the range that do not overlap cover it only when their lengths add up to it.
        return sorted.reduce(0) { $0 + $1.end - $1.start } < rangeEnd - rangeStart
    }
    /// The schedule part of the blocking rule: enabled, inside the range, outside every window.
    public func blocks(at now: Date, calendar: Calendar) -> Bool { blocks(second: Self.second(of: now, calendar: calendar)) }
    public func isInsideRange(at now: Date, calendar: Calendar) -> Bool { isInsideRange(second: Self.second(of: now, calendar: calendar)) }
    /// The next time that `blocks` changes, today or tomorrow; `nil` for a layer that is off.
    public func nextChange(after now: Date, calendar: Calendar) -> Date? {
        guard enabled else { return nil }
        let second = Self.second(of: now, calendar: calendar), current = blocks(second: second)
        let today = calendar.startOfDay(for: now)
        let edges = Set([rangeStart, rangeEnd] + windows.flatMap { [$0.start, $0.end] }).map { $0 * 60 }.sorted()
        for (dayOffset, candidates) in [(0, edges.filter { $0 > second }), (1, edges)] {
            for edge in candidates where blocks(second: edge) != current {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { return nil }
                return calendar.date(bySettingHour: edge / 3600, minute: edge % 3600 / 60, second: 0, of: day)
            }
        }
        return nil
    }
    /// The schedule conditions of the spec "Editing rules": outside the stored range, or with nothing on, every edit passes.
    /// Inside it, the new schedule must stay on and block at every time from `now` to the stored range end where `stored` blocks.
    public func isAtLeastAsStrict(as stored: EverydaySchedule, from now: Date, calendar: Calendar) -> Bool {
        let second = Self.second(of: now, calendar: calendar)
        guard stored.enabled, stored.isInsideRange(second: second) else { return true }
        guard enabled else { return false }
        // Both schedules are constant between their edges, so the start of each segment decides it.
        let end = stored.rangeEnd * 60
        let edges = (edgeSeconds + stored.edgeSeconds).filter { $0 > second && $0 < end }
        return ([second] + edges).allSatisfy { !stored.blocks(second: $0) || blocks(second: $0) }
    }

    // MARK: Seconds after midnight

    private var edgeSeconds: [Int] { ([rangeStart, rangeEnd] + windows.flatMap { [$0.start, $0.end] }).map { $0 * 60 } }
    private func isInsideRange(second: Int) -> Bool { rangeStart * 60 <= second && second < rangeEnd * 60 }
    private func blocks(second: Int) -> Bool {
        enabled && isInsideRange(second: second) && !windows.contains { $0.start * 60 <= second && second < $0.end * 60 }
    }
    /// The local wall-clock time, so that 11:59:59 is not 12:00.
    private static func second(of date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
    }
}
/// The whole blocking rule of the spec "The blocking rule".
public enum EverydayRules {
    /// `authorized` is `nil` when the section does not know the access value. A `nil` session drops the break line, as the re-block needs.
    public static func blocks(schedule: EverydaySchedule?, session: ControlSession?, authorized: Bool?, now: Date, calendar: Calendar) -> Bool {
        guard let schedule, authorized != false, schedule.blocks(at: now, calendar: calendar) else { return false }
        if let session, session.phase == .onBreak, now < (session.breakEndsAt ?? .distantPast) { return false }
        return true
    }
    /// The next time that `blocks` changes; `nil` for a layer that is off or without access.
    /// During a break the rule stays off until `breakEndsAt`, and from then it follows the schedule.
    public static func nextChange(schedule: EverydaySchedule?, session: ControlSession?, authorized: Bool?, now: Date, calendar: Calendar) -> Date? {
        guard let schedule, authorized != false else { return nil }
        if let session, session.phase == .onBreak, let breakEndsAt = session.breakEndsAt, now < breakEndsAt {
            return schedule.blocks(at: breakEndsAt, calendar: calendar) ? breakEndsAt : schedule.nextChange(after: breakEndsAt, calendar: calendar)
        }
        return schedule.nextChange(after: now, calendar: calendar)
    }
}
