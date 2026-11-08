import Foundation
/// Break pass timing. Production uses `standard`; only DEBUG fixtures and tests inject other values.
public struct BreakTiming: Equatable {
    public static let maxBreaks = 3
    /// The system minimum for a DeviceActivity interval; a break activity always has this length.
    public static let breakActivityLength: TimeInterval = 900
    public static let standard = BreakTiming(waits: [15, 30, 60], breakLength: 180, slack: 600, staleWaitGrace: 10)
    public var waits: [TimeInterval]
    public var breakLength: TimeInterval
    public var slack: TimeInterval
    public var staleWaitGrace: TimeInterval
    /// The wait before the everyday layer turns off for today. The app keeps it in memory and uses `staleWaitGrace` after it.
    public var everydayOffWait: TimeInterval
    public init(waits: [TimeInterval], breakLength: TimeInterval, slack: TimeInterval, staleWaitGrace: TimeInterval, everydayOffWait: TimeInterval = 30) {
        self.waits = waits; self.breakLength = breakLength; self.slack = slack; self.staleWaitGrace = staleWaitGrace; self.everydayOffWait = everydayOffWait
    }
    /// The break activity warning fires `breakLength` after the break starts.
    public var breakWarning: TimeInterval { Self.breakActivityLength - breakLength }
}
