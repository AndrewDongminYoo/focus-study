import XCTest
import FamilyControls
import ManagedSettings

final class BreakSelectionFileTests: XCTestCase {
    /// Synthetic Codable tokens are only used for persistence tests, never Screen Time calls.
    private func selection() throws -> FamilyActivitySelection {
        var selection = FamilyActivitySelection()
        selection.applicationTokens = [try JSONDecoder().decode(ApplicationToken.self, from: JSONEncoder().encode(["data": Data([1])]))]
        selection.webDomainTokens = [try JSONDecoder().decode(WebDomainToken.self, from: JSONEncoder().encode(["data": Data([2])]))]
        return selection
    }
    func testBreakSelectionFileLifecycle() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = BreakSelectionFile(directory: directory, shield: ScreenTimeShield())
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertFalse(file.restoreShield(id: a)) // A missing copy never applies the shield.
        for id in [a, b, c] { try file.save(try selection(), id: id) }
        XCTAssertTrue(file.exists(id: a))
        let unrelated = directory.appendingPathComponent("control.json")
        try Data("{}".utf8).write(to: unrelated)
        // The copy holds application and web domain tokens only.
        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("break-selection.\(a.uuidString).json"))) as? [String: Any])
        XCTAssertEqual(Set(stored.keys), ["applications", "webDomains"])
        file.remove(id: a)
        XCTAssertFalse(file.exists(id: a)); XCTAssertTrue(file.exists(id: b)); XCTAssertTrue(file.exists(id: c))
        file.removeAll(except: b)
        XCTAssertTrue(file.exists(id: b)); XCTAssertFalse(file.exists(id: c))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        file.removeAll(except: nil)
        XCTAssertFalse(file.exists(id: b)); XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        XCTAssertFalse(file.restoreShield(id: b))
    }
}
