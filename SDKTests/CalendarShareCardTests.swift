import UIKit
import XCTest

/// The rendering of the 순공 calendar share image (docs/specs/2026-11-26-share-image-design.md, "Rendering").
@MainActor final class CalendarShareCardTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.firstWeekday = 1
        return calendar
    }
    private func render(month: Int, days: [Int], minutes: Int = 600) throws -> UIImage {
        let start = calendar.date(from: DateComponents(year: 2026, month: month, day: 1))!
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24))!
        let recorded = Set(days.map { calendar.date(from: DateComponents(year: 2026, month: month, day: $0))! })
        return try XCTUnwrap(CalendarShareCard.render(month: SessionMonth.interval(containing: start, calendar: calendar), today: today,
                                                      recordedDays: recorded, focusDuration: TimeInterval(minutes * 60), calendar: calendar))
    }

    func testImageIsFixedWidthAtScaleThree() throws {
        let image = try render(month: 11, days: [1, 2, 24])
        XCTAssertEqual(image.size.width, 402)
        XCTAssertEqual(image.scale, 3)
        XCTAssertEqual(image.cgImage?.width, 1206)
    }
    func testSameMonthGivesTheSameImage() throws {
        let first = try XCTUnwrap(render(month: 11, days: [1, 5, 9, 24]).pngData())
        let second = try XCTUnwrap(render(month: 11, days: [1, 5, 9, 24]).pngData())
        XCTAssertEqual(first, second, "the stamp variation is a function of the date only")
    }
    func testFocusTimeDoesNotChangeTheStamps() throws {
        // The summary line changes with the time, so compare only the image above it: a stamp looks the same for 25 minutes and for 2.5 hours.
        let short = try render(month: 11, days: [1, 5], minutes: 25), long = try render(month: 11, days: [1, 5], minutes: 150)
        XCTAssertEqual(short.size, long.size)
        let crop = CGRect(x: 0, y: 0, width: 1206, height: Int(short.size.height * 3) - 150)
        let shortTop = try XCTUnwrap(short.cgImage?.cropping(to: crop)).png, longTop = try XCTUnwrap(long.cgImage?.cropping(to: crop)).png
        XCTAssertEqual(shortTop, longTop)
        // The same crop does see the stamps, whose ink is a literal color; the asset colors of the text do not resolve in this test bundle.
        let otherDay = try XCTUnwrap(render(month: 11, days: [1, 6], minutes: 25).cgImage?.cropping(to: crop)).png
        XCTAssertNotEqual(shortTop, otherDay, "a stamp on another day changes the crop")
    }
    func testImageHeightFollowsTheWeekRows() throws {
        // February 2026 needs four rows and August 2026 six, at 60 pt and a 1 pt line each.
        let four = try render(month: 2, days: [3]), six = try render(month: 8, days: [3])
        XCTAssertEqual(six.size.height - four.size.height, 122, accuracy: 0.5)
    }
}
private extension CGImage {
    /// A copy of only these pixels; a crop alone keeps the data provider of the whole image.
    var png: Data? { UIImage(cgImage: self).pngData() }
}
