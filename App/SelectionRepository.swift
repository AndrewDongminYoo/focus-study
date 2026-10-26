import Foundation
import FamilyControls
import Observation

@MainActor protocol SelectionStoring: AnyObject {
    var selection: FamilyActivitySelection { get }
    var counts: (apps: Int, websites: Int, categories: Int) { get }
    func save(_ selection: FamilyActivitySelection) throws
}
@MainActor @Observable final class SelectionRepository: SelectionStoring {
    private(set) var selection = FamilyActivitySelection()
    private let url: URL
    var counts: (apps: Int, websites: Int, categories: Int) { (selection.applicationTokens.count, selection.webDomainTokens.count, selection.categoryTokens.count) }
    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("selection.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let loaded = try JSONDecoder().decode(FamilyActivitySelection.self, from: Data(contentsOf: url))
            try SelectionValidator.validate(appCount: loaded.applicationTokens.count, webCount: loaded.webDomainTokens.count, categoryCount: loaded.categoryTokens.count)
            selection = loaded
        }
    }
    func save(_ selection: FamilyActivitySelection) throws {
        try SelectionValidator.validate(appCount: selection.applicationTokens.count, webCount: selection.webDomainTokens.count, categoryCount: selection.categoryTokens.count)
        try JSONEncoder().encode(selection).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        self.selection = selection
    }
}
