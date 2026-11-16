import XCTest
import FamilyControls
import ManagedSettings

/// The move of the focus length, the display-only filter values and the focus selection to the App Group (2026-11-16 extension design, decisions 12 to 17).
@MainActor final class AppGroupMigrationTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func suite() -> UserDefaults { UserDefaults(suiteName: UUID().uuidString)! }

    // MARK: Settings

    func testLengthMovesFirstAndTheOldKeyIsRemoved() {
        let old = suite(), shared = suite()
        FocusSettings(defaults: old).lengthMinutes = 40
        let settings = FocusSettings(defaults: old, shared: shared)
        XCTAssertTrue(settings.migrateToAppGroup())
        XCTAssertEqual(shared.integer(forKey: "focusLengthMinutes"), 40)
        XCTAssertNil(old.object(forKey: "focusLengthMinutes"))
        XCTAssertTrue(FocusSettings(defaults: old, shared: shared).hasStoredLength)
        XCTAssertEqual(FocusSettings(defaults: old, shared: shared).lengthMinutes, 40)
    }
    func testNoStoredLengthWritesTheDefault() {
        let old = suite(), shared = suite()
        XCTAssertTrue(FocusSettings(defaults: old, shared: shared).migrateToAppGroup())
        XCTAssertEqual(shared.integer(forKey: "focusLengthMinutes"), FocusLength.defaultMinutes)
    }
    func testTheAppGroupValueWinsAndANewValueIsWrittenThere() {
        let old = suite(), shared = suite()
        old.set(30, forKey: "focusLengthMinutes"); shared.set(45, forKey: "focusLengthMinutes")
        let settings = FocusSettings(defaults: old, shared: shared)
        XCTAssertEqual(settings.lengthMinutes, 45)
        settings.lengthMinutes = 50
        XCTAssertEqual(shared.integer(forKey: "focusLengthMinutes"), 50); XCTAssertEqual(old.integer(forKey: "focusLengthMinutes"), 30)
    }
    func testBeforeTheMigrationTheOldValueIsRead() {
        let old = suite(), shared = suite()
        old.set(35, forKey: "focusLengthMinutes")
        let settings = FocusSettings(defaults: old, shared: shared)
        XCTAssertEqual(settings.lengthMinutes, 35); XCTAssertFalse(settings.hasStoredLength)
    }
    func testRefusalAndPendingCardMoveAndTheOnboardingFlagStays() {
        let old = suite(), shared = suite(), id = UUID(), time = Date(timeIntervalSince1970: 1000)
        let before = FocusSettings(defaults: old)
        before.recordFilterRefusal(.selection, at: time); before.recordPendingCompletion(id: id, length: 1500); before.hasCompletedOnboarding = true
        XCTAssertTrue(FocusSettings(defaults: old, shared: shared).migrateToAppGroup())
        let after = FocusSettings(defaults: old, shared: shared)
        XCTAssertEqual(after.lastFilterRefusal?.reason, .selection); XCTAssertEqual(after.lastFilterRefusal?.at, time)
        XCTAssertEqual(after.pendingCompletion?.id, id); XCTAssertEqual(after.pendingCompletion?.length, 1500)
        XCTAssertTrue(after.hasCompletedOnboarding)
        XCTAssertNil(old.object(forKey: "focusFilterRefusal")); XCTAssertNil(old.object(forKey: "pendingCompletionID"))
        XCTAssertNotNil(old.object(forKey: "onboardingCompleted")); XCTAssertNil(shared.object(forKey: "onboardingCompleted"))
    }
    func testMigrationRunsAgainWithoutLosingAValue() {
        let old = suite(), shared = suite()
        old.set(40, forKey: "focusLengthMinutes")
        XCTAssertTrue(FocusSettings(defaults: old, shared: shared).migrateToAppGroup())
        XCTAssertTrue(FocusSettings(defaults: old, shared: shared).migrateToAppGroup())
        XCTAssertEqual(FocusSettings(defaults: old, shared: shared).lengthMinutes, 40)
    }

    // MARK: Selection

    private var legacy: URL { root.appendingPathComponent("PrivateSelection") }
    private var group: URL { root.appendingPathComponent("FocusSelection") }
    private func writeLegacy(_ data: Data) throws {
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try data.write(to: legacy.appendingPathComponent("selection.json"))
    }
    /// Synthetic Codable tokens for persistence only, as in `SelectionRepositoryTests`; never passed to Screen Time.
    private func syntheticSelection(apps: Int, websites: Int, includeEntireCategory: Bool) throws -> FamilyActivitySelection {
        func token<T>(_ type: Token<T>.Type, _ id: Int) throws -> Token<T> {
            try JSONDecoder().decode(type, from: JSONEncoder().encode(["data": Data([UInt8(id)])]))
        }
        var selection = FamilyActivitySelection(includeEntireCategory: includeEntireCategory)
        selection.applicationTokens = Set(try (0..<apps).map { try token(ApplicationToken.self, $0) })
        selection.webDomainTokens = Set(try (0..<websites).map { try token(WebDomainToken.self, $0) })
        selection.categoryTokens = [try token(ActivityCategoryToken.self, 0)]
        return selection
    }
    /// A selection that passes validation, as every saved file does.
    /// Encoded once: a second encoding of the same selection can order its keys differently.
    private lazy var savedSelection: Data = try! JSONEncoder().encode(syntheticSelection(apps: 1, websites: 0, includeEntireCategory: true))

    func testSelectionMovesAndThePrivateFileIsDeleted() throws {
        try writeLegacy(savedSelection)
        _ = try SelectionRepository(directory: group, legacyDirectory: legacy, migrate: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: group.appendingPathComponent("selection.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("selection.json").path))
    }
    func testWithoutMigrationThePrivateFileIsReadAndKept() throws {
        try writeLegacy(savedSelection)
        _ = try SelectionRepository(directory: group, legacyDirectory: legacy, migrate: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: group.appendingPathComponent("selection.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("selection.json").path))
    }
    func testAPrivateFileLeftNextToACopyReplacesTheCopyAndIsDeleted() throws {
        // A process exit after the copy and before the delete leaves both; the private file is still the source.
        try writeLegacy(savedSelection)
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: group.appendingPathComponent("selection.json"))
        _ = try SelectionRepository(directory: group, legacyDirectory: legacy, migrate: true)
        XCTAssertEqual(try Data(contentsOf: group.appendingPathComponent("selection.json")), savedSelection)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("selection.json").path))
    }
    func testASaveBeforeTheMigrationGoesToThePrivateFile() throws {
        try writeLegacy(savedSelection)
        let repository = try SelectionRepository(directory: group, legacyDirectory: legacy, migrate: false)
        try repository.save(syntheticSelection(apps: 2, websites: 0, includeEntireCategory: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: group.appendingPathComponent("selection.json").path))
        _ = try SelectionRepository(directory: group, legacyDirectory: legacy, migrate: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: group.appendingPathComponent("selection.json").path))
    }
    func testAnUnreadablePrivateFileStaysAndThrows() throws {
        try writeLegacy(Data("not json".utf8))
        XCTAssertThrowsError(try SelectionRepository(directory: group, legacyDirectory: legacy, migrate: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("selection.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: group.appendingPathComponent("selection.json").path))
    }
}
