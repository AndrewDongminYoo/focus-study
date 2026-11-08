import SwiftUI

/// Personal settings opened from the timer screen's top-right button, or with the everyday screen pushed from the timer screen's everyday status row.
struct SettingsView: View {
    let model: FocusModel
    @Environment(\.dismiss) private var dismiss
    @State private var everydayHasChanges = false
    @State private var confirmingDiscard = false
    @State private var path: [SettingsRoute]
    init(model: FocusModel, opensEveryday: Bool = false) {
        self.model = model
        _path = State(initialValue: opensEveryday ? [.everyday] : [])
    }
    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    Picker("집중 시간", selection: Binding(get: { model.services.settings.lengthMinutes }, set: { model.services.settings.lengthMinutes = $0 })) {
                        ForEach(FocusLength.allowedMinutes, id: \.self) { Text("\($0)분").tag($0) }
                    }.pickerStyle(.menu).accessibilityIdentifier("lengthPicker")
                } header: { Text("집중 시간") } footer: { Text("바꾼 시간은 다음 집중부터 적용돼요.") }
                Section {
                    NavigationLink {
                        everydayScreen
                    } label: {
                        VStack(alignment: .leading, spacing: FocusTheme.Layout.detailSpacing) {
                            Text("시간과 앱 정하기")
                            Text(EverydaySettingsModel.statusLine(model.everydayStatus, calendar: model.services.engine.calendar)).font(.footnote).foregroundStyle(FocusTheme.Palette.secondaryText)
                        }
                    }.accessibilityIdentifier("everydayRow")
                } header: { Text("매일 제한") } footer: { Text("정한 시간대에 매일 앱과 웹사이트를 제한해요.") }
                Section {
                    NavigationLink("집중 모드 연결") { FocusGuideView(settings: model.services.settings) }.accessibilityIdentifier("focusGuideRow")
                } header: { Text("집중 모드") } footer: { Text("iOS 집중 모드를 켤 때 집중도 함께 시작할 수 있어요.") }
                #if DEBUG
                if let diagnostics = model.services.diagnostics {
                    DeviceDiagnosticsSection(diagnostics: diagnostics, model: model, filterHandler: try? FocusRuntime.process().holder.filterHandler(), readFilter: FocusStudyFilter.reading)
                }
                #endif
            }
            .contentMargins(.horizontal, FocusTheme.Layout.screenInset, for: .scrollContent)
            .navigationTitle("설정").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsRoute.self) { _ in everydayScreen }
            .onAppear { model.refreshEveryday() }
            // The row's status changes at a range or window boundary while the sheet stays open, also with no focus tick.
            .task(id: model.everydayStatus) {
                await EverydaySettingsModel.followStatus({ model.everydayStatus }, now: Date.init) { model.refreshEveryday() }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { finish(everydayHasChanges) }.accessibilityIdentifier("settingsDone")
                }
            }
        }
        .modifier(FocusEditorSheet())
        .interactiveDismissDisabled(everydayHasChanges)
        .alert("변경 사항을 버릴까요?", isPresented: $confirmingDiscard) {
            Button("변경 버리기", role: .destructive) { dismiss() }
            Button("계속 편집", role: .cancel) {}
        } message: { Text("저장하지 않은 변경은 사라져요.") }
    }
    /// One builder for the settings row and the timer's status row, so both keep the same unsaved-changes and finish handling.
    private var everydayScreen: some View {
        EverydaySettingsView(model: model, onUnsavedChanges: { everydayHasChanges = $0 }, onFinish: finish)
    }
    private func finish(_ hasChanges: Bool) {
        everydayHasChanges = hasChanges
        if hasChanges { confirmingDiscard = true }
        else { dismiss() }
    }
}
/// The one screen that the timer can open already pushed.
private enum SettingsRoute: Hashable { case everyday }
