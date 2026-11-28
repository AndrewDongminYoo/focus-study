import Foundation
import SwiftUI
import WidgetKit

/// The plan widget's only file access: one path from the App Group container and the two constants of `EverydayPlanFile`.
/// It reads that file and nothing else in the container, writes nothing and lists no directory.
enum EverydayPlanReader {
    static func read() -> TodaySnapshotRead {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "FocusAppGroupIdentifier") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else { return .unreadable }
        let url = container.appendingPathComponent(EverydayPlanFile.directoryName, isDirectory: true).appendingPathComponent(EverydayPlanFile.fileName)
        return .read { try Data(contentsOf: url) }
    }
}

struct EverydayPlanEntry: TimelineEntry {
    let date: Date
    let display: EverydayPlanDisplay
}

/// One read for each timeline; each entry's view comes from that read and the entry's date.
/// The last entry is the next local midnight and the policy is `atEnd`, so a new day needs no write from the app.
struct EverydayPlanProvider: TimelineProvider {
    func placeholder(in context: Context) -> EverydayPlanEntry { EverydayPlanEntry(date: Date(), display: EverydayPlanWidgetView.sample(calendar: .current)) }
    func getSnapshot(in context: Context, completion: @escaping (EverydayPlanEntry) -> Void) {
        let now = Date()
        // The gallery shows the sample plan and never reads the file.
        if context.isPreview { return completion(EverydayPlanEntry(date: now, display: EverydayPlanWidgetView.sample(calendar: .current))) }
        completion(EverydayPlanEntry(date: now, display: EverydayPlanFile.display(EverydayPlanReader.read(), at: now, calendar: .current)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EverydayPlanEntry>) -> Void) {
        let entries = EverydayPlanFile.entries(EverydayPlanReader.read(), now: Date(), calendar: .current).map { EverydayPlanEntry(date: $0.date, display: $0.display) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// Today's plan of the everyday layer as planned times: never a session state or an applied restriction. A tap opens the app.
struct EverydayPlanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: EverydayPlanFile.widgetKind, provider: EverydayPlanProvider()) { entry in
            EverydayPlanWidgetView(display: entry.display)
        }
        .configurationDisplayName("오늘의 제한 계획")
        .description("매일 제한에 정해 둔 오늘의 계획을 시간표로 보여 줘요.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
