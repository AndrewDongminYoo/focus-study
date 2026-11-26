import SwiftUI
import Combine
import UIKit

/// The main screen: the idle screen, the timer screen of an active session, the break screen and the completion card
/// (docs/specs/2026-11-23-screen-redesign-design.md; the completion card keeps docs/specs/2026-11-20-navy-focus-room-design.md).
struct FocusView: View {
    let model: FocusModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 57
    @ScaledMetric(relativeTo: .footnote) private var markerSize: CGFloat = 6
    @ScaledMetric(relativeTo: .title2) private var colonMarkHeight: CGFloat = 56
    @State private var sheet: FocusSheet?
    /// `nil` only in a preview without a runtime; the start gate then never asks for the sheet.
    @Environment(PaidAccessStore.self) private var paidAccess: PaidAccessStore?
    /// `nil` only in a preview without a runtime.
    @Environment(WeeklyReviewModel.self) private var review: WeeklyReviewModel?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                Group {
                    if model.current?.isPaused == true {
                        BreakSessionView(model: model, onEnd: { sheet = .endConfirmation }, onSettings: showsDiagnostics ? { sheet = .settings } : nil)
                    } else if model.isActive {
                        activeScreen
                    } else if model.completedSessionID != nil {
                        completionScreen
                    } else {
                        idleScreen
                    }
                }.frame(minHeight: geometry.size.height)
            }
        }
        .background { (isRoom ? FocusTheme.Room.background : FocusTheme.Screen.canvas).ignoresSafeArea().animation(roomAnimation, value: isRoom) }
        // The dark appearance makes the controls, the error text and the status bar read light on navy; sheets presented from the room follow it.
        .preferredColorScheme(isRoom ? .dark : nil)
        .sheet(item: $sheet, onDismiss: { model.dismissPaywall(); presentReviewOrExplanation() }) { item in
            switch item {
            case .selection: selectionEditor
            case .settings: SettingsView(model: model)
            case .everydaySettings: SettingsView(model: model, opensEveryday: true)
            case .history: SungongCalendarView(model: model)
            case .endConfirmation: FocusEndConfirmation(model: model)
            case .paywall:
                if let paidAccess {
                    // The callbacks carry the request that this sheet opened for, so a late result never reaches another request.
                    let request = model.paywallRequest
                    PaidAccessSheet(store: paidAccess, startMinutes: request?.holdsStart == true ? Int(model.services.settings.lengthSeconds) / 60 : nil,
                                    onConfirmed: { if let request { model.confirmPaywallStart(request.id) } },
                                    onDropStart: { if let request { model.dropPaywallStart(request.id) } })
                }
            case .review: if let review, let request = review.presented { WeeklyReviewView(model: model, review: review, day: request.day, requestID: request.id, form: reviewForm) }
            case .reviewExplanation: if let review { ReviewExplanationView(review: review) }
            }
        }
        // The start entry's paywall; its close (`onDismiss`) runs the start path once after a trial or purchase confirmed inside it.
        .onChange(of: model.paywallRequest?.id) { _, request in if request != nil, paidAccess != nil { sheet = .paywall } }
        // The calendar entry replaces the calendar sheet with the review; a notification tap waits until no session runs.
        .onChange(of: review?.request) { _, request in if request != nil { presentReviewOrExplanation() } }
        .onChange(of: review?.explanationDue) { _, _ in presentReviewOrExplanation() }
        .onChange(of: paidAccess?.facts) { _, _ in refreshReview() }
        .sensoryFeedback(.success, trigger: model.completedSessionID) { _, new in new != nil }
        // The explanation waits for the completion card; closing the card is a retry point.
        .onChange(of: model.completedSessionID) { _, id in if id == nil { presentReviewOrExplanation() } }
        .task { refreshIfIdle(); refreshReview() }
        // While the idle screen or the completion card shows, a range or window boundary changes the everyday row with no lock section of the app, and `tick()` does not read it.
        .task(id: model.isInSession ? nil : model.everydayStatus) {
            guard !model.isInSession else { return }
            await EverydaySettingsModel.followStatus({ model.everydayStatus }, now: Date.init) { model.refreshEveryday() }
        }
        .onDisappear { cancelPendingStart() }
        .onChange(of: scenePhase) { _, value in
            // Only the background cancels a wait (spec: background or close); `.inactive` overlays such as Control Center do not.
            switch value {
            case .active: refreshIfIdle(); refreshReview()
            case .inactive: model.sceneDidBecomeInactive()
            case .background: model.sceneDidLeaveForeground()
            default: break
            }
        }
        // A change to approved keeps a reserved start: the access recovery reserves one right after the value settles.
        .onChange(of: model.access) { _, access in if access != .approved { cancelPendingStart() }; model.refresh() }
        .onChange(of: model.isInSession) { _, inSession in
            if !inSession, sheet == .endConfirmation { sheet = nil }
            if !inSession { presentReviewOrExplanation() }
            // A session that starts without the start button, such as from a Focus filter, closes the review and the explanation; both show again after it.
            if inSession, sheet == .review { review?.suspendOpenReview(); sheet = nil }
            if inSession, sheet == .reviewExplanation { review?.suspendExplanation(); sheet = nil }
        }
        // A start that ends without a session is a retry point; after a successful start `isInSession` is already true and the guard waits.
        .onChange(of: model.isStarting) { _, starting in if !starting { presentReviewOrExplanation() } }
        .onReceive(timer) { _ in
            if scenePhase == .active, !model.isStarting, model.pendingBreak == nil { model.tick(defersBreakStart: true) }
            // A trial end changes access by time alone; an open review closes within a second when access reads `locked`.
            if sheet == .review, paidAccess?.state == .locked { sheet = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshIfIdle(); refreshReview() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in refreshIfIdle(); refreshReview() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in cancelPendingStart(); model.refresh(clockChanged: true) }
    }

    // MARK: Idle screen

    private var idleScreen: some View {
        let selectionDisabled = model.isStarting || model.errorMessage != nil
        return FocusScreenLayout {
            headerButton("제한할 앱", identifier: "selection", disabled: selectionDisabled) { sheet = .selection }
            Spacer()
            headerButton("설정", identifier: "settingsButton", disabled: model.isStarting) { sheet = .settings }
        } title: {
            Text("작은 시작,\n깊은 몰입.").foregroundStyle(FocusTheme.Screen.ink).accessibilityAddTraits(.isHeader)
        } dial: {
            FocusDial(turns: 0, background: FocusTheme.Screen.canvas, animatesDot: false) {
                dialLabel("집중할 시간", color: FocusTheme.Screen.secondaryInk)
                clock(model.remaining, color: FocusTheme.Screen.ink)
                    .accessibilityLabel("남은 시간 \(model.remaining / 60)분 \(model.remaining % 60)초").accessibilityIdentifier("countdown")
                // Only a start that can run is "ready"; the blocker below says what is missing. `canStart` is also true while the
                // access is `checking`, where the start button runs the access recovery and the blocker shows.
                if model.canStart, model.startBlocker == nil { dialLabel("집중 준비 완료", color: FocusTheme.Screen.accentText, weight: .medium, style: .footnote) }
            }
        } notes: {
            Text("\(Int(model.services.settings.lengthSeconds) / 60)분 동안, 한 가지에만.").font(.subheadline).foregroundStyle(FocusTheme.Screen.secondaryInk)
            if let request = model.startRequestID {
                PendingFeedback(request: request, textColor: FocusTheme.Screen.secondaryInk, ready: model.performPendingStart, cancel: model.cancelPendingStart)
                    .frame(minHeight: FocusTheme.Layout.minimumTapTarget)
            }
            if let blocker = model.startBlocker {
                Text(blockerText(blocker)).font(.footnote).foregroundStyle(FocusTheme.Screen.secondaryInk).accessibilityIdentifier("startBlocker")
            }
            errorLines
        } actions: {
            Button { if model.access == .checking { Task { await model.recoverAccessAndStart() } } else { model.requestStart() } } label: {
                Label("집중 시작하기", systemImage: "play.fill")
            }
            .buttonStyle(FocusFillButtonStyle(fill: FocusTheme.Palette.accent, label: FocusTheme.Palette.onAccent))
            .disabled(!model.canStart).accessibilityIdentifier("start")
            restrictionCard
            todayCard
        }
    }
    private func headerButton(_ title: String, identifier: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            FocusCapsuleLabel(text: title, textColor: FocusTheme.Screen.ink, fill: FocusTheme.Screen.card)
                .frame(minWidth: FocusTheme.Layout.minimumTapTarget, minHeight: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
        }
        .buttonStyle(.plain).opacity(disabled ? 0.4 : 1).disabled(disabled).accessibilityIdentifier(identifier)
    }
    private var restrictionCard: some View {
        VStack(alignment: .leading, spacing: FocusTheme.Layout.relatedSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text("집중 중 제한").foregroundStyle(FocusTheme.Screen.secondaryInk)
                Spacer(minLength: FocusTheme.Layout.inlineSpacing)
                Text("앱 \(model.counts.apps)개 · 웹사이트 \(model.counts.websites)개").fontWeight(.medium).foregroundStyle(FocusTheme.Screen.ink)
                    .multilineTextAlignment(.trailing).monospacedDigit().accessibilityIdentifier("restrictionSummary")
            }
            .font(.subheadline)
            if let line = EverydaySettingsModel.timerLine(model.everydayStatus, calendar: model.services.engine.calendar) {
                Divider()
                everydayCardRow(line)
            }
        }
        .modifier(FocusCard())
    }
    /// `EverydaySettingsModel.timerLine` split at its " · ": the state on the leading side, the end time on the trailing side.
    private func everydayCardRow(_ line: String) -> some View {
        let parts = line.components(separatedBy: " · "), blocking = line.hasPrefix("매일 제한 중")
        return Button { sheet = .everydaySettings } label: {
            HStack(spacing: FocusTheme.Layout.inlineSpacing) {
                if blocking { Circle().fill(FocusTheme.Screen.accentText).frame(width: markerSize, height: markerSize) }
                Text(parts[0]).foregroundStyle(blocking ? FocusTheme.Screen.accentText : FocusTheme.Screen.ink)
                Spacer(minLength: FocusTheme.Layout.inlineSpacing)
                if parts.count > 1 { Text(parts[1...].joined(separator: " · ")).foregroundStyle(FocusTheme.Screen.ink).monospacedDigit() }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(FocusTheme.Screen.secondaryInk)
            }
            .font(.subheadline.weight(.medium)).frame(minHeight: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(model.isStarting).accessibilityLabel(line).accessibilityIdentifier("everydayStatusRow")
    }
    private var todayCard: some View {
        let summary = SessionSummary(records: model.records), failed = model.errorMessage != nil
        return Button { sheet = .history } label: {
            VStack(alignment: .leading, spacing: FocusTheme.Layout.relatedSpacing) {
                HStack {
                    Text("오늘의 집중").fontWeight(.medium)
                    Spacer()
                    Text("기록 보기")
                    Image(systemName: "chevron.right").font(.caption)
                }
                .font(.subheadline).foregroundStyle(FocusTheme.Screen.secondaryInk)
                HStack {
                    stat(failed ? "–" : "\(Int(summary.focusDuration) / 60)", unit: "분")
                    stat(failed ? "–" : "\(summary.completedCount)", unit: "회")
                }
            }
            .modifier(FocusCard()).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(model.isStarting).accessibilityLabel(todaySummary).accessibilityIdentifier("todaySummary")
    }
    private func stat(_ value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(FocusTheme.Screen.ink)
            Text(unit).font(.subheadline).foregroundStyle(FocusTheme.Screen.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Timer screen of an active session

    private var activeScreen: some View {
        let open = model.openElapsed
        return FocusScreenLayout {
            Text("나의 집중").font(.subheadline.weight(.medium)).foregroundStyle(FocusTheme.Room.secondaryText)
            Spacer()
            // The status line inside the dial says the same, so the pill is hidden from VoiceOver.
            FocusCapsuleLabel(text: "집중 진행 중", dot: FocusTheme.Room.marker, textColor: FocusTheme.Room.marker, fill: FocusTheme.Screen.pill).accessibilityHidden(true)
            if showsDiagnostics { diagnosticsButton }
        } title: {
            Text("지금은,\n나에게 집중할 시간").foregroundStyle(FocusTheme.Room.text).accessibilityAddTraits(.isHeader)
        } dial: {
            FocusDial(turns: focusTurns, background: FocusTheme.Room.background, animatesDot: !reduceMotion) {
                dialLabel(open == nil ? "남은 집중 시간" : "집중한 시간", color: FocusTheme.Room.secondaryText)
                if let elapsed = open {
                    clock(elapsed, countsDown: false, color: FocusTheme.Room.text)
                        .accessibilityLabel("집중한 시간 \(elapsed / 3600 > 0 ? "\(elapsed / 3600)시간 " : "")\(elapsed % 3600 / 60)분 \(elapsed % 60)초").accessibilityIdentifier("countdown")
                } else {
                    clock(model.remaining, color: FocusTheme.Room.text)
                        .accessibilityLabel("남은 시간 \(model.remaining / 60)분 \(model.remaining % 60)초").accessibilityIdentifier("countdown")
                }
                HStack(spacing: 6) {
                    Circle().fill(FocusTheme.Room.marker).frame(width: markerSize, height: markerSize).accessibilityHidden(true)
                    Text(open == nil ? "집중 시간 진행 중" : "집중 모드를 끌 때까지 이어져요").font(.footnote).foregroundStyle(FocusTheme.Room.marker)
                        .lineLimit(1).minimumScaleFactor(0.5).accessibilityIdentifier("sessionStatus")
                }
            }
        } notes: {
            Text("지금 이 순간에 머물러요").font(.subheadline).foregroundStyle(FocusTheme.Room.secondaryText)
            errorLines
        } actions: {
            // After the third break, the only way to leave before completion is `end`.
            if model.breaksLeft > 0 { breakCard }
            FocusEndButton { sheet = .endConfirmation }.disabled(model.pendingBreak != nil)
        }
    }
    private var breakCard: some View {
        VStack(alignment: .leading, spacing: FocusTheme.Layout.relatedSpacing) {
            HStack {
                Text("잠깐 쉬어가도 괜찮아요").font(.subheadline.weight(.medium)).foregroundStyle(FocusTheme.Room.text)
                Spacer(minLength: FocusTheme.Layout.inlineSpacing)
                Text("\(model.breaksLeft)번 남음").font(.footnote.weight(.medium)).foregroundStyle(FocusTheme.Room.marker)
                    .padding(.horizontal, 9).padding(.vertical, 4).background(Capsule().fill(FocusTheme.Screen.chip))
                    .accessibilityLabel("쉬는 시간 \(model.breaksLeft)번 남았어요").accessibilityIdentifier("breaksLeft")
            }
            Button("쉬는 시간 갖기") { model.requestBreakAction(.request) }
                .buttonStyle(FocusFillButtonStyle(fill: FocusTheme.Screen.creamFill, label: FocusTheme.Room.background))
                .disabled(model.pendingBreak != nil).accessibilityIdentifier("breakStart")
            // The request re-registers monitoring synchronously, which can take seconds on a device; the feedback renders first.
            if let pending = model.pendingBreak, pending.action == .request {
                BreakFeedback(model: model, pending: pending, textColor: FocusTheme.Room.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: FocusTheme.Layout.minimumTapTarget)
            }
        }
        .modifier(FocusCard())
    }
    /// The dot of the timer dial (spec "Dial"): the share of the focus length, or a 60-minute lap of an open session.
    /// With Reduce Motion on, it moves once per minute.
    private var focusTurns: Double {
        var elapsed: Int, lap: Double
        if let open = model.openElapsed {
            elapsed = open; lap = 3600
        } else {
            lap = max(1, model.current?.length ?? model.services.settings.lengthSeconds); elapsed = Int(lap) - model.remaining
        }
        if reduceMotion { elapsed = elapsed / 60 * 60 }
        return Double(max(0, elapsed)) / lap
    }
    private var diagnosticsButton: some View {
        Button { sheet = .settings } label: {
            Image(systemName: "gearshape").frame(width: FocusTheme.Layout.minimumTapTarget, height: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(FocusTheme.Room.text).accessibilityLabel("설정").accessibilityIdentifier("settingsButton")
    }

    // MARK: Completion card (navy focus room design)

    private var completionScreen: some View {
        VStack(spacing: 0) {
            HStack {
                Button { sheet = .selection } label: {
                    Text("제한할 앱").frame(minWidth: FocusTheme.Layout.minimumTapTarget, minHeight: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
                }.modifier(FocusSecondaryAction(tint: FocusTheme.Room.text))
                    .disabled(model.isStarting || model.errorMessage != nil).accessibilityIdentifier("selection")
                Spacer()
                Button { sheet = .settings } label: {
                    Image(systemName: "gearshape").frame(width: FocusTheme.Layout.minimumTapTarget, height: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
                }.modifier(FocusSecondaryAction(tint: FocusTheme.Room.text)).disabled(model.isStarting)
                    .accessibilityLabel("설정").accessibilityIdentifier("settingsButton")
            }
            .modifier(FocusGlassGroup()).frame(minHeight: FocusTheme.Layout.minimumTapTarget).padding(.horizontal, FocusTheme.Layout.screenInset)
            Spacer(minLength: 32)
            VStack(spacing: FocusTheme.Layout.controlSpacing) {
                ColonMark(height: colonMarkHeight)
                Text("\(completedMinutes)분 집중을 마쳤어요").font(.title2.weight(.semibold)).multilineTextAlignment(.center).roomForeground(FocusTheme.Room.text, animation: roomAnimation).accessibilityIdentifier("completion")
                Text("오늘의 세션에 기록했어요. 잠시 쉬었다가 다음 집중을 시작해 보세요.").multilineTextAlignment(.center).roomForeground(FocusTheme.Room.secondaryText, animation: roomAnimation)
                Text("제한이 풀리기까지 조금 걸릴 수 있어요.").font(.footnote).multilineTextAlignment(.center).roomForeground(FocusTheme.Room.secondaryText, animation: roomAnimation).accessibilityIdentifier("releaseDelayNote")
                if let line = EverydaySettingsModel.timerLine(model.everydayStatus, calendar: model.services.engine.calendar) {
                    Button { sheet = .everydaySettings } label: {
                        HStack(spacing: FocusTheme.Layout.detailSpacing) {
                            Text(line).multilineTextAlignment(.center).monospacedDigit()
                            Image(systemName: "chevron.right").font(.caption)
                        }.frame(minWidth: FocusTheme.Layout.minimumTapTarget, minHeight: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
                    }.buttonStyle(.plain).font(.footnote).roomForeground(FocusTheme.Room.secondaryText, animation: roomAnimation)
                        .disabled(model.isStarting).accessibilityLabel(line).accessibilityIdentifier("everydayStatusRow")
                }
                Button("닫기") { model.dismissCompletion() }.modifier(FocusSecondaryAction(tint: FocusTheme.Room.text)).accessibilityIdentifier("completionDismiss")
            }
            .frame(maxWidth: .infinity).padding(.horizontal, FocusTheme.Layout.screenInset)
            Spacer(minLength: 64)
        }
    }

    // MARK: Shared parts

    @ViewBuilder private var errorLines: some View {
        if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(FocusTheme.Palette.error).accessibilityIdentifier("startError")
            // The room tints it cream (spec contract 6); the idle screen keeps the accent color.
            Button("다시 확인하기") { model.refresh() }.tint(isRoom ? FocusTheme.Room.text : nil).accessibilityIdentifier("retry")
        }
    }
    private func dialLabel(_ text: String, color: Color, weight: Font.Weight = .regular, style: Font = .subheadline) -> some View {
        Text(text).font(style.weight(weight)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.5)
    }
    /// `mm:ss`, or `h:mm:ss` from one hour, which only the count-up of an open session reaches.
    private func clock(_ seconds: Int, countsDown: Bool = true, color: Color) -> some View {
        Text(seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60) : String(format: "%02d:%02d", seconds / 60, seconds % 60))
            .font(.system(size: countdownSize, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).foregroundStyle(color)
            .contentTransition(.numericText(countsDown: countsDown)).animation(reduceMotion ? nil : .default, value: seconds)
            .accessibilityAddTraits(.updatesFrequently)
    }
    /// The navy room: an active session (the break screen excluded) and the completion card (docs/specs/2026-11-20-navy-focus-room-design.md).
    private var isRoom: Bool { model.isActive || (model.completedSessionID != nil && !model.isInSession) }
    /// The crossfade of the room; none with Reduce Motion on.
    private var roomAnimation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.35) }
    /// DEBUG device diagnostics live in settings and must stay reachable during a session (docs/notes/development-launch-arguments.md, device diagnostics step 2).
    private var showsDiagnostics: Bool {
        #if DEBUG
        model.services.diagnostics != nil
        #else
        false
        #endif
    }
    /// Completed sessions only: early exits and interruptions do not count toward today's focus.
    private var todaySummary: String {
        guard model.errorMessage == nil else { return "오늘의 기록" }
        return SessionSummary(records: model.records).text
    }
    private var completedMinutes: Int { Int(model.completedLength ?? model.services.settings.lengthSeconds) / 60 }
    private func refreshIfIdle() { if !model.isStarting { model.refresh() } }
    /// The review's form when it opens: pages while the trial grants access, one sheet otherwise.
    private var reviewForm: ReviewForm {
        guard let paidAccess else { return .sheet }
        return PaidAccess.reviewForm(configuration: paidAccess.configuration, facts: paidAccess.facts, now: Date())
    }
    /// Fixes day 1, keeps the pending notification in line with paid access, and shows the explanation when it is due.
    private func refreshReview() {
        guard let review, let paidAccess else { return }
        Task {
            await review.refresh(state: paidAccess.state, configuration: paidAccess.configuration, facts: paidAccess.facts)
            presentReviewOrExplanation()
        }
    }
    /// The review and the explanation never show over a running session or a break. The review replaces the calendar sheet, from its entry,
    /// and waits for any other sheet, such as an editor with a draft, to close; the explanation waits for the idle screen with no sheet.
    private func presentReviewOrExplanation() {
        guard let review, !model.isInSession, !model.isStarting else { return }
        if review.request != nil {
            // With access `locked` there is no entry to the review, also from a notification that fired before a trial end or a refund,
            // and a review that is already open closes.
            if paidAccess?.state == .locked {
                if sheet == .review { sheet = nil } else { review.close() }
                return
            }
            guard sheet == nil || sheet == .history, review.presentRequest() else { return }
            sheet = .review
        } else if review.explanationDue, sheet == nil, model.completedSessionID == nil, review.presentExplanation() {
            sheet = .reviewExplanation
        }
    }
    private func cancelPendingStart() {
        if let request = model.startRequestID { model.cancelPendingStart(request) }
    }
    private func blockerText(_ blocker: StartBlocker) -> String {
        switch blocker {
        case .access: "스크린 타임 권한을 허용하면 시작할 수 있어요."
        case .checking: "스크린 타임 권한을 확인하고 있어요. 시작하면 다시 확인해요."
        case .error: "오류를 다시 확인한 뒤에 시작할 수 있어요."
        case .selection: "제한할 앱이나 웹사이트를 고르면 시작할 수 있어요."
        }
    }
    @ViewBuilder private var selectionEditor: some View {
        #if DEBUG
        if let fixture = model.services.selection as? FixtureSelection { FixtureSelectionEditor(repository: fixture) }
        else { SelectionEditor(model: model) }
        #else
        SelectionEditor(model: model)
        #endif
    }
}
private enum FocusSheet: String, Identifiable { case selection, settings, everydaySettings, history, endConfirmation, paywall, review, reviewExplanation; var id: String { rawValue } }

/// The feedback of a pending break action, in the place of the action on the screen that shows it.
struct BreakFeedback: View {
    let model: FocusModel
    let pending: PendingBreak
    var textColor = FocusTheme.Palette.secondaryText
    var body: some View {
        PendingFeedback(request: pending.id, text: text, identifier: "breakProgress", textColor: textColor, hold: hold, ready: model.performPendingBreak, cancel: model.cancelPendingBreak)
    }
    private var text: String {
        switch pending.action {
        case .request: "쉬는 시간을 준비하고 있어요"
        case .startBreak: "쉬는 시간을 시작하고 있어요"
        case .cancelWait, .resume: "집중으로 돌아가고 있어요"
        }
    }
    private var hold: TimeInterval {
        #if DEBUG
        model.services.fixtureBreakHold
        #else
        0
        #endif
    }
}

/// A mounted native feedback view provides a frame opportunity before a synchronous control call.
/// The start and the break transitions share it; each passes its own text and accessibility identifier.
struct PendingFeedback: UIViewRepresentable {
    let request: UUID
    var text = "집중 시간을 시작하고 있어요"
    var identifier = "startProgress"
    var textColor = FocusTheme.Palette.secondaryText
    /// DEBUG fixtures only: seconds to keep the feedback after the frame boundary, without blocking the main thread.
    var hold: TimeInterval = 0
    let ready: (UUID) -> Void
    let cancel: (UUID) -> Void
    func makeUIView(context: Context) -> PendingFeedbackView { PendingFeedbackView() }
    func updateUIView(_ uiView: PendingFeedbackView, context: Context) {
        uiView.configure(request: request, text: text, identifier: identifier, textColor: UIColor(textColor), hold: hold, ready: ready, cancel: cancel)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PendingFeedbackView, context: Context) -> CGSize? {
        uiView.systemLayoutSizeFitting(CGSize(width: proposal.width ?? 320, height: UIView.layoutFittingCompressedSize.height),
                                       withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
    }
    static func dismantleUIView(_ uiView: PendingFeedbackView, coordinator: ()) { uiView.cancel() }
}
final class PendingFeedbackView: UIView {
    private var request: UUID?
    private var ready: ((UUID) -> Void)?
    private var cancellation: ((UUID) -> Void)?
    private var hold: TimeInterval = 0
    private var displayLink: CADisplayLink?
    private var firstFrame: CFTimeInterval?
    private var completed = false
    private let label = UILabel()
    init() {
        super.init(frame: .zero)
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.startAnimating()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [indicator, label])
        stack.spacing = FocusTheme.Layout.inlineSpacing; stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        ])
        isUserInteractionEnabled = false; isAccessibilityElement = true
        accessibilityTraits = .staticText
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(request: UUID, text: String, identifier: String, textColor: UIColor, hold: TimeInterval, ready: @escaping (UUID) -> Void, cancel: @escaping (UUID) -> Void) {
        self.ready = ready; cancellation = cancel; self.hold = hold
        label.textColor = textColor; label.text = text; accessibilityLabel = text; accessibilityIdentifier = identifier
        guard self.request != request else { return }
        invalidate(); self.request = request; completed = false
        setNeedsLayout()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { invalidate() }
        else { setNeedsLayout() }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard window != nil, bounds.width > 0, bounds.height > 0, request != nil, !completed, displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(frameReady(_:)))
        displayLink = link; link.add(to: .main, forMode: .common)
    }
    @objc private func frameReady(_ link: CADisplayLink) {
        guard window != nil, UIApplication.shared.applicationState == .active else { firstFrame = nil; return }
        guard let firstFrame else { firstFrame = link.timestamp; return }
        guard link.timestamp > firstFrame, let request else { return }
        // Two distinct display ticks provide a render opportunity, not proof of physical presentation.
        completed = true; invalidate()
        guard hold > 0 else { ready?(request); return }
        // A held request runs only if it is still this view's request; a cancel or a new request in the meantime drops it.
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
            guard let self, self.request == request, self.window != nil else { return }
            self.ready?(request)
        }
    }
    private func invalidate() { displayLink?.invalidate(); displayLink = nil; firstFrame = nil }
    func cancel() {
        invalidate()
        guard let request else { return }
        self.request = nil
        let cancellation = cancellation
        // Teardown can run during a SwiftUI update; defer the observable mutation and reject stale IDs in the model.
        DispatchQueue.main.async { cancellation?(request) }
    }
}

private extension View {
    /// A text color that crossfades with the room background. The animation is scoped to the color, because an animation
    /// over the whole screen left the glass buttons of the completion card light on navy (iOS 26.5 simulator, 2026-11-20).
    func roomForeground(_ color: Color, animation: Animation?) -> some View {
        self.animation(animation) { $0.foregroundStyle(color) }
    }
}
