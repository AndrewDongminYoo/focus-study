import XCTest
@testable import FocusCore

final class TodaySnapshotTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        return value
    }
    private func date(_ text: String, _ calendar: Calendar) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }
    private func read(_ snapshot: TodaySnapshot) throws -> TodaySnapshotRead { .data(try snapshot.encoded()) }
    private func json(_ text: String) -> TodaySnapshotRead { .data(Data(text.utf8)) }

    func testEncodingRoundTripsTheExactDayStart() throws {
        let cal = calendar("Asia/Seoul")
        let snapshot = TodaySnapshot(dayStart: cal.startOfDay(for: Date(timeIntervalSinceReferenceDate: 784_123_456.789)), completedCount: 2, focusSeconds: 3000.5)
        XCTAssertEqual(TodaySnapshot.decode(try snapshot.encoded()), snapshot)
        XCTAssertEqual(snapshot.schemaVersion, 1)
    }
    func testStateForEachStoredState() throws {
        let cal = calendar("Asia/Seoul"), now = date("2026-11-14 15:00", cal), today = cal.startOfDay(for: now)
        XCTAssertEqual(TodaySnapshot.state(.missing, at: now, calendar: cal), .empty)
        XCTAssertEqual(TodaySnapshot.state(try read(TodaySnapshot(dayStart: today, completedCount: 3, focusSeconds: 4500)), at: now, calendar: cal),
                       .numbers(count: 3, focusSeconds: 4500))
        XCTAssertEqual(TodaySnapshot.state(try read(TodaySnapshot(dayStart: today, completedCount: 0, focusSeconds: 0)), at: now, calendar: cal), .empty)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!, tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        XCTAssertEqual(TodaySnapshot.state(try read(TodaySnapshot(dayStart: yesterday, completedCount: 3, focusSeconds: 4500)), at: now, calendar: cal), .empty, "an earlier day")
        XCTAssertEqual(TodaySnapshot.state(try read(TodaySnapshot(dayStart: tomorrow, completedCount: 3, focusSeconds: 4500)), at: now, calendar: cal), .empty, "a dayStart in the future")
        XCTAssertEqual(TodaySnapshot.state(.unreadable, at: now, calendar: cal), .check)
        XCTAssertEqual(TodaySnapshot.state(json("not json"), at: now, calendar: cal), .check, "undecodable")
        XCTAssertEqual(TodaySnapshot.state(json("{\"schemaVersion\":1}"), at: now, calendar: cal), .check, "missing fields")
        var other = TodaySnapshot(dayStart: today, completedCount: 3, focusSeconds: 4500); other.schemaVersion = 2
        XCTAssertEqual(TodaySnapshot.state(try read(other), at: now, calendar: cal), .check, "another schema version")
    }
    func testEveryInvalidValueGivesCheck() throws {
        let cal = calendar("Asia/Seoul"), now = date("2026-11-14 15:00", cal), today = cal.startOfDay(for: now)
        let invalid: [(Int, Double, String)] = [
            (-1, 0, "negative count"), (1, -1500, "negative seconds"), (0, 1500, "seconds without a count"), (2, 0, "a count without seconds"),
            (1, TodaySnapshot.maxFocusSeconds + 1, "above the bound"),
        ]
        for (count, seconds, name) in invalid {
            let snapshot = TodaySnapshot(dayStart: today, completedCount: count, focusSeconds: seconds)
            XCTAssertFalse(snapshot.isValid, name)
            XCTAssertEqual(TodaySnapshot.state(try read(snapshot), at: now, calendar: cal), .check, name)
        }
        // JSON has no literal for infinity or NaN, so a non-finite value can only be checked on the type.
        XCTAssertFalse(TodaySnapshot(dayStart: today, completedCount: 1, focusSeconds: .infinity).isValid)
        XCTAssertFalse(TodaySnapshot(dayStart: today, completedCount: 1, focusSeconds: .nan).isValid)
        XCTAssertTrue(TodaySnapshot(dayStart: today, completedCount: 1, focusSeconds: TodaySnapshot.maxFocusSeconds).isValid)
    }
    func testReadMapsAMissingFileToMissingAndOtherErrorsToUnreadable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TodaySnapshotTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("today.json")
        XCTAssertEqual(TodaySnapshotRead.read { try Data(contentsOf: url) }, .missing)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertEqual(TodaySnapshotRead.read { try Data(contentsOf: url) }, .unreadable, "a directory at the path")
        XCTAssertEqual(TodaySnapshotRead.read { throw CocoaError(.fileReadNoPermission) }, .unreadable)
        XCTAssertEqual(TodaySnapshotRead.read { Data("x".utf8) }, .data(Data("x".utf8)))
    }
    func testDayCheckAcrossADaylightSavingChange() throws {
        // New York leaves daylight saving time on 2026-11-01: that day has 25 hours.
        let cal = calendar("America/New_York"), late = date("2026-11-01 23:30", cal), dayStart = cal.startOfDay(for: late)
        let snapshot = try read(TodaySnapshot(dayStart: dayStart, completedCount: 1, focusSeconds: 1500))
        XCTAssertEqual(TodaySnapshot.state(snapshot, at: late, calendar: cal), .numbers(count: 1, focusSeconds: 1500))
        XCTAssertEqual(late.timeIntervalSince(dayStart), 24.5 * 3600, "24 hours and a half after the start of a 25-hour day is still that day")
        let entries = TodaySnapshot.entries(snapshot, now: late, calendar: cal)
        XCTAssertEqual(entries.map(\.date), [late, dayStart.addingTimeInterval(25 * 3600)])
        XCTAssertEqual(entries.map(\.state), [.numbers(count: 1, focusSeconds: 1500), .empty])
    }
    func testDayCheckAfterATimeZoneChange() throws {
        let written = calendar("Asia/Seoul"), now = date("2026-11-14 15:00", written)
        let snapshot = try read(TodaySnapshot(dayStart: written.startOfDay(for: now), completedCount: 2, focusSeconds: 3000))
        XCTAssertEqual(TodaySnapshot.state(snapshot, at: now, calendar: written), .numbers(count: 2, focusSeconds: 3000))
        // The same instant is 2026-11-14 01:00 in New York, the same calendar day, but its start of day is another instant.
        XCTAssertEqual(TodaySnapshot.state(snapshot, at: now, calendar: calendar("America/New_York")), .empty)
    }
    func testEntriesAreNumbersThenEmptyAtTheNextStartOfDay() throws {
        let cal = calendar("Asia/Seoul"), now = date("2026-11-14 15:00", cal), today = cal.startOfDay(for: now)
        let entries = TodaySnapshot.entries(try read(TodaySnapshot(dayStart: today, completedCount: 3, focusSeconds: 4500)), now: now, calendar: cal)
        XCTAssertEqual(entries.map(\.date), [now, date("2026-11-15 00:00", cal)])
        XCTAssertEqual(entries.map(\.state), [.numbers(count: 3, focusSeconds: 4500), .empty])
    }
    func testEveryOtherStateGivesOneEntry() throws {
        let cal = calendar("Asia/Seoul"), now = date("2026-11-14 15:00", cal), today = cal.startOfDay(for: now)
        let reads: [(TodaySnapshotRead, TodayWidgetState)] = [
            (.missing, .empty), (try read(TodaySnapshot(dayStart: today, completedCount: 0, focusSeconds: 0)), .empty),
            (try read(TodaySnapshot(dayStart: cal.date(byAdding: .day, value: -1, to: today)!, completedCount: 1, focusSeconds: 1500)), .empty),
            (.unreadable, .check), (json("{}"), .check),
        ]
        for (value, state) in reads {
            let entries = TodaySnapshot.entries(value, now: now, calendar: cal)
            XCTAssertEqual(entries.map(\.date), [now]); XCTAssertEqual(entries.map(\.state), [state])
        }
    }
    func testDurationTextUsesTheTodaySummaryFormat() {
        XCTAssertEqual(TodaySnapshot.durationText(4500), Duration.seconds(4500).formatted(.units(allowed: [.hours, .minutes], width: .wide)))
    }
}
