import XCTest
@testable import FocusCore
final class FocusLengthTests: XCTestCase {
    func testAllowedLengthsAre25To50InFiveMinuteSteps() {
        XCTAssertEqual(FocusLength.allowedMinutes, [25, 30, 35, 40, 45, 50])
        XCTAssertEqual(FocusLength.defaultMinutes, 25)
        XCTAssertTrue(FocusLength.isAllowed(seconds: 3000)); XCTAssertFalse(FocusLength.isAllowed(seconds: 1560))
    }
}
