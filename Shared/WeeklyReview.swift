import Foundation

/// A local calendar day, stored as its year, month and day so that a time zone change never moves it (docs/specs/2026-11-25-weekly-review-design.md).
/// The fields are always Gregorian in the time zone of the calendar passed in, so a stored day and its order do not change when the device's calendar is
/// Buddhist or Japanese, or changes between them; local days, weekdays and day steps are the same in every one of them.
struct ReviewDay: Codable, Hashable, Comparable {
    var year: Int, month: Int, day: Int
    init(year: Int, month: Int, day: Int) { self.year = year; self.month = month; self.day = day }
    /// A Gregorian calendar in the time zone of `calendar`.
    static func gregorian(_ calendar: Calendar) -> Calendar {
        guard calendar.identifier != .gregorian else { return calendar }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }
    /// The local day of `date` in the time zone of `calendar`.
    init(_ date: Date, calendar: Calendar) {
        let parts = Self.gregorian(calendar).dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 2001, month: parts.month ?? 1, day: parts.day ?? 1)
    }
    /// The start of this day in the time zone of `calendar`.
    func start(in calendar: Calendar) -> Date {
        let calendar = Self.gregorian(calendar)
        return calendar.date(from: DateComponents(year: year, month: month, day: day)).map { calendar.startOfDay(for: $0) } ?? Date(timeIntervalSinceReferenceDate: 0)
    }
    /// The wall-clock time `minute` minutes after local midnight on this day, built from calendar fields, so a day of 23 or 25 hours keeps the clock time.
    /// A time that a spring-forward change skips gives the next valid time.
    func date(atMinute minute: Int, in calendar: Calendar) -> Date {
        let gregorian = Self.gregorian(calendar)
        return gregorian.date(from: DateComponents(year: year, month: month, day: day, hour: minute / 60, minute: minute % 60))
            ?? start(in: calendar).addingTimeInterval(TimeInterval(minute * 60))
    }
    /// Local noon, which every day has, also a day with a daylight saving change.
    private func noon(in calendar: Calendar) -> Date { date(atMinute: 12 * 60, in: calendar) }
    /// A calendar step, so a day of 23 or 25 hours is one day.
    func adding(_ days: Int, calendar: Calendar) -> ReviewDay {
        let noon = noon(in: calendar)
        return ReviewDay(calendar.date(byAdding: .day, value: days, to: noon) ?? noon, calendar: calendar)
    }
    /// `Calendar` weekday numbering: 1 is Sunday, 7 is Saturday.
    func weekday(calendar: Calendar) -> Int { calendar.component(.weekday, from: noon(in: calendar)) }
    /// The number of days from `self` to `other`; negative when `other` is earlier.
    func days(to other: ReviewDay, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: noon(in: calendar), to: other.noon(in: calendar)).day ?? 0
    }
    /// The next day with `weekday`, on or after `self`.
    func next(weekday: Int, calendar: Calendar) -> ReviewDay {
        adding((weekday - self.weekday(calendar: calendar) + 7) % 7, calendar: calendar)
    }
    /// `2026-11-25`, the key of a stored note.
    var key: String { String(format: "%04d-%02d-%02d", year, month, day) }
    static func < (lhs: ReviewDay, rhs: ReviewDay) -> Bool { (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day) }
}

/// One review period: its first and last local day, at most seven days.
struct ReviewPeriod: Equatable {
    var first: ReviewDay
    var last: ReviewDay
    func contains(_ day: ReviewDay) -> Bool { first <= day && day <= last }
    func days(calendar: Calendar) -> [ReviewDay] {
        (0...max(0, first.days(to: last, calendar: calendar))).map { first.adding($0, calendar: calendar) }
    }
}

/// The review periods and the notification settings of one person, kept in the app's own storage.
/// The periods depend on the history of weekday changes, so the schedule stores them as segments instead of deriving them from the weekday alone.
struct ReviewSchedule: Codable, Equatable {
    /// After `anchor`, the last day of a period, the following periods end on `weekday` until the next segment's anchor.
    struct Segment: Codable, Equatable {
        var anchor: ReviewDay
        var weekday: Int
    }
    static let defaultMinute = 20 * 60
    /// Day 1: the local day on which paid access started for this person.
    var dayOne: ReviewDay
    /// Never empty, sorted by `anchor`. The first anchor is the last day of the first period.
    var segments: [Segment]
    /// The time of the review notification, in minutes after local midnight.
    var minute: Int
    /// The student's switch of the review notification.
    var notificationsOn: Bool

    /// The first period runs from day 1 to day 3; the default weekday is the weekday of day 3.
    static func start(dayOne: ReviewDay, calendar: Calendar) -> ReviewSchedule {
        let dayThree = dayOne.adding(2, calendar: calendar)
        return ReviewSchedule(dayOne: dayOne, segments: [Segment(anchor: dayThree, weekday: dayThree.weekday(calendar: calendar))], minute: defaultMinute, notificationsOn: true)
    }
    /// The weekday of the review notification and of the ends of later periods.
    var weekday: Int { segments[segments.count - 1].weekday }

    /// The period that holds `day`. A day before day 1, which only a clock moved back can give, belongs to the first period.
    func period(containing day: ReviewDay, calendar: Calendar) -> ReviewPeriod {
        guard day > segments[0].anchor else { return ReviewPeriod(first: dayOne, last: segments[0].anchor) }
        let index = segments.lastIndex { $0.anchor < day } ?? 0
        let segment = segments[index]
        var first = segment.anchor.adding(1, calendar: calendar)
        var last = first.next(weekday: segment.weekday, calendar: calendar)
        if last < day {
            let weeks = (last.days(to: day, calendar: calendar) + 6) / 7
            last = last.adding(7 * weeks, calendar: calendar)
            first = last.adding(-6, calendar: calendar)
        }
        // A later weekday change ended this period early.
        if index + 1 < segments.count, last > segments[index + 1].anchor { last = segments[index + 1].anchor }
        return ReviewPeriod(first: first, last: last)
    }
    /// The period just before `period`; `nil` for the first period.
    func period(before period: ReviewPeriod, calendar: Calendar) -> ReviewPeriod? {
        guard period.first > dayOne else { return nil }
        return self.period(containing: period.first.adding(-1, calendar: calendar), calendar: calendar)
    }
    func period(after period: ReviewPeriod, calendar: Calendar) -> ReviewPeriod {
        self.period(containing: period.last.adding(1, calendar: calendar), calendar: calendar)
    }
    /// A new review weekday, changed on `today`. No period is longer than seven days, no day falls between two periods and no day belongs to two:
    /// when the new weekday comes on or after today and on or before the last day of the current period, the current period ends on it;
    /// otherwise the current period keeps its last day and the next one ends on the first following occurrence of the new weekday.
    /// The first period always ends on day 3, because the trial's only notification is on day 3 and must open the first review.
    mutating func changeWeekday(to weekday: Int, today: ReviewDay, calendar: Calendar) {
        guard (1...7).contains(weekday), weekday != self.weekday else { return }
        let current = period(containing: today, calendar: calendar)
        let candidate = max(today, current.first).next(weekday: weekday, calendar: calendar)
        let anchor = candidate <= current.last && current.first != dayOne ? candidate : current.last
        segments = segments.filter { $0.anchor < current.first } + [Segment(anchor: anchor, weekday: weekday)]
    }
    /// The period that a review notification fired at `date` announces. Every notification fires on the last day of a period at `minute`, but the local day of `date`
    /// moves by one when the time zone changed between the fire and the tap: a day before a period's last day is in that period, and a period's first day
    /// can be the day after the period before it. On a first day, the announced period is the one of the two whose end notification time is nearest to `date`,
    /// because the day alone cannot tell a one-day period from the day after the period before it.
    func announcedPeriod(firedAt date: Date, calendar: Calendar) -> ReviewPeriod {
        let day = ReviewDay(date, calendar: calendar), period = period(containing: day, calendar: calendar)
        guard period.first == day, let before = self.period(before: period, calendar: calendar) else { return period }
        func distance(_ period: ReviewPeriod) -> TimeInterval { abs(period.last.date(atMinute: minute, in: calendar).timeIntervalSince(date)) }
        return distance(before) < distance(period) ? before : period
    }
    /// The note of a period stays editable until the end of the next period; the note of an older period is read-only.
    func isNoteEditable(_ period: ReviewPeriod, today: ReviewDay, calendar: Calendar) -> Bool {
        today <= self.period(after: period, calendar: calendar).last
    }
}

/// One completed session, as the review reads it: only a record that counts gives one.
struct ReviewEntry: Equatable {
    var startedAt: Date
    var focusDuration: TimeInterval
}

/// The values of "what I did" for one period.
struct ReviewSummary: Equatable {
    struct Day: Equatable {
        var day: ReviewDay
        /// `nil` for a day after today, which shows as a dimmed bar without a value.
        var focusDuration: TimeInterval?
        var completedCount: Int
    }
    var days: [Day]
    var recordedDays: Int { days.filter { $0.completedCount > 0 }.count }
    var completedCount: Int { days.reduce(0) { $0 + $1.completedCount } }
    var focusDuration: TimeInterval { days.reduce(0) { $0 + ($1.focusDuration ?? 0) } }
    /// A session belongs to the local day of its `startedAt`; entries outside the period are left out.
    init(entries: [ReviewEntry], period: ReviewPeriod, today: ReviewDay, calendar: Calendar) {
        var totals: [ReviewDay: (TimeInterval, Int)] = [:]
        for entry in entries {
            let day = ReviewDay(entry.startedAt, calendar: calendar)
            guard period.contains(day) else { continue }
            let old = totals[day] ?? (0, 0)
            totals[day] = (old.0 + entry.focusDuration, old.1 + 1)
        }
        days = period.days(calendar: calendar).map { day in
            let value = totals[day] ?? (0, 0)
            return Day(day: day, focusDuration: day > today ? nil : value.0, completedCount: day > today ? 0 : value.1)
        }
    }
}

/// A moment from the period that the student can use again (spec "Moment rule").
enum ReviewMoment: Equatable {
    /// Two different days whose first sessions started within 60 minutes of each other by time of day; `first` is the earlier day.
    case repetition(first: ReviewDay, firstStart: Date, second: ReviewDay, secondStart: Date)
    /// A day with a completed session whose previous day is inside the period and has none.
    case returnAfterGap(gap: ReviewDay, day: ReviewDay, start: Date)
}

/// Who can get the review notification, from the paid access of the person.
enum ReviewAccessKind: Equatable {
    /// Access `unknown` or `locked`: no notification.
    case none
    /// Access granted by the trial: only the day 3 notification, which is before the trial end.
    case trial
    /// The unlock, an earlier user, or a gate that is off: one repeating notification.
    case ongoing
}

/// What the app keeps pending for the review notification.
enum ReviewNotificationPlan: Equatable {
    case none
    case once(Date)
    case repeating(weekday: Int, minute: Int)
    /// The end of the first period, and the repeating notification, whose first fire comes after it.
    case onceThenRepeating(Date, weekday: Int, minute: Int)
    /// The end of the first period and the ends of the periods after it, while a repeating notification would fire inside the first period.
    /// A refresh after the first period replaces them with `.repeating`.
    case dates([Date])
}

enum WeeklyReview {
    /// The longest difference of two first starts that counts as a repetition at a similar time.
    static let repetitionWindow: TimeInterval = 60 * 60
    static let emptyMessage = "집중이 기록되지 않았더라도 괜찮아요. 다음엔 온:공과 함께해요."
    /// The native Korean day counts of the "what I did" sentence.
    static func dayWord(_ days: Int) -> String {
        ["하루", "이틀", "사흘", "나흘", "닷새", "엿새", "이레"][min(max(days, 1), 7) - 1]
    }
    /// "이번 주 지금까지, 이틀에 걸쳐 5번 집중했어요." While the period is not over the sentence says "지금까지".
    /// One day reads "하루 동안" and seven days read "일주일 내내", because "에 걸쳐" does not fit them.
    static func sentence(_ summary: ReviewSummary, inProgress: Bool) -> String {
        let sessions = summary.completedCount, days = summary.recordedDays
        guard sessions > 0, days > 0 else { return emptyMessage }
        let span = days == 1 ? "하루 동안" : days >= 7 ? "일주일 내내" : "\(dayWord(days))에 걸쳐"
        return "\(inProgress ? "이번 주 지금까지," : "이번 주") \(span) \(sessions)번 집중했어요."
    }
    /// "수요일".
    static func weekdayName(_ day: ReviewDay, calendar: Calendar) -> String {
        ["일요일", "월요일", "화요일", "수요일", "목요일", "금요일", "토요일"][day.weekday(calendar: calendar) - 1]
    }
    /// "오후 7시 10분", "오후 4시", "오전 12시 5분": built by hand, so the host locale never changes it.
    static func clock(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        let half = hour < 12 ? "오전" : "오후", twelve = hour % 12 == 0 ? 12 : hour % 12
        return "\(half) \(twelve)시" + (minute == 0 ? "" : " \(minute)분")
    }

    /// The rule reads only the first completed session of each local day of the period. It never fills an empty result with something else.
    static func moment(entries: [ReviewEntry], period: ReviewPeriod, calendar: Calendar) -> ReviewMoment? {
        var firsts: [ReviewDay: Date] = [:]
        for entry in entries {
            let day = ReviewDay(entry.startedAt, calendar: calendar)
            guard period.contains(day) else { continue }
            firsts[day] = min(firsts[day] ?? entry.startedAt, entry.startedAt)
        }
        let days = firsts.keys.sorted()
        func timeOfDay(_ date: Date) -> TimeInterval {
            let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
            return TimeInterval((parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0))
        }
        // 1. The smallest difference; on a tie, the pair whose later day is more recent, then whose earlier day is more recent.
        var best: (difference: TimeInterval, first: ReviewDay, second: ReviewDay)?
        for (i, first) in days.enumerated() {
            for second in days[(i + 1)...] {
                let difference = abs(timeOfDay(firsts[first]!) - timeOfDay(firsts[second]!))
                guard difference <= repetitionWindow else { continue }
                if let current = best {
                    if difference > current.difference { continue }
                    if difference == current.difference, (second, first) <= (current.second, current.first) { continue }
                }
                best = (difference, first, second)
            }
        }
        if let best { return .repetition(first: best.first, firstStart: firsts[best.first]!, second: best.second, secondStart: firsts[best.second]!) }
        // 2. The most recent day whose previous day is inside the period and has no completed session.
        for day in days.reversed() {
            let previous = day.adding(-1, calendar: calendar)
            if period.contains(previous), firsts[previous] == nil { return .returnAfterGap(gap: previous, day: day, start: firsts[day]!) }
        }
        return nil
    }
    /// The sentence states only days and actual start times.
    static func text(_ moment: ReviewMoment, calendar: Calendar) -> String {
        switch moment {
        case let .repetition(first, firstStart, second, secondStart):
            return "\(weekdayName(first, calendar: calendar)) \(clock(firstStart, calendar: calendar)), \(weekdayName(second, calendar: calendar)) \(clock(secondStart, calendar: calendar))에 그날 첫 집중을 시작했어요."
        case let .returnAfterGap(gap, day, start):
            return "\(weekdayName(gap, calendar: calendar))엔 온:공 기록이 없었고, \(weekdayName(day, calendar: calendar)) \(clock(start, calendar: calendar))에 시작한 세션을 마쳤어요."
        }
    }

    /// The pending review notification (contract item 6). A trial gets only the day 3 notification, and only while it is still ahead and before the trial end;
    /// the unlock or an earlier user gets one repeating notification on the review weekday and time. Its text holds no numbers, so it never needs a reschedule for content.
    static func notificationPlan(kind: ReviewAccessKind, schedule: ReviewSchedule?, now: Date, trialEnd: Date?, calendar: Calendar) -> ReviewNotificationPlan {
        guard let schedule, schedule.notificationsOn else { return .none }
        switch kind {
        case .none: return .none
        case .trial:
            let fire = schedule.dayOne.adding(2, calendar: calendar).date(atMinute: schedule.minute, in: calendar)
            guard fire > now, trialEnd.map({ fire < $0 }) ?? true else { return .none }
            return .once(fire)
        case .ongoing:
            // A weekday change during the first period applies from the next period, and the first period still ends on day 3 with its own notification.
            // A repeating trigger cannot start later: while its next fire comes before the end of the first period, the ends of the following periods
            // are scheduled one by one, up to `pendingDates`, so the notification comes every week also when the app does not run.
            let repeating = ReviewNotificationPlan.repeating(weekday: schedule.weekday, minute: schedule.minute)
            let firstPeriod = schedule.period(containing: schedule.dayOne, calendar: calendar)
            let firstEnd = firstPeriod.last.date(atMinute: schedule.minute, in: calendar)
            let matching = DateComponents(hour: schedule.minute / 60, minute: schedule.minute % 60, weekday: schedule.weekday)
            guard firstEnd > now, let next = calendar.nextDate(after: now, matching: matching, matchingPolicy: .nextTime), next != firstEnd else { return repeating }
            if next > firstEnd { return .onceThenRepeating(firstEnd, weekday: schedule.weekday, minute: schedule.minute) }
            // The dates follow from the first period, not from `now`, so a refresh that changes nothing gives the same plan.
            var dates = [firstEnd], period = firstPeriod
            while dates.count < pendingDates {
                period = schedule.period(after: period, calendar: calendar)
                dates.append(period.last.date(atMinute: schedule.minute, in: calendar))
            }
            return .dates(dates)
        }
    }
    /// The most review notifications that the app keeps pending at once, below the system limit of 64 per app.
    static let pendingDates = 52
}
