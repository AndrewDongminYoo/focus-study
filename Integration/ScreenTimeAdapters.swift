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
    var registeredSessionIDs: [UUID] { center.activities.compactMap(Self.sessionID) }
    static func sessionID(_ activity: DeviceActivityName) -> UUID? {
        guard activity.rawValue.hasPrefix("focus.") else { return nil }
        return UUID(uuidString: String(activity.rawValue.dropFirst(6)))
    }
    func register(id: UUID, start: Date, end: Date) throws {
        try center.startMonitoring(name(id), during: Self.schedule(start: start, end: end, calendar: .current))
    }
    static func schedule(start: Date, end: Date, calendar: Calendar) -> DeviceActivitySchedule {
        let fields: Set<Calendar.Component> = [.era, .year, .month, .day, .hour, .minute, .second, .timeZone]
        let roundedEnd = Date(timeIntervalSince1970: ceil(end.timeIntervalSince1970))
        return DeviceActivitySchedule(intervalStart: calendar.dateComponents(fields, from: start), intervalEnd: calendar.dateComponents(fields, from: roundedEnd), repeats: false)
    }
    func isRegistered(id: UUID) -> Bool { center.activities.contains(name(id)) }
    func stop(id: UUID) { center.stopMonitoring([name(id)]) }
    private func name(_ id: UUID) -> DeviceActivityName { DeviceActivityName("focus.\(id.uuidString)") }
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
