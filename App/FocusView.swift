import SwiftUI
import Combine

struct FocusView: View {
    let model: FocusModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: SelectionSheet?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("나를 위한 집중 시간", systemImage: "leaf").font(.headline)
                        Text("주의를 빼앗는 것들을 잠시 내려놓고, 지금 할 일에 집중해 보세요.").foregroundStyle(.secondary)
                        Text(String(format: "%02d:%02d", model.remaining / 60, model.remaining % 60))
                            .font(.system(size: 54, weight: .light, design: .rounded)).monospacedDigit().accessibilityIdentifier("countdown")
                        if model.isActive {
                            Text("집중 시간 진행 중").font(.subheadline)
                            Button("중도 종료", role: .destructive) { model.end() }.accessibilityIdentifier("end")
                        } else {
                            Button("25분 시작") { model.start() }.buttonStyle(.borderedProminent).disabled(!model.canStart).accessibilityIdentifier("start")
                        }
                    }.padding(.vertical, 12)
                } footer: { Text("기록은 실제 공부 여부나 연속 차단을 증명하지 않습니다. 자동 해제는 지연될 수 있습니다.") }
                if model.access != .approved { accessSection }
                Section("제한할 항목") {
                    Button { sheet = .editor } label: {
                        HStack { Label("앱과 웹사이트 선택", systemImage: "hand.raised"); Spacer(); Text("앱 \(model.counts.apps) · 웹 \(model.counts.websites)").foregroundStyle(.secondary) }
                    }.disabled(model.access != .approved || model.isActive || model.isStarting || model.errorMessage != nil).accessibilityIdentifier("selection")
                    Text("웹사이트는 도메인 단위로 제한합니다. 경로별 차단이나 모든 브라우저의 우회 방지를 보장하지 않습니다.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).accessibilityIdentifier("startError")
                        Button("다시 확인") { model.refresh() }.accessibilityIdentifier("retry")
                    }
                }
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
                } footer: { Text("시스템 사용 보고서는 세션 기록과 별개이며 보고서 확장 안에서만 표시됩니다.") }
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
        .onReceive(timer) { _ in if scenePhase == .active { model.tick() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in model.refresh(clockChanged: true) }
    }
    private var accessSection: some View {
        Section("Screen Time 접근") {
            Text("선택한 항목을 제한하고 사용 보고서를 보려면 개인 Screen Time 접근이 필요합니다.")
            if model.access == .notRequested {
                Button("개인 접근 허용") { Task { await model.services.authorization.requestIndividual(); model.refresh() } }.accessibilityIdentifier("authorize")
            } else {
                Text("설정에서 이 앱의 Screen Time 접근을 확인해 주세요.")
                Link("설정 열기", destination: URL(string: UIApplication.openSettingsURLString)!).accessibilityIdentifier("settings")
            }
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
