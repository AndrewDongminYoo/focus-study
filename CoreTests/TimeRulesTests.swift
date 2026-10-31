import XCTest
@testable import FocusCore
final class TimeRulesTests: XCTestCase {
    func testCountdownClampsAndRecomputesAfterRestart() {
        let start = Date(timeIntervalSince1970: 500), end = Date(timeIntervalSince1970: 2000)
        XCTAssertEqual(TimeRules.remaining(startedAt: start, expiresAt: end, now: Date(timeIntervalSince1970: 500)), 1500)
        XCTAssertEqual(TimeRules.remaining(startedAt: start, expiresAt: end, now: Date(timeIntervalSince1970: 1500)), 500)
        XCTAssertEqual(TimeRules.remaining(startedAt: start, expiresAt: end, now: Date(timeIntervalSince1970: 2500)), 0)
        XCTAssertEqual(TimeRules.remaining(startedAt: start, expiresAt: end, now: Date(timeIntervalSince1970: 0)), 1500)
    }
    func testRemainingIsCappedBySessionLength() {
        let start = Date(timeIntervalSince1970: 0), end = start.addingTimeInterval(3000)
        XCTAssertEqual(TimeRules.remaining(startedAt: start, expiresAt: end, now: start.addingTimeInterval(-60)), 3000)
        XCTAssertEqual(TimeRules.remaining(startedAt: start, expiresAt: end, now: start.addingTimeInterval(2999.2)), 1)
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
