import Foundation
import FamilyControls

/// A save that would make both selections together exceed the shield limit.
struct SelectionUnionLimit: Error, Equatable { let issue: SelectionIssue }
/// Copy for draft validation before saving and for save failures; the repository validates again when it writes.
enum SelectionFeedback {
    /// Counts the distinct tokens of both selections; `SelectionUnionLimit` names which limit was passed.
    static func validateUnion(_ selection: FamilyActivitySelection, _ other: FamilyActivitySelection?) throws {
        do {
            try SelectionValidator.validateUnion(apps: selection.applicationTokens.union(other?.applicationTokens ?? []).count,
                                                 websites: selection.webDomainTokens.union(other?.webDomainTokens ?? []).count)
        } catch let issue as SelectionIssue { throw SelectionUnionLimit(issue: issue) }
    }
    static func draftIssue(appCount: Int, websiteCount: Int) -> String? {
        do { try SelectionValidator.validate(appCount: appCount, webCount: websiteCount, categoryCount: 0); return nil }
        catch { return message(for: error) }
    }
    static func message(for error: Error) -> String {
        switch error {
        case SelectionIssue.empty: "앱이나 웹사이트를 1개 이상 선택해 주세요."
        case SelectionIssue.tooManyApps: "앱은 50개까지 선택할 수 있어요."
        case SelectionIssue.tooManyWebsites: "웹사이트는 50개까지 선택할 수 있어요."
        case let union as SelectionUnionLimit where union.issue == .tooManyApps: "집중 시간과 매일 제한을 합쳐 앱은 50개까지 고를 수 있어요."
        case let union as SelectionUnionLimit where union.issue == .tooManyWebsites: "집중 시간과 매일 제한을 합쳐 웹사이트는 50개까지 고를 수 있어요."
        case ControlIssue.busy: "집중 시간이 끝난 뒤에 바꿀 수 있어요."
        case let cocoa as CocoaError where cocoa.code == .fileWriteOutOfSpace: "기기 저장 공간이 부족해요. 공간을 확보한 뒤 다시 저장해 주세요."
        default: "선택 항목을 저장하지 못했어요. 다시 저장해 주세요."
        }
    }
}
