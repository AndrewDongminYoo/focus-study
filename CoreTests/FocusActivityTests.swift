import XCTest
@testable import FocusCore

final class FocusActivityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1400)
    private func session(_ phase: SessionPhase = .active) -> ControlSession {
        var value = ControlSession(startedAt: Date(timeIntervalSince1970: 1000))
        value.phase = phase
        return value
    }
    func testFocusProjectionUsesPausedFocusEndAndDeadlineSeparately() throws {
        var value = session()
        value.pausedSeconds = 120; value.deadlineCredit = 195
        let projection = try XCTUnwrap(FocusActivityProjection.make(session: value, now: now, timing: .standard))
        XCTAssertEqual(projection.sessionID, value.id)
        XCTAssertEqual(projection.content.phase, .focus)
        XCTAssertEqual(projection.content.targetAt, Date(timeIntervalSince1970: 2620))
        XCTAssertEqual(projection.content.deadline, Date(timeIntervalSince1970: 3295))
        XCTAssertEqual(projection.content.focusRemaining, 1220)
        XCTAssertEqual(projection.content.checkedAt, now)
    }
    func testBreakProjectionKeepsFocusFrozenAndUsesScheduledBreakBoundary() throws {
        var value = session(.onBreak)
        value.pausedAt = Date(timeIntervalSince1970: 1300)
        value.breakEndsAt = Date(timeIntervalSince1970: 1510); value.deadlineCredit = 210
        let content = try XCTUnwrap(FocusActivityProjection.make(session: value, now: now, timing: .standard)).content
        XCTAssertEqual(content.phase, .onBreak)
        XCTAssertEqual(content.targetAt, Date(timeIntervalSince1970: 1510))
        XCTAssertEqual(content.focusRemaining, 1200)
        XCTAssertEqual(content.deadline, Date(timeIntervalSince1970: 3310))
    }
    func testReturnBoundaryIsNotTheAbsoluteSessionDeadline() throws {
        var value = session(.breakOver)
        value.pausedAt = Date(timeIntervalSince1970: 1300)
        value.breakEndsAt = Date(timeIntervalSince1970: 1480); value.deadlineCredit = 195
        let content = try XCTUnwrap(FocusActivityProjection.make(session: value, now: Date(timeIntervalSince1970: 1600), timing: .standard)).content
        XCTAssertEqual(content.phase, .breakOver)
        XCTAssertEqual(content.targetAt, Date(timeIntervalSince1970: 2095))
        XCTAssertEqual(content.deadline, Date(timeIntervalSince1970: 3295))
        let late = try XCTUnwrap(FocusActivityProjection.make(session: value, now: Date(timeIntervalSince1970: 2200), timing: .standard)).content
        XCTAssertEqual(late.targetAt, content.targetAt)
        XCTAssertEqual(late.phase, .breakOver)
        XCTAssertLessThan(late.staleAt, late.checkedAt)
    }
    func testWaitingHasNoExternalRunningCountdown() throws {
        var value = session(.waiting)
        value.pausedAt = Date(timeIntervalSince1970: 1390); value.waitEndsAt = Date(timeIntervalSince1970: 1405)
        let content = try XCTUnwrap(FocusActivityProjection.make(session: value, now: now, timing: .standard)).content
        XCTAssertEqual(content.phase, .waiting)
        XCTAssertNil(content.targetAt)
        XCTAssertEqual(content.staleAt, now)
    }
    func testDeadlineBeforeFocusEndIsNotPresentedAsFocusCompletion() throws {
        var value = session()
        value.pausedSeconds = 900
        let content = try XCTUnwrap(FocusActivityProjection.make(session: value, now: now, timing: .standard)).content
        XCTAssertEqual(content.targetAt, Date(timeIntervalSince1970: 3100))
        XCTAssertEqual(content.focusEnd, Date(timeIntervalSince1970: 3400))
    }
    func testEarlyReturnUsesOnlyActuallyChargedPauseTime() throws {
        var value = session()
        value.pausedSeconds = 75; value.deadlineCredit = 75
        let content = try XCTUnwrap(FocusActivityProjection.make(session: value, now: now, timing: .standard)).content
        XCTAssertEqual(content.targetAt, Date(timeIntervalSince1970: 2575))
        XCTAssertEqual(content.deadline, Date(timeIntervalSince1970: 3175))
        XCTAssertEqual(content.focusRemaining, 1175)
    }
    func testInactiveOrUnreadableStateProducesNoDisplay() {
        XCTAssertNil(FocusActivityProjection.make(session: nil, now: now, timing: .standard))
        for phase in [SessionPhase.preparing, .ending, .terminal] {
            XCTAssertNil(FocusActivityProjection.make(session: session(phase), now: now, timing: .standard))
        }
    }
    func testMalformedTimingAndIncompletePauseAreNotDisplayed() {
        var zeroLength = session(); zeroLength.expiresAt = zeroLength.startedAt
        var negativePause = session(); negativePause.pausedSeconds = -1
        var missingPause = session(.onBreak); missingPause.breakEndsAt = now.addingTimeInterval(30)
        for invalid in [zeroLength, negativePause, missingPause] {
            XCTAssertNil(FocusActivityProjection.make(session: invalid, now: now, timing: .standard))
        }
        XCTAssertNil(FocusActivityProjection.make(session: session(), now: Date(timeIntervalSince1970: .infinity), timing: .standard))
        XCTAssertNil(FocusActivityProjection.make(session: session(), now: Date(timeIntervalSince1970: 999), timing: .standard))
    }
    func testPayloadContainsOnlySmallDisplayMetadata() throws {
        let content = try XCTUnwrap(FocusActivityProjection.make(session: session(), now: now, timing: .standard)).content
        let data = try JSONEncoder().encode(content)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(Set(object.keys).isSubset(of: ["phase", "checkedAt", "targetAt", "deadline", "focusRemaining", "focusEnd"]))
        XCTAssertLessThan(data.count, 4096)
        XCTAssertEqual(try JSONDecoder().decode(FocusActivityContent.self, from: data), content)
    }
    func testPassedFocusEndOrDeadlineRetiresTheOptionalDisplay() {
        XCTAssertNil(FocusActivityProjection.make(session: session(), now: Date(timeIntervalSince1970: 2500), timing: .standard))
        var value = session(.onBreak)
        value.pausedAt = Date(timeIntervalSince1970: 1300); value.breakEndsAt = Date(timeIntervalSince1970: 1510)
        XCTAssertNil(FocusActivityProjection.make(session: value, now: Date(timeIntervalSince1970: 3100), timing: .standard))
    }
}
