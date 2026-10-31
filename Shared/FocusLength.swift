import Foundation
/// Focus lengths a person can choose; a stored session must use one of them.
public enum FocusLength {
    public static let allowedMinutes = [25, 30, 35, 40, 45, 50]
    public static let defaultMinutes = 25
    public static func isAllowed(seconds: TimeInterval) -> Bool {
        allowedMinutes.contains { abs(TimeInterval($0 * 60) - seconds) < 0.01 }
    }
}
