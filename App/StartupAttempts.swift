import UIKit

/// The startup attempts of the bootstrap screen (issue #155).
/// A launch before the first unlock after a restart cannot read protected files, so its failure waits for protected data instead of showing the failure screen.
@MainActor final class StartupAttempts {
    enum Outcome: Equatable { case loaded, waiting, failed }
    private let isProtectedDataAvailable: @MainActor () -> Bool
    private(set) var outcome: Outcome?
    /// Whether the failure screen still has its one signal retry; only a failure from `run` grants it.
    private var failureSignalRetry = false
    init(isProtectedDataAvailable: @escaping @MainActor () -> Bool = { UIApplication.shared.isProtectedDataAvailable }) {
        self.isProtectedDataAvailable = isProtectedDataAvailable
    }
    /// Runs one startup attempt; a failure shows the failure screen only while protected data is available.
    @discardableResult func run(_ attempt: () throws -> Void) -> Outcome {
        let result = perform(attempt)
        failureSignalRetry = result == .failed
        return result
    }
    /// Runs the startup once more for each protected-data signal while it waits.
    /// A failure screen gets one retry, on the first signal after it, for a failure that read protected data as available just before the signal.
    /// When that retry fails again, the result is nil, so the screen keeps its message, such as the request to end the session.
    func protectedDataDidBecomeAvailable(_ attempt: () throws -> Void) -> Outcome? {
        switch outcome {
        case .waiting:
            return perform(attempt)
        case .failed where failureSignalRetry:
            failureSignalRetry = false
            let result = perform(attempt)
            return result == .failed ? nil : result
        default:
            return nil
        }
    }
    /// Runs the startup once more on a foreground while it waits, in case the protected-data signal did not reach this process; a failure screen keeps its retry button instead.
    func didBecomeActive(_ attempt: () throws -> Void) -> Outcome? {
        guard outcome == .waiting else { return nil }
        return perform(attempt)
    }
    private func perform(_ attempt: () throws -> Void) -> Outcome {
        let result: Outcome
        do { try attempt(); result = .loaded } catch { result = isProtectedDataAvailable() ? .failed : .waiting }
        outcome = result
        return result
    }
}
