import XCTest

final class SelectionFeedbackTests: XCTestCase {
    func testDraftIssueFollowsTheFiftyItemBoundary() {
        XCTAssertNil(SelectionFeedback.draftIssue(appCount: 50, websiteCount: 50))
        XCTAssertEqual(SelectionFeedback.draftIssue(appCount: 51, websiteCount: 0), "앱은 50개까지 선택할 수 있어요.")
        XCTAssertEqual(SelectionFeedback.draftIssue(appCount: 0, websiteCount: 51), "웹사이트는 50개까지 선택할 수 있어요.")
        XCTAssertEqual(SelectionFeedback.draftIssue(appCount: 0, websiteCount: 0), "앱이나 웹사이트를 1개 이상 선택해 주세요.")
    }
    func testSaveFailuresAreNotReportedAsSelectionCountProblems() {
        XCTAssertEqual(SelectionFeedback.message(for: ControlIssue.busy), "집중 시간이 끝난 뒤에 바꿀 수 있어요.")
        let other = "선택 항목을 저장하지 못했어요. 다시 저장해 주세요."
        XCTAssertEqual(SelectionFeedback.message(for: CocoaError(.fileWriteNoPermission)), other)
        XCTAssertEqual(SelectionFeedback.message(for: SelectionIssue.categoriesUnsupported), other)
    }
}
