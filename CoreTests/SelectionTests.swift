import XCTest
@testable import FocusCore
final class SelectionTests: XCTestCase {
    func testRejectsEmptySelection() { XCTAssertThrowsError(try SelectionValidator.validate(appCount: 0, webCount: 0, categoryCount: 0)) { XCTAssertEqual($0 as? SelectionIssue, .empty) } }
    func testAcceptsIndividualAppsAndWebsites() throws {
        for counts in [(1,0),(0,1),(50,50)] { try SelectionValidator.validate(appCount: counts.0, webCount: counts.1, categoryCount: 0) }
    }
    func testRejects51Apps() { XCTAssertThrowsError(try SelectionValidator.validate(appCount: 51, webCount: 0, categoryCount: 0)) { XCTAssertEqual($0 as? SelectionIssue, .tooManyApps) } }
    func testRejects51Websites() { XCTAssertThrowsError(try SelectionValidator.validate(appCount: 0, webCount: 51, categoryCount: 0)) { XCTAssertEqual($0 as? SelectionIssue, .tooManyWebsites) } }
    func testRejectsCategoriesEvenWithIndividualSelection() { XCTAssertThrowsError(try SelectionValidator.validate(appCount: 1, webCount: 1, categoryCount: 1)) { XCTAssertEqual($0 as? SelectionIssue, .categoriesUnsupported) } }
}
