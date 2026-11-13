import XCTest
import SwiftData
import FocusCore
@testable import FocusHistory

/// The counting rule of the display-only streak. Every case uses a fixed calendar and time zone.
@MainActor final class StreakTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: zone)!; return calendar
    }
    private var seoul: Calendar { calendar("Asia/Seoul") }
    /// A local wall-clock time in the calendar's zone, such as `"2026-11-13 09:00"`.
    private func at(_ text: String, _ calendar: Calendar) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }
    private func days(_ starts: [String], now: String, _ calendar: Calendar) -> Int {
        Streak.days(starts: starts.map { at($0, calendar) }, now: at(now, calendar), calendar: calendar)
    }
    private func fixture() throws -> (ModelContext, SessionHistory) {
        let container = try ModelContainer(for: SessionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        return (context, SessionHistory(context: context, acknowledge: { _ in }))
    }
    private func session(_ start: Date, _ reason: EndReason = .expired, length: TimeInterval = 1500) -> ControlSession {
        var session = ControlSession(startedAt: start, length: length)
        session.phase = .terminal; session.reason = reason; session.observedAt = session.expiresAt
        return session
    }

    func testNoRecordGivesZero() {
        XCTAssertEqual(days([], now: "2026-11-13 12:00", seoul), 0)
    }
    func testOneCompletedSessionTodayGivesOne() {
        XCTAssertEqual(days(["2026-11-13 09:00"], now: "2026-11-13 12:00", seoul), 1)
    }
    func testOneYesterdayAndNoneTodayGivesOne() {
        XCTAssertEqual(days(["2026-11-12 23:10"], now: "2026-11-13 00:05", seoul), 1)
        XCTAssertEqual(days(["2026-11-12 09:00"], now: "2026-11-13 23:59", seoul), 1)
    }
    func testNewestTwoDaysAgoGivesZero() {
        XCTAssertEqual(days(["2026-11-11 09:00", "2026-11-10 09:00"], now: "2026-11-13 00:00", seoul), 0)
    }
    func testRunOfSeveralDaysWithAndWithoutToday() {
        let run = ["2026-11-12 09:00", "2026-11-11 21:00", "2026-11-10 07:00"]
        XCTAssertEqual(days(run, now: "2026-11-13 08:00", seoul), 3)
        XCTAssertEqual(days(["2026-11-13 07:00"] + run, now: "2026-11-13 08:00", seoul), 4)
    }
    func testGapInsideOlderHistoryEndsTheRunAtTheGap() {
        let starts = ["2026-11-13 07:00", "2026-11-12 09:00", "2026-11-10 09:00", "2026-11-09 09:00", "2026-11-08 09:00"]
        XCTAssertEqual(days(starts, now: "2026-11-13 08:00", seoul), 2)
    }
    func testSeveralSessionsOnOneDayCountOnce() {
        let starts = ["2026-11-13 07:00", "2026-11-13 09:00", "2026-11-13 11:00", "2026-11-12 09:00", "2026-11-12 10:00"]
        XCTAssertEqual(days(starts, now: "2026-11-13 12:00", seoul), 2)
    }
    func testStartOrderDoesNotChangeTheNumber() {
        let starts = ["2026-11-11 09:00", "2026-11-13 07:00", "2026-11-12 09:00"]
        XCTAssertEqual(days(starts, now: "2026-11-13 12:00", seoul), 3)
    }
    /// Stored records: each end reason other than `.expired` does not count and does not join the runs on its two sides.
    func testOtherEndReasonsDoNotCountAndDoNotJoinTwoRuns() throws {
        let calendar = seoul, now = at("2026-11-13 12:00", calendar)
        for reason in [EndReason.earlyExit, .authorizationRevoked, .startFailed, .recoveryInterrupted, .clockChanged, .deadlineMissed] {
            let (_, history) = try fixture()
            try history.importTerminal(session(at("2026-11-13 09:00", calendar)))
            try history.importTerminal(session(at("2026-11-12 09:00", calendar), reason))
            try history.importTerminal(session(at("2026-11-11 09:00", calendar)))
            XCTAssertEqual(try history.streak(at: now, calendar: calendar), 1, reason.rawValue)
            let (_, alone) = try fixture()
            try alone.importTerminal(session(at("2026-11-13 09:00", calendar), reason))
            XCTAssertEqual(try alone.streak(at: now, calendar: calendar), 0, reason.rawValue)
        }
    }
    func testUnknownReasonRawDoesNotCountAndDoesNotJoinTwoRuns() throws {
        let calendar = seoul, now = at("2026-11-13 12:00", calendar)
        let (context, history) = try fixture()
        try history.importTerminal(session(at("2026-11-13 09:00", calendar)))
        let unknown = SessionRecord(session: session(at("2026-11-12 09:00", calendar))); unknown.reasonRaw = "rewarded"
        context.insert(unknown); try context.save()
        try history.importTerminal(session(at("2026-11-11 09:00", calendar)))
        XCTAssertFalse(unknown.counts)
        XCTAssertEqual(try history.streak(at: now, calendar: calendar), 1)
    }
    /// The summary and the streak use one definition of a record that counts.
    func testSummaryAndStreakCountTheSameRecords() {
        for reason in [EndReason.expired, .earlyExit, .authorizationRevoked, .startFailed, .recoveryInterrupted, .clockChanged, .deadlineMissed] {
            let record = SessionRecord(session: session(Date(timeIntervalSince1970: 1000), reason))
            XCTAssertEqual(record.counts, reason == .expired, reason.rawValue)
            XCTAssertEqual(SessionSummary(records: [record]).completedCount, record.counts ? 1 : 0, reason.rawValue)
            XCTAssertEqual(record.reasonRaw == SessionRecord.countingReason.rawValue, record.counts, reason.rawValue)
        }
    }
    func testSessionCrossingMidnightCountsForItsStartDayOnly() throws {
        let calendar = seoul
        let (_, history) = try fixture()
        try history.importTerminal(session(at("2026-11-11 23:40", calendar), length: 3000))
        // On the day of its end the run holds without a new session; one whole day later it is gone.
        XCTAssertEqual(try history.streak(at: at("2026-11-11 23:50", calendar), calendar: calendar), 1)
        XCTAssertEqual(try history.streak(at: at("2026-11-12 23:00", calendar), calendar: calendar), 1)
        XCTAssertEqual(try history.streak(at: at("2026-11-13 00:00", calendar), calendar: calendar), 0)
        // A start day of 11-12 would give 2 here.
        try history.importTerminal(session(at("2026-11-13 08:00", calendar)))
        XCTAssertEqual(try history.streak(at: at("2026-11-13 09:00", calendar), calendar: calendar), 1)
    }
    func testSameRecordsGiveTheExpectedNumbersInTwoTimeZones() {
        let utc = calendar("UTC")
        // 11-11 16:00, 11-12 10:00 and 11-12 20:00 in UTC are 11-12 01:00, 11-12 19:00 and 11-13 05:00 in Seoul.
        let starts = ["2026-11-11 16:00", "2026-11-12 10:00", "2026-11-12 20:00"].map { at($0, utc) }
        let now = at("2026-11-12 22:00", utc)
        XCTAssertEqual(Streak.days(starts: starts, now: now, calendar: utc), 2)
        XCTAssertEqual(Streak.days(starts: starts, now: now, calendar: seoul), 2)
        // Two UTC days become one Seoul day, and a Seoul day without a session appears.
        let moved = ["2026-11-10 16:00", "2026-11-11 14:00", "2026-11-12 16:00"].map { at($0, utc) }
        XCTAssertEqual(Streak.days(starts: moved, now: now, calendar: utc), 3)
        XCTAssertEqual(Streak.days(starts: moved, now: now, calendar: seoul), 1)
    }
    func testRunAcrossDaylightSavingChanges() {
        let newYork = calendar("America/New_York")
        // 2026-03-08 has 23 hours and 2026-11-01 has 25 hours in New York.
        XCTAssertEqual(days(["2026-03-07 23:30", "2026-03-08 00:10", "2026-03-09 00:10", "2026-03-10 23:50"], now: "2026-03-10 23:59", newYork), 4)
        XCTAssertEqual(days(["2026-10-31 23:30", "2026-11-01 23:30", "2026-11-02 00:10"], now: "2026-11-02 12:00", newYork), 3)
        XCTAssertEqual(days(["2026-10-31 23:30", "2026-11-02 00:10"], now: "2026-11-02 12:00", newYork), 1)
    }
    /// A calendar whose day can start at 01:00: midnight of 2018-11-04 does not exist in São Paulo.
    func testRunAcrossADayWithoutMidnight() {
        let saoPaulo = calendar("America/Sao_Paulo")
        XCTAssertEqual(days(["2018-11-03 12:00", "2018-11-04 12:00", "2018-11-05 12:00"], now: "2018-11-05 13:00", saoPaulo), 3)
    }
    func testRecordAfterTodayDoesNotCountAndDoesNotBreakARun() {
        XCTAssertEqual(days(["2026-11-15 09:00"], now: "2026-11-13 12:00", seoul), 0)
        XCTAssertEqual(days(["2026-11-15 09:00", "2026-11-14 09:00", "2026-11-13 09:00", "2026-11-12 09:00"], now: "2026-11-13 12:00", seoul), 2)
        XCTAssertEqual(days(["2026-11-14 09:00", "2026-11-12 09:00", "2026-11-11 09:00"], now: "2026-11-13 12:00", seoul), 2)
    }
    func testRecordImportedAfterNewerRecordsCountsForItsOwnStartDay() throws {
        let calendar = seoul, now = at("2026-11-13 12:00", calendar)
        let (_, history) = try fixture()
        try history.importTerminal(session(at("2026-11-13 09:00", calendar)))
        try history.importTerminal(session(at("2026-11-11 09:00", calendar)))
        XCTAssertEqual(try history.streak(at: now, calendar: calendar), 1)
        try history.importTerminal(session(at("2026-11-12 22:00", calendar)))
        XCTAssertEqual(try history.streak(at: now, calendar: calendar), 3)
    }
    func testStoredRunLongerThanOneBatchGivesTheFullNumber() throws {
        let calendar = seoul, now = at("2026-11-13 12:00", calendar)
        let (_, history) = try fixture()
        let length = Streak.batch * 2 + 5
        for day in 0..<length {
            let noon = calendar.date(byAdding: .day, value: -day, to: at("2026-11-13 11:00", calendar))!
            try history.importTerminal(session(noon)); try history.importTerminal(session(noon.addingTimeInterval(-3600)))
        }
        // An older run behind a gap is never part of the number.
        try history.importTerminal(session(calendar.date(byAdding: .day, value: -(length + 1), to: now)!))
        XCTAssertEqual(try history.streak(at: now, calendar: calendar), length)
    }
    /// Newest-first start times, one per day, with a fetch that records what the bounded read asks for.
    private func bounded(run: Int, gap: Int = 1, olderDays: Int, batch: Int) -> (days: Int, fetches: [Int]) {
        let calendar = seoul, newest = at("2026-11-13 09:00", calendar)
        // Days 0..<run, then `gap` days with no record, then `olderDays` more days.
        let starts = (Array(0..<run) + Array((run + gap)..<(run + gap + olderDays))).map { calendar.date(byAdding: .day, value: -$0, to: newest)! }
        var fetches: [Int] = []
        let days = Streak.days(now: at("2026-11-13 12:00", calendar), calendar: calendar, batch: batch) { before, limit in
            // The index of the first row that the fetch may return.
            let offset = before.map { before in starts.firstIndex { $0 < before } ?? starts.count } ?? 0
            fetches.append(offset)
            return Array(starts.dropFirst(offset).prefix(limit))
        }
        return (days, fetches)
    }
    func testShortRunInALongHistoryReadsNoMoreThanTheBoundAllows() {
        // The first batch already holds the gap, so 1,000 older rows are never read.
        var read = bounded(run: 3, olderDays: 1000, batch: 8)
        XCTAssertEqual(read.days, 3); XCTAssertEqual(read.fetches, [0])
        // A run that fills the first batch needs the next one to see the gap, and no more.
        read = bounded(run: 8, olderDays: 1000, batch: 8)
        XCTAssertEqual(read.days, 8); XCTAssertEqual(read.fetches, [0, 8])
        read = bounded(run: 20, olderDays: 1000, batch: 8)
        XCTAssertEqual(read.days, 20); XCTAssertEqual(read.fetches, [0, 8, 16])
        // No record today or yesterday: one batch.
        read = bounded(run: 0, gap: 2, olderDays: 1000, batch: 8)
        XCTAssertEqual(read.days, 0); XCTAssertEqual(read.fetches, [0])
    }
    func testBoundedReadStopsAtTheEndOfTheHistory() {
        var read = bounded(run: 5, olderDays: 0, batch: 8)
        XCTAssertEqual(read.days, 5); XCTAssertEqual(read.fetches, [0])
        // A history of exactly one batch needs one empty read to know that it ended.
        read = bounded(run: 8, olderDays: 0, batch: 8)
        XCTAssertEqual(read.days, 8); XCTAssertEqual(read.fetches, [0, 8])
    }
    /// The bounded read keeps its walk between batches; every batch size must give the number of one read of all the start times.
    func testBoundedReadGivesTheNumberOfTheWholeHistoryForEveryBatchSize() {
        let calendar = seoul, now = at("2026-11-13 12:00", calendar), noon = at("2026-11-13 11:00", calendar)
        func starts(_ days: [Int]) -> [Date] {
            // Two records per day, newest first.
            days.sorted().flatMap { day -> [Date] in
                let start = calendar.date(byAdding: .day, value: -day, to: noon)!
                return [start, start.addingTimeInterval(-3600)]
            }
        }
        let histories = [
            starts(Array(0..<40)), starts(Array(1..<40)), starts(Array(2..<40)),
            // Records after today fill the first batches before today's record is read.
            starts(Array(-6..<12) + Array(13..<30)), starts(Array(-6..<0) + Array(1..<12)), starts(Array(-6..<0)), starts([]),
            // Records with one start time: a fetch that continues below it skips the rest of them, and their day is already known.
            starts(Array(0..<10)).flatMap { [$0, $0, $0] }
        ]
        for history in histories {
            let whole = Streak.days(starts: history, now: now, calendar: calendar)
            for batch in 1...9 {
                let read = Streak.days(now: now, calendar: calendar, batch: batch) { before, limit in Array(history.filter { $0 < before ?? .distantFuture }.prefix(limit)) }
                XCTAssertEqual(read, whole, "batch \(batch), \(history.count) rows")
            }
        }
        XCTAssertEqual(histories.map { Streak.days(starts: $0, now: now, calendar: calendar) }, [40, 39, 0, 12, 11, 0, 0, 10])
    }
    /// The walk takes only the new rows of each step and continues from the day where it stopped.
    func testWalkContinuesFromTheEarlierSteps() {
        let calendar = seoul, now = at("2026-11-13 12:00", calendar), noon = at("2026-11-13 11:00", calendar)
        let history = (0..<400).map { calendar.date(byAdding: .day, value: -$0, to: noon)! }
        var walk = Streak.Walk(now: now, calendar: calendar)
        for offset in stride(from: 0, to: history.count, by: 8) {
            walk.add(Array(history[offset..<offset + 8]))
            XCTAssertEqual(walk.days, offset + 8); XCTAssertTrue(walk.open)
        }
        walk.add([calendar.date(byAdding: .day, value: -401, to: noon)!])
        XCTAssertEqual(walk.days, 400); XCTAssertFalse(walk.open)
    }
    func testBoundedReadPropagatesAFetchFailure() {
        XCTAssertThrowsError(try Streak.days(now: Date(), calendar: seoul) { _, _ in throw HistoryTestError.injected })
    }
}
