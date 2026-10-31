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
    func testStoreLoadsEveryAllowedLengthIncludingLegacy1500() throws {
        let store = SharedControlStore(directory: directory)
        for length in [1500.0, 3000.0] {
            let s = ControlSession(startedAt: Date(timeIntervalSince1970: 100), length: length)
            try store.withExclusiveAccess { locked in var envelope = try locked.load(); envelope.session = s; try locked.save(envelope) }
            XCTAssertEqual(try store.withExclusiveAccess { try $0.load() }.session?.length, length)
        }
    }
    func testStoreRejectsSessionWithDisallowedLength() throws {
        let store = SharedControlStore(directory: directory)
        var s = ControlSession(startedAt: Date(timeIntervalSince1970: 100)); s.expiresAt = s.startedAt.addingTimeInterval(1560)
        try store.withExclusiveAccess { locked in var envelope = try locked.load(); envelope.session = s; try locked.save(envelope) }
        XCTAssertThrowsError(try store.withExclusiveAccess { try $0.load() }) { XCTAssertEqual($0 as? ControlIssue, .invalidState) }
    }
    func testAtomicReplacementFailurePreservesFileAndAllowsRetry() throws {
        let store = SharedControlStore(directory: directory)
        let file = directory.appendingPathComponent("control.json")
        var original = ControlEnvelope()
        original.session = ControlSession(startedAt: Date(timeIntervalSince1970: 100))
        try store.withExclusiveAccess { try $0.save(original) }
        let originalBytes = try Data(contentsOf: file)
        var replacement = ControlEnvelope()
        replacement.session = ControlSession(startedAt: Date(timeIntervalSince1970: 200))
        // The immutable destination blocks the real atomic write without a fake writer.
        XCTAssertEqual(chflags((file.path as NSString).fileSystemRepresentation, UInt32(UF_IMMUTABLE)), 0)
        defer { _ = chflags((file.path as NSString).fileSystemRepresentation, 0) }
        XCTAssertThrowsError(try store.withExclusiveAccess { try $0.save(replacement) })
        XCTAssertEqual(try Data(contentsOf: file), originalBytes)
        let reopened = SharedControlStore(directory: directory, timeout: 0.02)
        XCTAssertEqual(try reopened.withExclusiveAccess { try $0.load() }.session?.id, original.session?.id)
        XCTAssertEqual(chflags((file.path as NSString).fileSystemRepresentation, 0), 0)
        try reopened.withExclusiveAccess { try $0.save(replacement) }
        XCTAssertEqual(try store.withExclusiveAccess { try $0.load() }.session?.id, replacement.session?.id)
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
