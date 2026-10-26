import Foundation
import Darwin

private final class LocalMonitor: MonitoringClient {
    var registeredSessionIDs: [UUID] { Array(ids) }
    var ids = Set<UUID>()
    func register(id: UUID, start: Date, end: Date) throws { ids.insert(id) }
    func isRegistered(id: UUID) -> Bool { ids.contains(id) }
    func stop(id: UUID) { ids.remove(id) }
}
private final class FileShield: ShieldClient {
    let file: URL
    init(_ root: URL) { file = root.appendingPathComponent("synthetic-shield") }
    func clear() { try? FileManager.default.removeItem(at: file) }
}
@main struct ControlRaceHelper {
    static func main() throws {
        let args = CommandLine.arguments
        if args.count > 2 {
            let root = URL(fileURLWithPath: args[2]), shield = FileShield(URL(fileURLWithPath: args[2]))
            let engine = SessionControl(store: SharedControlStore(directory: root), monitoring: LocalMonitor(), shield: shield)
            if args[1] == "new" {
                _ = try engine.start(now: Date(timeIntervalSince1970: 2000), authorized: { true }, apply: {
                    try! Data("B".utf8).write(to: shield.file)
                    try! Data().write(to: root.appendingPathComponent("ready"))
                    usleep(60_000) // Hold the actual production lock while the stale worker attempts entry.
                }, matches: { true })
            } else {
                let deadline = Date().addingTimeInterval(3)
                while !FileManager.default.fileExists(atPath: root.appendingPathComponent("ready").path) {
                    if Date() > deadline { exit(2) }; usleep(1000)
                }
                try engine.handleCallback(activityName: args[3], now: Date(timeIntervalSince1970: 5000), authorized: true)
            }
            return
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shield = FileShield(root), engine = SessionControl(store: SharedControlStore(directory: root), monitoring: LocalMonitor(), shield: shield)
        let a = try engine.start(now: Date(timeIntervalSince1970: 100), authorized: { true }, apply: {}, matches: { true })
        try engine.finish(id: a.id, reason: .earlyExit, now: Date(timeIntervalSince1970: 101))
        try engine.acknowledgeTerminal(id: a.id)
        let stale = Process(), next = Process()
        for process in [stale, next] { process.executableURL = URL(fileURLWithPath: args[0]) }
        stale.arguments = ["stale", root.path, a.activityName]; next.arguments = ["new", root.path]
        try stale.run(); try next.run(); stale.waitUntilExit(); next.waitUntilExit()
        let current = try engine.snapshot().session
        guard stale.terminationStatus == 0, next.terminationStatus == 0,
              current?.phase == .active, current?.id != a.id,
              try String(contentsOf: shield.file, encoding: .utf8) == "B" else { exit(1) }
        print("PASS: stale A cannot clear B")
    }
}
