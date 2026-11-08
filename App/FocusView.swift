import SwiftUI
import Combine
import UIKit

/// The main screen (layout A): a full-screen timer, with selection and settings in the top corners and today's summary at the bottom.
struct FocusView: View {
    let model: FocusModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 54
    @State private var sheet: FocusSheet?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    header
                    if model.current?.isPaused == true {
                        BreakSessionView(model: model, onEnd: { sheet = .endConfirmation })
                            .frame(minHeight: max(0, geometry.size.height - FocusTheme.Layout.minimumTapTarget))
                    } else {
                        Spacer(minLength: 32)
                        center.frame(maxWidth: .infinity).padding(.horizontal, FocusTheme.Layout.screenInset)
                        Spacer(minLength: 64)
                        if model.isActive {
                            focusActions.padding(.horizontal, FocusTheme.Layout.screenInset).padding(.bottom, FocusTheme.Layout.sectionSpacing)
                        } else if model.completedSessionID == nil {
                            Button { sheet = .history } label: {
                                HStack {
                                    Label(todaySummary, systemImage: "clock.arrow.circlepath")
                                    Image(systemName: "chevron.right").font(.footnote)
                                }.frame(minWidth: FocusTheme.Layout.minimumTapTarget, minHeight: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
                            }.font(.subheadline).foregroundStyle(FocusTheme.Palette.primaryText)
                                .modifier(FocusSecondaryAction())
                                .disabled(model.isStarting).accessibilityLabel(todaySummary)
                                .accessibilityIdentifier("todaySummary").padding(.bottom, FocusTheme.Layout.relatedSpacing)
                        }
                    }
                }.frame(minHeight: geometry.size.height)
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .selection: selectionEditor
            case .settings: SettingsView(model: model)
            case .everydaySettings: SettingsView(model: model, opensEveryday: true)
            case .history: TodayHistoryView(model: model)
            case .endConfirmation: FocusEndConfirmation(model: model)
            }
        }
        .sensoryFeedback(.success, trigger: model.completedSessionID) { _, new in new != nil }
        .task { refreshIfIdle() }
        // While the idle screen or the completion card shows, a range or window boundary changes the everyday row with no lock section of the app, and `tick()` does not read it.
        .task(id: model.isInSession ? nil : model.everydayStatus) {
            guard !model.isInSession else { return }
            await EverydaySettingsModel.followStatus({ model.everydayStatus }, now: Date.init) { model.refreshEveryday() }
        }
        .onDisappear { cancelPendingStart() }
        .onChange(of: scenePhase) { _, value in
            // Only the background cancels a wait (spec: background or close); `.inactive` overlays such as Control Center do not.
            switch value {
            case .active: refreshIfIdle()
            case .inactive: model.sceneDidBecomeInactive()
            case .background: model.sceneDidLeaveForeground()
            default: break
            }
        }
        .onChange(of: model.access) { _, _ in cancelPendingStart(); model.refresh() }
        .onChange(of: model.isInSession) { _, inSession in
            if !inSession, sheet == .endConfirmation { sheet = nil }
        }
        .onReceive(timer) { _ in if scenePhase == .active, !model.isStarting, model.pendingBreak == nil { model.tick(defersBreakStart: true) } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshIfIdle() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in refreshIfIdle() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in cancelPendingStart(); model.refresh(clockChanged: true) }
    }
    private var header: some View {
        HStack {
            if !model.isInSession {
                Button { sheet = .selection } label: {
                    Text("제한할 앱").frame(minWidth: FocusTheme.Layout.minimumTapTarget, minHeight: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
                }.modifier(FocusSecondaryAction())
                    .disabled(model.isStarting || model.errorMessage != nil).accessibilityIdentifier("selection")
            }
            Spacer()
            if !model.isInSession || showsDiagnostics {
                Button { sheet = .settings } label: {
                    Image(systemName: "gearshape").frame(width: FocusTheme.Layout.minimumTapTarget, height: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
                }.modifier(FocusSecondaryAction()).disabled(model.isStarting)
                    .accessibilityLabel("설정").accessibilityIdentifier("settingsButton")
            }
        }
        .modifier(FocusGlassGroup()).frame(minHeight: FocusTheme.Layout.minimumTapTarget).padding(.horizontal, FocusTheme.Layout.screenInset)
    }
    @ViewBuilder private var center: some View {
        VStack(spacing: FocusTheme.Layout.controlSpacing) {
            if model.completedSessionID != nil {
                Label("\(completedMinutes)분 집중을 마쳤어요", systemImage: "checkmark.circle.fill").font(.title2.weight(.semibold)).foregroundStyle(FocusTheme.Palette.accent).accessibilityIdentifier("completion")
                Text("오늘의 세션에 기록했어요. 잠시 쉬었다가 다음 집중을 시작해 보세요.").multilineTextAlignment(.center).foregroundStyle(FocusTheme.Palette.secondaryText)
                Text("제한이 풀리기까지 조금 걸릴 수 있어요.").font(.footnote).multilineTextAlignment(.center).foregroundStyle(FocusTheme.Palette.secondaryText).accessibilityIdentifier("releaseDelayNote")
                everydayStatusRow
                Button("닫기") { model.dismissCompletion() }.modifier(FocusSecondaryAction()).accessibilityIdentifier("completionDismiss")
            } else {
                clock(model.remaining)
                    .accessibilityLabel("남은 시간 \(model.remaining / 60)분 \(model.remaining % 60)초").accessibilityIdentifier("countdown")
                if model.isInSession {
                    Text("집중 시간 진행 중").font(.subheadline).foregroundStyle(FocusTheme.Palette.secondaryText)
                } else {
                    Button("집중 시작하기") { model.requestStart() }.modifier(FocusPrimaryAction()).controlSize(.large).modifier(ProminentLabel())
                        .disabled(!model.canStart).accessibilityIdentifier("start")
                    if let request = model.startRequestID {
                        PendingFeedback(request: request, ready: model.performPendingStart, cancel: model.cancelPendingStart)
                            .frame(minHeight: FocusTheme.Layout.minimumTapTarget)
                    }
                    Text("앱 \(model.counts.apps)개 · 웹사이트 \(model.counts.websites)개 제한").font(.footnote).foregroundStyle(FocusTheme.Palette.secondaryText)
                        .monospacedDigit().accessibilityIdentifier("restrictionSummary")
                    everydayStatusRow
                    if let blocker = model.startBlocker {
                        Text(blockerText(blocker)).font(.footnote).foregroundStyle(FocusTheme.Palette.secondaryText).multilineTextAlignment(.center).accessibilityIdentifier("startBlocker")
                    }
                }
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(FocusTheme.Palette.error).accessibilityIdentifier("startError")
                    Button("다시 확인하기") { model.refresh() }.accessibilityIdentifier("retry")
                }
            }
        }
    }
    /// Only the idle screen and the completion card place it; the in-progress screen and the break screen never show it.
    @ViewBuilder private var everydayStatusRow: some View {
        if let line = EverydaySettingsModel.timerLine(model.everydayStatus, calendar: model.services.engine.calendar) {
            Button { sheet = .everydaySettings } label: {
                HStack(spacing: FocusTheme.Layout.detailSpacing) {
                    Text(line).multilineTextAlignment(.center).monospacedDigit()
                    Image(systemName: "chevron.right").font(.caption)
                }.frame(minWidth: FocusTheme.Layout.minimumTapTarget, minHeight: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
            }.buttonStyle(.plain).font(.footnote).foregroundStyle(FocusTheme.Palette.secondaryText)
                .disabled(model.isStarting).accessibilityLabel(line).accessibilityIdentifier("everydayStatusRow")
        }
    }
    private func clock(_ seconds: Int) -> some View {
        Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
            .font(.system(size: countdownSize, weight: .light, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            .contentTransition(.numericText(countsDown: true)).animation(reduceMotion ? nil : .default, value: seconds)
            .accessibilityAddTraits(.updatesFrequently)
    }
    private var focusActions: some View {
        VStack(spacing: FocusTheme.Layout.controlSpacing) {
            // After the third break, the only way to leave before completion is `end`.
            if model.breaksLeft > 0 {
                Button("쉬는 시간 갖기") { model.requestBreakAction(.request) }.modifier(FocusSecondaryAction()).controlSize(.large)
                    .disabled(model.pendingBreak != nil).accessibilityIdentifier("breakStart")
                // The request re-registers monitoring synchronously, which can take seconds on a device; the feedback renders first.
                if let pending = model.pendingBreak, pending.action == .request {
                    BreakFeedback(model: model, pending: pending).frame(minHeight: FocusTheme.Layout.minimumTapTarget)
                } else {
                    Text("쉬는 시간 \(model.breaksLeft)번 남았어요").font(.footnote).foregroundStyle(FocusTheme.Palette.secondaryText).accessibilityIdentifier("breaksLeft")
                }
            }
            Button("집중 종료", role: .destructive) { sheet = .endConfirmation }.frame(minHeight: FocusTheme.Layout.minimumTapTarget)
                .disabled(model.pendingBreak != nil).accessibilityIdentifier("end")
        }
    }
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
    private func cancelPendingStart() {
        if let request = model.startRequestID { model.cancelPendingStart(request) }
    }
    private func blockerText(_ blocker: StartBlocker) -> String {
        switch blocker {
        case .access: "스크린 타임 권한을 허용하면 시작할 수 있어요."
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
private enum FocusSheet: String, Identifiable { case selection, settings, everydaySettings, history, endConfirmation; var id: String { rawValue } }

/// The feedback of a pending break action, in the place of the action on the screen that shows it.
struct BreakFeedback: View {
    let model: FocusModel
    let pending: PendingBreak
    var body: some View {
        PendingFeedback(request: pending.id, text: text, identifier: "breakProgress", hold: hold, ready: model.performPendingBreak, cancel: model.cancelPendingBreak)
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
    /// DEBUG fixtures only: seconds to keep the feedback after the frame boundary, without blocking the main thread.
    var hold: TimeInterval = 0
    let ready: (UUID) -> Void
    let cancel: (UUID) -> Void
    func makeUIView(context: Context) -> PendingFeedbackView { PendingFeedbackView() }
    func updateUIView(_ uiView: PendingFeedbackView, context: Context) {
        uiView.configure(request: request, text: text, identifier: identifier, hold: hold, ready: ready, cancel: cancel)
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
        label.textColor = UIColor(FocusTheme.Palette.secondaryText); label.numberOfLines = 0
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
    func configure(request: UUID, text: String, identifier: String, hold: TimeInterval, ready: @escaping (UUID) -> Void, cancel: @escaping (UUID) -> Void) {
        self.ready = ready; cancellation = cancel; self.hold = hold
        label.text = text; accessibilityLabel = text; accessibilityIdentifier = identifier
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
