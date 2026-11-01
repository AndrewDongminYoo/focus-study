import XCTest
import FamilyControls

final class SelectionFeedbackTests: XCTestCase {
    func testDraftIssueFollowsTheFiftyItemBoundary() {
        XCTAssertNil(SelectionFeedback.draftIssue(appCount: 50, websiteCount: 50))
        XCTAssertEqual(SelectionFeedback.draftIssue(appCount: 51, websiteCount: 0), "앱은 50개까지 선택할 수 있어요.")
        XCTAssertEqual(SelectionFeedback.draftIssue(appCount: 0, websiteCount: 51), "웹사이트는 50개까지 선택할 수 있어요.")
        XCTAssertEqual(SelectionFeedback.draftIssue(appCount: 0, websiteCount: 0), "앱이나 웹사이트를 1개 이상 선택해 주세요.")
    }
    func testUnionLimitMessage() throws {
        var focus = FamilyActivitySelection(), everyday = FamilyActivitySelection()
        focus.applicationTokens = syntheticApps(0..<49); everyday.applicationTokens = syntheticApps(49..<51)
        XCTAssertThrowsError(try SelectionFeedback.validateUnion(focus, everyday)) {
            XCTAssertEqual(SelectionFeedback.message(for: $0), "집중 시간과 매일 제한을 합쳐 앱은 50개까지 고를 수 있어요.")
        }
        everyday.applicationTokens = syntheticApps(0..<50)
        XCTAssertNoThrow(try SelectionFeedback.validateUnion(focus, everyday))
        XCTAssertNoThrow(try SelectionFeedback.validateUnion(focus, nil))
        XCTAssertEqual(SelectionFeedback.message(for: SelectionUnionLimit(issue: .tooManyWebsites)), "집중 시간과 매일 제한을 합쳐 웹사이트는 50개까지 고를 수 있어요.")
    }
    func testSaveFailuresAreNotReportedAsSelectionCountProblems() {
        XCTAssertEqual(SelectionFeedback.message(for: ControlIssue.busy), "집중 시간이 끝난 뒤에 바꿀 수 있어요.")
        let other = "선택 항목을 저장하지 못했어요. 다시 저장해 주세요."
        XCTAssertEqual(SelectionFeedback.message(for: CocoaError(.fileWriteOutOfSpace)), "기기 저장 공간이 부족해요. 공간을 확보한 뒤 다시 저장해 주세요.")
        XCTAssertEqual(SelectionFeedback.message(for: NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteOutOfSpace.rawValue)), "기기 저장 공간이 부족해요. 공간을 확보한 뒤 다시 저장해 주세요.")
        XCTAssertEqual(SelectionFeedback.message(for: CocoaError(.fileWriteNoPermission)), other)
        XCTAssertEqual(SelectionFeedback.message(for: SelectionIssue.categoriesUnsupported), other)
    }
}
