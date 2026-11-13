import XCTest
import FamilyControls
import ManagedSettings

final class EverydayLayerFileTests: XCTestCase {
    /// Synthetic Codable tokens are only used for persistence tests, never Screen Time calls.
    private func token<T: Decodable>(_ byte: UInt8) throws -> T { try JSONDecoder().decode(T.self, from: JSONEncoder().encode(["data": Data([byte])])) }
    private func selection(apps: [UInt8], sites: [UInt8]) throws -> FamilyActivitySelection {
        var selection = FamilyActivitySelection()
        selection.applicationTokens = Set(try apps.map { try token($0) as ApplicationToken })
        selection.webDomainTokens = Set(try sites.map { try token($0) as WebDomainToken })
        return selection
    }
    private let schedule = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 480, rangeEnd: 1080, windows: [EverydayWindow(kind: .lunch, start: 720, end: 780)])
    func testEverydayLayerFileLifecycle() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = EverydayLayerFile(directory: directory, shield: ScreenTimeEverydayShield())
        XCTAssertNil(try file.load()); XCTAssertNil(try file.selection())
        XCTAssertTrue(try file.contains(FamilyActivitySelection()), "no stored layer limits nothing")
        let stored = try selection(apps: [1, 2], sites: [3])
        try file.write(schedule, selection: stored)
        XCTAssertEqual(try file.load(), schedule)
        XCTAssertEqual(try file.selection()?.applicationTokens, stored.applicationTokens)
        XCTAssertTrue(try file.contains(try selection(apps: [1, 2, 4], sites: [3, 5])))
        XCTAssertFalse(try file.contains(try selection(apps: [1], sites: [3])))
        XCTAssertFalse(try file.contains(try selection(apps: [1, 2], sites: [])))
        // The file holds the schedule and application and web domain tokens only.
        let url = directory.appendingPathComponent("everyday-layer.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "revision", "enabled", "rangeStart", "rangeEnd", "windows", "applications", "webDomains"])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        object["schemaVersion"] = 2
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        XCTAssertThrowsError(try file.load())
        object["schemaVersion"] = 1; object["rangeEnd"] = 500
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        XCTAssertThrowsError(try file.load(), "a schedule that is not valid is a read failure")
        XCTAssertFalse(file.storeMatches()); XCTAssertFalse(file.applyStored())
        try Data("{".utf8).write(to: url)
        XCTAssertThrowsError(try file.load())
    }
    func testOffDayIsOptionalAndTheOffDayWriteKeepsTheTokens() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = EverydayLayerFile(directory: directory, shield: ScreenTimeEverydayShield())
        let url = directory.appendingPathComponent("everyday-layer.json")
        let stored = try selection(apps: [1, 2], sites: [3])
        try file.write(schedule, selection: stored)
        XCTAssertNil(try file.load()?.offDay, "a file without the key has no off day")
        var off = schedule; off.offDay = "2026-11-02"
        try file.writeOffDay(off)
        XCTAssertEqual(try file.load(), off)
        XCTAssertEqual(try file.selection()?.applicationTokens, stored.applicationTokens); XCTAssertEqual(try file.selection()?.webDomainTokens, stored.webDomainTokens)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(object["offDay"] as? String, "2026-11-02"); XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        var other = off; other.revision = UUID()
        XCTAssertThrowsError(try file.writeOffDay(other), "the off-day write keeps the stored revision")
        XCTAssertEqual(try file.load(), off)
        // A malformed value is not a read failure: the rule matches no day with it.
        var malformed = object; malformed["offDay"] = "not a day"
        try JSONSerialization.data(withJSONObject: malformed).write(to: url)
        XCTAssertEqual(try file.load()?.offDay, "not a day")
        // A file that an earlier build wrote has no `offDay` key.
        var earlier = object; earlier["offDay"] = nil
        try JSONSerialization.data(withJSONObject: earlier).write(to: url)
        XCTAssertEqual(try file.load(), schedule)
        // A save writes the schedule's `offDay`, and none when it is `nil`.
        try file.write(schedule, selection: stored)
        XCTAssertNil((try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]))["offDay"])
    }
    func testWeekdaysAreOptionalToleratedOnLoadAndKeptByTheOffDayWrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = EverydayLayerFile(directory: directory, shield: ScreenTimeEverydayShield())
        let url = directory.appendingPathComponent("everyday-layer.json")
        func object() throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]) }
        let stored = try selection(apps: [1], sites: [])
        // A save of all seven days writes no key; a file without the key is every day, as an earlier build wrote it.
        var every = schedule; every.weekdays = [1, 2, 3, 4, 5, 6, 7]
        try file.write(every, selection: stored)
        XCTAssertNil(try object()["weekdays"]); XCTAssertEqual(try object()["schemaVersion"] as? Int, 1)
        XCTAssertNil(try file.load()?.weekdays); XCTAssertEqual(try file.load(), schedule)
        // A chosen set is stored sorted and loads back.
        var weekdays = schedule; weekdays.weekdays = [2, 3, 4, 5, 6]
        try file.write(weekdays, selection: stored)
        XCTAssertEqual(try object()["weekdays"] as? [Int], [2, 3, 4, 5, 6])
        XCTAssertEqual(try file.load(), weekdays)
        // The off-for-today write keeps the weekdays.
        var off = weekdays; off.offDay = "2026-11-02"
        try file.writeOffDay(off)
        XCTAssertEqual(try file.load(), off); XCTAssertEqual(try object()["weekdays"] as? [Int], [2, 3, 4, 5, 6])
        // A malformed list is never a read failure: numbers outside 1 to 7 and repeats are dropped, and nothing left is every day.
        let cases: [([Int], [Int]?)] = [([2, 2, 9, 0, 6], [2, 6]), ([0, 8], nil), ([], nil), ([7, 6, 5, 4, 3, 2, 1], nil), ([5], [5])]
        for (raw, expected) in cases {
            var malformed = try object(); malformed["weekdays"] = raw
            try JSONSerialization.data(withJSONObject: malformed).write(to: url)
            XCTAssertEqual(try file.load()?.weekdays, expected, "\(raw)")
        }
        // Another JSON type fails the decode, as any corrupt file does.
        var wrongType = try object(); wrongType["weekdays"] = "weekdays"
        try JSONSerialization.data(withJSONObject: wrongType).write(to: url)
        XCTAssertThrowsError(try file.load())
    }
}
