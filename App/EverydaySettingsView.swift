import SwiftUI
import FamilyControls

/// The everyday layer, opened from the settings sheet. The timer screen does not show it.
struct EverydaySettingsView: View {
    @State private var settings: EverydaySettingsModel
    @State private var picker = false
    @State private var loaded = false
    @State private var choosingWindow = false
    @State private var confirmingDiscard = false
    @State private var saveFeedback = 0
    @ScaledMetric(relativeTo: .footnote) private var saveStatusHeight = FocusTheme.Layout.minimumTapTarget
    @Environment(\.dismiss) private var dismiss
    private let onUnsavedChanges: (Bool) -> Void
    private let onFinish: ((Bool) -> Void)?
    init(model: FocusModel, onUnsavedChanges: @escaping (Bool) -> Void = { _ in }, onFinish: ((Bool) -> Void)? = nil) {
        _settings = State(initialValue: EverydaySettingsModel(focus: model))
        self.onUnsavedChanges = onUnsavedChanges
        self.onFinish = onFinish
    }
    var body: some View {
        Form {
            Section {
                Text(EverydaySettingsModel.statusLine(settings.status, calendar: settings.focus.services.engine.calendar)).accessibilityIdentifier("everydayStatus")
                if let message = settings.strictOnlyMessage {
                    Text(message).font(.footnote).foregroundStyle(FocusTheme.Palette.secondaryText).accessibilityIdentifier("everydayStrictOnly")
                }
            } header: { Text("저장된 상태") }
            Section {
                Toggle("매일 제한 켜기", isOn: $settings.draft.enabled).accessibilityIdentifier("everydayToggle")
                TimeField(title: "제한 시작", minutes: $settings.draft.rangeStart).accessibilityIdentifier("everydayRangeStart")
                TimeField(title: "제한 끝", minutes: $settings.draft.rangeEnd).accessibilityIdentifier("everydayRangeEnd")
                if let issue = settings.rangeIssue { Text(issue).foregroundStyle(FocusTheme.Palette.error).accessibilityIdentifier("everydayRangeIssue") }
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
                if let issue = settings.windowsIssue { Text(issue).foregroundStyle(FocusTheme.Palette.error).accessibilityIdentifier("everydayWindowsIssue") }
            } header: { Text("잠시 풀어 두는 시간") } footer: { Text("점심이나 등하교처럼 제한을 풀어 둘 시간을 3개까지 정할 수 있어요. 한 번에 15분에서 2시간까지예요.") }
            Section {
                Button { picker = true } label: {
                    HStack {
                        Text("제한할 앱")
                        Spacer()
                        Text("앱 \(settings.counts.apps)개 · 웹사이트 \(settings.counts.websites)개").foregroundStyle(FocusTheme.Palette.secondaryText).monospacedDigit()
                    }
                }.accessibilityIdentifier("everydaySelection")
                if let issue = settings.selectionIssue { Text(issue).foregroundStyle(FocusTheme.Palette.error).accessibilityIdentifier("everydaySelectionIssue") }
            } footer: { Text("집중 시간에 제한할 앱과 따로 골라요.") }
            Section {
                schedulePreview(settings.draft, prefix: "everydayDraft")
                DisclosureGroup("저장된 일정") {
                    if let schedule = settings.status?.schedule {
                        schedulePreview(schedule, prefix: "everydayStored")
                    } else {
                        Text(settings.status?.issue == nil ? "저장된 일정이 없어요." : "저장된 일정을 확인하지 못했어요.")
                            .accessibilityIdentifier("everydayStoredUnavailable")
                    }
                }
            } header: { Text("일정 미리보기") } footer: {
                Text("편집 중인 일정이에요. 저장하면 매일 반복해요. 제한 시간 밖에는 매일 제한이 꺼져요. 집중 시간의 제한은 따로 적용해요.")
            }
        }
        .contentMargins(.horizontal, FocusTheme.Layout.screenInset, for: .scrollContent)
        .safeAreaInset(edge: .bottom, spacing: 0) { saveActions }
        .navigationTitle("매일 제한").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(settings.hasChanges)
        .toolbar {
            if settings.hasChanges {
                ToolbarItem(placement: .topBarLeading) {
                    Button { confirmingDiscard = true } label: { Label("뒤로", systemImage: "chevron.left") }
                        .accessibilityIdentifier("everydayBack")
                }
            }
            if let onFinish {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { onFinish(settings.hasChanges) }.accessibilityIdentifier("settingsDone")
                }
            }
        }
        .alert("변경 사항을 버릴까요?", isPresented: $confirmingDiscard) {
            Button("변경 버리기", role: .destructive) { dismiss() }
            Button("계속 편집", role: .cancel) {}
        } message: { Text("저장하지 않은 변경은 사라져요.") }
        .sensoryFeedback(.success, trigger: saveFeedback)
        .onAppear {
            if !loaded { loaded = true; settings.refresh() }
            onUnsavedChanges(settings.hasChanges)
        }
        .onChange(of: settings.hasChanges) { _, hasChanges in onUnsavedChanges(hasChanges) }
        .onDisappear { onUnsavedChanges(false) }
        // FocusView's foreground, day, time zone, clock and access refreshes run their lock section first, then change this value.
        .onChange(of: settings.focus.everydayStatus) { _, _ in settings.refreshStatus() }
        // While the screen stays open, a range or window boundary changes the status without any lock section of the app.
        .task(id: settings.status) {
            await EverydaySettingsModel.followStatus({ settings.status }, now: settings.clock) { settings.refreshStatus() }
        }
        .sheet(isPresented: $picker) { selectionEditor }
    }
    @ViewBuilder private func schedulePreview(_ schedule: EverydaySchedule, prefix: String) -> some View {
        if let segments = EverydaySettingsModel.previewSegments(for: schedule) {
            if !schedule.enabled {
                Text("매일 제한이 꺼져 있어요.").accessibilityIdentifier("\(prefix)Off")
            } else {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    let start = EverydaySettingsModel.time(segment.start), end = EverydaySettingsModel.time(segment.end)
                    let state = segment.blocked ? "제한" : "해제"
                    Text("\(start)–\(end) · \(state)")
                        .monospacedDigit().fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("\(start)부터 \(end)까지, \(state)")
                        .accessibilityIdentifier("\(prefix)Segment.\(index + 1)")
                }
            }
        } else {
            Text("시간을 확인하면 미리보기를 볼 수 있어요.")
                .foregroundStyle(FocusTheme.Palette.secondaryText).accessibilityIdentifier("\(prefix)Invalid")
        }
    }
    private var saveActions: some View {
        VStack(spacing: FocusTheme.Layout.inlineSpacing) {
            saveStatus
                .frame(maxWidth: .infinity, minHeight: saveStatusHeight, alignment: .center)
            Button {
                settings.save()
                if settings.successMessage != nil { saveFeedback += 1 }
            } label: {
                Text("저장").frame(maxWidth: .infinity)
            }.modifier(FocusPrimaryAction()).controlSize(.large).modifier(ProminentLabel())
                .disabled(!settings.canSave).accessibilityIdentifier("everydaySave")
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, FocusTheme.Layout.screenInset)
        .padding(.top, FocusTheme.Layout.relatedSpacing)
        .padding(.bottom, FocusTheme.Layout.inlineSpacing)
        .background(FocusTheme.Palette.groupedSurface)
    }
    private var saveStatus: some View {
        VStack(spacing: FocusTheme.Layout.detailSpacing) {
            if let message = settings.successMessage {
                HStack(alignment: .center, spacing: FocusTheme.Layout.inlineSpacing) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(FocusTheme.Palette.accent)
                    Text(message).foregroundStyle(FocusTheme.Palette.primaryText)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(message).accessibilityIdentifier("everydaySaveSuccess")
            }
            if settings.hasChanges {
                Text("저장하지 않은 변경이 있어요.").foregroundStyle(FocusTheme.Palette.secondaryText).accessibilityIdentifier("everydayUnsavedChanges")
            }
            if let message = settings.refusalMessage {
                Text(message).foregroundStyle(FocusTheme.Palette.error).accessibilityIdentifier("everydayRefusal")
            } else if !settings.canEdit {
                Text(SelectionFeedback.message(for: ControlIssue.busy)).foregroundStyle(FocusTheme.Palette.secondaryText)
            }
        }
        .font(.footnote)
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
        .modifier(FocusEditorSheet())
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
        .modifier(FocusEditorSheet())
    }
}
#endif
