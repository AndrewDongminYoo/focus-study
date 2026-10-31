import XCTest

@MainActor final class FocusSettingsTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: UUID().uuidString)! }
    func testLengthDefaultsTo25AndPersistsAllowedValues() {
        let store = defaults()
        XCTAssertEqual(FocusSettings(defaults: store).lengthMinutes, 25)
        FocusSettings(defaults: store).lengthMinutes = 40
        XCTAssertEqual(FocusSettings(defaults: store).lengthMinutes, 40)
        XCTAssertEqual(FocusSettings(defaults: store).lengthSeconds, 2400)
    }
    func testDisallowedLengthLeavesStoredValueUnchanged() {
        let store = defaults(), settings = FocusSettings(defaults: store)
        settings.lengthMinutes = 35; settings.lengthMinutes = 27
        XCTAssertEqual(FocusSettings(defaults: store).lengthMinutes, 35)
    }
    func testMigrationMarksExistingUserAsOnboarded() {
        let settings = FocusSettings(defaults: defaults())
        settings.migrateIfNeeded(accessApproved: true, hasSelection: true)
        XCTAssertTrue(settings.hasCompletedOnboarding)
    }
    func testMigrationLeavesNewUserForOnboarding() {
        let settings = FocusSettings(defaults: defaults())
        settings.migrateIfNeeded(accessApproved: false, hasSelection: false)
        XCTAssertFalse(settings.hasCompletedOnboarding)
    }
    func testMigrationRunsOnlyOnce() {
        let store = defaults()
        FocusSettings(defaults: store).migrateIfNeeded(accessApproved: false, hasSelection: false)
        let later = FocusSettings(defaults: store)
        later.migrateIfNeeded(accessApproved: true, hasSelection: true)
        XCTAssertFalse(later.hasCompletedOnboarding)
    }
}
