import Foundation
import Darwin

/// All readers and writers use the same stable lock inode; only the JSON is replaced.
final class SharedControlStore: ControlStore {
    /// The options of every `control.json` write; the registration marker file uses the same options.
    #if os(iOS)
    static let fileWritingOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
    #else
    static let fileWritingOptions: Data.WritingOptions = .atomic
    #endif
    private let directory: URL
    private let timeout: TimeInterval
    private let markers: any RegistrationMarkerStore
    var registrationMarkers: (any RegistrationMarkerStore)? { markers }
    init(directory: URL, timeout: TimeInterval = 0.25, markers: (any RegistrationMarkerStore)? = nil) {
        self.directory = directory; self.timeout = timeout; self.markers = markers ?? RegistrationMarkerFile(directory: directory)
    }
    func withExclusiveAccess<T>(timeout: TimeInterval?, _ body: (LockedControl) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        #endif
        let fd = open(directory.appendingPathComponent("control.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ControlIssue.io }
        defer { close(fd) }
        // A timeout of 0 makes exactly one `flock` call.
        let deadline = ProcessInfo.processInfo.systemUptime + (timeout ?? self.timeout)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN else { throw ControlIssue.io }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw ControlIssue.lockTimeout }
            usleep(2_000)
        }
        defer { flock(fd, LOCK_UN) }
        // No process can be inside a registration or stop call now, so a marker here is a leftover of a holder that exited. A failed delete does not fail the section.
        try? markers.delete()
        return try body(FileControl(url: directory.appendingPathComponent("control.json")))
    }
}
private struct FileControl: LockedControl {
    let url: URL
    func load() throws -> ControlEnvelope {
        guard FileManager.default.fileExists(atPath: url.path) else { return ControlEnvelope() }
        let value = try JSONDecoder().decode(ControlEnvelope.self, from: Data(contentsOf: url))
        // Version 1 (M1) sessions have no break fields; the break-shape checks apply to both versions.
        guard value.schemaVersion == 1 || value.schemaVersion == 2 else { throw ControlIssue.unsupportedSchema }
        if let session = value.session {
            guard session.startedAt.timeIntervalSince1970.isFinite,
                  FocusLength.isAllowed(seconds: session.length),
                  (session.phase == .terminal || session.phase == .ending) == (session.reason != nil && session.observedAt != nil),
                  Self.hasValidBreakShape(session)
            else { throw ControlIssue.invalidState }
        }
        return value
    }
    private static func hasValidBreakShape(_ session: ControlSession) -> Bool {
        let breaks = session.breaksTaken ?? 0
        guard (0...BreakTiming.maxBreaks).contains(breaks), (session.pausedSeconds ?? 0) >= 0, (session.deadlineCredit ?? 0) >= 0 else { return false }
        switch session.phase {
        case .preparing, .active: return session.pausedAt == nil
        case .waiting: return session.pausedAt != nil && session.waitEndsAt != nil && breaks < BreakTiming.maxBreaks
        case .onBreak, .breakOver: return session.pausedAt != nil && session.breakEndsAt != nil && breaks >= 1
        case .ending, .terminal: return true
        }
    }
    func save(_ envelope: ControlEnvelope) throws {
        // Every transition saves the envelope it decoded, so a version 1 file becomes version 2 here.
        var envelope = envelope
        envelope.schemaVersion = 2
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: url, options: SharedControlStore.fileWritingOptions)
    }
}
