import SwiftUI
import SwiftData

@main struct FocusStudyApp: App {
    var body: some Scene { WindowGroup { FocusBootstrap() } }
}
@MainActor private struct FocusBootstrap: View {
    @State private var model: FocusModel?
    @State private var container: ModelContainer?
    @State private var runtime: FocusRuntime?
    @State private var errorMessage: String?
    var body: some View {
        Group {
            if let model, let container { FocusView(model: model).modelContainer(container) }
            else if let errorMessage {
                ContentUnavailableView {
                    Label("앱 데이터를 확인해 주세요", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("다시 확인하기") { load() }.accessibilityIdentifier("startupRetry")
                    if let runtime {
                        Button("현재 세션 종료하기", role: .destructive) {
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
            guard model == nil, let runtime else { return }
            do { try runtime.recovery.engine.reconcile(now: Date(), authorized: runtime.hasAccess()) }
            catch { errorMessage = "세션 상태를 확인하지 못했어요. 다시 확인해 주세요." }
        }
    }
    private func load() {
        do {
            if runtime == nil {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") { runtime = try .fixture(arguments: ProcessInfo.processInfo.arguments) }
                else { runtime = try .real() }
                #else
                runtime = try .real()
                #endif
            }
            guard let runtime else { throw ControlIssue.io }
            let (services, created) = try runtime.prepare()
            container = created
            model = FocusModel(services: services, context: ModelContext(created))
            errorMessage = nil
        } catch {
            errorMessage = runtime == nil ? "앱을 준비하지 못했어요. 다시 시도해 주세요." : "선택 항목이나 기록을 불러오지 못했어요. 현재 세션을 종료하거나 다시 시도해 주세요."
        }
    }
}
