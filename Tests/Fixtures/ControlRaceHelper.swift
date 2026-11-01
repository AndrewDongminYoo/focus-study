import Foundation
import Darwin

private final class LocalMonitor: MonitoringClient {
    var registeredSessionIDs: [UUID] { Array(ids) }
    var ids = Set<UUID>()
    var breaks: [(id: UUID, index: Int)] = []
    func register(id: UUID, start: Date, end: Date) throws { ids.insert(id) }
    func isRegistered(id: UUID) -> Bool { ids.contains(id) }
    func stop(id: UUID) { ids.remove(id); breaks.removeAll { $0.id == id } }
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws { breaks.append((id, index)) }
    func isBreakRegistered(id: UUID, index: Int) -> Bool { breaks.contains { $0.id == id && $0.index == index } }
    var registeredBreaks: [(id: UUID, index: Int)] { breaks }
    func stopBreak(id: UUID, index: Int) { breaks.removeAll { $0.id == id && $0.index == index } }
}
private final class FileShield: ShieldClient {
    let file: URL
    init(_ root: URL) { file = root.appendingPathComponent("synthetic-shield") }
    func clear() { try? FileManager.default.removeItem(at: file) }
}
/// Synthetic selection copies in the shared directory; a restore writes "restored" to the synthetic shield.
private final class FileCopies: BreakSelectionStore {
    let root: URL, shield: FileShield
    init(_ root: URL, shield: FileShield) { self.root = root; self.shield = shield }
    private func url(_ id: UUID) -> URL { root.appendingPathComponent("break-selection.\(id.uuidString).json") }
    func save(id: UUID) throws { try Data("copy".utf8).write(to: url(id)) }
    func restoreShield(id: UUID) -> Bool {
        guard exists(id: id) else { return false }
        return (try? Data("restored".utf8).write(to: shield.file)) != nil
    }
    func exists(id: UUID) -> Bool { FileManager.default.fileExists(atPath: url(id).path) }
    func remove(id: UUID) { try? FileManager.default.removeItem(at: url(id)) }
    func removeAll(except id: UUID?) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for name in names where name.hasPrefix("break-selection.") && name != id.map({ url($0).lastPathComponent }) {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
        }
    }
}
private func waitForReady(_ root: URL) {
    let deadline = Date().addingTimeInterval(3)
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("ready").path) {
        if Date() > deadline { exit(2) }; usleep(1000)
    }
}
@main struct ControlRaceHelper {
    static func main() throws {
        let args = CommandLine.arguments
        if args.count > 2 {
            let root = URL(fileURLWithPath: args[2]), shield = FileShield(URL(fileURLWithPath: args[2])), copies = FileCopies(root, shield: shield)
            let engine = SessionControl(store: SharedControlStore(directory: root), monitoring: LocalMonitor(), shield: shield, breakSelection: copies)
            switch args[1] {
            case "new":
                _ = try engine.start(now: Date(timeIntervalSince1970: 2000), authorized: { true }, apply: {
                    try! Data("B".utf8).write(to: shield.file)
                    try! Data().write(to: root.appendingPathComponent("ready"))
                    usleep(60_000) // Hold the actual production lock while the stale worker attempts entry.
                }, matches: { true })
            case "break-new":
                let id = UUID(uuidString: args[3])!
                try engine.startBreak(id: id, now: Date(timeIntervalSince1970: 530), saveSelection: {
                    try copies.save(id: id)
                    try! Data().write(to: root.appendingPathComponent("ready"))
                    usleep(60_000) // Hold the lock during the start of break 2 while the stale worker attempts entry.
                })
            case "break-stale":
                waitForReady(root)
                try engine.handleCallback(activityName: args[3], kind: .willEndWarning, now: Date(timeIntervalSince1970: 540), authorized: true)
            default:
                waitForReady(root)
                try engine.handleCallback(activityName: args[3], kind: .didEnd, now: Date(timeIntervalSince1970: 5000), authorized: true)
            }
            return
        }
        try verifyStaleSession(executable: args[0])
        try verifyStaleBreak(executable: args[0])
    }
    private static func run(_ executable: String, _ stale: [String], _ next: [String]) throws -> Bool {
        let staleProcess = Process(), nextProcess = Process()
        for process in [staleProcess, nextProcess] { process.executableURL = URL(fileURLWithPath: executable) }
        staleProcess.arguments = stale; nextProcess.arguments = next
        try staleProcess.run(); try nextProcess.run(); staleProcess.waitUntilExit(); nextProcess.waitUntilExit()
        return staleProcess.terminationStatus == 0 && nextProcess.terminationStatus == 0
    }
    private static func verifyStaleSession(executable: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shield = FileShield(root), engine = SessionControl(store: SharedControlStore(directory: root), monitoring: LocalMonitor(), shield: shield, breakSelection: FileCopies(root, shield: shield))
        let a = try engine.start(now: Date(timeIntervalSince1970: 100), authorized: { true }, apply: {}, matches: { true })
        try engine.finish(id: a.id, reason: .earlyExit, now: Date(timeIntervalSince1970: 101))
        try engine.acknowledgeTerminal(id: a.id)
        let exited = try run(executable, ["stale", root.path, a.activityName], ["new", root.path])
        let current = try engine.snapshot().session
        guard exited, current?.phase == .active, current?.id != a.id,
              try String(contentsOf: shield.file, encoding: .utf8) == "B" else { exit(1) }
        print("PASS: stale A cannot clear B")
    }
    /// A late warning of break 1 waits for the lock while another process starts break 2; it must leave break 2 unchanged.
    private static func verifyStaleBreak(executable: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shield = FileShield(root), copies = FileCopies(root, shield: shield)
        let engine = SessionControl(store: SharedControlStore(directory: root), monitoring: LocalMonitor(), shield: shield, breakSelection: copies)
        let s = try engine.start(now: Date(timeIntervalSince1970: 100), authorized: { true }, apply: { try! Data("on".utf8).write(to: shield.file) }, matches: { true })
        _ = try engine.requestBreak(id: s.id, now: Date(timeIntervalSince1970: 200))
        try engine.startBreak(id: s.id, now: Date(timeIntervalSince1970: 215), saveSelection: { try copies.save(id: s.id) })
        try engine.handleCallback(activityName: s.breakActivityName(index: 1), kind: .willEndWarning, now: Date(timeIntervalSince1970: 390), authorized: true)
        try engine.resume(id: s.id, now: Date(timeIntervalSince1970: 400))
        _ = try engine.requestBreak(id: s.id, now: Date(timeIntervalSince1970: 500))
        let exited = try run(executable, ["break-stale", root.path, s.breakActivityName(index: 1)], ["break-new", root.path, s.id.uuidString])
        let current = try engine.snapshot().session
        guard exited, current?.id == s.id, current?.phase == .onBreak, current?.breaksTaken == 2,
              !FileManager.default.fileExists(atPath: shield.file.path), copies.exists(id: s.id) else { exit(1) }
        print("PASS: stale break 1 cannot touch break 2")
    }
}
