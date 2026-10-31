import Foundation

/// Copy for draft validation before saving and for save failures; the repository validates again when it writes.
enum SelectionFeedback {
    static func draftIssue(appCount: Int, websiteCount: Int) -> String? {
        do { try SelectionValidator.validate(appCount: appCount, webCount: websiteCount, categoryCount: 0); return nil }
        catch { return message(for: error) }
    }
    static func message(for error: Error) -> String {
        switch error {
        case SelectionIssue.empty: "앱이나 웹사이트를 1개 이상 선택해 주세요."
        case SelectionIssue.tooManyApps: "앱은 50개까지 선택할 수 있어요."
        case SelectionIssue.tooManyWebsites: "웹사이트는 50개까지 선택할 수 있어요."
        case ControlIssue.busy: "집중 시간이 끝난 뒤에 바꿀 수 있어요."
        case let cocoa as CocoaError where cocoa.code == .fileWriteOutOfSpace: "기기 저장 공간이 부족해요. 공간을 확보한 뒤 다시 저장해 주세요."
        default: "선택 항목을 저장하지 못했어요. 다시 저장해 주세요."
        }
    }
}
