import Foundation
public enum SelectionIssue: Error, Equatable { case empty, tooManyApps, tooManyWebsites, categoriesUnsupported }
public enum SelectionValidator {
    public static func validate(appCount: Int, webCount: Int, categoryCount: Int) throws {
        guard categoryCount == 0 else { throw SelectionIssue.categoriesUnsupported }
        guard appCount <= 50 else { throw SelectionIssue.tooManyApps }
        guard webCount <= 50 else { throw SelectionIssue.tooManyWebsites }
        guard appCount + webCount > 0 else { throw SelectionIssue.empty }
    }
}
