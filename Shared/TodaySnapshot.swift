import Foundation

/// The display copy of today's history that the app writes and the home screen widget reads (spec "Data path").
/// It holds today's completed count and focus seconds only: no session, time of a session, end reason, token, name or usage.
public struct TodaySnapshot: Codable, Equatable {
    public static let schema = 1
    /// `TodaySnapshot/today.json` in the App Group container, next to `SessionControl/`.
    public static let directoryName = "TodaySnapshot", fileName = "today.json"
    /// The widget's `kind`, which the app's reload request names.
    public static let widgetKind = "TodayFocusWidget"
    /// One week of seconds: far above what the sessions of one day can hold, so only a damaged file reaches it.
    public static let maxFocusSeconds: TimeInterval = 7 * 86_400
    public var schemaVersion: Int
    /// The start of the local day of the app's history query.
    public var dayStart: Date
    public var completedCount: Int
    public var focusSeconds: Double
    public init(dayStart: Date, completedCount: Int, focusSeconds: Double) {
        schemaVersion = Self.schema; self.dayStart = dayStart; self.completedCount = completedCount; self.focusSeconds = focusSeconds
    }
    /// The count is 0 exactly when the seconds are 0; every other content gives the Check view.
    public var isValid: Bool {
        completedCount >= 0 && focusSeconds.isFinite && focusSeconds >= 0 && focusSeconds <= Self.maxFocusSeconds && (completedCount == 0) == (focusSeconds == 0)
    }
    /// The default date strategy stores the exact `Double`, so the day check compares the same `Date` that the app wrote.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }
    public static func decode(_ data: Data) -> TodaySnapshot? { try? JSONDecoder().decode(TodaySnapshot.self, from: data) }
    /// The time format of the today summary, `1시간 15분`.
    public static func durationText(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }
}

/// What a read of the snapshot file found.
public enum TodaySnapshotRead: Equatable {
    case missing, unreadable, data(Data)
    /// A missing file is `missing`; every other error, such as file protection before the first unlock, is `unreadable`.
    public static func read(_ load: () throws -> Data) -> TodaySnapshotRead {
        do { return .data(try load()) }
        catch CocoaError.fileReadNoSuchFile { return .missing }
        catch { return .unreadable }
    }
}

/// The three views of the widget (spec "What the widget shows").
public enum TodayWidgetState: Equatable {
    case numbers(count: Int, focusSeconds: Double)
    case empty
    case check
}

extension TodaySnapshot {
    /// The view for the entry date, with the widget's own calendar. The snapshot is for that day only when `dayStart` is the start of that day.
    public static func state(_ read: TodaySnapshotRead, at date: Date, calendar: Calendar) -> TodayWidgetState {
        switch read {
        case .missing: return .empty
        case .unreadable: return .check
        case .data(let data):
            guard let snapshot = decode(data), snapshot.schemaVersion == schema, snapshot.isValid else { return .check }
            guard calendar.startOfDay(for: date) == snapshot.dayStart, snapshot.completedCount > 0 else { return .empty }
            return .numbers(count: snapshot.completedCount, focusSeconds: snapshot.focusSeconds)
        }
    }
    /// The entries of one timeline, each computed from the same read and its own date (spec "Refresh"); the policy is always `never`.
    /// Numbers get a second entry at the next local start of day, which the day check turns into Empty.
    public static func entries(_ read: TodaySnapshotRead, now: Date, calendar: Calendar) -> [(date: Date, state: TodayWidgetState)] {
        let current = state(read, at: now, calendar: calendar)
        guard case .numbers = current, let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return [(now, current)] }
        let nextDay = calendar.startOfDay(for: next)
        return [(now, current), (nextDay, state(read, at: nextDay, calendar: calendar))]
    }
}
