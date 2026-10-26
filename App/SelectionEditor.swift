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
                Text("개별 앱과 웹사이트를 각각 최대 50개까지 선택해 주세요. 카테고리는 지원하지 않습니다.").font(.footnote).padding()
                FamilyActivityPicker(selection: $draft)
                if let issue { Text(issue).foregroundStyle(.red).padding() }
            }
            .navigationTitle("집중할 동안 제한")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() }.accessibilityIdentifier("pickerCancel") }
                ToolbarItem(placement: .confirmationAction) { Button("저장") {
                    do { try model.saveSelection(draft); dismiss() }
                    catch { issue = "개별 앱이나 웹사이트를 1개 이상, 각각 50개 이하로 선택해 주세요." }
                }.accessibilityIdentifier("pickerSave") }
            }
        }
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
                Text("합성 선택 데이터")
                Button("샘플 선택") { selected = true }.accessibilityIdentifier("fixtureSelect")
                Button("선택 지우기") { selected = false }.accessibilityIdentifier("fixtureClear")
            }.toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() }.accessibilityIdentifier("pickerCancel") }
                ToolbarItem(placement: .confirmationAction) { Button("저장") { repository.selected = selected; dismiss() }.accessibilityIdentifier("pickerSave") }
            }
        }
    }
}
#endif
