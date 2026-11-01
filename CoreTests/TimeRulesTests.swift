import XCTest
@testable import FocusCore
final class TimeRulesTests: XCTestCase {
    private func session(start: Date, end: Date) -> ControlSession { ControlSession(startedAt: start, length: end.timeIntervalSince(start)) }
    func testCountdownClampsAndRecomputesAfterRestart() {
        let s = session(start: Date(timeIntervalSince1970: 500), end: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(TimeRules.remaining(session: s, now: Date(timeIntervalSince1970: 500)), 1500)
        XCTAssertEqual(TimeRules.remaining(session: s, now: Date(timeIntervalSince1970: 1500)), 500)
        XCTAssertEqual(TimeRules.remaining(session: s, now: Date(timeIntervalSince1970: 2500)), 0)
        XCTAssertEqual(TimeRules.remaining(session: s, now: Date(timeIntervalSince1970: 0)), 1500)
    }
    func testRemainingIsCappedBySessionLength() {
        let start = Date(timeIntervalSince1970: 0), s = session(start: start, end: start.addingTimeInterval(3000))
        XCTAssertEqual(TimeRules.remaining(session: s, now: start.addingTimeInterval(-60)), 3000)
        XCTAssertEqual(TimeRules.remaining(session: s, now: start.addingTimeInterval(2999.2)), 1)
    }
    func testRemainingStopsWhilePausedAndContinuesAfterResume() {
        let start = Date(timeIntervalSince1970: 0)
        var paused = ControlSession(startedAt: start); paused.phase = .waiting; paused.pausedAt = start.addingTimeInterval(600)
        XCTAssertEqual(TimeRules.remaining(session: paused, now: start.addingTimeInterval(600)), 900)
        XCTAssertEqual(TimeRules.remaining(session: paused, now: start.addingTimeInterval(900)), 900)
        var resumed = ControlSession(startedAt: start); resumed.phase = .active; resumed.pausedSeconds = 300
        XCTAssertEqual(TimeRules.remaining(session: resumed, now: start.addingTimeInterval(900)), 1500 - 600)
    }
    func testTodayRespects23HourDSTDay() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let date = ISO8601DateFormatter().date(from: "2026-03-08T16:00:00Z")!
        let interval = TimeRules.today(now: date, calendar: calendar)
        XCTAssertEqual(interval.duration, 23 * 3600)
        XCTAssertEqual(interval.start, ISO8601DateFormatter().date(from: "2026-03-08T05:00:00Z"))
    }
    func testTimezoneChangesTodayWithoutChangingExpiry() {
        let date = ISO8601DateFormatter().date(from: "2026-10-26T01:00:00Z")!
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var west = utc; west.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertNotEqual(TimeRules.today(now: date, calendar: utc).start, TimeRules.today(now: date, calendar: west).start)
    }
}
