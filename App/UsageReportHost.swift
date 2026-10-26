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
        VStack(spacing: 12) {
            Text("보고서를 준비하는 데 시간이 걸릴 수 있습니다. 비어 있는 화면은 사용량이 0이라는 뜻이 아닙니다.").font(.footnote).foregroundStyle(.secondary)
            report(TimeRules.today(now: date, calendar: .current))
                .id(refreshID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button("다시 불러오기") { date = Date(); refreshID = UUID() }.accessibilityIdentifier("reportReload")
        }.padding().navigationTitle("오늘의 사용 보고서")
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in date = Date() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in date = Date() }
    }
}
