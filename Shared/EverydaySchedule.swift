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
/// A broken rule of the spec section "Times", in the order that `EverydaySchedule.issue` checks them.
public enum EverydayScheduleIssue: CaseIterable, Equatable {
    /// A time is not on the 5-minute grid.
    case offGrid
    /// The range starts before 00:00 or ends after 23:55.
    case outOfDay
    /// The range is shorter than `minimumRange`, or ends before it starts.
    case rangeTooShort
    /// More than `maxWindows` windows.
    case tooManyWindows
    /// A window is shorter or longer than `windowLengths`.
    case windowLength
    /// A window starts before the range or ends after it.
    case windowOutsideRange
    /// Two windows overlap.
    case windowsOverlap
    /// The windows cover the whole range.
    case windowsCoverRange
}
/// The editing conditions of the spec "Refused save: conditions and their order", in the order that a save checks them.
public enum EverydayLockReason: Error, CaseIterable, Equatable {
    /// The new schedule turns the layer off.
    case turnsOff
    /// The new range does not contain `now`.
    case rangeExcludesNow
    /// The new range ends before the stored range end.
    case rangeEndsEarlier
    /// Between `now` and the stored range end, the new schedule leaves a time free that the stored schedule blocks.
    case unblocksTime
    /// The new selection leaves out an app or a website of the stored selection.
    case removesSelection
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
    /// The day key of the day that the layer is off for; `nil` when no day is off. The load does not validate it.
    public var offDay: String?
    public init(revision: UUID, enabled: Bool, rangeStart: Int, rangeEnd: Int, windows: [EverydayWindow], offDay: String? = nil) {
        self.revision = revision; self.enabled = enabled; self.rangeStart = rangeStart; self.rangeEnd = rangeEnd; self.windows = windows; self.offDay = offDay
    }
    /// The local calendar day of `date` in `calendar`, as `yyyy-MM-dd`, independent of the locale.
    public static func dayKey(of date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    /// The layer is off for the local day of `now`. A malformed `offDay` matches no day.
    public func isOff(at now: Date, calendar: Calendar) -> Bool { offDay == Self.dayKey(of: now, calendar: calendar) }
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
    public var isValid: Bool { issue == nil }
    /// The first rule of the spec section "Times" that the schedule breaks, or `nil` for a valid schedule.
    public var issue: EverydayScheduleIssue? {
        let times = [rangeStart, rangeEnd] + windows.flatMap { [$0.start, $0.end] }
        guard times.allSatisfy({ $0 % Self.grid == 0 }) else { return .offGrid }
        guard rangeStart >= 0, rangeEnd <= Self.latestRangeEnd else { return .outOfDay }
        guard rangeEnd - rangeStart >= Self.minimumRange else { return .rangeTooShort }
        guard windows.count <= Self.maxWindows else { return .tooManyWindows }
        let sorted = windows.sorted { $0.start < $1.start }
        for (index, window) in sorted.enumerated() {
            guard Self.windowLengths.contains(window.end - window.start) else { return .windowLength }
            guard window.start >= rangeStart, window.end <= rangeEnd else { return .windowOutsideRange }
            if index > 0, sorted[index - 1].end > window.start { return .windowsOverlap }
        }
        // Windows inside the range that do not overlap cover it only when their lengths add up to it.
        return sorted.reduce(0) { $0 + $1.end - $1.start } < rangeEnd - rangeStart ? nil : .windowsCoverRange
    }
    /// The schedule part of the blocking rule: enabled, not off for today, inside the range, outside every window.
    public func blocks(at now: Date, calendar: Calendar) -> Bool {
        !isOff(at: now, calendar: calendar) && blocks(second: Self.second(of: now, calendar: calendar))
    }
    public func isInsideRange(at now: Date, calendar: Calendar) -> Bool { isInsideRange(second: Self.second(of: now, calendar: calendar)) }
    /// The next time that `blocks` changes, today or tomorrow; `nil` for a layer that is off.
    /// A day that is off blocks nothing, so on such a day the next change is the next day's first blocked time.
    public func nextChange(after now: Date, calendar: Calendar) -> Date? {
        guard enabled else { return nil }
        let second = Self.second(of: now, calendar: calendar), current = blocks(at: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let edges = Set([rangeStart, rangeEnd] + windows.flatMap { [$0.start, $0.end] }).map { $0 * 60 }.sorted()
        for (dayOffset, candidates) in [(0, edges.filter { $0 > second }), (1, edges)] {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { return nil }
            let off = isOff(at: day, calendar: calendar)
            for edge in candidates where (!off && blocks(second: edge)) != current {
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
        return enabled && blocksWherever(stored, from: second)
    }
    /// The first schedule condition of the spec "Refused save: conditions and their order" that the new schedule breaks, or `nil`.
    /// The gate reads `enabled` and the stored range, never `offDay`; the selection condition is checked by the caller after these.
    public func lockReason(against stored: EverydaySchedule, at now: Date, calendar: Calendar) -> EverydayLockReason? {
        let second = Self.second(of: now, calendar: calendar)
        guard stored.enabled, stored.isInsideRange(second: second) else { return nil }
        guard enabled else { return .turnsOff }
        guard isInsideRange(second: second) else { return .rangeExcludesNow }
        guard rangeEnd >= stored.rangeEnd else { return .rangeEndsEarlier }
        return blocksWherever(stored, from: second) ? nil : .unblocksTime
    }
    /// At every time from `second` to the stored range end, this schedule blocks wherever `stored` blocks; the off day is not read.
    private func blocksWherever(_ stored: EverydaySchedule, from second: Int) -> Bool {
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
