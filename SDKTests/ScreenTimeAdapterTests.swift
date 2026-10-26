import XCTest
import FamilyControls
import DeviceActivity
import ManagedSettings
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
    func testNewSelectionIncludesEntireCategoryForPicker() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(try SelectionRepository(directory: dir).selection.includeEntireCategory)
    }
    func testExpandedCategorySavesIndividualTokensAndReloadsWithoutCategoryPolicy() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repository = try SelectionRepository(directory: dir)
        let expanded = try syntheticSelection(apps: 2, websites: 1, includeEntireCategory: true)
        XCTAssertEqual(expanded.categoryTokens.count, 1)
        XCTAssertEqual(expanded.applicationTokens.count, 2)
        try repository.save(expanded)
        let stored = try JSONDecoder().decode(FamilyActivitySelection.self, from: Data(contentsOf: dir.appendingPathComponent("selection.json")))
        XCTAssertEqual(stored.applicationTokens, expanded.applicationTokens)
        XCTAssertEqual(stored.webDomainTokens, expanded.webDomainTokens)
        XCTAssertTrue(stored.categoryTokens.isEmpty)
        let reopened = try SelectionRepository(directory: dir)
        XCTAssertTrue(reopened.selection.includeEntireCategory)
        XCTAssertEqual(reopened.selection.applicationTokens, expanded.applicationTokens)
        XCTAssertEqual(reopened.selection.webDomainTokens, expanded.webDomainTokens)
        XCTAssertEqual(reopened.counts.categories, 0)
    }
    func testExpandedCategoryHonorsFiftyLimitAndRejectedSavePreservesSelection() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repository = try SelectionRepository(directory: dir)
        let accepted = try syntheticSelection(apps: 50, websites: 50, includeEntireCategory: true)
        try repository.save(accepted)
        let file = dir.appendingPathComponent("selection.json"), previous = try Data(contentsOf: dir.appendingPathComponent("selection.json"))
        for (apps, websites, expected) in [(51, 1, SelectionIssue.tooManyApps), (1, 51, .tooManyWebsites)] {
            let rejected = try syntheticSelection(apps: apps, websites: websites, includeEntireCategory: true)
            XCTAssertThrowsError(try repository.save(rejected)) { XCTAssertEqual($0 as? SelectionIssue, expected) }
            XCTAssertEqual(try Data(contentsOf: file), previous)
            XCTAssertEqual(repository.selection.applicationTokens, accepted.applicationTokens)
            XCTAssertEqual(repository.selection.webDomainTokens, accepted.webDomainTokens)
        }
    }
    func testCollapsedCategoryIsNotSilentlyDropped() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repository = try SelectionRepository(directory: dir)
        let collapsed = try syntheticSelection(apps: 1, websites: 0, includeEntireCategory: false)
        XCTAssertThrowsError(try repository.save(collapsed)) { XCTAssertEqual($0 as? SelectionIssue, .categoriesUnsupported) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("selection.json").path))
    }
    func testLegacyIndividualSelectionReopensWithExpandedPickerMode() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var legacy = try syntheticSelection(apps: 1, websites: 1, includeEntireCategory: false)
        legacy.categoryTokens = []
        try JSONEncoder().encode(legacy).write(to: dir.appendingPathComponent("selection.json"))
        let reopened = try SelectionRepository(directory: dir)
        XCTAssertTrue(reopened.selection.includeEntireCategory)
        XCTAssertEqual(reopened.selection.applicationTokens, legacy.applicationTokens)
        XCTAssertEqual(reopened.selection.webDomainTokens, legacy.webDomainTokens)
    }
    private func syntheticSelection(apps: Int, websites: Int, includeEntireCategory: Bool) throws -> FamilyActivitySelection {
        // Synthetic Codable tokens are only used for persistence tests, never Screen Time calls.
        func token<T>(_ type: Token<T>.Type, _ id: Int) throws -> Token<T> {
            try JSONDecoder().decode(type, from: JSONEncoder().encode(["data": Data([UInt8(id)])]))
        }
        var selection = FamilyActivitySelection(includeEntireCategory: includeEntireCategory)
        selection.applicationTokens = Set(try (0..<apps).map { try token(ApplicationToken.self, $0) })
        selection.webDomainTokens = Set(try (0..<websites).map { try token(WebDomainToken.self, $0) })
        selection.categoryTokens = [try token(ActivityCategoryToken.self, 0)]
        return selection
    }
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
