import SwiftUI
import FamilyControls

/// The everyday layer, opened in the settings sheet from its settings row or from the timer screen's everyday status row.
struct EverydaySettingsView: View {
    @State private var settings: EverydaySettingsModel
    @State private var picker = false
    @State private var loaded = false
    @State private var choosingWindow = false
    @State private var confirmingDiscard = false
    @State private var saveFeedback = 0
    @ScaledMetric(relativeTo: .footnote) private var saveStatusHeight = FocusTheme.Layout.minimumTapTarget
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let onUnsavedChanges: (Bool) -> Void
    private let onFinish: ((Bool) -> Void)?
    init(model: FocusModel, onUnsavedChanges: @escaping (Bool) -> Void = { _ in }, onFinish: ((Bool) -> Void)? = nil) {
        _settings = State(initialValue: EverydaySettingsModel(focus: model))
        self.onUnsavedChanges = onUnsavedChanges
        self.onFinish = onFinish
    }
    var body: some View {
        // A real container, so that swapping the form for the waiting screen does not run the lifecycle modifiers below.
        ZStack {
            if settings.offWait != nil { offWaitScreen } else { form }
        }
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
        // Closing this screen or the settings sheet cancels the off-for-today wait.
        .onDisappear { onUnsavedChanges(false); settings.screenDidClose() }
        // The model decides what each phase does to the off-for-today wait.
        .onChange(of: scenePhase, initial: true) { _, value in
            switch value {
            case .active: settings.sceneDidBecomeActive()
            case .inactive: settings.sceneDidBecomeInactive()
            case .background: settings.sceneDidLeaveForeground()
            default: break
            }
        }
        .task(id: settings.offWait?.id) {
            while !Task.isCancelled, settings.offWait != nil {
                settings.tickOffWait()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        // FocusView's foreground, day, time zone, clock and access refreshes run their lock section first, then change this value.
        .onChange(of: settings.focus.everydayStatus) { _, _ in settings.refreshStatus() }
        // While the screen stays open, a range or window boundary changes the status without any lock section of the app.
        .task(id: settings.status) {
            await EverydaySettingsModel.followStatus({ settings.status }, now: settings.clock, rangeCalendar: settings.focus.services.engine.calendar) {
                settings.refreshStatus()
            }
        }
        .sheet(isPresented: $picker) { selectionEditor }
    }
    private var form: some View {
        Form {
            Section {
                Text(EverydaySettingsModel.statusLine(settings.status, calendar: settings.focus.services.engine.calendar)).accessibilityIdentifier("everydayStatus")
                if let message = settings.strictOnlyMessage {
                    Text(message).font(.footnote).foregroundStyle(FocusTheme.Palette.secondaryText).accessibilityIdentifier("everydayStrictOnly")
                }
                if settings.offersOffForToday {
                    Button("오늘만 끄기") { settings.startOffWait() }.accessibilityIdentifier("everydayOffToday")
                }
            } header: { Text("저장된 상태") }
            Section {
                Toggle("매일 제한 켜기", isOn: $settings.draft.enabled).accessibilityIdentifier("everydayToggle")
                TimeField(title: "제한 시작", minutes: $settings.draft.rangeStart).accessibilityIdentifier("everydayRangeStart")
                TimeField(title: "제한 끝", minutes: $settings.draft.rangeEnd).accessibilityIdentifier("everydayRangeEnd")
                if let issue = settings.rangeIssue { Label(issue, systemImage: "exclamationmark.circle").foregroundStyle(FocusTheme.Palette.error).accessibilityIdentifier("everydayRangeIssue") }
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
                if let issue = settings.windowsIssue { Label(issue, systemImage: "exclamationmark.circle").foregroundStyle(FocusTheme.Palette.error).accessibilityIdentifier("everydayWindowsIssue") }
            } header: { Text("잠시 풀어 두는 시간") } footer: { Text("점심이나 등하교처럼 제한을 풀어 둘 시간을 3개까지 정할 수 있어요. 한 번에 15분에서 2시간까지예요.") }
            Section {
                Button { picker = true } label: {
                    HStack {
                        Text("제한할 앱")
                        Spacer()
                        Text("앱 \(settings.counts.apps)개 · 웹사이트 \(settings.counts.websites)개").foregroundStyle(FocusTheme.Palette.secondaryText).monospacedDigit()
                    }
                }.accessibilityIdentifier("everydaySelection")
                if let issue = settings.selectionIssue { Label(issue, systemImage: "exclamationmark.circle").foregroundStyle(FocusTheme.Palette.error).accessibilityIdentifier("everydaySelectionIssue") }
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
    }
    /// The off-for-today wait, in the manner of the M2 break wait: a progress bar with the countdown and a cancel button.
    private var offWaitScreen: some View {
        let progress = settings.offWaitProgress ?? 0, left = settings.offWaitRemaining ?? 0
        let line = "\(left)초 뒤에 오늘 매일 제한이 꺼져요"
        return VStack(spacing: FocusTheme.Layout.controlSpacing) {
            Spacer(minLength: 32)
            Text(line).font(.headline).monospacedDigit()
                .padding(.vertical, FocusTheme.Layout.controlSpacing).padding(.horizontal, FocusTheme.Layout.screenInset).frame(maxWidth: .infinity)
                .background(alignment: .leading) {
                    GeometryReader { proxy in Capsule().fill(FocusTheme.Palette.progressFill).frame(width: proxy.size.width * progress) }
                }
                .background(Capsule().fill(FocusTheme.Palette.progressTrack)).clipShape(Capsule())
                .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
                .accessibilityElement(children: .ignore).accessibilityLabel(line).accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("everydayOffWait")
            Button("그대로 두기") { settings.cancelOffWait() }.frame(minHeight: FocusTheme.Layout.minimumTapTarget)
                .accessibilityIdentifier("everydayOffCancel")
            Spacer(minLength: 48)
        }
        .padding(.horizontal, FocusTheme.Layout.screenInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FocusTheme.Palette.groupedSurface)
    }
    @ViewBuilder private func schedulePreview(_ schedule: EverydaySchedule, prefix: String) -> some View {
        if let segments = EverydaySettingsModel.previewSegments(for: schedule) {
            if !schedule.enabled {
                Text("매일 제한이 꺼져 있어요.").accessibilityIdentifier("\(prefix)Off")
            } else {
                // A sibling row of the text rows, so that no container identifier masks the row identifiers below.
                EverydayDayClock(segments: segments, identifier: "\(prefix)Clock")
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
                Label(message, systemImage: "exclamationmark.circle").foregroundStyle(FocusTheme.Palette.error).accessibilityIdentifier("everydayRefusal")
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
/// The schedule preview as a clock: 24 hours as one turn, midnight at the top, clockwise.
/// A restricted interval is a thick solid arc, an unblocked interval a dashed arc of the same width, and the time outside the range a thin track.
/// The text rows below it stay the accessible alternative, so the clock is one element with a short label.
private struct EverydayDayClock: View {
    let segments: [EverydaySettingsModel.PreviewSegment]
    let identifier: String
    private static let band: CGFloat = 14
    private static let track: CGFloat = 3
    private static let maximumSide: CGFloat = 240
    /// The hour ticks run from 2 to 8 points inside the band.
    private static let tickStart: CGFloat = 2
    private static let tickEnd: CGFloat = 8
    /// From the inner edge of the band to the center of an hour label: the tick, half of "18시" at the capped size (about 19 points), and a gap.
    private static let labelInset: CGFloat = tickEnd + 19 + 5
    private static let hours = [0, 6, 12, 18]
    var body: some View {
        VStack(spacing: FocusTheme.Layout.relatedSpacing) {
            dial.aspectRatio(1, contentMode: .fit).frame(maxWidth: Self.maximumSide).frame(maxWidth: .infinity)
            legend
        }
        .padding(.vertical, FocusTheme.Layout.inlineSpacing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("하루 일정표")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier(identifier)
    }
    private var dial: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let inner = side / 2 - Self.band
            ZStack {
                Circle().stroke(FocusTheme.Palette.secondaryText.opacity(0.35), lineWidth: Self.track)
                    .frame(width: side - Self.band, height: side - Self.band)
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Circle()
                        .trim(from: EverydaySettingsModel.dayClockFraction(segment.start), to: EverydaySettingsModel.dayClockFraction(segment.end))
                        .stroke(Self.color(blocked: segment.blocked), style: Self.stroke(blocked: segment.blocked, width: Self.band))
                        .rotationEffect(.degrees(-90))
                        .frame(width: side - Self.band, height: side - Self.band)
                }
                Path { path in
                    for hour in Self.hours {
                        path.move(to: Self.point(hour: hour, radius: inner - Self.tickStart, center: center))
                        path.addLine(to: Self.point(hour: hour, radius: inner - Self.tickEnd, center: center))
                    }
                }
                .stroke(FocusTheme.Palette.secondaryText, lineWidth: 1.5)
                ForEach(Self.hours, id: \.self) { hour in
                    Text("\(hour)시").font(.caption2).monospacedDigit().foregroundStyle(FocusTheme.Palette.secondaryText)
                        // The labels only orient the eye; the text rows carry the times at every size.
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .fixedSize()
                        .position(Self.point(hour: hour, radius: inner - Self.labelInset, center: center))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: FocusTheme.Layout.controlSpacing) { legendItems }
            VStack(alignment: .leading, spacing: FocusTheme.Layout.inlineSpacing) { legendItems }
        }
        .font(.footnote).foregroundStyle(FocusTheme.Palette.secondaryText)
    }
    @ViewBuilder private var legendItems: some View {
        legendItem("실선 · 제한", blocked: true)
        legendItem("점선 · 해제", blocked: false)
    }
    private func legendItem(_ title: String, blocked: Bool) -> some View {
        HStack(spacing: FocusTheme.Layout.inlineSpacing) {
            Path { path in path.move(to: CGPoint(x: 0, y: 4)); path.addLine(to: CGPoint(x: 24, y: 4)) }
                .stroke(Self.color(blocked: blocked), style: Self.stroke(blocked: blocked, width: 8))
                .frame(width: 24, height: 8)
            Text(title).fixedSize(horizontal: false, vertical: true)
        }
    }
    private static func color(blocked: Bool) -> Color { blocked ? FocusTheme.Palette.accent : FocusTheme.Palette.secondaryText }
    private static func stroke(blocked: Bool, width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .butt, dash: blocked ? [] : [4, 3])
    }
    /// Clockwise from the top: an hour's point on a circle around the center.
    private static func point(hour: Int, radius: CGFloat, center: CGPoint) -> CGPoint {
        let angle = EverydaySettingsModel.dayClockFraction(hour * 60) * 2 * .pi
        return CGPoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
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
