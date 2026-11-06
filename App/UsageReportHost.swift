import SwiftUI
import DeviceActivity

struct UsageReportHost: View {
    var body: some View {
        UsageReportContainer { interval in
            DeviceActivityReport(DeviceActivityReport.Context("focus.today"), filter: DeviceActivityFilter(segment: .daily(during: interval), devices: nil))
        }
    }
}
struct UsageReportContainer<Report: View>: View {
    private let report: (DateInterval) -> Report
    @State private var date = Date()
    @State private var refreshID = UUID()
    init(@ViewBuilder report: @escaping (DateInterval) -> Report) { self.report = report }
    var body: some View {
        VStack(spacing: FocusTheme.Layout.relatedSpacing) {
            report(TimeRules.today(now: date, calendar: .current))
                .id(refreshID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("사용량이 보이지 않으면 다시 불러와 주세요.").font(.footnote).foregroundStyle(FocusTheme.Palette.secondaryText)
                .multilineTextAlignment(.center).accessibilityIdentifier("reportWaiting")
        }.padding(FocusTheme.Layout.screenInset).navigationTitle("오늘의 사용 보고서")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { date = Date(); refreshID = UUID() } label: {
                    Label("다시 불러오기", systemImage: "arrow.clockwise")
                }.labelStyle(.iconOnly).accessibilityIdentifier("reportReload")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in date = Date() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in date = Date() }
    }
}
