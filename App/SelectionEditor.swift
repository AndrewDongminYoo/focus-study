import SwiftUI
import FamilyControls

struct SelectionEditor: View {
    let model: FocusModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FamilyActivitySelection
    @State private var issue: String?
    init(model: FocusModel) { self.model = model; _draft = State(initialValue: model.services.selection.selection) }
    var body: some View {
        NavigationStack {
            VStack {
                SelectionSummary(appCount: draft.applicationTokens.count, websiteCount: draft.webDomainTokens.count)
                FamilyActivityPicker(selection: $draft)
                if let issue { Text(issue).foregroundStyle(.red).padding() }
            }
            .navigationTitle("집중할 동안 제한")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() }.accessibilityIdentifier("pickerCancel") }
                ToolbarItem(placement: .confirmationAction) { Button("저장") {
                    do { try model.saveSelection(draft); dismiss() }
                    catch { issue = SelectionFeedback.message(for: error) }
                }.disabled(SelectionFeedback.draftIssue(appCount: draft.applicationTokens.count, websiteCount: draft.webDomainTokens.count) != nil).accessibilityIdentifier("pickerSave") }
            }
        }
    }
}
private struct SelectionSummary: View {
    let appCount: Int
    let websiteCount: Int
    var body: some View {
        VStack(spacing: 8) {
            Text("앱 \(appCount)개 · 웹사이트 \(websiteCount)개 선택")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .accessibilityIdentifier("selectionCounts")
            Text("앱·웹사이트 각각 최대 50개. 카테고리 전체 선택도 가능합니다.").font(.footnote)
            if let draftIssue = SelectionFeedback.draftIssue(appCount: appCount, websiteCount: websiteCount) {
                Label(draftIssue, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red).accessibilityIdentifier("selectionIssue")
            }
        }.padding()
    }
}
#if DEBUG
struct FixtureSelectionEditor: View {
    let repository: FixtureSelection
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Bool
    init(repository: FixtureSelection) { self.repository = repository; _selected = State(initialValue: repository.selected) }
    var body: some View {
        NavigationStack {
            Form {
                SelectionSummary(appCount: selected ? 1 : 0, websiteCount: 0)
                Text("합성 선택 데이터")
                Button("샘플 선택") { selected = true }.accessibilityIdentifier("fixtureSelect")
                Button("선택 지우기") { selected = false }.accessibilityIdentifier("fixtureClear")
            }.toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() }.accessibilityIdentifier("pickerCancel") }
                ToolbarItem(placement: .confirmationAction) { Button("저장") { repository.selected = selected; dismiss() }.disabled(SelectionFeedback.draftIssue(appCount: selected ? 1 : 0, websiteCount: 0) != nil).accessibilityIdentifier("pickerSave") }
            }
        }
    }
}
#endif
