import Foundation

/// The only writer of `TodaySnapshot/everyday-plan.json`, in the app process (everyday plan widget design, "Data path").
/// It runs on the main actor after an everyday status read, outside every process lock.
@MainActor final class EverydayPlanWriter {
    let url: URL
    private let read: (URL) throws -> Data
    private let store: (Data, URL, Data.WritingOptions) throws -> Void
    private let reload: () -> Void
    /// `true` after the first write check of this process that ended with a correct file.
    private var checked = false
    /// `container` is the root of the App Group container. `reload` asks WidgetKit for a new timeline of the plan widget's kind.
    init(container: URL, read: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) },
         store: @escaping (Data, URL, Data.WritingOptions) throws -> Void = TodaySnapshotWriter.replace, reload: @escaping () -> Void) {
        url = container.appendingPathComponent(EverydayPlanFile.directoryName, isDirectory: true).appendingPathComponent(EverydayPlanFile.fileName)
        self.read = read; self.store = store; self.reload = reload
    }
    /// The write check of `TodaySnapshotWriter`: write only when the decoded content differs, or the file is missing or unreadable.
    func write(_ file: EverydayPlanFile) throws {
        let changed = (try? read(url)).flatMap(EverydayPlanFile.decode) != file
        if changed { try store(try file.encoded(), url, SharedControlStore.fileWritingOptions) }
        if changed || !checked { checked = true; reload() }
    }
}
