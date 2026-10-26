import SwiftUI
import DeviceActivity
import FamilyControls
import ManagedSettings
import ExtensionKit

@main struct FocusReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene { FocusReportScene { configuration in UsageSummaryView(configuration: configuration) } }
}
struct AppUsage: Identifiable { let token: ApplicationToken; let duration: TimeInterval; var id: ApplicationToken { token } }
struct WebUsage: Identifiable { let token: WebDomainToken; let duration: TimeInterval; var id: WebDomainToken { token } }
struct ReportConfiguration {
    let summary: UsageSummary
    let apps: [AppUsage]
    let websites: [WebUsage]
}
struct FocusReportScene: DeviceActivityReportScene {
    let context = DeviceActivityReport.Context("focus.today")
    let content: (ReportConfiguration) -> UsageSummaryView
    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> ReportConfiguration {
        var durations: [TimeInterval] = []
        var apps: [(key: ApplicationToken, duration: TimeInterval)] = []
        var websites: [(key: WebDomainToken, duration: TimeInterval)] = []
        for await device in data {
            for await segment in device.activitySegments {
                durations.append(segment.totalActivityDuration)
                for await category in segment.categories {
                    for await app in category.applications {
                        if let token = app.application.token { apps.append((token, app.totalActivityDuration)) }
                    }
                    for await web in category.webDomains {
                        if let token = web.webDomain.token { websites.append((token, web.totalActivityDuration)) }
                    }
                }
            }
        }
        return ReportConfiguration(summary: UsageSummary(durations: durations),
            apps: UsageSummary.grouped(apps).sorted { $0.value > $1.value }.map { AppUsage(token: $0.key, duration: $0.value) },
            websites: UsageSummary.grouped(websites).sorted { $0.value > $1.value }.map { WebUsage(token: $0.key, duration: $0.value) })
    }
}
struct UsageSummaryView: View {
    let configuration: ReportConfiguration
    var body: some View {
        List {
            UsageSummarySection(total: configuration.summary.total)
            if !configuration.apps.isEmpty {
                Section("앱") { ForEach(configuration.apps) { row in HStack { Label(row.token); Spacer(); Text(formatted(row.duration)) } } }
            }
            if !configuration.websites.isEmpty {
                Section("웹사이트") { ForEach(configuration.websites) { row in HStack { Label(row.token); Spacer(); Text(formatted(row.duration)) } } }
            }
            Section { Text("다음 집중 시간에 제한할 항목을 골라보세요.").font(.footnote) }
        }
    }
    private func formatted(_ seconds: TimeInterval) -> String { Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .wide)) }
}
