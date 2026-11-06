import Foundation

/// Display metadata only. No restriction tokens, usage, report or history data belongs here.
public struct FocusActivityContent: Codable, Hashable {
    public enum Phase: String, Codable, Hashable { case focus, waiting, onBreak, breakOver }
    public var phase: Phase
    public var checkedAt: Date
    public var targetAt: Date?
    public var deadline: Date
    public var focusRemaining: Int
    public var focusEnd: Date?
    public var staleAt: Date { targetAt ?? checkedAt }
}
