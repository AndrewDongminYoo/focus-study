import SwiftUI
import Combine

struct FocusView: View {
    let model: FocusModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 54
    @State private var sheet: SelectionSheet?
    @State private var confirmingEnd = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        NavigationStack {
            List {
                if model.access != .approved { accessSection }
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("나를 위한 집중 시간", systemImage: "leaf").font(.headline)
                        Text("25분 동안, 지금 할 일에 집중해 보세요.").foregroundStyle(.secondary)
                        if model.completedSessionID != nil {
                            Label("25분 집중을 마쳤습니다", systemImage: "checkmark.circle.fill").font(.title2.weight(.semibold)).foregroundStyle(.green).accessibilityIdentifier("completion")
                            Text("오늘의 세션에 기록했습니다. 잠시 쉬었다가 다음 집중을 시작해 보세요.").foregroundStyle(.secondary)
                            Button("닫기") { model.dismissCompletion() }.buttonStyle(.bordered).accessibilityIdentifier("completionDismiss")
                        } else {
                        Text(String(format: "%02d:%02d", model.remaining / 60, model.remaining % 60))
                            .font(.system(size: countdownSize, weight: .light, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                            .contentTransition(.numericText(countsDown: true)).animation(reduceMotion ? nil : .default, value: model.remaining)
                            .accessibilityLabel("남은 시간 \(model.remaining / 60)분 \(model.remaining % 60)초").accessibilityAddTraits(.updatesFrequently)
                            .accessibilityIdentifier("countdown")
                        if model.isActive {
                            Text("집중 시간 진행 중").font(.subheadline)
                            Button("중도 종료", role: .destructive) { confirmingEnd = true }.accessibilityIdentifier("end")
                                .confirmationDialog("집중을 여기서 끝낼까요?", isPresented: $confirmingEnd, titleVisibility: .visible) {
                                    Button("종료하기", role: .destructive) { model.end() }
                                    Button("계속 집중하기", role: .cancel) {}
                                } message: { Text("지금 끝내면 이 세션은 중도 종료로 기록됩니다.") }
                        } else {
                            Button("25분 시작") { model.start() }.buttonStyle(.borderedProminent).disabled(!model.canStart).accessibilityIdentifier("start")
                            if let blocker = model.startBlocker {
                                Text(blockerText(blocker)).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("startBlocker")
                                if blocker == .selection {
                                    Button("제한할 항목 고르기") { sheet = .editor }.buttonStyle(.borderless).accessibilityIdentifier("chooseSelection")
                                }
                            }
                        }
                        }
                    }.padding(.vertical, 12)
                    .sensoryFeedback(.success, trigger: model.completedSessionID) { _, new in new != nil }
                } footer: { Text("제한이 자동으로 풀리기까지 시간이 걸릴 수 있습니다.") }
                Section("제한할 항목") {
                    Button { sheet = .editor } label: {
                        HStack { Label("앱과 웹사이트 선택", systemImage: "hand.raised"); Spacer(); Text("앱 \(model.counts.apps) · 웹 \(model.counts.websites)").foregroundStyle(.secondary) }
                    }.disabled(model.access != .approved || model.isActive || model.isStarting || model.errorMessage != nil).accessibilityIdentifier("selection")
                    Text("웹사이트 전체를 제한합니다. 브라우저에 따라 제한되지 않을 수 있습니다.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).accessibilityIdentifier("startError")
                        Button("다시 확인") { model.refresh() }.accessibilityIdentifier("retry")
                    }
                }
                #if DEBUG
                if let diagnostics = model.services.diagnostics { DeviceDiagnosticsSection(diagnostics: diagnostics, model: model) }
                #endif
                Section("오늘의 세션") {
                    if model.records.isEmpty { Text("아직 기록이 없습니다.").foregroundStyle(.secondary) }
                    ForEach(model.records, id: \.id) { record in
                        HStack {
                            VStack(alignment: .leading) { Text(record.startedAt, style: .time); Text(reason(record.reason)).font(.caption).foregroundStyle(.secondary) }
                            Spacer(); Text("\(Int(record.duration) / 60)분 \(Int(record.duration) % 60)초").monospacedDigit()
                        }
                    }
                }
                Section {
                    NavigationLink { 
                        #if DEBUG
                        if model.services.isFixture { FixtureUsageReportHost() }
                        else { UsageReportHost() }
                        #else
                        UsageReportHost()
                        #endif
                    } label: { Label("오늘의 사용 보고서", systemImage: "chart.bar") }
                    .disabled(model.access != .approved).accessibilityIdentifier("report")
                } footer: { Text("집중 기록과 별도로 기기 사용 시간을 확인합니다.") }
            }
            .navigationTitle("FocusStudy")
            .sheet(item: $sheet) { _ in
                #if DEBUG
                if let fixture = model.services.selection as? FixtureSelection { FixtureSelectionEditor(repository: fixture) }
                else { SelectionEditor(model: model) }
                #else
                SelectionEditor(model: model)
                #endif
            }
        }
        .task { model.refresh() }
        .onChange(of: scenePhase) { _, value in if value == .active { model.refresh() } }
        .onChange(of: model.access) { _, _ in model.refresh() }
        .onChange(of: model.isActive) { _, active in if !active { confirmingEnd = false } }
        .onReceive(timer) { _ in if scenePhase == .active { model.tick() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in model.refresh(clockChanged: true) }
    }
    private var accessSection: some View {
        Section("시작하기 전에") {
            Label("25분 동안 고른 앱과 웹사이트를 제한해서 지금 할 일에 집중하도록 돕습니다.", systemImage: "timer").accessibilityIdentifier("purpose")
            Label("앱 제한과 사용 보고서에 스크린 타임 권한이 필요합니다.", systemImage: "hourglass")
            Label("선택한 항목과 집중 기록은 서버로 보내지 않고 이 기기에 저장합니다.", systemImage: "lock.iphone")
            if model.access == .notRequested {
                Button("권한 허용") { Task { await model.services.authorization.requestIndividual(); model.refresh() } }.buttonStyle(.borderedProminent).accessibilityIdentifier("authorize")
            } else {
                Text("설정에서 스크린 타임 권한을 확인해 주세요.")
                Link("설정 열기", destination: URL(string: UIApplication.openSettingsURLString)!).accessibilityIdentifier("settings")
            }
        }
    }
    private func blockerText(_ blocker: StartBlocker) -> String {
        switch blocker {
        case .access: "스크린 타임 권한을 허용하면 시작할 수 있습니다."
        case .error: "오류를 다시 확인한 뒤에 시작할 수 있습니다."
        case .selection: "제한할 앱이나 웹사이트를 고르면 시작할 수 있습니다."
        }
    }
    private func reason(_ reason: EndReason) -> String {
        switch reason {
        case .expired: "25분 만료"
        case .earlyExit: "중도 종료"
        case .authorizationRevoked: "접근 철회로 중단"
        case .startFailed: "시작 실패"
        case .clockChanged: "시각 변경으로 중단"
        case .recoveryInterrupted: "중단된 세션 정리"
        }
    }
}
private enum SelectionSheet: String, Identifiable { case editor; var id: String { rawValue } }
