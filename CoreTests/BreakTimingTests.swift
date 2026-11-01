import XCTest
@testable import FocusCore
final class BreakTimingTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func testStandardTimingMatchesOperatorDecisions() {
        XCTAssertEqual(BreakTiming.standard.waits, [15, 30, 60]); XCTAssertEqual(BreakTiming.standard.breakLength, 180)
        XCTAssertEqual(BreakTiming.standard.slack, 600); XCTAssertEqual(BreakTiming.maxBreaks, 3)
        XCTAssertEqual(BreakTiming.standard.staleWaitGrace, 10)
        XCTAssertEqual(BreakTiming.standard.breakWarning, 720)
    }
    func testDeadlineIsStartPlusLengthPlusBreakCreditPlusSlack() {
        var s = ControlSession(startedAt: start); s.deadlineCredit = 15 + 180
        XCTAssertEqual(s.deadline(timing: .standard), start.addingTimeInterval(1500 + 195 + 600))
    }
    func testTimedEndComparesFocusEndWithDeadline() {
        func session(_ phase: SessionPhase, paused: TimeInterval) -> ControlSession {
            var s = ControlSession(startedAt: start); s.phase = phase; s.deadlineCredit = 195; s.pausedSeconds = paused
            if phase != .active { s.pausedAt = start.addingTimeInterval(1000) }
            return s
        }
        let late = session(.active, paused: 895)
        XCTAssertEqual(late.focusEnd, start.addingTimeInterval(2395))
        XCTAssertNil(late.timedEnd(at: start.addingTimeInterval(2294), timing: .standard))
        XCTAssertEqual(late.timedEnd(at: start.addingTimeInterval(2295), timing: .standard), .deadlineMissed)
        XCTAssertEqual(late.timedEnd(at: start.addingTimeInterval(9000), timing: .standard), .deadlineMissed)
        let onTime = session(.active, paused: 600)
        XCTAssertNil(onTime.timedEnd(at: start.addingTimeInterval(2099), timing: .standard))
        XCTAssertEqual(onTime.timedEnd(at: start.addingTimeInterval(2100), timing: .standard), .expired)
        XCTAssertEqual(onTime.timedEnd(at: start.addingTimeInterval(9000), timing: .standard), .expired)
        let over = session(.breakOver, paused: 0)
        XCTAssertNil(over.timedEnd(at: start.addingTimeInterval(2294), timing: .standard))
        XCTAssertEqual(over.timedEnd(at: start.addingTimeInterval(2295), timing: .standard), .deadlineMissed)
        XCTAssertNil(session(.waiting, paused: 0).timedEnd(at: start.addingTimeInterval(9000), timing: .standard))
    }
    func testFocusedTimeExcludesClosedAndOpenPauses() {
        var s = ControlSession(startedAt: start); s.phase = .breakOver; s.pausedSeconds = 100; s.pausedAt = start.addingTimeInterval(700)
        XCTAssertEqual(s.focused(at: start.addingTimeInterval(1000)), 600)
        XCTAssertTrue(s.isPaused); XCTAssertEqual(s.breaksLeft, 3)
        s.breaksTaken = 2; XCTAssertEqual(s.breaksLeft, 1)
    }
}
