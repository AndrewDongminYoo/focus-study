import Foundation
import SwiftUI
import WidgetKit

/// The widget's only file access: one path from the App Group container and the two constants of `TodaySnapshot`.
/// It reads that file and nothing else in the container, writes nothing and lists no directory.
enum TodaySnapshotReader {
    static func read() -> TodaySnapshotRead {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "FocusAppGroupIdentifier") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else { return .unreadable }
        let url = container.appendingPathComponent(TodaySnapshot.directoryName, isDirectory: true).appendingPathComponent(TodaySnapshot.fileName)
        return .read { try Data(contentsOf: url) }
    }
}

struct TodayWidgetEntry: TimelineEntry {
    let date: Date
    let state: TodayWidgetState
}

/// One read for each timeline; each entry's view comes from that read and the entry's date. The policy is `never`: only the app asks for a reload.
struct TodayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry { TodayWidgetEntry(date: Date(), state: TodayWidgetView.sample) }
    func getSnapshot(in context: Context, completion: @escaping (TodayWidgetEntry) -> Void) {
        let now = Date()
        // The gallery shows sample numbers and never reads the snapshot.
        if context.isPreview { return completion(TodayWidgetEntry(date: now, state: TodayWidgetView.sample)) }
        completion(TodayWidgetEntry(date: now, state: TodaySnapshot.state(TodaySnapshotReader.read(), at: now, calendar: .current)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWidgetEntry>) -> Void) {
        let entries = TodaySnapshot.entries(TodaySnapshotReader.read(), now: Date(), calendar: .current).map { TodayWidgetEntry(date: $0.date, state: $0.state) }
        completion(Timeline(entries: entries, policy: .never))
    }
}

/// Today's completed focus time and count. A tap opens the app: no `widgetURL`, no `Link` and no App Intent.
struct TodayFocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodaySnapshot.widgetKind, provider: TodayWidgetProvider()) { entry in
            TodayWidgetView(state: entry.state)
        }
        .configurationDisplayName("오늘 집중")
        .description("오늘 완료한 집중 시간과 횟수를 보여 줘요.")
        .supportedFamilies([.systemSmall])
    }
}
