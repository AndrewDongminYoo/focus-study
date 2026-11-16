import Foundation

/// Display metadata only. No restriction tokens, usage, report or history data belongs here.
public struct FocusActivityContent: Codable, Hashable {
    /// `openFocus`: a Focus filter session past its base length, which counts up until the Focus turns off (2026-11-16 extension design, decision 25).
    public enum Phase: String, Codable, Hashable { case focus, waiting, onBreak, breakOver, openFocus }
    public var phase: Phase
    public var checkedAt: Date
    public var targetAt: Date?
    public var deadline: Date
    public var focusRemaining: Int
    public var focusEnd: Date?
    /// `openFocus` only: the start of the count-up, so that `now - focusStart` is the focused time. A rollover is never shown as a planned end.
    public var focusStart: Date?
    public var staleAt: Date { targetAt ?? checkedAt }
}
