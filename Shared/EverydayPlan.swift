import Foundation

// The home screen widget compiles this file (everyday plan widget design, "Data path"): it imports Foundation only, and of the other `Shared/` files it names only types of `Shared/TodaySnapshot.swift` (`TodaySnapshot`, `TodaySnapshotRead`), which the widget also compiles.

/// The label of an unblocked window. `custom` is a window that the person names by time only.
public enum EverydayWindowKind: String, Codable, CaseIterable { case lunch, toSchool, fromSchool, custom }
/// An unblocked window, in minutes after midnight, half-open (`[start, end)`).
public struct EverydayWindow: Codable, Equatable {
    public var kind: EverydayWindowKind
    public var start: Int
    public var end: Int
    public init(kind: EverydayWindowKind, start: Int, end: Int) { self.kind = kind; self.start = start; self.end = end }
}

/// The plan fields of the everyday schedule, which the app writes for the everyday plan widget: no token, no revision and no engine state.
public struct EverydayPlan: Codable, Equatable {
    public var enabled: Bool
    public var rangeStart: Int
    public var rangeEnd: Int
    public var windows: [EverydayWindow]
    /// The weekday numbers, 1 for Sunday to 7 for Saturday; `nil` means every day.
    public var weekdays: [Int]?
    /// The day key of the day that the layer is off for.
    public var offDay: String?
    public init(enabled: Bool, rangeStart: Int, rangeEnd: Int, windows: [EverydayWindow], weekdays: [Int]? = nil, offDay: String? = nil) {
        self.enabled = enabled; self.rangeStart = rangeStart; self.rangeEnd = rangeEnd; self.windows = windows; self.weekdays = weekdays; self.offDay = offDay
    }

    // MARK: Days

    /// The local calendar day of `date` in `calendar`, as `yyyy-MM-dd`, independent of the locale. `offDay` holds this key.
    public static func dayKey(of date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    /// Weekday numbers from the calendar's first weekday, 1 for Sunday.
    public static func weekdayOrder(calendar: Calendar) -> [Int] { (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 } }
    public static func shortWeekdayName(_ day: Int) -> String { ["일", "월", "화", "수", "목", "금", "토"][(day - 1) % 7] }
    public static func weekdayName(_ day: Int) -> String { shortWeekdayName(day) + "요일" }
    /// The summary of the chosen days: 매일, 평일, 주말, the short names in the order of the first weekday, or 요일 없음.
    public static func weekdaySummary(_ days: Set<Int>, calendar: Calendar) -> String {
        switch days {
        case Set(1...7): "매일"
        case Set(2...6): "평일"
        case [1, 7]: "주말"
        case []: "요일 없음"
        default: weekdayOrder(calendar: calendar).filter(days.contains).map(shortWeekdayName).joined(separator: ", ")
        }
    }
    /// The reading of `EverydaySchedule.storedWeekdays`: numbers outside 1 to 7 are dropped, and nothing left is every day.
    public var chosenWeekdays: Set<Int> {
        let kept = Set((weekdays ?? []).filter { (1...7).contains($0) })
        return kept.isEmpty ? Set(1...7) : kept
    }
    public func applies(on date: Date, calendar: Calendar) -> Bool { chosenWeekdays.contains(calendar.component(.weekday, from: date)) }
    public func isOff(at date: Date, calendar: Calendar) -> Bool { offDay == Self.dayKey(of: date, calendar: calendar) }

    // MARK: Spans

    /// The time rules that the spans need: the 5-minute grid, inside one day, a range of at least 5 minutes, windows inside it that do not overlap
    /// and do not cover it. A plan that breaks one is a damaged file, which the widget shows as the check state.
    public var isValid: Bool {
        let times = [rangeStart, rangeEnd] + windows.flatMap { [$0.start, $0.end] }
        guard times.allSatisfy({ $0 % 5 == 0 }), rangeStart >= 0, rangeEnd <= 23 * 60 + 55, rangeStart < rangeEnd, windows.count <= 3 else { return false }
        let sorted = windows.sorted { $0.start < $1.start }
        for (index, window) in sorted.enumerated() {
            guard window.start < window.end, window.start >= rangeStart, window.end <= rangeEnd else { return false }
            if index > 0, sorted[index - 1].end > window.start { return false }
        }
        return sorted.reduce(0) { $0 + $1.end - $1.start } < rangeEnd - rangeStart
    }
    /// The merged runs of the range, in order: adjacent windows form one unblocked span, and the parts outside every window are restricted.
    public var spans: [EverydayPlanSpan] {
        var merged: [(start: Int, end: Int)] = []
        for window in windows.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, last.end >= window.start { merged[merged.count - 1].end = max(last.end, window.end) }
            else { merged.append((window.start, window.end)) }
        }
        var spans: [EverydayPlanSpan] = [], cursor = rangeStart
        for window in merged {
            if window.start > cursor { spans.append(EverydayPlanSpan(restricted: true, start: cursor, end: window.start)) }
            spans.append(EverydayPlanSpan(restricted: false, start: window.start, end: window.end))
            cursor = window.end
        }
        if cursor < rangeEnd { spans.append(EverydayPlanSpan(restricted: true, start: cursor, end: rangeEnd)) }
        return spans
    }
    /// A fixed plan for the widget gallery, the placeholder and the DEBUG preview: 08:00-18:00 with 12:00-13:00 and 16:00-16:30 unblocked.
    public static let sample = EverydayPlan(enabled: true, rangeStart: 8 * 60, rangeEnd: 18 * 60,
                                            windows: [EverydayWindow(kind: .lunch, start: 12 * 60, end: 13 * 60), EverydayWindow(kind: .fromSchool, start: 16 * 60, end: 16 * 60 + 30)])
}

/// One merged run of the range, in minutes after midnight, half-open.
public struct EverydayPlanSpan: Equatable {
    public var restricted: Bool
    public var start: Int
    public var end: Int
    public init(restricted: Bool, start: Int, end: Int) { self.restricted = restricted; self.start = start; self.end = end }
    /// The insets of a drawn span of `width`: each inner edge gives up half of `gap`, but at most a quarter of `width`,
    /// so that a short span keeps at least half of its width and never disappears from the timeline.
    public static func edgeInsets(width: Double, leading: Bool, trailing: Bool, gap: Double) -> (leading: Double, trailing: Double) {
        let inset = min(gap / 2, max(width, 0) / 4)
        return (leading ? inset : 0, trailing ? inset : 0)
    }
}

/// `TodaySnapshot/everyday-plan.json`, which only the app writes and the everyday plan widget reads.
public struct EverydayPlanFile: Codable, Equatable {
    public static let schema = 1
    public static let directoryName = TodaySnapshot.directoryName, fileName = "everyday-plan.json"
    /// The widget's `kind`, which the app's reload request names.
    public static let widgetKind = "EverydayPlanWidget"
    public var schemaVersion: Int
    /// `nil` when the app found no everyday file.
    public var plan: EverydayPlan?
    /// The app's last read found an issue or access `denied`: the widget shows the check state, not the plan.
    public var needsCheck: Bool
    public init(plan: EverydayPlan?, needsCheck: Bool) { schemaVersion = Self.schema; self.plan = plan; self.needsCheck = needsCheck }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }
    public static func decode(_ data: Data) -> EverydayPlanFile? { try? JSONDecoder().decode(EverydayPlanFile.self, from: data) }
}

// MARK: What the widget shows

/// One block below the timeline: a caption, a headline and an optional caption, with the words that the accessibility text says.
public struct EverydayPlanBlock: Equatable {
    public var label: String
    public var value: String
    public var detail: String?
    /// The headline is the current restricted span's `제한`, which takes the accent color.
    public var accent = false
    public var spoken: String
}

/// A restriction day at one time: the timeline and the two blocks.
public struct EverydayPlanToday: Equatable {
    public var rangeStart: Int
    public var rangeEnd: Int
    public var spans: [EverydayPlanSpan]
    /// The shown time in minutes after midnight, rounded down to 5 minutes.
    public var now: Int
    public var left: EverydayPlanBlock
    public var right: EverydayPlanBlock
    /// The now ticks are drawn inside the range only.
    public var nowIsInsideRange: Bool { rangeStart <= now && now < rangeEnd }
}

/// The views of the states table of the everyday plan widget design.
public enum EverydayPlanState: Equatable {
    case noSchedule, check, off, dayOff, offToday
    case today(EverydayPlanToday)
    /// The one line of an empty timeline, or `nil` on a restriction day.
    public var line: String? {
        switch self {
        case .noSchedule: "앱에서 매일 제한을 정해 보세요"
        case .check: "앱에서 확인해 주세요"
        case .off: "매일 제한이 꺼져 있어요"
        case .dayOff: "오늘은 제한하지 않는 요일이에요"
        case .offToday: "오늘은 매일 제한을 꺼 두었어요"
        case .today: nil
        }
    }
}

/// The widget's whole content at one time.
public struct EverydayPlanDisplay: Equatable {
    public static let title = "오늘의 제한 계획"
    /// `매일` or the weekday summary; `nil` without a readable plan.
    public var weekdays: String?
    public var state: EverydayPlanState
    public var accessibilityText: String {
        switch state {
        case .today(let today): "\(Self.title), \(today.left.spoken), \(today.right.spoken)"
        default: "\(Self.title), \(state.line ?? "")"
        }
    }
}

extension EverydayPlanFile {
    /// The view for `date`, with the widget's own calendar: whether today is a chosen weekday, whether `offDay` is today, the spans and the next change.
    public static func display(_ read: TodaySnapshotRead, at date: Date, calendar: Calendar) -> EverydayPlanDisplay {
        switch read {
        case .missing: return EverydayPlanDisplay(weekdays: nil, state: .noSchedule)
        case .unreadable: return EverydayPlanDisplay(weekdays: nil, state: .check)
        case .data(let data):
            guard let file = decode(data), file.schemaVersion == schema else { return EverydayPlanDisplay(weekdays: nil, state: .check) }
            return file.display(at: date, calendar: calendar)
        }
    }
    public func display(at date: Date, calendar: Calendar) -> EverydayPlanDisplay {
        guard let plan else { return EverydayPlanDisplay(weekdays: nil, state: needsCheck ? .check : .noSchedule) }
        guard !needsCheck, plan.isValid else { return EverydayPlanDisplay(weekdays: nil, state: .check) }
        let weekdays = EverydayPlan.weekdaySummary(plan.chosenWeekdays, calendar: calendar)
        guard plan.enabled else { return EverydayPlanDisplay(weekdays: weekdays, state: .off) }
        guard plan.applies(on: date, calendar: calendar) else { return EverydayPlanDisplay(weekdays: weekdays, state: .dayOff) }
        guard !plan.isOff(at: date, calendar: calendar) else { return EverydayPlanDisplay(weekdays: weekdays, state: .offToday) }
        return EverydayPlanDisplay(weekdays: weekdays, state: .today(Self.today(plan, at: date, calendar: calendar)))
    }
    /// The entries of one timeline: now, every 5 minutes of today after it, which include each span boundary, and the next local midnight.
    /// A day without restriction stays the same until midnight, so it gets only the first and the last entry. The policy is `atEnd`.
    public static func entries(_ read: TodaySnapshotRead, now: Date, calendar: Calendar) -> [(date: Date, display: EverydayPlanDisplay)] {
        let startOfDay = calendar.startOfDay(for: now)
        guard let midnight = calendar.date(byAdding: .day, value: 1, to: startOfDay).map(calendar.startOfDay) else { return [(now, display(read, at: now, calendar: calendar))] }
        let current = display(read, at: now, calendar: calendar)
        var dates = [now]
        if case .today = current.state {
            // Steps run to the next local midnight, not a fixed 24 hours, so a 25-hour day keeps its last hour.
            var step = 1
            while let date = calendar.date(byAdding: .minute, value: step * 5, to: startOfDay), date < midnight {
                if date > now { dates.append(date) }
                step += 1
            }
        }
        dates.append(midnight)
        return dates.map { ($0, $0 == now ? current : display(read, at: $0, calendar: calendar)) }
    }

    // MARK: Now and next

    static func today(_ plan: EverydayPlan, at date: Date, calendar: Calendar) -> EverydayPlanToday {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let now = ((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) / 5 * 5
        let spans = plan.spans, nowLabel = "지금 \(time(now))"
        let left: EverydayPlanBlock, right: EverydayPlanBlock
        if now < plan.rangeStart, let first = spans.first {
            left = EverydayPlanBlock(label: nowLabel, value: "제한 전", detail: "\(time(plan.rangeStart))부터", spoken: "\(nowLabel) 제한 전, \(time(plan.rangeStart))부터")
            let word = first.restricted ? "제한" : "해제"
            right = EverydayPlanBlock(label: word, value: "\(time(first.start))부터", detail: "\(time(first.end))까지", spoken: "\(word) \(spokenSpan(first))")
        } else if let index = spans.firstIndex(where: { $0.start <= now && now < $0.end }) {
            let span = spans[index], word = span.restricted ? "제한" : "해제"
            left = EverydayPlanBlock(label: nowLabel, value: word, detail: "\(time(span.start))–\(time(span.end))", accent: span.restricted,
                                     spoken: "\(nowLabel) \(word), \(spokenSpan(span))")
            // Merged spans alternate, so the next span is the next change of kind.
            if index + 1 < spans.count {
                let next = spans[index + 1]
                if span.restricted {
                    let after = index + 2 < spans.count ? spans[index + 2] : nil
                    let value = "\(time(next.start))부터 \(duration(next.end - next.start))"
                    right = EverydayPlanBlock(label: "다음 해제", value: value, detail: after.map { "그다음 제한 \(time($0.start))–\(time($0.end))" },
                                              spoken: "다음 해제 \(value)" + (after.map { ", 그다음 제한 \(spokenSpan($0))" } ?? ""))
                } else {
                    right = EverydayPlanBlock(label: "다음 제한", value: "\(time(next.start))부터", detail: "\(time(next.end))까지", spoken: "다음 제한 \(spokenSpan(next))")
                }
            } else {
                let rest = span.restricted ? "남은 해제 없음" : "남은 제한 없음"
                right = EverydayPlanBlock(label: "제한 끝", value: time(plan.rangeEnd), detail: rest, spoken: "제한 끝 \(time(plan.rangeEnd)), \(rest)")
            }
        } else {
            left = EverydayPlanBlock(label: nowLabel, value: "제한 끝", detail: "\(time(plan.rangeEnd))에 끝났어요", spoken: "\(nowLabel) 제한 끝, \(time(plan.rangeEnd))에 끝났어요")
            let next = nextRestriction(plan, after: date, calendar: calendar)
            right = EverydayPlanBlock(label: "다음 제한", value: next, detail: nil, spoken: "다음 제한 \(next)")
        }
        return EverydayPlanToday(rangeStart: plan.rangeStart, rangeEnd: plan.rangeEnd, spans: spans, now: now, left: left, right: right)
    }
    /// The first restriction day after today and the start of its first restricted span: `내일 08:00`, or a later day by its weekday as the app's status line names it.
    static func nextRestriction(_ plan: EverydayPlan, after date: Date, calendar: Calendar) -> String {
        let start = plan.spans.first(where: \.restricted)?.start ?? plan.rangeStart, today = calendar.startOfDay(for: date)
        for offset in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { break }
            guard plan.applies(on: day, calendar: calendar), !plan.isOff(at: day, calendar: calendar) else { continue }
            let word = offset == 1 ? "내일" : EverydayPlan.weekdayName(calendar.component(.weekday, from: day))
            return "\(word) \(time(start))"
        }
        return time(start)
    }
    static func time(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
    /// `30분`, `1시간`, `1시간 30분`.
    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest)분" }
        return rest == 0 ? "\(hours)시간" : "\(hours)시간 \(rest)분"
    }
    private static func spokenSpan(_ span: EverydayPlanSpan) -> String { "\(time(span.start))부터 \(time(span.end))까지" }
}
