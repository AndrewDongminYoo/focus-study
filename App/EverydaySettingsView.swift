import SwiftUI
import FamilyControls

/// The everyday layer, opened in the settings sheet from its settings row or from the timer screen's everyday status row.
/// Layout, colors and locked editing: docs/specs/2026-11-23-everyday-screen-redesign-design.md.
struct EverydaySettingsView: View {
    @State private var settings: EverydaySettingsModel
    @State private var picker = false
    @State private var loaded = false
    @State private var choosingWindow = false
    @State private var confirmingDiscard = false
    @State private var confirmingSave = false
    @State private var editingRange = false
    @State private var saveFeedback = 0
    @State private var windowStartWidth: CGFloat = 0
    @ScaledMetric(relativeTo: .footnote) private var saveStatusHeight = FocusTheme.Layout.minimumTapTarget
    @ScaledMetric(relativeTo: .title2) private var headingSize: CGFloat = 25
    @ScaledMetric(relativeTo: .largeTitle) private var rangeSize: CGFloat = 29
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let onUnsavedChanges: (Bool) -> Void
    init(model: FocusModel, onUnsavedChanges: @escaping (Bool) -> Void = { _ in }) {
        _settings = State(initialValue: EverydaySettingsModel(focus: model))
        self.onUnsavedChanges = onUnsavedChanges
    }
    var body: some View {
        // A real container, so that swapping the form for the waiting screen does not run the lifecycle modifiers below.
        ZStack {
            if settings.offWait != nil { offWaitScreen } else { form }
        }
        // The status card's "매일 제한" is the visible title; the bar keeps the title for VoiceOver and the back stack.
        .navigationTitle("매일 제한").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(settings.hasChanges)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            if settings.hasChanges {
                ToolbarItem(placement: .topBarLeading) {
                    Button { confirmingDiscard = true } label: { Label("뒤로", systemImage: "chevron.left") }
                        .accessibilityIdentifier("everydayBack")
                }
            }
        }
        .alert("변경 사항을 버릴까요?", isPresented: $confirmingDiscard) {
            Button("변경 버리기", role: .destructive) { dismiss() }
            Button("계속 편집", role: .cancel) {}
        } message: { Text("저장하지 않은 변경은 사라져요.") }
        .alert("매일 제한을 저장할까요?", isPresented: $confirmingSave) {
            Button("저장") { save() }.accessibilityIdentifier("everydaySaveConfirm")
            Button("취소", role: .cancel) {}
        } message: {
            Text("저장하면 제한 시간(\(EverydaySettingsModel.time(settings.draft.rangeStart))–\(EverydaySettingsModel.time(settings.draft.rangeEnd)))에는 매일 제한을 끄거나 느슨하게 바꿀 수 없어요.")
        }
        // A draft that the lock changed is not the one the alert named, so the alert closes and the next save asks again.
        .onChange(of: settings.lockRevertMessage) { _, message in if message != nil { confirmingSave = false } }
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
            await EverydaySettingsModel.followStatus({ settings.status }, now: settings.clock, rangeCalendar: settings.focus.services.engine.calendar,
                                                     dayWordCalendar: settings.focus.services.engine.calendar) {
                settings.refreshStatus()
            }
        }
        .sheet(isPresented: $picker) { selectionEditor }
        .sheet(isPresented: $editingRange) { rangeEditor }
    }
    private var calendar: Calendar { settings.focus.services.engine.calendar }
    private var form: some View {
        ScrollView {
            VStack(spacing: FocusTheme.Layout.relatedSpacing) {
                statusCard
                rangeCard
                weekdayCard
                windowCard
                appCard
                previewCard
            }
            .padding(.horizontal, FocusTheme.Layout.screenInset).padding(.top, FocusTheme.Layout.inlineSpacing).padding(.bottom, FocusTheme.Layout.controlSpacing)
        }
        .background(EverydayPalette.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { saveActions }
    }

    // MARK: Cards

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: FocusTheme.Layout.relatedSpacing) {
            HStack(spacing: FocusTheme.Layout.inlineSpacing) {
                Text("매일 제한").font(.system(size: headingSize, weight: .bold)).foregroundStyle(EverydayPalette.ink).accessibilityAddTraits(.isHeader)
                Spacer(minLength: FocusTheme.Layout.inlineSpacing)
                if !settings.canToggleEnabled { EverydayLockMark() }
                Toggle("매일 제한 켜기", isOn: $settings.draft.enabled).labelsHidden().tint(EverydayPalette.accent)
                    .disabled(!settings.canToggleEnabled).accessibilityIdentifier("everydayToggle")
            }
            if settings.isLocked {
                // The lock marks say what is locked; this line says why, and that the lock ends with the range.
                Text("제한 시간에는 \(Image(systemName: "lock.fill")) 표시한 항목을 바꿀 수 없어요.")
                    .font(.footnote).foregroundStyle(EverydayPalette.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("제한 시간에는 잠긴 항목을 바꿀 수 없어요.").accessibilityIdentifier("everydayLockNote")
            }
            if EverydaySettingsModel.showsStatusLine(settings.status) {
                Text(EverydaySettingsModel.statusLine(settings.status, at: settings.statusReadAt ?? settings.clock(), calendar: calendar))
                    .font(.footnote).foregroundStyle(EverydayPalette.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("everydayStatus")
            }
            if settings.offersOffForToday {
                Button { settings.startOffWait() } label: {
                    Text("오늘만 끄기").font(.subheadline.weight(.bold)).foregroundStyle(EverydayPalette.accent)
                        .frame(maxWidth: .infinity, minHeight: FocusTheme.Layout.minimumTapTarget)
                        .background(RoundedRectangle(cornerRadius: 12).fill(EverydayPalette.accentTint)).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("everydayOffToday")
            }
        }
        .modifier(EverydayCard())
    }
    private var rangeCard: some View {
        let start = EverydaySettingsModel.time(settings.draft.rangeStart), end = EverydaySettingsModel.time(settings.draft.rangeEnd)
        return VStack(alignment: .leading, spacing: FocusTheme.Layout.inlineSpacing) {
            Button { editingRange = true } label: {
                VStack(alignment: .leading, spacing: FocusTheme.Layout.inlineSpacing) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("설정 시간").font(.subheadline.weight(.medium)).foregroundStyle(EverydayPalette.rangeSecondary)
                        Spacer(minLength: FocusTheme.Layout.inlineSpacing)
                        // The weekday card says the same days, so VoiceOver reads them there.
                        Text("\(EverydayPlan.weekdaySummary(settings.draft.chosenWeekdays, calendar: calendar)) 반복")
                            .font(.footnote.weight(.medium)).foregroundStyle(EverydayPalette.rangeSummary).accessibilityHidden(true)
                    }
                    Text("\(start)–\(end)").font(.system(size: rangeSize, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(EverydayPalette.rangeText).lineLimit(1).minimumScaleFactor(0.5)
                    Text("이 시간 안에서 제한과 해제를 반복해요").font(.footnote).foregroundStyle(EverydayPalette.rangeSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16).padding(.vertical, 13).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: FocusTheme.Screen.cornerRadius).fill(EverydayPalette.rangeCard))
                .contentShape(RoundedRectangle(cornerRadius: FocusTheme.Screen.cornerRadius))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("설정 시간 \(start)부터 \(end)까지").accessibilityHint("눌러서 제한 시작과 끝을 고쳐요")
            .accessibilityIdentifier("everydayRange")
            // The range issue reads on the screen background, because the error color does not read on the navy card.
            if let issue = settings.rangeIssue { issueLabel(issue, identifier: "everydayRangeIssue") }
        }
    }
    private var weekdayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("제한 요일").font(.subheadline.weight(.bold)).foregroundStyle(EverydayPalette.ink)
                Spacer(minLength: FocusTheme.Layout.inlineSpacing)
                Text(EverydayPlan.weekdaySummary(settings.draft.chosenWeekdays, calendar: calendar))
                    .font(.footnote.weight(.bold)).foregroundStyle(EverydayPalette.accent).multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("everydayWeekdaysSummary")
            }
            EverydayWeekdayChips(order: settings.weekdayOrder, chosen: settings.draft.chosenWeekdays, canToggle: settings.canToggleWeekday) { settings.toggleWeekday($0) }
            if let issue = settings.weekdaysIssue { issueLabel(issue, identifier: "everydayWeekdaysIssue") }
        }
        .modifier(EverydayCard())
    }
    private var windowCard: some View {
        VStack(alignment: .leading, spacing: FocusTheme.Layout.inlineSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text("잠시 풀어 두는 시간").font(.subheadline.weight(.bold)).foregroundStyle(EverydayPalette.ink)
                Spacer(minLength: FocusTheme.Layout.inlineSpacing)
                Text("\(settings.draft.windows.count)/\(EverydaySchedule.maxWindows)").font(.footnote).monospacedDigit().foregroundStyle(EverydayPalette.secondary)
                    .accessibilityLabel("\(EverydaySchedule.maxWindows)개 중 \(settings.draft.windows.count)개")
            }
            ForEach(Array(settings.draft.windows.enumerated()), id: \.offset) { index, _ in
                HStack(spacing: FocusTheme.Layout.inlineSpacing) {
                    // One line reads as a range, "오후 12:00 – 오후 1:00"; the pickers keep "시작" and "끝" as accessibility labels.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: FocusTheme.Layout.inlineSpacing) { windowTimes(index, separator: true) }
                        VStack(alignment: .leading, spacing: FocusTheme.Layout.inlineSpacing) { windowTimes(index, separator: false) }
                    }
                    .disabled(!settings.canEditWindowTimes)
                    Spacer(minLength: 0)
                    // The frame is inside the label, so the whole 44-point area takes the tap.
                    Button(role: .destructive) { settings.removeWindow(at: index) } label: {
                        Text("삭제").font(.footnote).foregroundStyle(FocusTheme.Palette.error)
                            .frame(minWidth: FocusTheme.Layout.minimumTapTarget, minHeight: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
                .accessibilityElement(children: .contain).accessibilityIdentifier("everydayWindow.\(index + 1)")
            }
            EverydayDivider()
            Button { choosingWindow = true } label: {
                HStack(spacing: FocusTheme.Layout.inlineSpacing) {
                    if settings.isLocked { EverydayLockMark() } else { Text("+").accessibilityHidden(true) }
                    Text("시간 추가하기")
                }
                .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: FocusTheme.Layout.minimumTapTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            // A locked button shows the lock mark in the secondary color; a button with three windows is dimmed, because nothing locks it.
            .buttonStyle(EverydayLockableButtonStyle()).foregroundStyle(settings.isLocked ? EverydayPalette.secondary : EverydayPalette.accent)
            .opacity(settings.canAddWindow || settings.isLocked ? 1 : 0.45)
            .disabled(!settings.canAddWindow).accessibilityIdentifier("everydayAddWindow")
            .confirmationDialog("시간 추가하기", isPresented: $choosingWindow, titleVisibility: .visible) {
                ForEach(EverydayWindowKind.allCases, id: \.self) { kind in
                    Button(kind == .custom ? "직접 정하기" : EverydaySettingsModel.label(kind)) { settings.addWindow(kind) }
                }
                Button("닫기", role: .cancel) {}
            }
            if let issue = settings.windowsIssue { issueLabel(issue, identifier: "everydayWindowsIssue") }
            Text("점심이나 등하교처럼 제한을 풀어 둘 시간을 3개까지 정할 수 있어요. 한 번에 15분에서 2시간까지예요.")
                .font(.caption).foregroundStyle(EverydayPalette.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onPreferenceChange(WindowStartWidthKey.self) { windowStartWidth = $0 }
        .modifier(EverydayCard())
    }
    private var appCard: some View {
        Button { picker = true } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: FocusTheme.Layout.inlineSpacing) {
                    Text("제한할 앱").font(.subheadline.weight(.bold)).foregroundStyle(EverydayPalette.ink)
                    Spacer(minLength: FocusTheme.Layout.inlineSpacing)
                    Text("앱 \(settings.counts.apps)개 · 웹사이트 \(settings.counts.websites)개").font(.footnote.weight(.medium))
                        .foregroundStyle(EverydayPalette.accent).monospacedDigit().multilineTextAlignment(.trailing)
                    if settings.canEditSelection {
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(EverydayPalette.secondary).accessibilityHidden(true)
                    } else {
                        EverydayLockMark()
                    }
                }
                Text("집중 시간에 제한할 앱과 따로 골라요.").font(.footnote).foregroundStyle(EverydayPalette.secondary).fixedSize(horizontal: false, vertical: true)
                if let issue = settings.selectionIssue { issueLabel(issue, identifier: "everydaySelectionIssue") }
            }
            .modifier(EverydayCard()).contentShape(Rectangle())
        }
        .buttonStyle(EverydayLockableButtonStyle())
        .disabled(!settings.canEditSelection).accessibilityIdentifier("everydaySelection")
    }
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("일정 미리보기").font(.subheadline.weight(.bold)).foregroundStyle(EverydayPalette.ink)
                Spacer(minLength: FocusTheme.Layout.inlineSpacing)
                if settings.draft.enabled, settings.draft.issue == nil {
                    Text("\(EverydaySettingsModel.time(settings.draft.rangeStart))–\(EverydaySettingsModel.time(settings.draft.rangeEnd))")
                        .font(.footnote).monospacedDigit().foregroundStyle(EverydayPalette.secondary)
                }
            }
            schedulePreview(settings.draft, prefix: "everydayDraft")
            EverydayDivider()
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    if let schedule = settings.status?.schedule {
                        schedulePreview(schedule, prefix: "everydayStored")
                    } else {
                        Text(settings.status?.issue == nil ? "저장된 일정이 없어요." : "저장된 일정을 확인하지 못했어요.")
                            .font(.footnote).foregroundStyle(EverydayPalette.secondary).accessibilityIdentifier("everydayStoredUnavailable")
                    }
                }
                .padding(.top, FocusTheme.Layout.inlineSpacing)
            } label: {
                Text("저장된 일정 보기").font(.footnote).foregroundStyle(EverydayPalette.secondary).frame(minHeight: FocusTheme.Layout.minimumTapTarget)
            }
            .tint(EverydayPalette.secondary)
        }
        .modifier(EverydayCard())
    }
    @ViewBuilder private func schedulePreview(_ schedule: EverydaySchedule, prefix: String) -> some View {
        if let segments = EverydaySettingsModel.previewSegments(for: schedule) {
            if !schedule.enabled {
                Text("매일 제한이 꺼져 있어요.").font(.footnote).foregroundStyle(EverydayPalette.secondary).accessibilityIdentifier("\(prefix)Off")
            } else {
                Text("제한 요일 · \(EverydayPlan.weekdaySummary(schedule.chosenWeekdays, calendar: calendar))")
                    .font(.footnote).foregroundStyle(EverydayPalette.secondary).accessibilityIdentifier("\(prefix)Weekdays")
                // The rows below carry every state in text, so the legend and the bar are hidden from VoiceOver.
                HStack(spacing: FocusTheme.Layout.inlineSpacing) {
                    EverydayStateBadge(blocked: true)
                    EverydayStateBadge(blocked: false)
                }
                .accessibilityHidden(true)
                EverydayProportionBar(segments: segments).accessibilityHidden(true)
                EverydayDivider()
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    let start = EverydaySettingsModel.time(segment.start), end = EverydaySettingsModel.time(segment.end)
                    HStack {
                        Text("\(start)–\(end)").font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(EverydayPalette.ink)
                            .accessibilityLabel("\(start)부터 \(end)까지, \(segment.blocked ? "제한" : "해제")")
                            .accessibilityIdentifier("\(prefix)Segment.\(index + 1)")
                        Spacer(minLength: FocusTheme.Layout.inlineSpacing)
                        EverydayStateBadge(blocked: segment.blocked).accessibilityHidden(true)
                    }
                }
            }
        } else {
            Text(EverydaySettingsModel.invalidPreviewLine(schedule))
                .font(.footnote).foregroundStyle(EverydayPalette.secondary).accessibilityIdentifier("\(prefix)Invalid")
        }
    }

    // MARK: Range editor

    private var rangeEditor: some View {
        NavigationStack {
            Form {
                Section {
                    TimeField(title: "제한 시작", minutes: $settings.draft.rangeStart, bounds: settings.rangeStartBounds).accessibilityIdentifier("everydayRangeStart")
                    TimeField(title: "제한 끝", minutes: $settings.draft.rangeEnd, bounds: settings.rangeEndBounds).accessibilityIdentifier("everydayRangeEnd")
                    if let issue = settings.rangeIssue { issueLabel(issue, identifier: "everydayRangeEditorIssue") }
                } footer: {
                    Text(settings.isLocked ? "제한 시간에는 제한 시작을 더 이르게, 제한 끝을 더 늦게만 바꿀 수 있어요."
                                           : "고른 요일마다 이 시간에 고른 앱과 웹사이트를 제한해요. 앱을 열지 않아도 돼요.")
                }
            }
            .navigationTitle("설정 시간").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { editingRange = false }.accessibilityIdentifier("everydayRangeDone") } }
        }
        .modifier(FocusEditorSheet())
    }

    // MARK: Off for today

    /// The off-for-today wait, in the manner of the M2 break wait: a progress bar with the countdown and a cancel button.
    private var offWaitScreen: some View {
        let progress = settings.offWaitProgress ?? 0, left = settings.offWaitRemaining ?? 0
        let line = "\(left)초 뒤에 오늘 매일 제한이 꺼져요"
        return VStack(spacing: FocusTheme.Layout.controlSpacing) {
            Spacer(minLength: 32)
            Text(line).font(.headline).monospacedDigit().foregroundStyle(EverydayPalette.ink)
                .padding(.vertical, FocusTheme.Layout.controlSpacing).padding(.horizontal, FocusTheme.Layout.screenInset).frame(maxWidth: .infinity)
                .background(alignment: .leading) {
                    GeometryReader { proxy in Capsule().fill(EverydayPalette.accentTint).frame(width: proxy.size.width * progress) }
                }
                .background(Capsule().fill(FocusTheme.Screen.card)).clipShape(Capsule())
                .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
                .accessibilityElement(children: .ignore).accessibilityLabel(line).accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("everydayOffWait")
            Button { settings.cancelOffWait() } label: {
                Text("그대로 두기").frame(minWidth: FocusTheme.Layout.minimumTapTarget, minHeight: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
            }
            .tint(EverydayPalette.accent)
                .accessibilityIdentifier("everydayOffCancel")
            Spacer(minLength: 48)
        }
        .padding(.horizontal, FocusTheme.Layout.screenInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EverydayPalette.canvas.ignoresSafeArea())
    }

    // MARK: Save

    private var saveActions: some View {
        VStack(spacing: FocusTheme.Layout.inlineSpacing) {
            saveStatus
                .frame(maxWidth: .infinity, minHeight: saveStatusHeight, alignment: .center)
            Button {
                // Turning the layer off locks nothing, so it needs no confirmation.
                if settings.draft.enabled { confirmingSave = true } else { save() }
            } label: {
                Text("저장").frame(maxWidth: .infinity)
            }
            .buttonStyle(EverydaySaveButtonStyle())
            .disabled(!settings.canSave).accessibilityIdentifier("everydaySave")
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, FocusTheme.Layout.screenInset)
        .padding(.top, FocusTheme.Layout.relatedSpacing)
        .padding(.bottom, FocusTheme.Layout.inlineSpacing)
        .background(EverydayPalette.canvas)
    }
    private func save() {
        settings.save()
        if settings.successMessage != nil { saveFeedback += 1 }
    }
    private var saveStatus: some View {
        VStack(spacing: FocusTheme.Layout.detailSpacing) {
            if let message = settings.successMessage {
                HStack(alignment: .center, spacing: FocusTheme.Layout.inlineSpacing) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(EverydayPalette.accent)
                    Text(message).foregroundStyle(EverydayPalette.ink)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(message).accessibilityIdentifier("everydaySaveSuccess")
            }
            if let message = settings.lockRevertMessage {
                Text(message).foregroundStyle(EverydayPalette.ink).accessibilityIdentifier("everydayLockRevert")
            }
            if settings.hasChanges {
                Text("저장하지 않은 변경이 있어요.").foregroundStyle(EverydayPalette.secondary).accessibilityIdentifier("everydayUnsavedChanges")
            } else if settings.successMessage == nil, settings.refusalMessage == nil, settings.canEdit {
                Text("변경 사항이 없어요").foregroundStyle(EverydayPalette.secondary)
            }
            if let message = settings.refusalMessage {
                Label(message, systemImage: "exclamationmark.circle").foregroundStyle(FocusTheme.Palette.error).accessibilityIdentifier("everydayRefusal")
            } else if !settings.canEdit {
                Text(SelectionFeedback.message(for: ControlIssue.busy)).foregroundStyle(EverydayPalette.secondary)
            }
        }
        .font(.footnote)
    }

    // MARK: Parts

    private func issueLabel(_ issue: String, identifier: String) -> some View {
        Label(issue, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(FocusTheme.Palette.error)
            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(identifier)
    }
    @ViewBuilder private func windowTimes(_ index: Int, separator: Bool) -> some View {
        // Every start takes the width of the widest one, so that the dash and the end line up from row to row
        // ("오후 12:00" is wider than "오전 8:00"); a stacked row has no dash to line up.
        // The lock mark is inside each layout, so that the stacked layout still fits at the largest text size.
        if !settings.canEditWindowTimes { EverydayLockMark() }
        let start = TimeField(title: "시작", minutes: windowBinding(index, \.start)).labelsHidden()
        if separator {
            start.background(GeometryReader { proxy in Color.clear.preference(key: WindowStartWidthKey.self, value: proxy.size.width) })
                .frame(minWidth: windowStartWidth, alignment: .leading)
            Text("–").foregroundStyle(EverydayPalette.secondary).accessibilityHidden(true)
        } else {
            start
        }
        TimeField(title: "끝", minutes: windowBinding(index, \.end)).labelsHidden()
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

/// The colors of the everyday screen (docs/specs/2026-11-23-everyday-screen-redesign-design.md, "Tokens").
private enum EverydayPalette {
    static let canvas = Color("EverydayCanvas")
    static let ink = Color("EverydayInk")
    static let secondary = FocusTheme.Screen.secondaryInk
    static let accent = Color("EverydayAccent")
    static let accentTint = Color("EverydayAccentTint")
    static let neutralTint = Color("EverydayNeutralTint")
    static let unblockedBar = Color("EverydayUnblockedBar")
    static let divider = Color("EverydayDivider")
    static let rangeCard = Color("EverydayRangeCard")
    static let rangeText = Color("EverydayRangeText")
    static let rangeSecondary = Color("EverydayRangeSecondary")
    static let rangeSummary = Color("EverydayRangeSummary")
    static let disabledFill = Color("EverydayDisabledFill")
    static let disabledText = Color("EverydayDisabledText")
}

/// A white card on the light canvas, the shared card color on the dark one.
private struct EverydayCard: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.horizontal, 16).padding(.vertical, 13).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: FocusTheme.Screen.cornerRadius).fill(FocusTheme.Screen.card))
    }
}

/// The width of the widest window start, measured before the shared minimum width applies.
private struct WindowStartWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A plain button that a disabled state does not dim, because a locked element shows the lock mark instead.
private struct EverydayLockableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.opacity(configuration.isPressed ? 0.6 : 1) }
}

/// The lock mark of an element that the locked screen keeps; the lock note of the status card says it in words.
private struct EverydayLockMark: View {
    var color: Color = EverydayPalette.secondary
    var body: some View { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(color).accessibilityHidden(true) }
}

private struct EverydayDivider: View {
    var body: some View { Rectangle().fill(EverydayPalette.divider).frame(height: 1).accessibilityHidden(true) }
}

/// The accent with the on-accent label, or the gray disabled fill.
private struct EverydaySaveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(isEnabled ? FocusTheme.Palette.onAccent : EverydayPalette.disabledText)
            .frame(maxWidth: .infinity, minHeight: 47)
            .background(RoundedRectangle(cornerRadius: 14).fill(isEnabled ? EverydayPalette.accent : EverydayPalette.disabledFill))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// "제한" or "해제" as a text badge, so that the state differs by more than color.
private struct EverydayStateBadge: View {
    let blocked: Bool
    var body: some View {
        Text(blocked ? "제한" : "해제").font(.footnote.weight(.medium))
            .foregroundStyle(blocked ? EverydayPalette.accent : EverydayPalette.secondary)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 7).fill(blocked ? EverydayPalette.accentTint : EverydayPalette.neutralTint))
    }
}

/// The segments of the daily range side by side, each as wide as its share of the range.
private struct EverydayProportionBar: View {
    let segments: [EverydaySettingsModel.PreviewSegment]
    private static let gap: CGFloat = 3
    var body: some View {
        GeometryReader { proxy in
            let total = max(1, segments.reduce(0) { $0 + $1.end - $1.start })
            let width = max(0, proxy.size.width - Self.gap * CGFloat(max(0, segments.count - 1)))
            HStack(spacing: Self.gap) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    RoundedRectangle(cornerRadius: 3).fill(segment.blocked ? EverydayPalette.accent : EverydayPalette.unblockedBar)
                        .frame(width: width * CGFloat(segment.end - segment.start) / CGFloat(total))
                }
            }
        }
        .frame(height: 9)
    }
}

/// Seven day chips in the order of the first weekday. A chosen day is the accent tint with bold accent text, a day that is not
/// chosen is the neutral tint, so that the two differ by more than color; a chip that the locked screen keeps is disabled and
/// keeps its chosen look with a lock mark, so that the day still reads as chosen.
private struct EverydayWeekdayChips: View {
    let order: [Int]
    let chosen: Set<Int>
    let canToggle: (Int) -> Bool
    let toggle: (Int) -> Void
    var body: some View {
        // No spacing between the buttons: the gap is inside each button, so every tap target spans its whole column.
        // When seven 44-point columns do not fit (a 375-point screen), the chips wrap into a grid.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ForEach(order, id: \.self) { day in chip(day) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: FocusTheme.Layout.minimumTapTarget + 6), spacing: 0)], spacing: 4) {
                ForEach(order, id: \.self) { day in chip(day) }
            }
        }
        // The summary above carries the days at every size, so the chips stop growing at the first accessibility size.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
    private func chip(_ day: Int) -> some View {
        let isChosen = chosen.contains(day), enabled = canToggle(day)
        return Button { toggle(day) } label: {
            HStack(spacing: 2) {
                Text(EverydaySettingsModel.shortWeekdayName(day)).font(.subheadline.weight(isChosen ? .bold : .regular))
                if !enabled { EverydayLockMark(color: EverydayPalette.accent) }
            }
            .foregroundStyle(isChosen ? EverydayPalette.accent : EverydayPalette.secondary)
            .lineLimit(1).minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9).fill(isChosen ? EverydayPalette.accentTint : EverydayPalette.neutralTint))
            .padding(.horizontal, 3)
            .frame(minWidth: FocusTheme.Layout.minimumTapTarget, minHeight: FocusTheme.Layout.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(EverydayLockableButtonStyle()).disabled(!enabled)
        .accessibilityLabel(EverydaySettingsModel.weekdayName(day))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .accessibilityIdentifier("everydayWeekday.\(day)")
    }
}

/// A wall-clock time on the 5-minute grid, stored as minutes after midnight, inside `bounds`.
private struct TimeField: View {
    let title: String
    @Binding var minutes: Int
    var bounds: ClosedRange<Int> = 0...EverydaySchedule.latestRangeEnd
    var body: some View {
        DatePicker(title, selection: Binding(get: {
            Self.date(minutes)
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            let value = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            let rounded = (value + EverydaySchedule.grid / 2) / EverydaySchedule.grid * EverydaySchedule.grid
            minutes = min(bounds.upperBound, max(bounds.lowerBound, rounded))
        }), in: Self.date(bounds.lowerBound)...Self.date(bounds.upperBound), displayedComponents: .hourAndMinute)
    }
    private static func date(_ minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
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
