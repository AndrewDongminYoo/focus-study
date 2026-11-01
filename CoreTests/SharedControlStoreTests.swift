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
        XCTAssertEqual(actual.session?.id, s.id); XCTAssertEqual(actual.schemaVersion, 2)
    }
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    /// The JSON that the M1 build writes: schema version 1, no break keys, dates as seconds since the reference date.
    private func writeM1Envelope(id: UUID = UUID(), version: Int = 1, extra: String = "", phase: String = "active") throws {
        let json = #"{"schemaVersion":\#(version),"session":{"id":"\#(id.uuidString)","startedAt":\#(start.timeIntervalSinceReferenceDate),"expiresAt":\#(start.timeIntervalSinceReferenceDate + 1500),"phase":"\#(phase)"\#(extra)}}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("control.json"))
    }
    private func rawVersion() throws -> Int? {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("control.json"))) as? [String: Any]
        return object?["schemaVersion"] as? Int
    }
    func testVersion1EnvelopeFromM1BuildLoadsWithoutBreaks() throws {
        try writeM1Envelope()
        let session = try XCTUnwrap(SharedControlStore(directory: directory).withExclusiveAccess { try $0.load() }.session)
        XCTAssertEqual(session.breaksTaken ?? 0, 0); XCTAssertFalse(session.isPaused)
        XCTAssertEqual(TimeRules.remaining(session: session, now: start.addingTimeInterval(60)), 1440)
        XCTAssertNil(session.timedEnd(at: start.addingTimeInterval(1499), timing: .standard))
        XCTAssertEqual(session.timedEnd(at: start.addingTimeInterval(1500), timing: .standard), .expired)
    }
    func testSaveWritesVersion2AndUnknownVersionIsRejected() throws {
        let store = SharedControlStore(directory: directory)
        var envelope = ControlEnvelope(); envelope.session = ControlSession(startedAt: start)
        try store.withExclusiveAccess { try $0.save(envelope) }
        XCTAssertEqual(try rawVersion(), 2)
        try writeM1Envelope(version: 3)
        XCTAssertThrowsError(try store.withExclusiveAccess { try $0.load() }) { XCTAssertEqual($0 as? ControlIssue, .unsupportedSchema) }
    }
    func testSavingALoadedVersion1EnvelopeWritesVersion2() throws {
        try writeM1Envelope()
        let store = SharedControlStore(directory: directory)
        try store.withExclusiveAccess { locked in try locked.save(try locked.load()) }
        XCTAssertEqual(try rawVersion(), 2)
    }
    func testStoreRejectsInvalidBreakShapes() throws {
        let p = #","pausedAt":\#(start.timeIntervalSinceReferenceDate + 100)"#
        let shapes: [(phase: String, extra: String)] = [
            ("onBreak", p + #","breaksTaken":1"#),
            ("waiting", p + #","waitEndsAt":\#(start.timeIntervalSinceReferenceDate + 115),"breaksTaken":3"#),
            ("active", p),
            ("active", #","breaksTaken":4"#),
            ("active", #","pausedSeconds":-1"#),
        ]
        let store = SharedControlStore(directory: directory)
        for version in [1, 2] {
            for shape in shapes {
                try writeM1Envelope(version: version, extra: shape.extra, phase: shape.phase)
                XCTAssertThrowsError(try store.withExclusiveAccess { try $0.load() }, "\(version) \(shape)") { XCTAssertEqual($0 as? ControlIssue, .invalidState) }
            }
        }
    }
    func testStoreAcceptsValidBreakShapes() throws {
        let p = #","pausedAt":\#(start.timeIntervalSinceReferenceDate + 100)"#
        let store = SharedControlStore(directory: directory)
        for (phase, extra) in [("waiting", p + #","waitEndsAt":\#(start.timeIntervalSinceReferenceDate + 115)"#), ("onBreak", p + #","breaksTaken":1,"breakEndsAt":1"#), ("breakOver", p + #","breaksTaken":3,"breakEndsAt":1"#)] {
            try writeM1Envelope(version: 2, extra: extra, phase: phase)
            XCTAssertEqual(try store.withExclusiveAccess { try $0.load() }.session?.phase.rawValue, phase)
        }
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
