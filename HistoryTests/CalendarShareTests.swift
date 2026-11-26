import XCTest
@testable import FocusHistory

/// The rules of the 순공 calendar share image (docs/specs/2026-11-26-share-image-design.md).
final class CalendarShareTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.firstWeekday = 1
        return calendar
    }
    private func month(_ year: Int, _ month: Int) -> DateInterval {
        SessionMonth.interval(containing: calendar.date(from: DateComponents(year: year, month: month, day: 1))!, calendar: calendar)
    }

    func testWeeksHaveAsManyRowsAsTheMonthNeeds() {
        // February 2026 starts on a Sunday and has 28 days; August 2026 starts on a Saturday and has 31.
        XCTAssertEqual(CalendarShare.weeks(month(2026, 2), calendar: calendar).count, 4)
        XCTAssertEqual(CalendarShare.weeks(month(2026, 8), calendar: calendar).count, 6)
        let november = CalendarShare.weeks(month(2026, 11), calendar: calendar)
        XCTAssertEqual(november.count, 5)
        XCTAssertTrue(november.allSatisfy { $0.count == 7 })
        XCTAssertEqual(november.flatMap { $0 }.compactMap { $0 }.count, 30)
        XCTAssertEqual(november[0][0], calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
    }
    func testWeeksFollowTheFirstWeekday() {
        var monday = calendar; monday.firstWeekday = 2
        let november = CalendarShare.weeks(month(2026, 11), calendar: monday)
        XCTAssertNil(november[0][0], "Sunday the 1st is the last column when the week starts on Monday")
        XCTAssertEqual(november[0][6], monday.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        XCTAssertEqual(CalendarShare.weekdaySymbols(monday), ["월", "화", "수", "목", "금", "토", "일"])
        XCTAssertEqual(CalendarShare.weekdaySymbols(calendar), ["일", "월", "화", "수", "목", "금", "토"])
    }

    func testDayWords() {
        XCTAssertEqual(CalendarShare.dayWords(1), "하루 동안")
        XCTAssertEqual(CalendarShare.dayWords(2), "2일에 걸쳐")
        XCTAssertEqual(CalendarShare.dayWords(20), "20일에 걸쳐")
    }
    func testTimeWordsDropAZeroPart() {
        XCTAssertEqual(CalendarShare.timeWords(35 * 3600), "35시간")
        XCTAssertEqual(CalendarShare.timeWords(35 * 3600 + 20 * 60), "35시간 20분")
        XCTAssertEqual(CalendarShare.timeWords(40 * 60), "40분")
        XCTAssertEqual(CalendarShare.timeWords(3600 + 59), "1시간", "seconds under a minute are dropped, as in the calendar")
    }

    func testStampIsAFunctionOfTheDateOnly() {
        XCTAssertEqual(CalendarShare.stamp(year: 2026, month: 11, day: 24), CalendarShare.stamp(year: 2026, month: 11, day: 24))
        XCTAssertNotEqual(CalendarShare.stamp(year: 2026, month: 11, day: 24), CalendarShare.stamp(year: 2026, month: 11, day: 23))
        XCTAssertNotEqual(CalendarShare.stamp(year: 2026, month: 11, day: 24), CalendarShare.stamp(year: 2026, month: 10, day: 24))
    }
    func testStampStaysInsideItsBounds() {
        for month in 1...12 {
            for day in 1...31 {
                let stamp = CalendarShare.stamp(year: 2026, month: month, day: day)
                XCTAssertTrue((-8...8).contains(stamp.rotation))
                XCTAssertTrue((-1.5...1.5).contains(stamp.offsetX))
                XCTAssertTrue((-1...1).contains(stamp.offsetY))
                XCTAssertTrue((0.94...1.04).contains(stamp.scale))
                XCTAssertEqual(stamp.gaps.count, 3)
                XCTAssertEqual(stamp.grains.count, 23)
                XCTAssertTrue(stamp.gaps.allSatisfy { (0...(2 * .pi)).contains($0.angle) })
                XCTAssertTrue(stamp.grains.allSatisfy { (6...38).contains($0.x) && (6...38).contains($0.y) && (0.6...1.6).contains($0.width) && (0.4...1.0).contains($0.height) })
            }
        }
    }
    /// A fixed value of the generator, so a change of the function that would change every shared image fails here.
    func testStampGeneratorIsStable() {
        var random = CalendarShare.SplitMix64(seed: 0)
        XCTAssertEqual(random.next(), 0xE220_A839_7B1D_CDAF)
    }
}
