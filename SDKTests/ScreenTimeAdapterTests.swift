import XCTest
import FamilyControls
import DeviceActivity
import ManagedSettings
final class ScreenTimeAdapterTests: XCTestCase {
    func testStatusMapsToApprovedDeniedOrUnknown() {
        XCTAssertEqual(ScreenTimeAccess.state(.approved), .approved)
        XCTAssertEqual(ScreenTimeAccess.state(.denied), .denied)
        XCTAssertEqual(ScreenTimeAccess.state(.notDetermined), .unknown, "not determined is not a revocation")
        if #available(iOS 26.4, *) { XCTAssertEqual(ScreenTimeAccess.state(.approvedWithDataAccess), .approved) }
    }
    func testReaderReadsOnTheMainQueueFromAnyThread() {
        XCTAssertEqual(ScreenTimeAccess.current(read: { XCTAssertTrue(Thread.isMainThread); return .denied }), .denied)
        let done = expectation(description: "background read")
        DispatchQueue.global().async {
            let state = ScreenTimeAccess.current(read: { XCTAssertTrue(Thread.isMainThread); return .notDetermined })
            XCTAssertEqual(state, .unknown); done.fulfill()
        }
        wait(for: [done], timeout: 5)
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
    func testBreakScheduleIsFifteenMinutesWithTwelveMinuteWarning() {
        let calendar = Calendar(identifier: .gregorian), start = Date(timeIntervalSince1970: 1_800_000_000)
        let schedule = ScreenTimeMonitoring.breakSchedule(start: start, end: start.addingTimeInterval(BreakTiming.breakActivityLength), warning: BreakTiming.standard.breakWarning, calendar: calendar)
        XCTAssertFalse(schedule.repeats)
        XCTAssertEqual(calendar.date(from: schedule.intervalEnd)?.timeIntervalSince(calendar.date(from: schedule.intervalStart)!), 900)
        XCTAssertEqual(schedule.warningTime?.minute, 12); XCTAssertEqual(schedule.warningTime?.second, 0)
        let short = ScreenTimeMonitoring.breakSchedule(start: start, end: start.addingTimeInterval(900), warning: 897, calendar: calendar)
        XCTAssertEqual(short.warningTime?.minute, 14); XCTAssertEqual(short.warningTime?.second, 57)
    }
    func testSessionIDParsesFocusAndBreakNamesAndBreakIndexRejectsOthers() {
        let id = UUID()
        let focus = DeviceActivityName("focus.\(id.uuidString)"), breakTwo = DeviceActivityName("focus.\(id.uuidString).break.2")
        XCTAssertEqual(ScreenTimeMonitoring.sessionID(focus), id); XCTAssertEqual(ScreenTimeMonitoring.sessionID(breakTwo), id)
        XCTAssertNil(ScreenTimeMonitoring.breakIndex(focus)); XCTAssertEqual(ScreenTimeMonitoring.breakIndex(breakTwo), 2)
        for other in ["focus.bad", "other.\(id.uuidString)", "focus.\(id.uuidString)x", "focus.\(id.uuidString).break.x"] {
            XCTAssertNil(ScreenTimeMonitoring.breakIndex(DeviceActivityName(other)), other)
        }
        XCTAssertNil(ScreenTimeMonitoring.sessionID(DeviceActivityName("focus.bad")))
        XCTAssertNil(ScreenTimeMonitoring.sessionID(DeviceActivityName("other.\(id.uuidString)")))
        XCTAssertNil(ScreenTimeMonitoring.sessionID(DeviceActivityName("focus.\(id.uuidString)x")))
    }
    func testEverydayScheduleRepeatsWithTimeComponentsOnly() {
        let schedule = ScreenTimeMonitoring.everydaySchedule(start: 8 * 60, end: 12 * 60 + 35)
        XCTAssertTrue(schedule.repeats); XCTAssertNil(schedule.warningTime)
        for components in [schedule.intervalStart, schedule.intervalEnd] {
            XCTAssertNil(components.era); XCTAssertNil(components.year); XCTAssertNil(components.month); XCTAssertNil(components.day)
            // The weekdays of the everyday layer live in the blocking rule, not in the registered schedules.
            XCTAssertNil(components.weekday)
            XCTAssertNil(components.calendar); XCTAssertNil(components.timeZone); XCTAssertEqual(components.second, 0)
        }
        XCTAssertEqual(schedule.intervalStart.hour, 8); XCTAssertEqual(schedule.intervalStart.minute, 0)
        XCTAssertEqual(schedule.intervalEnd.hour, 12); XCTAssertEqual(schedule.intervalEnd.minute, 35)
    }
    func testEverydayNameParsesRangeAndWindowsAndRejectsOthers() {
        let revision = UUID()
        let range = ScreenTimeMonitoring.everydayName(DeviceActivityName("everyday.\(revision.uuidString).range"))
        XCTAssertEqual(range?.revision, revision); XCTAssertEqual(range?.part, .range)
        let window = ScreenTimeMonitoring.everydayName(DeviceActivityName("everyday.\(revision.uuidString).window.2"))
        XCTAssertEqual(window?.revision, revision); XCTAssertEqual(window?.part, .window(2))
        for other in ["everyday.\(revision.uuidString).window.4", "everyday.\(revision.uuidString).window.0", "everyday.\(revision.uuidString).window.02",
                      "everyday.bad.range", "everyday.\(revision.uuidString).ranged", "focus.\(revision.uuidString)"] {
            XCTAssertNil(ScreenTimeMonitoring.everydayName(DeviceActivityName(other)), other)
        }
        for part in [EverydayPart.range, .window(1), .window(3)] {
            let name = ScreenTimeMonitoring.everydayActivityName(revision: revision, part: part)
            XCTAssertEqual(ScreenTimeMonitoring.everydayName(name)?.part, part)
        }
    }
    func testSessionIDIgnoresEverydayNames() {
        let revision = UUID()
        for name in ["everyday.\(revision.uuidString).range", "everyday.\(revision.uuidString).window.1"] {
            XCTAssertNil(ScreenTimeMonitoring.sessionID(DeviceActivityName(name)), name)
            XCTAssertNil(ScreenTimeMonitoring.breakIndex(DeviceActivityName(name)), name)
        }
    }
    func testFocusScheduleFromStartedAtIsAtLeastTheFocusLength() {
        // A resume with less than 15 minutes of focus left registers from `startedAt`.
        let calendar = Calendar(identifier: .gregorian)
        var session = ControlSession(startedAt: Date(timeIntervalSince1970: 1_800_000_000)); session.phase = .active; session.pausedSeconds = 200; session.deadlineCredit = 195
        let schedule = ScreenTimeMonitoring.schedule(start: session.startedAt, end: min(session.focusEnd, session.deadline(timing: .standard)), calendar: calendar)
        let length = calendar.date(from: schedule.intervalEnd)!.timeIntervalSince(calendar.date(from: schedule.intervalStart)!)
        XCTAssertGreaterThanOrEqual(length, session.length); XCTAssertGreaterThanOrEqual(length, 900)
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
final class RegistrationMarkerAdapterTests: XCTestCase {
    func testRegistrationMarkerNamesAreTheNamesThatScreenTimeMonitoringRegisters() {
        let monitoring = ScreenTimeMonitoring(), id = UUID(), revision = UUID()
        XCTAssertEqual(MarkedMonitoring.focusActivityName(id: id), monitoring.name(id).rawValue)
        for index in 1...BreakTiming.maxBreaks {
            XCTAssertEqual(MarkedMonitoring.breakActivityName(id: id, index: index), monitoring.breakName(id, index).rawValue)
        }
        for part in [EverydayPart.range] + (1...EverydaySchedule.maxWindows).map(EverydayPart.window) {
            XCTAssertEqual(MarkedMonitoring.everydayActivityName(revision: revision, part: part), ScreenTimeMonitoring.everydayActivityName(revision: revision, part: part).rawValue)
        }
    }
    /// `center.activities` is empty on the simulator, so both sides get the same activity list.
    func testStopMarkerNamesAreTheNamesThatScreenTimeMonitoringStops() {
        let monitoring = ScreenTimeMonitoring(), id = UUID(), other = UUID()
        let lists: [(String, [DeviceActivityName])] = [
            ("without a registered break", [monitoring.name(id), monitoring.name(other), monitoring.breakName(other, 1)]),
            ("with a registered break", [monitoring.name(id), monitoring.breakName(id, 2), monitoring.name(other), monitoring.breakName(other, 1),
                                         ScreenTimeMonitoring.everydayActivityName(revision: UUID(), part: .range)])
        ]
        for (label, activities) in lists {
            let registeredBreaks = activities.compactMap { activity in
                ScreenTimeMonitoring.sessionID(activity).flatMap { session in ScreenTimeMonitoring.breakIndex(activity).map { (id: session, index: $0) } }
            }
            XCTAssertEqual(Set(MarkedMonitoring.stopActivityNames(id: id, registeredBreaks: registeredBreaks)), Set(monitoring.stopNames(id: id, activities: activities).map(\.rawValue)), label)
        }
    }
    /// The simulator reports no `.protectionKey` for any file, so the test records the write options instead of reading the file attributes.
    func testRegistrationMarkerFileHasTheProtectionOfTheControlState() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var recorded: [Data.WritingOptions] = []
        let marker = RegistrationMarkerFile(directory: dir, writeData: { _, _, options in recorded.append(options) })
        try marker.write(RegistrationMarker(activityName: "focus.\(UUID().uuidString)", uptime: ProcessInfo.processInfo.systemUptime, validUntil: Date()))
        XCTAssertEqual(recorded, [SharedControlStore.fileWritingOptions], "the options of every control.json write")
        XCTAssertEqual(SharedControlStore.fileWritingOptions, Data.WritingOptions([.atomic, .completeFileProtectionUntilFirstUserAuthentication]))
    }
}
