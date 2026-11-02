import Foundation
import Darwin

private final class LocalMonitor: MonitoringClient {
    /// Focus and everyday registrations live in shared files, so that both processes and the verifier see one center.
    private let everydayFile: URL, focusFile: URL
    init(_ root: URL) { everydayFile = root.appendingPathComponent("everyday-activities"); focusFile = root.appendingPathComponent("focus-activities") }
    var registeredSessionIDs: [UUID] { Array(ids) }
    private var ids: Set<UUID> {
        get { Set(((try? String(contentsOf: focusFile, encoding: .utf8)) ?? "").split(separator: "\n").compactMap { UUID(uuidString: String($0)) }) }
        set { try! Data(newValue.map(\.uuidString).joined(separator: "\n").utf8).write(to: focusFile) }
    }
    var breaks: [(id: UUID, index: Int)] = []
    func register(id: UUID, start: Date, end: Date) throws { ids.insert(id) }
    func isRegistered(id: UUID) -> Bool { ids.contains(id) }
    func stop(id: UUID) { ids.remove(id); breaks.removeAll { $0.id == id } }
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws { breaks.append((id, index)) }
    func isBreakRegistered(id: UUID, index: Int) -> Bool { breaks.contains { $0.id == id && $0.index == index } }
    var registeredBreaks: [(id: UUID, index: Int)] { breaks }
    func stopBreak(id: UUID, index: Int) { breaks.removeAll { $0.id == id && $0.index == index } }
    private var everydayNames: [String] {
        get { ((try? String(contentsOf: everydayFile, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }
        set { try! Data(newValue.joined(separator: "\n").utf8).write(to: everydayFile) }
    }
    private static func name(_ revision: UUID, _ part: EverydayPart) -> String {
        switch part { case .range: "\(revision.uuidString).range"; case .window(let n): "\(revision.uuidString).window.\(n)" }
    }
    func registerEveryday(revision: UUID, part: EverydayPart, start: Int, end: Int) throws {
        let name = Self.name(revision, part)
        if !everydayNames.contains(name) { everydayNames.append(name) }
    }
    var registeredEveryday: [(revision: UUID, part: EverydayPart)] {
        everydayNames.compactMap { name in
            let parts = name.split(separator: ".")
            guard let revision = UUID(uuidString: String(parts[0])) else { return nil }
            return (revision, parts[1] == "range" ? .range : .window(Int(parts[2])!))
        }
    }
    func stopEveryday(revision: UUID, part: EverydayPart) { everydayNames.removeAll { $0 == Self.name(revision, part) } }
}
/// The synthetic everyday file holds the schedule and a selection label; the synthetic everyday shield holds the applied label.
private struct SyntheticLayer: Codable { var schedule: EverydaySchedule; var selection: String }
private final class FileLayer: EverydayLayerStore {
    let file: URL, shield: URL
    init(_ root: URL) { file = root.appendingPathComponent("everyday-layer.json"); shield = root.appendingPathComponent("everyday-shield") }
    func stored() throws -> SyntheticLayer? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(SyntheticLayer.self, from: Data(contentsOf: file))
    }
    func write(_ layer: SyntheticLayer) throws { try JSONEncoder().encode(layer).write(to: file, options: .atomic) }
    func load() throws -> EverydaySchedule? { try stored()?.schedule }
    var applied: String? { try? String(contentsOf: shield, encoding: .utf8) }
    func storeMatches() -> Bool { applied != nil && ((try? stored()) ?? nil)?.selection == applied }
    func applyStored() -> Bool {
        guard let layer = (try? stored()) ?? nil else { return false }
        try? Data(layer.selection.utf8).write(to: shield)
        return storeMatches()
    }
    var hasShield: Bool { FileManager.default.fileExists(atPath: shield.path) }
    func clearShield() { try? FileManager.default.removeItem(at: shield) }
}
private let utc: Calendar = { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!; return calendar }()
/// 12:00 UTC: inside the range 00:00-23:55 of the everyday race.
private let everydayNow = Date(timeIntervalSince1970: 12 * 3600)
private func everydayLayer() -> EverydaySchedule {
    EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 0, rangeEnd: 23 * 60 + 55, windows: [EverydayWindow(kind: .lunch, start: 13 * 60, end: 14 * 60)])
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
            let layer = FileLayer(root)
            let engine = SessionControl(store: SharedControlStore(directory: root), monitoring: LocalMonitor(root), shield: shield, breakSelection: copies, everyday: layer, calendar: utc)
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
            case "everyday-new":
                let next = everydayLayer()
                try engine.saveEveryday(next, now: everydayNow, authorized: { true }, containsStoredSelection: { true }, write: {
                    try! Data().write(to: root.appendingPathComponent("ready"))
                    usleep(60_000) // Hold the lock between the registration and the write of the new revision while the stale worker attempts entry.
                    try layer.write(SyntheticLayer(schedule: next, selection: "B"))
                })
            case "everyday-stale":
                waitForReady(root)
                try engine.handleCallback(activityName: args[3], kind: .didEnd, now: everydayNow, authorized: true)
            case "filter-end":
                waitForReady(root)
                try engine.endFromFocusFilter(now: Date(timeIntervalSince1970: 2100), authorized: true)
            default:
                waitForReady(root)
                try engine.handleCallback(activityName: args[3], kind: .didEnd, now: Date(timeIntervalSince1970: 5000), authorized: true)
            }
            return
        }
        try verifyStaleSession(executable: args[0])
        try verifyStaleBreak(executable: args[0])
        try verifyStaleEveryday(executable: args[0])
        try verifyFilterEnd(executable: args[0])
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
        let shield = FileShield(root), engine = SessionControl(store: SharedControlStore(directory: root), monitoring: LocalMonitor(root), shield: shield, breakSelection: FileCopies(root, shield: shield), everyday: FileLayer(root))
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
        let engine = SessionControl(store: SharedControlStore(directory: root), monitoring: LocalMonitor(root), shield: shield, breakSelection: copies, everyday: FileLayer(root))
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
    /// A late callback of revision 1 waits for the lock while another process saves revision 2; it must not undo the save.
    private static func verifyStaleEveryday(executable: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let layer = FileLayer(root), monitor = LocalMonitor(root), shield = FileShield(root)
        let engine = SessionControl(store: SharedControlStore(directory: root), monitoring: monitor, shield: shield, breakSelection: FileCopies(root, shield: shield), everyday: layer, calendar: utc)
        let first = everydayLayer()
        try engine.saveEveryday(first, now: everydayNow, authorized: { true }, containsStoredSelection: { true }, write: { try layer.write(SyntheticLayer(schedule: first, selection: "A")) })
        guard layer.applied == "A" else { exit(1) }
        let exited = try run(executable, ["everyday-stale", root.path, "everyday.\(first.revision.uuidString).range"], ["everyday-new", root.path])
        guard exited, let stored = try layer.stored(), stored.schedule.revision != first.revision,
              Set(monitor.registeredEveryday.map { "\($0.revision).\($0.part)" }) == Set([EverydayPart.range, .window(1)].map { "\(stored.schedule.revision).\($0)" }),
              layer.applied == "B" else { exit(1) }
        print("PASS: stale everyday revision cannot undo a newer save")
    }
    /// A Focus off call waits for the lock while another process starts a manual session; it clears the marker and leaves that session running.
    private static func verifyFilterEnd(executable: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shield = FileShield(root)
        let engine = SessionControl(store: SharedControlStore(directory: root), monitoring: LocalMonitor(root), shield: shield, breakSelection: FileCopies(root, shield: shield), everyday: FileLayer(root))
        // A refused on call stores the activation marker without a session.
        guard try engine.startFromFocusFilter(now: Date(timeIntervalSince1970: 1000), length: 1500, authorized: { true }, selectionReady: false, apply: {}, matches: { true }) == .refused(.selection),
              try engine.snapshot().filterActivation != nil else { exit(1) }
        let exited = try run(executable, ["filter-end", root.path], ["new", root.path])
        let stored = try engine.snapshot(), current = stored.session
        guard exited, current?.phase == .active, current?.origin == .manual, stored.filterActivation == nil,
              try String(contentsOf: shield.file, encoding: .utf8) == "B" else { exit(1) }
        print("PASS: focus off cannot end a manual session")
    }
}
