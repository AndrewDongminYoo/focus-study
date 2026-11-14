import Foundation

extension TodaySnapshot {
    /// The snapshot of a successful history read of today: the day of the query and the numbers of `SessionSummary`.
    init(records: [SessionRecord], now: Date, calendar: Calendar) {
        let summary = SessionSummary(records: records)
        self.init(dayStart: TimeRules.today(now: now, calendar: calendar).start, completedCount: summary.completedCount, focusSeconds: summary.focusDuration)
    }
}

/// The only writer of `TodaySnapshot/today.json`, in the app process (spec "Writer" and "Refresh").
/// It runs on the main actor, outside every process lock, and never takes the control lock.
@MainActor final class TodaySnapshotWriter {
    let url: URL
    private let read: (URL) throws -> Data
    private let store: (Data, URL, Data.WritingOptions) throws -> Void
    private let reload: () -> Void
    /// `true` after the first write check of this process that ended with a correct file.
    private var checked = false
    /// `container` is the root of the App Group container. `reload` asks WidgetKit for a new timeline of the widget's kind.
    init(container: URL, read: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) },
         store: @escaping (Data, URL, Data.WritingOptions) throws -> Void = TodaySnapshotWriter.replace, reload: @escaping () -> Void) {
        url = container.appendingPathComponent(TodaySnapshot.directoryName, isDirectory: true).appendingPathComponent(TodaySnapshot.fileName)
        self.read = read; self.store = store; self.reload = reload
    }
    nonisolated static func replace(_ data: Data, at url: URL, options: Data.WritingOptions) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: options)
    }
    /// The write check: write only when the decoded content differs, or the file is missing or unreadable.
    /// A reload follows a changed write, and once the first check of the process that ends with a correct file. A thrown write asks for nothing.
    func write(_ snapshot: TodaySnapshot) throws {
        let changed = (try? read(url)).flatMap(TodaySnapshot.decode) != snapshot
        if changed { try store(try snapshot.encoded(), url, SharedControlStore.fileWritingOptions) }
        if changed || !checked { checked = true; reload() }
    }
}
