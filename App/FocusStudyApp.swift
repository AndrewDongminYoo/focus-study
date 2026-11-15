import SwiftUI
import SwiftData

@main struct FocusStudyApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--activity-preview"), index + 1 < ProcessInfo.processInfo.arguments.count {
                FocusActivityPreviewView(mode: ProcessInfo.processInfo.arguments[index + 1])
            } else if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--widget-preview"), index + 1 < ProcessInfo.processInfo.arguments.count {
                TodayWidgetPreviewView(mode: ProcessInfo.processInfo.arguments[index + 1])
            } else { FocusBootstrap() }
            #else
            FocusBootstrap()
            #endif
        }
    }
}
@MainActor private struct FocusBootstrap: View {
    @State private var model: FocusModel?
    @State private var container: ModelContainer?
    @State private var runtime: FocusRuntime?
    @State private var errorMessage: String?
    @State private var attempts = StartupAttempts()
    var body: some View {
        Group {
            if let model, let container {
                Group {
                    switch model.route {
                    case .timer: FocusView(model: model)
                    case .onboarding(let step): OnboardingView(model: model, start: step)
                    }
                }.modelContainer(container)
            }
            else if let errorMessage {
                ContentUnavailableView {
                    Label("앱 데이터를 확인해 주세요", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("다시 확인하기") { load() }.accessibilityIdentifier("startupRetry")
                    if let runtime {
                        Button("현재 세션 종료하기", role: .destructive) {
                            defer { runtime.holder.notifyActivity() }
                            do {
                                try runtime.recovery.endCurrent(now: Date())
                                self.errorMessage = "종료를 요청했어요. 다시 확인해 주세요."
                            } catch { self.errorMessage = "세션 상태를 읽지 못했어요. 다시 확인해 주세요." }
                        }.accessibilityIdentifier("startupEnd")
                    }
                }
            } else { ProgressView("준비 중") }
        }
        .task { if model == nil && errorMessage == nil { load() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // The off call is one-shot, so each foreground repairs a marker that it left set.
            if model != nil, let runtime { Task { await runtime.checkActivation() }; return }
            if let outcome = attempts.didBecomeActive(startup) { show(outcome); return }
            guard model == nil, let runtime else { return }
            defer { runtime.holder.notifyActivity() }
            do { try runtime.recovery.engine.reconcile(now: Date(), authorized: runtime.accessState()) }
            catch { errorMessage = "세션 상태를 확인하지 못했어요. 다시 확인해 주세요." }
        }
        // A launch before the first unlock waits on the progress view and runs the startup again here, without a tap.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            if let outcome = attempts.protectedDataDidBecomeAvailable(startup) { show(outcome) }
        }
    }
    private func load() { show(attempts.run(startup)) }
    private func show(_ outcome: StartupAttempts.Outcome) {
        guard outcome == .failed else { errorMessage = nil; return }
        errorMessage = runtime == nil ? "앱을 준비하지 못했어요. 다시 시도해 주세요." : "선택 항목이나 기록을 불러오지 못했어요. 현재 세션을 종료하거나 다시 시도해 주세요."
    }
    private func startup() throws {
        if runtime == nil { runtime = try .process() }
        guard let runtime else { throw ControlIssue.io }
        let (services, created) = try runtime.prepare()
        let counts = services.selection.counts
        services.settings.migrateIfNeeded(hasSelection: counts.apps + counts.websites > 0)
        container = created
        let loaded = FocusModel(services: services, context: ModelContext(created))
        // A filter call in this process refreshes the screen that is shown.
        runtime.holder.refreshScreens = { [weak loaded] in loaded?.refresh() }
        model = loaded
        Task { await runtime.checkActivation() }
    }
}
