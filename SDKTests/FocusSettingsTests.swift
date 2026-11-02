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
        settings.migrateIfNeeded(hasSelection: true)
        XCTAssertTrue(settings.hasCompletedOnboarding)
    }
    func testMigrationLeavesNewUserForOnboarding() {
        let settings = FocusSettings(defaults: defaults())
        settings.migrateIfNeeded(hasSelection: false)
        XCTAssertFalse(settings.hasCompletedOnboarding)
    }
    func testMigrationRunsOnlyOnce() {
        let store = defaults()
        FocusSettings(defaults: store).migrateIfNeeded(hasSelection: false)
        let later = FocusSettings(defaults: store)
        later.migrateIfNeeded(hasSelection: true)
        XCTAssertFalse(later.hasCompletedOnboarding)
    }
    func testLastFilterRefusalRoundTrips() {
        let store = defaults(), time = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(FocusSettings(defaults: store).lastFilterRefusal)
        FocusSettings(defaults: store).recordFilterRefusal(.busy, at: time)
        let loaded = FocusSettings(defaults: store)
        XCTAssertEqual(loaded.lastFilterRefusal?.reason, .busy); XCTAssertEqual(loaded.lastFilterRefusal?.at, time)
        loaded.clearFilterRefusal()
        XCTAssertNil(loaded.lastFilterRefusal); XCTAssertNil(FocusSettings(defaults: store).lastFilterRefusal)
    }
    func testPendingCompletionIsTakenOnce() {
        let store = defaults(), id = UUID()
        FocusSettings(defaults: store).recordPendingCompletion(id: id, length: 2400)
        let settings = FocusSettings(defaults: store)
        XCTAssertEqual(settings.pendingCompletion?.id, id)
        let taken = settings.takePendingCompletion()
        XCTAssertEqual(taken?.id, id); XCTAssertEqual(taken?.length, 2400)
        XCTAssertNil(settings.takePendingCompletion()); XCTAssertNil(FocusSettings(defaults: store).pendingCompletion)
    }
}
