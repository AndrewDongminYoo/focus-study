import SwiftUI
import SwiftData

@main struct FocusStudyApp: App {
    var body: some Scene { WindowGroup { FocusBootstrap() } }
}
private struct FocusBootstrap: View {
    @State private var model: FocusModel?
    @State private var container: ModelContainer?
    @State private var failed = false
    var body: some View {
        Group {
            if let model, let container { FocusView(model: model).modelContainer(container) }
            else if failed {
                ContentUnavailableView("초기 설정을 확인해 주세요", systemImage: "exclamationmark.triangle", description: Text("App Group 식별자와 로컬 저장소를 확인해야 합니다. 개발 서명 설정은 README를 참고해 주세요."))
            } else { ProgressView("준비 중") }
        }
        .task {
            guard model == nil, !failed else { return }
            do {
                let services: FocusServices
                var inMemory = false
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") { services = .fixture(arguments: ProcessInfo.processInfo.arguments); inMemory = true }
                else { services = try .real() }
                #else
                services = try .real()
                #endif
                let created = try ModelContainer(for: SessionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none))
                container = created
                model = FocusModel(services: services, context: ModelContext(created))
            } catch { failed = true }
        }
    }
}
