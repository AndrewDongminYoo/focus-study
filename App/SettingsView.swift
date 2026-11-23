import SwiftUI
#if DEBUG
import FamilyControls
#endif

/// Personal settings opened from the timer screen's top-right button, or with the everyday screen pushed from the timer screen's everyday status row.
struct SettingsView: View {
    let model: FocusModel
    @Environment(\.dismiss) private var dismiss
    /// The everyday screen's unsaved draft blocks the swipe-down; its own back button asks before the draft goes.
    @State private var everydayHasChanges = false
    @State private var path: [SettingsRoute]
    #if DEBUG
    @State private var diagnosticEverydayPicker = false
    @State private var diagnosticEverydayDraft = FamilyActivitySelection(includeEntireCategory: true)
    #endif
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
                            Text(EverydaySettingsModel.statusLine(model.everydayStatus, at: model.everydayReadAt ?? Date(), calendar: model.services.engine.calendar)).font(.footnote).foregroundStyle(FocusTheme.Palette.secondaryText)
                        }
                    }.accessibilityIdentifier("everydayRow")
                } header: { Text("매일 제한") } footer: { Text("정한 시간대에 매일 앱과 웹사이트를 제한해요.") }
                Section {
                    NavigationLink("집중 모드 연결") { FocusGuideView(settings: model.services.settings) }.accessibilityIdentifier("focusGuideRow")
                } header: { Text("집중 모드") } footer: { Text("iOS 집중 모드를 켤 때 집중도 함께 시작할 수 있어요.") }
                #if DEBUG
                if let diagnostics = model.services.diagnostics {
                    DeviceDiagnosticsSection(diagnostics: diagnostics, model: model, filterHandler: try? FocusRuntime.process().holder.filterHandler(),
                                             readFilter: FocusStudyFilter.reading, openEverydayPicker: { diagnosticEverydayPicker = true })
                }
                #endif
            }
            .contentMargins(.horizontal, FocusTheme.Layout.screenInset, for: .scrollContent)
            .navigationTitle("설정").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsRoute.self) { _ in everydayScreen }
            .onAppear { model.refreshEveryday() }
            // The row's status changes at a range or window boundary while the sheet stays open, also with no focus tick,
            // and its day word changes at local midnight.
            .task(id: model.everydayStatus) {
                await EverydaySettingsModel.followStatus({ model.everydayStatus }, now: Date.init, dayWordCalendar: model.services.engine.calendar) {
                    model.refreshEveryday()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }.accessibilityIdentifier("settingsDone")
                }
            }
        }
        #if DEBUG
        // A sheet on the diagnostics Form section can trigger overlapping presentations from its rows.
        .sheet(isPresented: $diagnosticEverydayPicker) {
            NavigationStack {
                FamilyActivityPicker(selection: $diagnosticEverydayDraft)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("닫기") { diagnosticEverydayPicker = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("적용") {
                                model.services.diagnostics?.applyEverydayWithoutUnionCheck(diagnosticEverydayDraft)
                                diagnosticEverydayPicker = false
                            }
                        }
                    }
            }
            .modifier(FocusEditorSheet())
        }
        #endif
        .modifier(FocusEditorSheet())
        .interactiveDismissDisabled(everydayHasChanges)
    }
    /// One builder for the settings row and the timer's status row, so both keep the same unsaved-changes handling.
    private var everydayScreen: some View {
        EverydaySettingsView(model: model, onUnsavedChanges: { everydayHasChanges = $0 })
    }
}
/// The one screen that the timer can open already pushed.
private enum SettingsRoute: Hashable { case everyday }
