import SwiftUI

/// Today's sessions and the link to the usage report, opened from the timer screen's bottom summary.
struct TodayHistoryView: View {
    let model: FocusModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let error = model.errorMessage {
                        Text(error).foregroundStyle(.secondary).accessibilityIdentifier("historyError")
                        Button("다시 확인하기") { model.refresh() }.accessibilityIdentifier("historyRetry")
                    } else {
                        Text(SessionSummary(records: model.records).text)
                            .accessibilityIdentifier("historySummary")
                    }
                }
                if model.errorMessage == nil {
                    Section("오늘의 세션") {
                        if model.records.isEmpty { Text("아직 기록이 없어요.").foregroundStyle(.secondary) }
                        ForEach(model.records, id: \.id) { record in
                            HStack {
                                if record.reason == .expired {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                        .accessibilityLabel("완료").accessibilityIdentifier("completedSessionIcon")
                                }
                                VStack(alignment: .leading) { Text(record.startedAt, style: .time); Text(reasonText(record)).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                            }
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
                    .accessibilityIdentifier("report")
                } footer: { Text("집중 기록과 별도로 기기 사용 시간을 볼 수 있어요.") }
            }
            .navigationTitle("오늘의 기록").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() }.accessibilityIdentifier("historyDone") } }
        }
    }
    private func reasonText(_ record: SessionRecord) -> String {
        switch record.reason {
        case .expired: "\(Duration.seconds(record.focusDuration).formatted(.units(allowed: [.hours, .minutes], width: .wide))) 완료"
        case .earlyExit: "집중 종료"
        case .authorizationRevoked: "접근 철회로 중단"
        case .startFailed: "시작 실패"
        case .clockChanged: "시각 변경으로 중단"
        case .recoveryInterrupted: "중단된 세션 정리"
        case .deadlineMissed: "시간 초과로 집중에서 제외"
        }
    }
}
