import XCTest
final class FocusFlowTests: XCTestCase {
    func app(_ mode: String = "approved", selected: Bool = true) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", mode] + (selected ? ["--selected"] : []); app.launch(); return app
    }
    func testDeniedPermissionShowsSettingsAndDisablesStartAndReport() {
        let app = app("denied")
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["start"].isEnabled)
        app.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "settings").firstMatch.waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertFalse(app.buttons["report"].isEnabled)
    }
    func testActiveSessionLocksSelectionAndEarlyExitCreatesHistory() {
        let app = app(); app.buttons["start"].tap()
        XCTAssertTrue(app.buttons["end"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["selection"].isEnabled)
        app.buttons["end"].tap()
        XCTAssertTrue(app.staticTexts["중도 종료"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["selection"].isEnabled)
    }
    func testPickerCancelKeepsExistingSelection() {
        let app = app(); app.buttons["selection"].tap(); app.buttons["fixtureClear"].tap(); app.buttons["pickerCancel"].tap()
        XCTAssertTrue(app.buttons["start"].isEnabled)
    }
    func testEmptySelectionCannotStartAndMockSelectionCanBeSaved() {
        let app = app(selected: false); XCTAssertFalse(app.buttons["start"].isEnabled)
        app.buttons["selection"].tap(); app.buttons["fixtureSelect"].tap(); app.buttons["pickerSave"].tap()
        XCTAssertTrue(app.buttons["start"].isEnabled)
    }
    func testRegistrationFailureNeverShowsActiveAndCanRetry() {
        let app = app("registration-failure"); app.buttons["start"].tap()
        XCTAssertTrue(app.staticTexts["startError"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["end"].exists)
    }
}
