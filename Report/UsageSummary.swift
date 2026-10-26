import Foundation
/// Exists only in Report memory. No persistence or host transport.
struct UsageSummary {
    let total: TimeInterval?
    init(durations: [TimeInterval]) { total = durations.isEmpty ? nil : durations.reduce(0, +) }
}
