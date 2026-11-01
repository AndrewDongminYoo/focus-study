import Foundation
import FamilyControls
import ManagedSettings

/// The frozen selection of one session, copied to the App Group while that session is on a break,
/// so that the Monitor can apply the shield again without the app. It holds application and web domain tokens only.
final class BreakSelectionFile: BreakSelectionStore {
    private struct Copy: Codable {
        var applications: Set<ApplicationToken>
        var webDomains: Set<WebDomainToken>
    }
    private static let prefix = "break-selection.", suffix = ".json"
    private let directory: URL
    private let shield: ScreenTimeShield
    init(directory: URL, shield: ScreenTimeShield) { self.directory = directory; self.shield = shield }
    func save(_ selection: FamilyActivitySelection, id: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let copy = Copy(applications: selection.applicationTokens, webDomains: selection.webDomainTokens)
        try JSONEncoder().encode(copy).write(to: url(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func restoreShield(id: UUID) -> Bool {
        guard let data = try? Data(contentsOf: url(id)), let copy = try? JSONDecoder().decode(Copy.self, from: data) else { return false }
        var selection = FamilyActivitySelection()
        selection.applicationTokens = copy.applications; selection.webDomainTokens = copy.webDomains
        shield.apply(selection)
        return shield.matches(selection)
    }
    func exists(id: UUID) -> Bool { FileManager.default.fileExists(atPath: url(id).path) }
    func remove(id: UUID) { try? FileManager.default.removeItem(at: url(id)) }
    func removeAll(except id: UUID?) {
        let kept = id.map { url($0).lastPathComponent }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix(Self.prefix) && name.hasSuffix(Self.suffix) && name != kept {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
    private func url(_ id: UUID) -> URL { directory.appendingPathComponent("\(Self.prefix)\(id.uuidString)\(Self.suffix)") }
}
