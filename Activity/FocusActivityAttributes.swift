import ActivityKit
import Foundation

struct FocusActivityAttributes: ActivityAttributes {
    typealias ContentState = FocusActivityContent
    let sessionID: UUID
}
