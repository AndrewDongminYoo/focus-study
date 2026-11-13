import Foundation
import FamilyControls
import ManagedSettings

/// `everyday-layer.json` in the App Group: the schedule and the only stored copy of the everyday selection.
/// The app writes it inside a lock section; the Monitor only reads it. It holds application and web domain tokens only.
final class EverydayLayerFile: EverydayLayerStore {
    private struct Stored: Codable {
        var schemaVersion: Int
        var revision: UUID
        var enabled: Bool
        var rangeStart: Int
        var rangeEnd: Int
        var windows: [EverydayWindow]
        var applications: Set<ApplicationToken>
        var webDomains: Set<WebDomainToken>
        /// Optional, so that a file without the key loads with no off day and an earlier build ignores it; `nil` is not written.
        var offDay: String?
        /// Optional in the same way; a missing key is every day, and all seven are not written.
        /// The load reads it with `EverydaySchedule.storedWeekdays`, so a malformed list is never a read failure.
        var weekdays: [Int]?
        var schedule: EverydaySchedule {
            EverydaySchedule(revision: revision, enabled: enabled, rangeStart: rangeStart, rangeEnd: rangeEnd, windows: windows, offDay: offDay,
                             weekdays: EverydaySchedule.storedWeekdays(weekdays))
        }
        var selection: FamilyActivitySelection {
            var selection = FamilyActivitySelection(includeEntireCategory: true)
            selection.applicationTokens = applications; selection.webDomainTokens = webDomains
            return selection
        }
    }
    static let schemaVersion = 1
    private let url: URL
    private let shield: ScreenTimeEverydayShield
    init(directory: URL, shield: ScreenTimeEverydayShield) {
        url = directory.appendingPathComponent("everyday-layer.json"); self.shield = shield
    }
    /// `nil` without a file. An unknown schema or a file that breaks a rule of "Times" or "Selection" is a read failure.
    private func stored() throws -> Stored? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let value = try JSONDecoder().decode(Stored.self, from: Data(contentsOf: url))
        guard value.schemaVersion == Self.schemaVersion else { throw ControlIssue.unsupportedSchema }
        guard value.schedule.isValid, value.applications.count <= 50, value.webDomains.count <= 50,
              !value.enabled || value.applications.count + value.webDomains.count > 0 else { throw ControlIssue.invalidState }
        return value
    }
    func load() throws -> EverydaySchedule? { try stored()?.schedule }
    func selection() throws -> FamilyActivitySelection? { try stored()?.selection }
    /// `true` when `selection` holds every app and website of the stored selection, or when no layer is stored.
    func contains(_ selection: FamilyActivitySelection) throws -> Bool {
        guard let stored = try stored() else { return true }
        return stored.applications.isSubset(of: selection.applicationTokens) && stored.webDomains.isSubset(of: selection.webDomainTokens)
    }
    func write(_ schedule: EverydaySchedule, selection: FamilyActivitySelection) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let value = Stored(schemaVersion: Self.schemaVersion, revision: schedule.revision, enabled: schedule.enabled, rangeStart: schedule.rangeStart,
                           rangeEnd: schedule.rangeEnd, windows: schedule.windows, applications: selection.applicationTokens, webDomains: selection.webDomainTokens,
                           offDay: schedule.offDay, weekdays: EverydaySchedule.storedWeekdays(schedule.weekdays))
        try JSONEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    /// The off-for-today write: the whole file again with the stored tokens and the schedule that the section passes, which keeps the stored revision.
    func writeOffDay(_ schedule: EverydaySchedule) throws {
        guard let stored = try stored(), stored.revision == schedule.revision else { throw ControlIssue.invalidState }
        try write(schedule, selection: stored.selection)
    }
    func storeMatches() -> Bool {
        guard let selection = (try? stored())?.selection else { return false }
        return shield.matches(selection)
    }
    func applyStored() -> Bool {
        guard let selection = (try? stored())?.selection else { return false }
        shield.apply(selection)
        return shield.matches(selection)
    }
    var hasShield: Bool { shield.hasShield }
    func clearShield() { shield.clear() }
}
