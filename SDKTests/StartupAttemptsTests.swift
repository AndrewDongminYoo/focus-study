import XCTest

/// Issue #155: a launch before the first unlock waits for protected data and runs the startup again without a tap.
@MainActor final class StartupAttemptsTests: XCTestCase {
    private struct StorageLocked: Error {}
    /// A startup that fails a set number of times and then loads, as the bootstrap's startup does once files are readable.
    private final class Startup {
        var failures: Int
        private(set) var runs = 0
        init(failures: Int) { self.failures = failures }
        func run() throws {
            runs += 1
            if failures > 0 { failures -= 1; throw StorageLocked() }
        }
    }
    func testFailureBeforeProtectedDataWaitsAndLoadsOnTheSignalWithoutRetryTap() {
        var available = false
        let attempts = StartupAttempts { available }, startup = Startup(failures: 1)
        XCTAssertEqual(attempts.run(startup.run), .waiting)
        available = true
        XCTAssertEqual(attempts.protectedDataDidBecomeAvailable(startup.run), .loaded)
        XCTAssertEqual(attempts.outcome, .loaded); XCTAssertEqual(startup.runs, 2)
    }
    func testFailureWithProtectedDataAvailableShowsTheFailureScreen() {
        let attempts = StartupAttempts { true }, startup = Startup(failures: 1)
        XCTAssertEqual(attempts.run(startup.run), .failed)
        XCTAssertEqual(attempts.outcome, .failed); XCTAssertEqual(startup.runs, 1)
    }
    func testSecondFailureAfterTheSignalShowsTheFailureScreenWithoutLooping() {
        var available = false
        let attempts = StartupAttempts { available }, startup = Startup(failures: 2)
        XCTAssertEqual(attempts.run(startup.run), .waiting)
        available = true
        XCTAssertEqual(attempts.protectedDataDidBecomeAvailable(startup.run), .failed)
        XCTAssertNil(attempts.protectedDataDidBecomeAvailable(startup.run))
        XCTAssertEqual(attempts.outcome, .failed); XCTAssertEqual(startup.runs, 2)
    }
    func testSignalOnTheFailureScreenRetriesOnceAndKeepsTheScreenWhenItFailsAgain() {
        let attempts = StartupAttempts { true }, startup = Startup(failures: 3)
        XCTAssertEqual(attempts.run(startup.run), .failed)
        // nil leaves the failure screen and its message, such as the request to end the session, unchanged.
        XCTAssertNil(attempts.protectedDataDidBecomeAvailable(startup.run))
        XCTAssertNil(attempts.protectedDataDidBecomeAvailable(startup.run))
        XCTAssertEqual(attempts.outcome, .failed); XCTAssertEqual(startup.runs, 2)
        // A retry tap is a new failure and gets its own signal retry.
        XCTAssertEqual(attempts.run(startup.run), .failed)
        XCTAssertEqual(attempts.protectedDataDidBecomeAvailable(startup.run), .loaded)
        XCTAssertEqual(startup.runs, 4)
    }
    func testForegroundWhileWaitingRunsTheStartupWhenTheSignalWasMissed() {
        var available = false
        let attempts = StartupAttempts { available }, startup = Startup(failures: 1)
        XCTAssertEqual(attempts.run(startup.run), .waiting)
        available = true
        XCTAssertEqual(attempts.didBecomeActive(startup.run), .loaded)
        XCTAssertEqual(startup.runs, 2)
    }
    func testForegroundOnTheFailureScreenOrAfterLoadDoesNotRunTheStartup() {
        let failing = StartupAttempts { true }, startup = Startup(failures: 1)
        XCTAssertEqual(failing.run(startup.run), .failed)
        XCTAssertNil(failing.didBecomeActive(startup.run))
        XCTAssertEqual(failing.run(startup.run), .loaded)
        XCTAssertNil(failing.didBecomeActive(startup.run))
        XCTAssertEqual(startup.runs, 2)
    }
    func testSignalAfterLoadOrBeforeAnyAttemptDoesNotRunTheStartup() {
        let attempts = StartupAttempts { true }, startup = Startup(failures: 0)
        XCTAssertNil(attempts.protectedDataDidBecomeAvailable(startup.run))
        XCTAssertEqual(attempts.run(startup.run), .loaded)
        XCTAssertNil(attempts.protectedDataDidBecomeAvailable(startup.run))
        XCTAssertEqual(startup.runs, 1)
    }
}
