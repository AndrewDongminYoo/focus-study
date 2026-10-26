import XCTest
import FamilyControls
import DeviceActivity
final class ScreenTimeAdapterTests: XCTestCase {
    func testApprovedStatusIsAcceptedButDeniedAndUnknownAreNot() {
        XCTAssertTrue(ScreenTimeAccess.isApproved(.approved))
        XCTAssertFalse(ScreenTimeAccess.isApproved(.denied)); XCTAssertFalse(ScreenTimeAccess.isApproved(.notDetermined))
        if #available(iOS 26.4, *) { XCTAssertTrue(ScreenTimeAccess.isApproved(.approvedWithDataAccess)) }
    }
    func testScheduleNeverExpiresBeforeFractionalDeadline() {
        let end = Date(timeIntervalSince1970: 3000.75)
        let calendar = Calendar(identifier: .gregorian)
        let schedule = ScreenTimeMonitoring.schedule(start: end.addingTimeInterval(-1500), end: end, calendar: calendar)
        XCTAssertEqual(calendar.date(from: schedule.intervalEnd), Date(timeIntervalSince1970: 3001))
    }
    func testScheduleIsNonRepeatingAndCrossesMidnightWithAbsoluteDates() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let start = ISO8601DateFormatter().date(from: "2026-10-26T14:50:00Z")!
        let end = ISO8601DateFormatter().date(from: "2026-10-26T15:15:00Z")!
        let schedule = ScreenTimeMonitoring.schedule(start: start, end: end, calendar: calendar)
        XCTAssertFalse(schedule.repeats)
        XCTAssertEqual(calendar.date(from: schedule.intervalStart), start); XCTAssertEqual(calendar.date(from: schedule.intervalEnd), end)
        XCTAssertEqual(schedule.intervalEnd.day, 27)
    }
}
@MainActor final class SelectionRepositoryTests: XCTestCase {
    func testEmptySaveDoesNotReplaceExistingFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repository = try SelectionRepository(directory: dir)
        XCTAssertThrowsError(try repository.save(FamilyActivitySelection()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("selection.json").path))
    }
    func testCorruptSelectionIsNotSilentlyReset() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("selection.json"); try Data("corrupt".utf8).write(to: file)
        XCTAssertThrowsError(try SelectionRepository(directory: dir))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "corrupt")
    }
}
