import SwiftUI
import Combine

/// The main screen (layout A): a full-screen timer, with selection and settings in the top corners and today's summary at the bottom.
struct FocusView: View {
    let model: FocusModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 54
    @State private var sheet: FocusSheet?
    @State private var confirmingEnd = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if !model.isActive {
                    Button("제한할 앱") { sheet = .selection }
                        .disabled(model.isStarting || model.errorMessage != nil).accessibilityIdentifier("selection")
                }
                Spacer()
                if !model.isActive || showsDiagnostics {
                    Button { sheet = .settings } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("설정").accessibilityIdentifier("settingsButton")
                }
            }
            .frame(minHeight: 44).padding(.horizontal)
            Spacer()
            center.frame(maxWidth: .infinity).padding(.horizontal, 24)
            Spacer()
            if !model.isActive && model.completedSessionID == nil {
                Button(todaySummary) { sheet = .history }.font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("todaySummary").padding(.bottom, 12)
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .selection: selectionEditor
            case .settings: SettingsView(model: model)
            case .history: TodayHistoryView(model: model)
            }
        }
        .sensoryFeedback(.success, trigger: model.completedSessionID) { _, new in new != nil }
        .task { model.refresh() }
        .onChange(of: scenePhase) { _, value in if value == .active { model.refresh() } }
        .onChange(of: model.access) { _, _ in model.refresh() }
        .onChange(of: model.isActive) { _, active in if !active { confirmingEnd = false } }
        .onReceive(timer) { _ in if scenePhase == .active { model.tick() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in model.refresh(clockChanged: true) }
    }
    @ViewBuilder private var center: some View {
        VStack(spacing: 16) {
            if model.completedSessionID != nil {
                Label("\(completedMinutes)분 집중을 마쳤어요", systemImage: "checkmark.circle.fill").font(.title2.weight(.semibold)).foregroundStyle(.green).accessibilityIdentifier("completion")
                Text("오늘의 세션에 기록했어요. 잠시 쉬었다가 다음 집중을 시작해 보세요.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("닫기") { model.dismissCompletion() }.buttonStyle(.bordered).accessibilityIdentifier("completionDismiss")
            } else {
                Text(String(format: "%02d:%02d", model.remaining / 60, model.remaining % 60))
                    .font(.system(size: countdownSize, weight: .light, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    .contentTransition(.numericText(countsDown: true)).animation(reduceMotion ? nil : .default, value: model.remaining)
                    .accessibilityLabel("남은 시간 \(model.remaining / 60)분 \(model.remaining % 60)초").accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier("countdown")
                if model.isActive {
                    Text("집중 시간 진행 중").font(.subheadline).foregroundStyle(.secondary)
                    Button("중도 종료", role: .destructive) { confirmingEnd = true }.accessibilityIdentifier("end")
                        .confirmationDialog("집중을 여기서 끝낼까요?", isPresented: $confirmingEnd, titleVisibility: .visible) {
                            Button("종료하기", role: .destructive) { model.end() }
                            Button("계속 집중하기", role: .cancel) {}
                        } message: { Text("지금 끝내면 이 세션은 중도 종료로 기록돼요.") }
                } else {
                    Button("집중 시작하기") { model.start() }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(!model.canStart).accessibilityIdentifier("start")
                    Text("앱 \(model.counts.apps)개 · 웹사이트 \(model.counts.websites)개 제한").font(.footnote).foregroundStyle(.secondary)
                        .monospacedDigit().accessibilityIdentifier("restrictionSummary")
                    if let blocker = model.startBlocker {
                        Text(blockerText(blocker)).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).accessibilityIdentifier("startBlocker")
                    }
                }
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red).accessibilityIdentifier("startError")
                    Button("다시 확인하기") { model.refresh() }.accessibilityIdentifier("retry")
                }
            }
        }
    }
    /// DEBUG device diagnostics live in settings and must stay reachable during a session (README device procedure 2).
    private var showsDiagnostics: Bool {
        #if DEBUG
        model.services.diagnostics != nil
        #else
        false
        #endif
    }
    /// Completed sessions only: early exits and interruptions do not count toward today's focus.
    private var todaySummary: String {
        let completed = model.records.filter { $0.reason == .expired }
        return "오늘 집중 \(Int(completed.reduce(0) { $0 + $1.duration }) / 60)분 · \(completed.count)회"
    }
    private var completedMinutes: Int {
        guard let id = model.completedSessionID, let record = model.records.first(where: { $0.id == id }) else { return model.services.settings.lengthMinutes }
        return Int(record.expiresAt.timeIntervalSince(record.startedAt)) / 60
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
private enum FocusSheet: String, Identifiable { case selection, settings, history; var id: String { rawValue } }
