import Foundation
import FamilyControls
import Observation

@MainActor protocol SelectionStoring: AnyObject {
    var selection: FamilyActivitySelection { get }
    var counts: (apps: Int, websites: Int, categories: Int) { get }
    func save(_ selection: FamilyActivitySelection) throws
}
@MainActor @Observable final class SelectionRepository: SelectionStoring {
    private(set) var selection = FamilyActivitySelection(includeEntireCategory: true)
    /// The file that is read and saved: the App Group file, or the private file while it is still the source.
    private var url: URL
    var counts: (apps: Int, websites: Int, categories: Int) { (selection.applicationTokens.count, selection.webDomainTokens.count, selection.categoryTokens.count) }
    /// `directory` is `FocusSelection/` in the App Group; `legacyDirectory` is the app's `PrivateSelection/` of a build before the move.
    /// With `migrate`, a private file is copied over the App Group file, read back and compared, and then deleted (2026-11-16 extension design, decision 16).
    /// Without it, or when a step fails, the private file stays the source and is read instead.
    init(directory: URL, legacyDirectory: URL? = nil, migrate: Bool = true) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let groupFile = directory.appendingPathComponent("selection.json")
        url = groupFile
        var source = groupFile
        if let legacyDirectory {
            let legacy = legacyDirectory.appendingPathComponent("selection.json")
            if FileManager.default.fileExists(atPath: legacy.path) {
                let data = try Data(contentsOf: legacy)
                // An unreadable private file is never copied: it stays, and the read below throws as it did before the move.
                _ = try individualSelection(from: JSONDecoder().decode(FamilyActivitySelection.self, from: data))
                source = legacy
                if migrate, (try? Self.write(data, to: groupFile)) != nil, (try? Data(contentsOf: groupFile)) == data, (try? FileManager.default.removeItem(at: legacy)) != nil {
                    source = groupFile
                }
            }
        }
        // A save goes to the file that is read: while the private file is the source, a save there is what the next migration copies.
        url = source
        if FileManager.default.fileExists(atPath: source.path) {
            let loaded = try JSONDecoder().decode(FamilyActivitySelection.self, from: Data(contentsOf: source))
            selection = try individualSelection(from: loaded)
        }
    }
    private static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func save(_ selection: FamilyActivitySelection) throws {
        let individual = try individualSelection(from: selection)
        try Self.write(JSONEncoder().encode(individual), to: url)
        self.selection = individual
    }
    private func individualSelection(from selection: FamilyActivitySelection) throws -> FamilyActivitySelection {
        guard selection.categoryTokens.isEmpty || selection.includeEntireCategory else { throw SelectionIssue.categoriesUnsupported }
        var individual = FamilyActivitySelection(includeEntireCategory: true)
        individual.applicationTokens = selection.applicationTokens
        individual.webDomainTokens = selection.webDomainTokens
        try SelectionValidator.validate(appCount: individual.applicationTokens.count, webCount: individual.webDomainTokens.count, categoryCount: individual.categoryTokens.count)
        return individual
    }
}
