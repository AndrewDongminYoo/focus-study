import Foundation
import Darwin

/// All readers and writers use the same stable lock inode; only the JSON is replaced.
final class SharedControlStore: ControlStore {
    private let directory: URL
    private let timeout: TimeInterval
    init(directory: URL, timeout: TimeInterval = 0.25) { self.directory = directory; self.timeout = timeout }
    func withExclusiveAccess<T>(_ body: (LockedControl) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        #endif
        let fd = open(directory.appendingPathComponent("control.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ControlIssue.io }
        defer { close(fd) }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN else { throw ControlIssue.io }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw ControlIssue.lockTimeout }
            usleep(2_000)
        }
        defer { flock(fd, LOCK_UN) }
        return try body(FileControl(url: directory.appendingPathComponent("control.json")))
    }
}
private struct FileControl: LockedControl {
    let url: URL
    func load() throws -> ControlEnvelope {
        guard FileManager.default.fileExists(atPath: url.path) else { return ControlEnvelope() }
        let value = try JSONDecoder().decode(ControlEnvelope.self, from: Data(contentsOf: url))
        guard value.schemaVersion == 1 else { throw ControlIssue.unsupportedSchema }
        if let session = value.session {
            guard session.startedAt.timeIntervalSince1970.isFinite,
                  abs(session.expiresAt.timeIntervalSince(session.startedAt) - 1500) < 0.01,
                  (session.phase == .terminal || session.phase == .ending) == (session.reason != nil && session.observedAt != nil)
            else { throw ControlIssue.invalidState }
        }
        return value
    }
    func save(_ envelope: ControlEnvelope) throws {
        let data = try JSONEncoder().encode(envelope)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
