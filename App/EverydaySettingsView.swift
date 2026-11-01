import SwiftUI
import FamilyControls

/// The everyday layer, opened from the settings sheet. The timer screen does not show it.
struct EverydaySettingsView: View {
    @State private var settings: EverydaySettingsModel
    @State private var picker = false
    @State private var loaded = false
    @State private var choosingWindow = false
    init(model: FocusModel) { _settings = State(initialValue: EverydaySettingsModel(focus: model)) }
    var body: some View {
        Form {
            Section {
                Text(EverydaySettingsModel.statusLine(settings.status, calendar: settings.focus.services.engine.calendar)).accessibilityIdentifier("everydayStatus")
            }
            Section {
                Toggle("매일 제한 켜기", isOn: $settings.draft.enabled).accessibilityIdentifier("everydayToggle")
                TimeField(title: "제한 시작", minutes: $settings.draft.rangeStart).accessibilityIdentifier("everydayRangeStart")
                TimeField(title: "제한 끝", minutes: $settings.draft.rangeEnd).accessibilityIdentifier("everydayRangeEnd")
            } header: { Text("제한 시간") } footer: { Text("매일 이 시간에 고른 앱과 웹사이트를 제한해요. 앱을 열지 않아도 돼요.") }
            Section {
                ForEach(Array(settings.draft.windows.enumerated()), id: \.offset) { index, window in
                    VStack(alignment: .leading) {
                        HStack {
                            Text(EverydaySettingsModel.label(window.kind))
                            Spacer()
                            Button("삭제", role: .destructive) { settings.removeWindow(at: index) }.buttonStyle(.borderless)
                        }
                        TimeField(title: "시작", minutes: windowBinding(index, \.start))
                        TimeField(title: "끝", minutes: windowBinding(index, \.end))
                    }.accessibilityElement(children: .contain).accessibilityIdentifier("everydayWindow.\(index + 1)")
                }
                Button("시간 추가하기") { choosingWindow = true }.disabled(!settings.canAddWindow).accessibilityIdentifier("everydayAddWindow")
                    .confirmationDialog("시간 추가하기", isPresented: $choosingWindow, titleVisibility: .visible) {
                        ForEach(EverydayWindowKind.allCases, id: \.self) { kind in
                            Button(kind == .custom ? "직접 정하기" : EverydaySettingsModel.label(kind)) { settings.addWindow(kind) }
                        }
                        Button("닫기", role: .cancel) {}
                    }
            } header: { Text("잠시 풀어 두는 시간") } footer: { Text("점심이나 등하교처럼 제한을 풀어 둘 시간을 3개까지 정할 수 있어요. 한 번에 15분에서 2시간까지예요.") }
            Section {
                Button { picker = true } label: {
                    HStack {
                        Text("제한할 앱")
                        Spacer()
                        Text("앱 \(settings.counts.apps)개 · 웹사이트 \(settings.counts.websites)개").foregroundStyle(.secondary).monospacedDigit()
                    }
                }.accessibilityIdentifier("everydaySelection")
            } footer: { Text("집중 시간에 제한할 앱과 따로 골라요.") }
            Section {
                Button("저장") { settings.save() }.disabled(!settings.canEdit).accessibilityIdentifier("everydaySave")
                if let message = settings.refusalMessage {
                    Text(message).foregroundStyle(.red).accessibilityIdentifier("everydayRefusal")
                } else if !settings.canEdit {
                    Text(SelectionFeedback.message(for: ControlIssue.busy)).foregroundStyle(.secondary)
                } else if let issue = settings.draftIssue {
                    Text(issue).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("매일 제한").navigationBarTitleDisplayMode(.inline)
        .onAppear { if !loaded { loaded = true; settings.refresh() } }
        // FocusView's foreground, day, time zone, clock and access refreshes run their lock section first, then change this value.
        .onChange(of: settings.focus.everydayStatus) { _, _ in settings.refreshStatus() }
        // While the screen stays open, a range or window boundary changes the status without any lock section of the app.
        .task(id: settings.status) {
            await EverydaySettingsModel.followStatus({ settings.status }, now: settings.clock) { settings.refreshStatus() }
        }
        .sheet(isPresented: $picker) { selectionEditor }
    }
    @ViewBuilder private var selectionEditor: some View {
        #if DEBUG
        if settings.focus.services.isFixture { FixtureEverydaySelectionEditor(settings: settings) } else { systemPicker(for: $settings.draftSelection) }
        #else
        systemPicker(for: $settings.draftSelection)
        #endif
    }
    private func systemPicker(for selection: Binding<FamilyActivitySelection>) -> some View {
        NavigationStack {
            FamilyActivityPicker(selection: selection)
                .navigationTitle("매일 제한할 앱").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { picker = false }.accessibilityIdentifier("pickerSave") } }
        }
    }
    private func windowBinding(_ index: Int, _ key: WritableKeyPath<EverydayWindow, Int>) -> Binding<Int> {
        Binding(get: { settings.draft.windows.indices.contains(index) ? settings.draft.windows[index][keyPath: key] : 0 },
                set: { if settings.draft.windows.indices.contains(index) { settings.draft.windows[index][keyPath: key] = $0 } })
    }
}
/// A wall-clock time on the 5-minute grid, stored as minutes after midnight.
private struct TimeField: View {
    let title: String
    @Binding var minutes: Int
    var body: some View {
        DatePicker(title, selection: Binding(get: {
            Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            let value = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            minutes = min(EverydaySchedule.latestRangeEnd, (value + EverydaySchedule.grid / 2) / EverydaySchedule.grid * EverydaySchedule.grid)
        }), displayedComponents: .hourAndMinute)
    }
}
#if DEBUG
/// Synthetic selection for UI tests; it never opens the system picker.
private struct FixtureEverydaySelectionEditor: View {
    let settings: EverydaySettingsModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Text("합성 선택 데이터")
                Button("샘플 선택") { settings.draftSelection = FixtureEverydayLayer.sampleSelection() }.accessibilityIdentifier("fixtureSelect")
                Button("선택 지우기") { settings.draftSelection = FamilyActivitySelection(includeEntireCategory: true) }.accessibilityIdentifier("fixtureClear")
            }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() }.accessibilityIdentifier("pickerSave") } }
        }
    }
}
#endif
