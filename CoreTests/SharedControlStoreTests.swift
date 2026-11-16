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
    // MARK: Open sessions (2026-11-16 Focus filter extension design, "Length validation")

    private func openSession(base: TimeInterval, length: TimeInterval) -> ControlSession {
        var s = ControlSession(startedAt: start, length: length)
        s.origin = .focusFilter; s.activation = UUID(); s.baseLength = base
        return s
    }
    private func saveAndReload(_ session: ControlSession, callAt: Date? = nil) throws -> ControlEnvelope {
        let store = SharedControlStore(directory: directory)
        var envelope = ControlEnvelope(); envelope.session = session; envelope.filterCallAt = callAt
        try store.withExclusiveAccess { try $0.save(envelope) }
        return try store.withExclusiveAccess { try $0.load() }
    }
    private func assertRejected(_ session: ControlSession, _ message: String) throws {
        let store = SharedControlStore(directory: directory)
        var envelope = ControlEnvelope(); envelope.session = session
        try store.withExclusiveAccess { try $0.save(envelope) }
        XCTAssertThrowsError(try store.withExclusiveAccess { try $0.load() }, message) { XCTAssertEqual($0 as? ControlIssue, .invalidState, message) }
    }
    func testVersion2FileWithoutOpenSessionFieldsDecodes() throws {
        try writeM1Envelope(version: 2, extra: #","origin":"focusFilter""#)
        let envelope = try SharedControlStore(directory: directory).withExclusiveAccess { try $0.load() }
        XCTAssertNil(envelope.session?.activation); XCTAssertNil(envelope.session?.baseLength); XCTAssertNil(envelope.filterCallAt)
    }
    func testOpenSessionFieldsRoundTrip() throws {
        let session = openSession(base: 2400, length: 2400), callAt = start.addingTimeInterval(5)
        let loaded = try saveAndReload(session, callAt: callAt)
        XCTAssertEqual(loaded.session?.activation, session.activation); XCTAssertEqual(loaded.session?.baseLength, 2400)
        XCTAssertEqual(loaded.filterCallAt, callAt)
    }
    func testRolledOverLengthIsAMultipleOfTheBase() throws {
        for multiple in [1.0, 2.0, 3.0] {
            XCTAssertEqual(try saveAndReload(openSession(base: 2400, length: 2400 * multiple)).session?.length, 2400 * multiple)
        }
        try assertRejected(openSession(base: 2400, length: 3000), "not a multiple")
        try assertRejected(openSession(base: 1560, length: 3120), "base not allowed")
        try assertRejected(openSession(base: 3000, length: 3000 * 202), "above one week")
    }
    func testExpiredOpenSessionStoresTheMeasuredTime() throws {
        for phase in [SessionPhase.ending, .terminal] {
            var s = openSession(base: 2400, length: 2850)
            s.phase = phase; s.reason = .expired; s.observedAt = start.addingTimeInterval(2900)
            XCTAssertEqual(try saveAndReload(s).session?.length, 2850, "\(phase)")
            var tooLong = s; tooLong.expiresAt = start.addingTimeInterval(ControlSession.maxLength + 1)
            try assertRejected(tooLong, "\(phase) above one week")
            var tooShort = s; tooShort.expiresAt = start.addingTimeInterval(2000)
            try assertRejected(tooShort, "\(phase) below the base")
            var earlyExit = s; earlyExit.reason = .earlyExit
            try assertRejected(earlyExit, "\(phase) early exit keeps a multiple")
        }
    }
    func testLengthRuleRejectsNonFiniteAndKeepsManualLengths() {
        var open = openSession(base: 2400, length: 2400); open.expiresAt = Date(timeIntervalSinceReferenceDate: .infinity)
        XCTAssertFalse(open.hasValidLength)
        XCTAssertFalse(ControlSession(startedAt: start, length: 5000).hasValidLength)
        XCTAssertTrue(ControlSession(startedAt: start, length: 3000).hasValidLength)
    }
    func testOneWeekBoundMatchesTheWidgetSnapshotBound() {
        XCTAssertEqual(ControlSession.maxLength, TodaySnapshot.maxFocusSeconds)
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
    func testM3EnvelopeLoadsAsManualWithoutMarker() throws {
        let id = UUID(), started = start.timeIntervalSinceReferenceDate
        let json = #"{"schemaVersion":2,"session":{"id":"\#(id.uuidString)","startedAt":\#(started),"expiresAt":\#(started + 1500),"phase":"active","breaksTaken":0}}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("control.json"))
        let envelope = try SharedControlStore(directory: directory).withExclusiveAccess { try $0.load() }
        let session = try XCTUnwrap(envelope.session)
        XCTAssertEqual(session.id, id); XCTAssertEqual(session.phase, .active)
        XCTAssertNil(session.origin); XCTAssertFalse(session.isFilterStarted); XCTAssertNil(envelope.filterActivation)
    }
    func testOriginAndMarkerRoundTripThroughTheStore() throws {
        let store = SharedControlStore(directory: directory), marker = UUID()
        var session = ControlSession(startedAt: start); session.origin = .focusFilter
        var envelope = ControlEnvelope(); envelope.session = session; envelope.filterActivation = marker
        try store.withExclusiveAccess { try $0.save(envelope) }
        let loaded = try store.withExclusiveAccess { try $0.load() }
        XCTAssertEqual(loaded.session?.origin, .focusFilter); XCTAssertEqual(loaded.session?.isFilterStarted, true)
        XCTAssertEqual(loaded.filterActivation, marker); XCTAssertEqual(try rawVersion(), 2)
    }
    func testStorageChecksAcceptEitherOriginInEveryPhase() throws {
        let p = #","pausedAt":\#(start.timeIntervalSinceReferenceDate + 100)"#
        let ended = #","reason":"earlyExit","observedAt":\#(start.timeIntervalSinceReferenceDate + 100)"#
        let shapes = [("preparing", ""), ("active", ""), ("waiting", p + #","waitEndsAt":\#(start.timeIntervalSinceReferenceDate + 115)"#),
                      ("onBreak", p + #","breaksTaken":1,"breakEndsAt":1"#), ("breakOver", p + #","breaksTaken":3,"breakEndsAt":1"#), ("ending", ended), ("terminal", ended)]
        let store = SharedControlStore(directory: directory)
        for (phase, extra) in shapes {
            for origin in [nil, "manual", "focusFilter"] {
                for marker in [nil, UUID()] {
                    let originKey = origin.map { #","origin":"\#($0)""# } ?? ""
                    let markerKey = marker.map { #","filterActivation":"\#($0.uuidString)""# } ?? ""
                    let id = UUID(), started = start.timeIntervalSinceReferenceDate
                    let json = #"{"schemaVersion":2\#(markerKey),"session":{"id":"\#(id.uuidString)","startedAt":\#(started),"expiresAt":\#(started + 1500),"phase":"\#(phase)"\#(extra)\#(originKey)}}"#
                    try Data(json.utf8).write(to: directory.appendingPathComponent("control.json"))
                    let context = "\(phase) \(origin ?? "none") \(marker != nil)"
                    let loaded = try store.withExclusiveAccess { try $0.load() }
                    XCTAssertEqual(loaded.session?.phase.rawValue, phase, context)
                    XCTAssertEqual(loaded.session?.origin?.rawValue, origin, context); XCTAssertEqual(loaded.filterActivation, marker, context)
                }
            }
        }
    }
    func testUnknownSchemaIsRejected() throws {
        try Data(#"{"schemaVersion":99}"#.utf8).write(to: directory.appendingPathComponent("control.json"))
        XCTAssertThrowsError(try SharedControlStore(directory: directory).withExclusiveAccess { try $0.load() })
    }
}
