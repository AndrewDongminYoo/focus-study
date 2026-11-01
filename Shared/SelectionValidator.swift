import Foundation
public enum SelectionIssue: Error, Equatable { case empty, tooManyApps, tooManyWebsites, categoriesUnsupported }
public enum SelectionValidator {
    public static func validate(appCount: Int, webCount: Int, categoryCount: Int) throws {
        guard categoryCount == 0 else { throw SelectionIssue.categoriesUnsupported }
        guard appCount <= 50 else { throw SelectionIssue.tooManyApps }
        guard webCount <= 50 else { throw SelectionIssue.tooManyWebsites }
        guard appCount + webCount > 0 else { throw SelectionIssue.empty }
    }
    /// Both selections together: the shield limit of 50 tokens is per app, not per store (spec "Selection").
    public static let unionLimit = 50
    /// `apps` and `websites` count the distinct tokens of the focus and the everyday selection together.
    public static func validateUnion(apps: Int, websites: Int) throws {
        guard apps <= unionLimit else { throw SelectionIssue.tooManyApps }
        guard websites <= unionLimit else { throw SelectionIssue.tooManyWebsites }
    }
}
