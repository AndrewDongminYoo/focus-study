import XCTest
@testable import FocusCore
final class SelectionTests: XCTestCase {
    func testRejectsEmptySelection() { XCTAssertThrowsError(try SelectionValidator.validate(appCount: 0, webCount: 0, categoryCount: 0)) { XCTAssertEqual($0 as? SelectionIssue, .empty) } }
    func testAcceptsIndividualAppsAndWebsites() throws {
        for counts in [(1,0),(0,1),(50,50)] { try SelectionValidator.validate(appCount: counts.0, webCount: counts.1, categoryCount: 0) }
    }
    func testRejects51Apps() { XCTAssertThrowsError(try SelectionValidator.validate(appCount: 51, webCount: 0, categoryCount: 0)) { XCTAssertEqual($0 as? SelectionIssue, .tooManyApps) } }
    func testRejects51Websites() { XCTAssertThrowsError(try SelectionValidator.validate(appCount: 0, webCount: 51, categoryCount: 0)) { XCTAssertEqual($0 as? SelectionIssue, .tooManyWebsites) } }
    func testUnionOfBothSelectionsIsLimitedTo50AppsAnd50Websites() throws {
        // The caller counts distinct tokens: 49 + 2 distinct apps are 51, and 50 + 50 equal apps are 50.
        XCTAssertThrowsError(try SelectionValidator.validateUnion(apps: 49 + 2, websites: 0)) { XCTAssertEqual($0 as? SelectionIssue, .tooManyApps) }
        XCTAssertThrowsError(try SelectionValidator.validateUnion(apps: 0, websites: 51)) { XCTAssertEqual($0 as? SelectionIssue, .tooManyWebsites) }
        try SelectionValidator.validateUnion(apps: 50, websites: 50)
        try SelectionValidator.validateUnion(apps: 0, websites: 0)
    }
    func testRejectsCategoriesEvenWithIndividualSelection() { XCTAssertThrowsError(try SelectionValidator.validate(appCount: 1, webCount: 1, categoryCount: 1)) { XCTAssertEqual($0 as? SelectionIssue, .categoriesUnsupported) } }
}
