import SwiftUI

/// Today's sessions and the link to the usage report, opened from the timer screen's bottom summary.
struct TodayHistoryView: View {
    let model: FocusModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("오늘의 세션") {
                    if model.records.isEmpty { Text("아직 기록이 없어요.").foregroundStyle(.secondary) }
                    ForEach(model.records, id: \.id) { record in
                        HStack {
                            VStack(alignment: .leading) { Text(record.startedAt, style: .time); Text(reasonText(record)).font(.caption).foregroundStyle(.secondary) }
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
                    .accessibilityIdentifier("report")
                } footer: { Text("집중 기록과 별도로 기기 사용 시간을 볼 수 있어요.") }
            }
            .navigationTitle("오늘의 기록").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() }.accessibilityIdentifier("historyDone") } }
        }
    }
    private func reasonText(_ record: SessionRecord) -> String {
        switch record.reason {
        case .expired: "\(Int(record.expiresAt.timeIntervalSince(record.startedAt)) / 60)분 만료"
        case .earlyExit: "중도 종료"
        case .authorizationRevoked: "접근 철회로 중단"
        case .startFailed: "시작 실패"
        case .clockChanged: "시각 변경으로 중단"
        case .recoveryInterrupted: "중단된 세션 정리"
        }
    }
}
