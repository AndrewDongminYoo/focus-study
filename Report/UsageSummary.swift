import Foundation
/// Exists only in Report memory. No persistence or host transport.
struct UsageSummary {
    let total: TimeInterval?
    init(durations: [TimeInterval]) { total = durations.isEmpty ? nil : durations.reduce(0, +) }
    static func grouped<Key: Hashable>(_ entries: [(key: Key, duration: TimeInterval)]) -> [Key: TimeInterval] {
        entries.reduce(into: [:]) { totals, entry in totals[entry.key, default: 0] += entry.duration }
    }
}
