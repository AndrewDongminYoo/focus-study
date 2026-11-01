import Foundation
import DeviceActivity
import ManagedSettings
import FamilyControls

enum ScreenTimeAccess {
    static func isApproved(_ status: AuthorizationStatus) -> Bool {
        if status == .approved { return true }
        if #available(iOS 26.4, *), status == .approvedWithDataAccess { return true }
        return false
    }
}
enum GroupConfiguration {
    static func directory() throws -> URL {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "FocusAppGroupIdentifier") as? String,
              let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else { throw ControlIssue.io }
        return url.appendingPathComponent("SessionControl", isDirectory: true)
    }
}
final class ScreenTimeMonitoring: MonitoringClient {
    private let center = DeviceActivityCenter()
    var registeredSessionIDs: [UUID] { Array(Set(center.activities.compactMap(Self.sessionID))) }
    /// The session of both `focus.<UUID>` and `focus.<UUID>.break.<n>`: the 36 characters after `focus.`.
    static func sessionID(_ activity: DeviceActivityName) -> UUID? {
        let raw = activity.rawValue
        guard raw.hasPrefix("focus.") else { return nil }
        let rest = raw.dropFirst(6)
        guard let id = UUID(uuidString: String(rest.prefix(36))) else { return nil }
        let suffix = rest.dropFirst(36)
        return suffix.isEmpty || suffix.hasPrefix(".break.") ? id : nil
    }
    /// `n` for `focus.<UUID>.break.<n>`, and `nil` for every other name.
    static func breakIndex(_ activity: DeviceActivityName) -> Int? {
        guard sessionID(activity) != nil else { return nil }
        let suffix = activity.rawValue.dropFirst(6 + 36)
        guard suffix.hasPrefix(".break."), let index = Int(suffix.dropFirst(7)), index > 0 else { return nil }
        return index
    }
    func register(id: UUID, start: Date, end: Date) throws {
        // `startMonitoring` with an existing name overwrites its schedule.
        try center.startMonitoring(name(id), during: Self.schedule(start: start, end: end, calendar: .current))
    }
    static func schedule(start: Date, end: Date, calendar: Calendar) -> DeviceActivitySchedule {
        let roundedEnd = Date(timeIntervalSince1970: ceil(end.timeIntervalSince1970))
        return DeviceActivitySchedule(intervalStart: calendar.dateComponents(fields, from: start), intervalEnd: calendar.dateComponents(fields, from: roundedEnd), repeats: false)
    }
    /// The break interval is 15 minutes, the system minimum; the warning re-blocks after the break length.
    static func breakSchedule(start: Date, end: Date, warning: TimeInterval, calendar: Calendar) -> DeviceActivitySchedule {
        let roundedEnd = Date(timeIntervalSince1970: ceil(end.timeIntervalSince1970))
        let seconds = Int(warning.rounded(.down))
        return DeviceActivitySchedule(intervalStart: calendar.dateComponents(fields, from: start), intervalEnd: calendar.dateComponents(fields, from: roundedEnd),
                                      repeats: false, warningTime: DateComponents(minute: seconds / 60, second: seconds % 60))
    }
    private static let fields: Set<Calendar.Component> = [.era, .year, .month, .day, .hour, .minute, .second, .timeZone]
    func isRegistered(id: UUID) -> Bool { center.activities.contains(name(id)) }
    func stop(id: UUID) {
        let breaks = center.activities.filter { Self.sessionID($0) == id && Self.breakIndex($0) != nil }
        center.stopMonitoring([name(id)] + breaks + (1...BreakTiming.maxBreaks).map { breakName(id, $0) })
    }
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws {
        try center.startMonitoring(breakName(id, index), during: Self.breakSchedule(start: start, end: end, warning: warning, calendar: .current))
    }
    func isBreakRegistered(id: UUID, index: Int) -> Bool { center.activities.contains(breakName(id, index)) }
    var registeredBreaks: [(id: UUID, index: Int)] {
        center.activities.compactMap { activity in
            guard let id = Self.sessionID(activity), let index = Self.breakIndex(activity) else { return nil }
            return (id: id, index: index)
        }
    }
    func stopBreak(id: UUID, index: Int) { center.stopMonitoring([breakName(id, index)]) }
    private func name(_ id: UUID) -> DeviceActivityName { DeviceActivityName("focus.\(id.uuidString)") }
    private func breakName(_ id: UUID, _ index: Int) -> DeviceActivityName { DeviceActivityName("focus.\(id.uuidString).break.\(index)") }

    // MARK: Everyday layer

    /// Time components only, so that the system uses `Calendar.current` and the wall clock every day.
    static func everydaySchedule(start: Int, end: Int) -> DeviceActivitySchedule {
        DeviceActivitySchedule(intervalStart: DateComponents(hour: start / 60, minute: start % 60, second: 0),
                               intervalEnd: DateComponents(hour: end / 60, minute: end % 60, second: 0), repeats: true)
    }
    static func everydayActivityName(revision: UUID, part: EverydayPart) -> DeviceActivityName {
        switch part {
        case .range: DeviceActivityName("everyday.\(revision.uuidString).range")
        case .window(let n): DeviceActivityName("everyday.\(revision.uuidString).window.\(n)")
        }
    }
    /// The revision and the part of `everyday.<UUID>.range` and `everyday.<UUID>.window.<n>` (`n` 1-3), and `nil` for every other name.
    static func everydayName(_ activity: DeviceActivityName) -> (revision: UUID, part: EverydayPart)? {
        let raw = activity.rawValue
        guard raw.hasPrefix("everyday.") else { return nil }
        let rest = raw.dropFirst(9)
        guard let revision = UUID(uuidString: String(rest.prefix(36))) else { return nil }
        let suffix = rest.dropFirst(36)
        if suffix == ".range" { return (revision, .range) }
        guard suffix.hasPrefix(".window."), let n = Int(suffix.dropFirst(8)), (1...EverydaySchedule.maxWindows).contains(n),
              suffix.dropFirst(8) == "\(n)" else { return nil }
        return (revision, .window(n))
    }
    func registerEveryday(revision: UUID, part: EverydayPart, start: Int, end: Int) throws {
        try center.startMonitoring(Self.everydayActivityName(revision: revision, part: part), during: Self.everydaySchedule(start: start, end: end))
    }
    var registeredEveryday: [(revision: UUID, part: EverydayPart)] { center.activities.compactMap(Self.everydayName) }
    /// One name per call: `stopMonitoring([])` would stop every activity, also the focus and break activities.
    func stopEveryday(revision: UUID, part: EverydayPart) { center.stopMonitoring([Self.everydayActivityName(revision: revision, part: part)]) }
}
final class ScreenTimeShield: ShieldClient {
    private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("focusSession"))
    func apply(_ selection: FamilyActivitySelection) {
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }
    func matches(_ selection: FamilyActivitySelection) -> Bool {
        (store.shield.applications ?? []) == selection.applicationTokens && (store.shield.webDomains ?? []) == selection.webDomainTokens
    }
    func clear() { store.clearAllSettings() }
}
/// The everyday layer's own store; the focus layer never writes it.
final class ScreenTimeEverydayShield {
    private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("everydayLayer"))
    func apply(_ selection: FamilyActivitySelection) {
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }
    func matches(_ selection: FamilyActivitySelection) -> Bool {
        (store.shield.applications ?? []) == selection.applicationTokens && (store.shield.webDomains ?? []) == selection.webDomainTokens
    }
    var hasShield: Bool { store.shield.applications != nil || store.shield.webDomains != nil }
    func clear() { store.clearAllSettings() }
}
