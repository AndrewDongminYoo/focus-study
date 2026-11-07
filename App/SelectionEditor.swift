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
                SelectionBrowserNote().padding(.horizontal, FocusTheme.Layout.screenInset)
                if let issue { Label(issue, systemImage: "exclamationmark.circle").foregroundStyle(FocusTheme.Palette.error).padding(FocusTheme.Layout.screenInset) }
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
        .modifier(FocusEditorSheet())
    }
}
private struct SelectionSummary: View {
    let appCount: Int
    let websiteCount: Int
    var body: some View {
        VStack(spacing: FocusTheme.Layout.inlineSpacing) {
            Text("앱 \(appCount)개 · 웹사이트 \(websiteCount)개 선택")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .accessibilityIdentifier("selectionCounts")
            Text("앱과 웹사이트는 각각 50개까지 고를 수 있어요. 카테고리 전체를 골라도 돼요.").font(.footnote)
            if let draftIssue = SelectionFeedback.draftIssue(appCount: appCount, websiteCount: websiteCount) {
                Label(draftIssue, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(FocusTheme.Palette.error).accessibilityIdentifier("selectionIssue")
            }
        }.padding(FocusTheme.Layout.screenInset)
    }
}
/// Footer copy below the selection, so it does not read as a tappable row.
private struct SelectionBrowserNote: View {
    var body: some View {
        Text("웹사이트 전체를 제한해요. 브라우저에 따라 제한되지 않을 수 있어요.").font(.footnote).foregroundStyle(FocusTheme.Palette.secondaryText)
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
                Section { SelectionSummary(appCount: selected ? 1 : 0, websiteCount: 0) } footer: { SelectionBrowserNote() }
                Text("합성 선택 데이터")
                Button("샘플 선택") { selected = true }.accessibilityIdentifier("fixtureSelect")
                Button("선택 지우기") { selected = false }.accessibilityIdentifier("fixtureClear")
            }.toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() }.accessibilityIdentifier("pickerCancel") }
                ToolbarItem(placement: .confirmationAction) { Button("저장") { repository.selected = selected; dismiss() }.disabled(SelectionFeedback.draftIssue(appCount: selected ? 1 : 0, websiteCount: 0) != nil).accessibilityIdentifier("pickerSave") }
            }
        }
        .modifier(FocusEditorSheet())
    }
}
#endif
