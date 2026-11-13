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
                        Text(error).foregroundStyle(FocusTheme.Palette.secondaryText).accessibilityIdentifier("historyError")
                        Button("다시 확인하기") { model.refresh() }.accessibilityIdentifier("historyRetry")
                    } else {
                        VStack(alignment: .leading, spacing: FocusTheme.Layout.detailSpacing) {
                            Text(SessionSummary(records: model.records).text)
                                .font(.title2.weight(.semibold)).monospacedDigit()
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("historySummary")
                            if let streak = model.streak {
                                Text("연속 집중 \(streak)일")
                                    .font(.subheadline).monospacedDigit().foregroundStyle(FocusTheme.Palette.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("historyStreak")
                            }
                        }.padding(.vertical, FocusTheme.Layout.inlineSpacing)
                    }
                }
                if model.errorMessage == nil {
                    Section("오늘의 세션") {
                        if model.records.isEmpty { Text("아직 기록이 없어요.").foregroundStyle(FocusTheme.Palette.secondaryText) }
                        ForEach(model.records, id: \.id) { record in
                            HStack {
                                if record.reason == .expired {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(FocusTheme.Palette.accent)
                                        .accessibilityLabel("완료").accessibilityIdentifier("completedSessionIcon")
                                } else {
                                    Image(systemName: "circle").foregroundStyle(FocusTheme.Palette.secondaryText).accessibilityHidden(true)
                                }
                                VStack(alignment: .leading, spacing: FocusTheme.Layout.detailSpacing) {
                                    Text(record.startedAt, style: .time).font(.headline)
                                    Text(reasonText(record)).font(.subheadline).foregroundStyle(FocusTheme.Palette.secondaryText)
                                }.fixedSize(horizontal: false, vertical: true)
                                Spacer()
                            }.padding(.vertical, FocusTheme.Layout.detailSpacing)
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
            .contentMargins(.horizontal, FocusTheme.Layout.screenInset, for: .scrollContent)
            .navigationTitle("오늘의 기록").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() }.accessibilityIdentifier("historyDone") } }
        }
        .modifier(FocusEditorSheet())
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
