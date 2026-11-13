import Foundation
import SwiftData
#if SWIFT_PACKAGE
import FocusCore
#endif

@Model final class SessionRecord {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var expiresAt: Date
    var endedAt: Date
    var observedAt: Date
    var reasonRaw: String
    var reason: EndReason { EndReason(rawValue: reasonRaw) ?? .recoveryInterrupted }
    /// The one end reason of a record that counts, for the summary and for the streak.
    static let countingReason = EndReason.expired
    /// A completed session; every other end reason, and an unknown `reasonRaw`, does not count.
    var counts: Bool { reason == Self.countingReason }
    /// Only a completed session gives focus time; with breaks, the elapsed time of any other session is not focus time.
    var focusDuration: TimeInterval { counts ? max(0, expiresAt.timeIntervalSince(startedAt)) : 0 }
    init(session: ControlSession) {
        id = session.id; startedAt = session.startedAt; expiresAt = session.expiresAt
        endedAt = session.recordedEnd ?? session.startedAt
        observedAt = session.observedAt ?? session.startedAt
        reasonRaw = (session.reason ?? .recoveryInterrupted).rawValue
    }
}
/// Summarizes the already day-filtered history; interruptions never earn focus time.
struct SessionSummary {
    let completedCount: Int
    let focusDuration: TimeInterval
    init(records: [SessionRecord]) {
        let completed = records.filter(\.counts)
        completedCount = completed.count
        focusDuration = completed.reduce(0) { $0 + $1.focusDuration }
    }
    var text: String {
        let duration = Duration.seconds(focusDuration).formatted(.units(allowed: [.hours, .minutes], width: .wide))
        return "오늘 집중 \(duration) · \(completedCount)회"
    }
}
/// The display-only streak: consecutive local days, ending today or yesterday, with at least one record that counts.
enum Streak {
    /// Rows per fetch of the bounded read.
    static let batch = 64
    /// The rule, fed with start times of records that count, in any order and in any number of steps. A record belongs to the local day of its start.
    /// Each start time is read once and the walk continues from the day where it stopped, so the cost follows the number of start times.
    struct Walk {
        private let calendar: Calendar, today: Date
        private var known: Set<Date> = [], oldest: Date?
        /// The newest day before today that is not known to count, and the length of the run between it and today.
        private var cursor: Date, before = 0
        init(now: Date, calendar: Calendar) {
            self.calendar = calendar; today = calendar.startOfDay(for: now)
            cursor = Self.dayBefore(today, calendar) ?? today
        }
        /// A calendar step, so a day of 23 or 25 hours is one day.
        private static func dayBefore(_ day: Date, _ calendar: Calendar) -> Date? {
            calendar.date(byAdding: .day, value: -1, to: day).map { calendar.startOfDay(for: $0) }
        }
        mutating func add(_ starts: [Date]) {
            for start in starts {
                let day = calendar.startOfDay(for: start)
                // A day after today exists only after the clock or the time zone moved back; it does not count and does not break a run.
                guard day <= today else { continue }
                known.insert(day); oldest = min(oldest ?? day, day)
            }
            while known.contains(cursor), let previous = Self.dayBefore(cursor, calendar), previous < cursor { before += 1; cursor = previous }
        }
        /// Today without a completed session keeps the run that ends yesterday.
        var days: Int { known.contains(today) ? before + 1 : before }
        /// `true` while no given start is older than the run, so older records could still make the run longer.
        var open: Bool { oldest.map { $0 > cursor } ?? true }
    }
    static func run(starts: [Date], now: Date, calendar: Calendar) -> (days: Int, open: Bool) {
        var walk = Walk(now: now, calendar: calendar)
        walk.add(starts)
        return (walk.days, walk.open)
    }
    static func days(starts: [Date], now: Date, calendar: Calendar) -> Int { run(starts: starts, now: now, calendar: calendar).days }
    /// The bounded read: `newest(before, limit)` returns the start times before `before` (all of them for `nil`) from the newest, and older rows are read only while the run reaches the oldest row read so far.
    /// Each fetch continues below the oldest start time read, so no fetch passes over the rows of an earlier one. A record with exactly that start time is on a day that is already known.
    static func days(now: Date, calendar: Calendar, batch: Int = batch, newest: (_ before: Date?, _ limit: Int) throws -> [Date]) rethrows -> Int {
        var walk = Walk(now: now, calendar: calendar), before: Date?
        while true {
            let rows = try newest(before, batch)
            walk.add(rows)
            if rows.count < batch || !walk.open { return walk.days }
            before = rows.min()
        }
    }
}
@MainActor protocol SessionHistoryProviding {
    func importTerminal(_ session: ControlSession) throws
    func records(on date: Date, calendar: Calendar) throws -> [SessionRecord]
    /// The streak at `date`: see `Streak`.
    func streak(at date: Date, calendar: Calendar) throws -> Int
}
@MainActor final class SessionHistory: SessionHistoryProviding {
    private let context: ModelContext
    private let acknowledge: (UUID) throws -> Void
    private let save: () throws -> Void
    init(context: ModelContext, acknowledge: @escaping (UUID) throws -> Void, save: (() throws -> Void)? = nil) {
        self.context = context; self.acknowledge = acknowledge; self.save = save ?? { try context.save() }
        context.autosaveEnabled = false
    }
    func importTerminal(_ session: ControlSession) throws {
        guard session.phase == .terminal, session.reason != nil, session.observedAt != nil else { throw HistoryIssue.invalidTerminal }
        let id = session.id
        let query = FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.id == id })
        if try context.fetch(query).isEmpty {
            context.insert(SessionRecord(session: session))
            do { try save() } catch { context.rollback(); throw error }
        }
        try acknowledge(id)
    }
    func records(on date: Date, calendar: Calendar = .current) throws -> [SessionRecord] {
        let interval = TimeRules.today(now: date, calendar: calendar), start = interval.start, end = interval.end
        return try context.fetch(FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.startedAt >= start && $0.startedAt < end }, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
    }
    func streak(at date: Date, calendar: Calendar = .current) throws -> Int {
        let counting = SessionRecord.countingReason.rawValue
        return try Streak.days(now: date, calendar: calendar) { before, limit in
            let before = before ?? .distantFuture
            var query = FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.reasonRaw == counting && $0.startedAt < before }, sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
            query.fetchLimit = limit
            return try context.fetch(query).map(\.startedAt)
        }
    }
}
enum HistoryIssue: Error { case invalidTerminal }
