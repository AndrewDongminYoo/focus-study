import XCTest
@testable import FocusReportLogic
final class UsageSummaryTests: XCTestCase {
    func testEmptyReportIsUnavailableNotZeroClaim() { XCTAssertNil(UsageSummary(durations: []).total) }
    func testSyntheticDurationsSum() { XCTAssertEqual(UsageSummary(durations: [60, 120]).total, 180) }
    func testActualZeroDiffersFromMissingData() { XCTAssertEqual(UsageSummary(durations: [0]).total, 0) }
    func testGroupsRepeatedSyntheticItemsAcrossSegments() {
        let grouped = UsageSummary.grouped([(key: "A", duration: 60.0), (key: "B", duration: 30.0), (key: "A", duration: 120.0)])
        XCTAssertEqual(grouped["A"], 180); XCTAssertEqual(grouped["B"], 30)
    }
}
