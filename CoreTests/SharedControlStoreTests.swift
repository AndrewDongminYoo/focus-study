import XCTest
import Darwin
@testable import FocusCore
final class SharedControlStoreTests: XCTestCase {
    var directory: URL!
    override func setUpWithError() throws { directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func testRoundTripAndTerminalAcknowledgement() throws {
        let store = SharedControlStore(directory: directory)
        let s = ControlSession(startedAt: Date(timeIntervalSince1970: 100))
        try store.withExclusiveAccess { locked in var envelope = try locked.load(); envelope.session = s; try locked.save(envelope) }
        let actual = try store.withExclusiveAccess { try $0.load() }
        XCTAssertEqual(actual.session?.id, s.id); XCTAssertEqual(actual.schemaVersion, 1)
    }
    func testCorruptStateIsNotSilentlyReplaced() throws {
        let url = directory.appendingPathComponent("control.json")
        try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try SharedControlStore(directory: directory).withExclusiveAccess { try $0.load() })
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "broken")
    }
    func testLockTimeoutDoesNotEnterCriticalSection() throws {
        let fd = open(directory.appendingPathComponent("control.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(fd, 0); defer { flock(fd, LOCK_UN); close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        var entered = false
        XCTAssertThrowsError(try SharedControlStore(directory: directory, timeout: 0.02).withExclusiveAccess { _ in entered = true })
        XCTAssertFalse(entered)
    }
    func testUnknownSchemaIsRejected() throws {
        try Data(#"{"schemaVersion":99}"#.utf8).write(to: directory.appendingPathComponent("control.json"))
        XCTAssertThrowsError(try SharedControlStore(directory: directory).withExclusiveAccess { try $0.load() })
    }
}
