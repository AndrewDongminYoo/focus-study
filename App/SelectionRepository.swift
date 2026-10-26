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
    private let url: URL
    var counts: (apps: Int, websites: Int, categories: Int) { (selection.applicationTokens.count, selection.webDomainTokens.count, selection.categoryTokens.count) }
    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("selection.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let loaded = try JSONDecoder().decode(FamilyActivitySelection.self, from: Data(contentsOf: url))
            selection = try individualSelection(from: loaded)
        }
    }
    func save(_ selection: FamilyActivitySelection) throws {
        let individual = try individualSelection(from: selection)
        try JSONEncoder().encode(individual).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
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
