import XCTest
@testable import FocusReportLogic
final class UsageSummaryTests: XCTestCase {
    func testEmptyReportIsUnavailableNotZeroClaim() { XCTAssertNil(UsageSummary(durations: []).total) }
    func testSyntheticDurationsSum() { XCTAssertEqual(UsageSummary(durations: [60, 120]).total, 180) }
    func testActualZeroDiffersFromMissingData() { XCTAssertEqual(UsageSummary(durations: [0]).total, 0) }
}
