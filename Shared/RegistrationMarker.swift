import Foundation

/// The activity that a lock holder is registering right now (the 2026-11-10 registration marker design).
/// A Monitor callback for that activity that finds the lock busy returns at once, because the holder's section decides that activity.
struct RegistrationMarker: Codable, Equatable {
    static let fileName = "registration-marker.json"
    static let currentSchemaVersion = 1
    /// The longest age, in seconds of `systemUptime`, at which a marker still counts.
    static let freshness: TimeInterval = 10
    var schemaVersion = currentSchemaVersion
    /// The exact `DeviceActivityName` raw value that the call passes to `startMonitoring`.
    var activityName: String
    /// `ProcessInfo.processInfo.systemUptime` right before the call.
    var uptime: TimeInterval
    /// The first time at which something can be due for that activity that the holder did not decide.
    var validUntil: Date
    /// `0 <= age <= 10` seconds. A negative age is a marker from before a restart.
    func isFresh(atUptime current: TimeInterval) -> Bool {
        let age = current - uptime
        return age >= 0 && age <= Self.freshness
    }
    /// Freshness aside, whether a callback that found the lock busy can return without its section.
    /// A warning never skips: it is the one-shot re-block of a break.
    func decides(activityName name: String, kind: CallbackKind, now: Date) -> Bool {
        kind != .willEndWarning && activityName == name && now < validUntil
    }
}
/// Only a lock holder writes or deletes the marker; a Monitor callback only reads it.
protocol RegistrationMarkerStore {
    /// `nil` for a missing, unreadable or undecodable file and for an unknown `schemaVersion`.
    func read() -> RegistrationMarker?
    func write(_ marker: RegistrationMarker) throws
    /// Deleting a missing file succeeds.
    func delete() throws
    /// The current `systemUptime`, the clock of `RegistrationMarker.uptime`.
    func uptime() -> TimeInterval
}
extension RegistrationMarkerStore {
    /// The marker, only when it is readable and fresh.
    func freshMarker() -> RegistrationMarker? {
        guard let marker = read(), marker.isFresh(atUptime: uptime()) else { return nil }
        return marker
    }
}
/// `registration-marker.json` in the App Group directory `SessionControl/`, next to `control.json`.
final class RegistrationMarkerFile: RegistrationMarkerStore {
    let url: URL
    private let clock: () -> TimeInterval
    private let writeData: (Data, URL, Data.WritingOptions) throws -> Void
    /// `writeData` is a test seam that receives the write options; the default writes the data.
    init(directory: URL, uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         writeData: @escaping (Data, URL, Data.WritingOptions) throws -> Void = { try $0.write(to: $1, options: $2) }) {
        url = directory.appendingPathComponent(RegistrationMarker.fileName); clock = uptime; self.writeData = writeData
    }
    func read() -> RegistrationMarker? {
        guard let data = try? Data(contentsOf: url), let marker = try? JSONDecoder().decode(RegistrationMarker.self, from: data),
              marker.schemaVersion == RegistrationMarker.currentSchemaVersion else { return nil }
        return marker
    }
    func write(_ marker: RegistrationMarker) throws {
        let data = try JSONEncoder().encode(marker)
        try writeData(data, url, SharedControlStore.fileWritingOptions)
    }
    func delete() throws {
        do { try FileManager.default.removeItem(at: url) }
        catch CocoaError.fileNoSuchFile {}
    }
    func uptime() -> TimeInterval { clock() }
}
/// Writes the marker right before each registration and deletes it right after the call returns or throws, inside the lock section that made it.
/// `now` is the section's time and `calendar` the engine calendar; the wrapper never reads the wall clock.
final class MarkedMonitoring: MonitoringClient {
    private let base: any MonitoringClient
    private let markers: any RegistrationMarkerStore
    private let now: Date
    private let calendar: Calendar
    init(base: any MonitoringClient, markers: any RegistrationMarkerStore, now: Date, calendar: Calendar) {
        self.base = base; self.markers = markers; self.now = now; self.calendar = calendar
    }
    /// The names that `ScreenTimeMonitoring` passes to `startMonitoring`; an SDK test checks that they are equal.
    static func focusActivityName(id: UUID) -> String { "focus.\(id.uuidString)" }
    static func breakActivityName(id: UUID, index: Int) -> String { "focus.\(id.uuidString).break.\(index)" }
    static func everydayActivityName(revision: UUID, part: EverydayPart) -> String {
        switch part {
        case .range: "everyday.\(revision.uuidString).range"
        case .window(let n): "everyday.\(revision.uuidString).window.\(n)"
        }
    }
    /// A marker write that throws does not stop the registration, and a delete that throws leaves a leftover for the next lock holder.
    private func marked(_ activityName: String, validUntil: Date, _ call: () throws -> Void) throws {
        try? markers.write(RegistrationMarker(activityName: activityName, uptime: markers.uptime(), validUntil: validUntil))
        defer { try? markers.delete() }
        try call()
    }
    /// Valid until the end that the call registers: the next time that the saved phase must change.
    func register(id: UUID, start: Date, end: Date) throws {
        try marked(Self.focusActivityName(id: id), validUntil: end) { try base.register(id: id, start: start, end: end) }
    }
    /// Valid until the warning, `breakLength` after the break start.
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws {
        try marked(Self.breakActivityName(id: id, index: index), validUntil: end.addingTimeInterval(-warning)) {
            try base.registerBreak(id: id, index: index, start: start, end: end, warning: warning)
        }
    }
    /// Valid until the next whole minute after the section's `now`: every everyday edge is on a whole minute, and the section's convergence has seen every edge up to `now`.
    func registerEveryday(revision: UUID, part: EverydayPart, start: Int, end: Int) throws {
        let nextMinute = calendar.dateInterval(of: .minute, for: now)?.end ?? now
        try marked(Self.everydayActivityName(revision: revision, part: part), validUntil: nextMinute) {
            try base.registerEveryday(revision: revision, part: part, start: start, end: end)
        }
    }
    var registeredSessionIDs: [UUID] { base.registeredSessionIDs }
    func isRegistered(id: UUID) -> Bool { base.isRegistered(id: id) }
    func stop(id: UUID) { base.stop(id: id) }
    func isBreakRegistered(id: UUID, index: Int) -> Bool { base.isBreakRegistered(id: id, index: index) }
    var registeredBreaks: [(id: UUID, index: Int)] { base.registeredBreaks }
    func stopBreak(id: UUID, index: Int) { base.stopBreak(id: id, index: index) }
    var registeredEveryday: [(revision: UUID, part: EverydayPart)] { base.registeredEveryday }
    func stopEveryday(revision: UUID, part: EverydayPart) { base.stopEveryday(revision: revision, part: part) }
}
