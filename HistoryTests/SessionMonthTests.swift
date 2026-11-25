import XCTest
import SwiftData
import FocusCore
@testable import FocusHistory

/// The month values of the 순공 calendar and the month read. Every case uses a fixed calendar and time zone.
@MainActor final class SessionMonthTests: XCTestCase {
    private var seoul: Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!; return calendar
    }
    /// A local wall-clock time in the calendar's zone, such as `"2026-11-13 09:00"`.
    private func at(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = seoul; formatter.timeZone = seoul.timeZone; formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }
    private func record(_ start: String, _ reason: EndReason = .expired, minutes: Double = 50) -> SessionRecord {
        var session = ControlSession(startedAt: at(start), length: minutes * 60)
        session.phase = .terminal; session.reason = reason; session.observedAt = session.expiresAt
        return SessionRecord(session: session)
    }
    private var november: DateInterval { SessionMonth.interval(containing: at("2026-11-24 12:00"), calendar: seoul) }

    func testMonthIntervalIsTheLocalMonth() {
        XCTAssertEqual(november.start, at("2026-11-01 00:00"))
        XCTAssertEqual(november.end, at("2026-12-01 00:00"))
    }
    func testDaysSumCompletedFocusTimeAndCount() {
        let month = SessionMonth(records: [record("2026-11-24 09:00"), record("2026-11-24 14:00", minutes: 25), record("2026-11-03 08:00", minutes: 30)], month: november, calendar: seoul)
        XCTAssertEqual(month.day(at("2026-11-24 00:00"), calendar: seoul), SessionMonth.Day(focusDuration: 75 * 60, completedCount: 2))
        XCTAssertEqual(month.day(at("2026-11-03 23:59"), calendar: seoul), SessionMonth.Day(focusDuration: 30 * 60, completedCount: 1))
        XCTAssertEqual(month.focusDuration, 105 * 60)
        XCTAssertEqual(month.recordedDays, 2)
    }
    func testADayWithNoSessionIsEmpty() {
        let month = SessionMonth(records: [record("2026-11-24 09:00")], month: november, calendar: seoul)
        XCTAssertEqual(month.day(at("2026-11-08 12:00"), calendar: seoul), SessionMonth.Day())
        XCTAssertEqual(SessionMonth(records: [], month: november, calendar: seoul).recordedDays, 0)
        XCTAssertEqual(SessionMonth(records: [], month: november, calendar: seoul).focusDuration, 0)
    }
    /// A session that ends after midnight belongs to the day of its start, with its whole focus time.
    func testASessionCrossingMidnightBelongsToItsStartDay() {
        let month = SessionMonth(records: [record("2026-11-24 23:40")], month: november, calendar: seoul)
        XCTAssertEqual(month.day(at("2026-11-24 12:00"), calendar: seoul), SessionMonth.Day(focusDuration: 50 * 60, completedCount: 1))
        XCTAssertEqual(month.day(at("2026-11-25 12:00"), calendar: seoul), SessionMonth.Day())
        XCTAssertEqual(month.recordedDays, 1)
    }
    /// Every end reason except `expired` gives no time, no count and no recorded day.
    func testASessionThatDidNotCompleteNeverCounts() {
        let reasons: [EndReason] = [.earlyExit, .authorizationRevoked, .startFailed, .clockChanged, .recoveryInterrupted, .deadlineMissed]
        let month = SessionMonth(records: reasons.map { record("2026-11-10 10:00", $0) }, month: november, calendar: seoul)
        XCTAssertEqual(month.recordedDays, 0)
        XCTAssertEqual(month.focusDuration, 0)
        XCTAssertEqual(month.day(at("2026-11-10 10:00"), calendar: seoul), SessionMonth.Day())
    }
    /// A session that starts before the month, and one that starts on the first moment of the next month, are outside it.
    func testTheMonthBoundaryFollowsTheStartTime() {
        let records = [record("2026-10-31 23:40"), record("2026-11-01 00:00", minutes: 25), record("2026-11-30 23:59", minutes: 30), record("2026-12-01 00:00")]
        let month = SessionMonth(records: records, month: november, calendar: seoul)
        XCTAssertEqual(month.recordedDays, 2)
        XCTAssertEqual(month.focusDuration, 55 * 60)
        XCTAssertEqual(month.day(at("2026-11-01 00:00"), calendar: seoul).completedCount, 1)
        XCTAssertEqual(month.day(at("2026-11-30 00:00"), calendar: seoul).completedCount, 1)
    }
    func testTexts() {
        XCTAssertEqual(SessionMonth.cellText(90 * 60), "1:30")
        XCTAssertEqual(SessionMonth.cellText(50 * 60), "0:50")
        XCTAssertEqual(SessionMonth.cellText(125 * 60 + 59), "2:05")
        XCTAssertEqual(SessionMonth.totalText(150 * 60), "2시간 30분")
        XCTAssertEqual(SessionMonth.totalText(35 * 3600), "35시간 0분")
        XCTAssertEqual(SessionMonth.totalText(25 * 60), "25분")
        XCTAssertEqual(SessionMonth.totalText(0), "0분")
    }
    /// The month read returns every record that starts inside the interval, also the ones that did not complete, newest first.
    func testMonthReadReturnsTheMonthNewestFirst() throws {
        let container = try ModelContainer(for: SessionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let history = SessionHistory(context: ModelContext(container), acknowledge: { _ in })
        let starts: [(String, EndReason)] = [("2026-10-31 23:40", .expired), ("2026-11-01 00:00", .earlyExit), ("2026-11-24 09:00", .expired), ("2026-11-30 23:59", .expired), ("2026-12-01 00:00", .expired)]
        for (start, reason) in starts {
            var session = ControlSession(startedAt: at(start), length: 1500)
            session.phase = .terminal; session.reason = reason; session.observedAt = session.expiresAt
            try history.importTerminal(session)
        }
        let read = try history.records(in: november)
        XCTAssertEqual(read.map(\.startedAt), [at("2026-11-30 23:59"), at("2026-11-24 09:00"), at("2026-11-01 00:00")])
        XCTAssertEqual(SessionMonth(records: read, month: november, calendar: seoul).recordedDays, 2)
    }
}
