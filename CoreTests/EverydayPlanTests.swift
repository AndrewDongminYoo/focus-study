import XCTest
@testable import FocusCore

/// The pure rules of the everyday plan widget (everyday plan widget design, "Verification for the implementation").
final class EverydayPlanTests: XCTestCase {
    private let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return value
    }()
    /// 2026-11-25 is a Wednesday (weekday 4).
    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }
    private func window(_ start: Int, _ end: Int) -> EverydayWindow { EverydayWindow(kind: .custom, start: start, end: end) }
    private func plan(_ start: Int = 480, _ end: Int = 1080, _ windows: [EverydayWindow] = [], weekdays: [Int]? = nil, offDay: String? = nil, enabled: Bool = true) -> EverydayPlan {
        EverydayPlan(enabled: enabled, rangeStart: start, rangeEnd: end, windows: windows, weekdays: weekdays, offDay: offDay)
    }
    private func read(_ plan: EverydayPlan?, needsCheck: Bool = false) throws -> TodaySnapshotRead {
        .data(try EverydayPlanFile(plan: plan, needsCheck: needsCheck).encoded())
    }
    private func today(_ plan: EverydayPlan, at text: String) throws -> EverydayPlanToday {
        let display = EverydayPlanFile.display(try read(plan), at: date(text), calendar: calendar)
        guard case .today(let today) = display.state else { XCTFail("not a restriction day: \(display.state)"); throw XCTSkip() }
        return today
    }
    private func blocks(_ today: EverydayPlanToday) -> [String?] {
        [today.left.label, today.left.value, today.left.detail, today.right.label, today.right.value, today.right.detail]
    }

    // MARK: Spans

    func testAdjacentWindowsMergeIntoOneUnblockedSpan() {
        let spans = plan(480, 1080, [window(780, 810), window(720, 780)]).spans
        XCTAssertEqual(spans, [EverydayPlanSpan(restricted: true, start: 480, end: 720), EverydayPlanSpan(restricted: false, start: 720, end: 810),
                               EverydayPlanSpan(restricted: true, start: 810, end: 1080)])
    }
    func testWindowsAtTheRangeStartAndEndOpenAndCloseTheDayUnblocked() {
        let spans = plan(480, 1080, [window(480, 510), window(1050, 1080)]).spans
        XCTAssertEqual(spans, [EverydayPlanSpan(restricted: false, start: 480, end: 510), EverydayPlanSpan(restricted: true, start: 510, end: 1050),
                               EverydayPlanSpan(restricted: false, start: 1050, end: 1080)])
    }
    func testAWideSpanGivesUpHalfOfTheGapAtEachInnerEdge() {
        let insets = EverydayPlanSpan.edgeInsets(width: 40, leading: true, trailing: true, gap: 1.4)
        XCTAssertEqual(insets.leading, 0.7, accuracy: 1e-9)
        XCTAssertEqual(insets.trailing, 0.7, accuracy: 1e-9)
        let outer = EverydayPlanSpan.edgeInsets(width: 40, leading: false, trailing: true, gap: 1.4)
        XCTAssertEqual(outer.leading, 0)
    }
    /// The range 00:00–23:55 on 328 pt with windows 12:00–13:00 and 13:05–14:05: the 13:00–13:05 span is about 1.14 pt wide.
    func testAFiveMinuteSpanStaysVisibleBetweenTwoGaps() {
        let width = 328 * 5 / 1435.0
        let insets = EverydayPlanSpan.edgeInsets(width: width, leading: true, trailing: true, gap: 1.4)
        XCTAssertEqual(width - insets.leading - insets.trailing, width / 2, accuracy: 1e-9)
    }

    // MARK: Now and next

    func testBeforeTheRange() throws {
        XCTAssertEqual(blocks(try today(.sample, at: "2026-11-25 07:03")), ["지금 07:00", "제한 전", "08:00부터", "제한", "08:00부터", "12:00까지"])
        let opensUnblocked = plan(480, 1080, [window(480, 510)])
        XCTAssertEqual(blocks(try today(opensUnblocked, at: "2026-11-25 07:00")), ["지금 07:00", "제한 전", "08:00부터", "해제", "08:00부터", "08:30까지"])
    }
    func testRestrictedWithALaterUnblockedSpan() throws {
        let value = try today(.sample, at: "2026-11-25 14:22")
        XCTAssertEqual(value.now, 860)
        XCTAssertTrue(value.left.accent)
        XCTAssertEqual(blocks(value), ["지금 14:20", "제한", "13:00–16:00", "다음 해제", "16:00부터 30분", "그다음 제한 16:30–18:00"])
        XCTAssertEqual(EverydayPlanFile.display(try read(.sample), at: date("2026-11-25 14:22"), calendar: calendar).accessibilityText,
                       "오늘의 제한 계획, 지금 14:20 제한, 13:00부터 16:00까지, 다음 해제 16:00부터 30분, 그다음 제한 16:30부터 18:00까지")
        // An unblocked span that runs to the range end has nothing after it.
        let endsUnblocked = plan(480, 1080, [window(990, 1080)])
        XCTAssertEqual(blocks(try today(endsUnblocked, at: "2026-11-25 09:00")), ["지금 09:00", "제한", "08:00–16:30", "다음 해제", "16:30부터 1시간 30분", nil])
    }
    func testRestrictedWithNoUnblockedSpanLeft() throws {
        XCTAssertEqual(blocks(try today(.sample, at: "2026-11-25 17:00")), ["지금 17:00", "제한", "16:30–18:00", "제한 끝", "18:00", "남은 해제 없음"])
    }
    func testUnblockedWithALaterRestrictedSpan() throws {
        let value = try today(.sample, at: "2026-11-25 12:00")
        XCTAssertFalse(value.left.accent)
        XCTAssertEqual(blocks(value), ["지금 12:00", "해제", "12:00–13:00", "다음 제한", "13:00부터", "16:00까지"])
    }
    func testUnblockedToTheRangeEnd() throws {
        let endsUnblocked = plan(480, 1080, [window(1020, 1080)])
        XCTAssertEqual(blocks(try today(endsUnblocked, at: "2026-11-25 17:59")), ["지금 17:55", "해제", "17:00–18:00", "제한 끝", "18:00", "남은 제한 없음"])
    }
    func testAfterTheRange() throws {
        let value = try today(.sample, at: "2026-11-25 18:00")
        XCTAssertFalse(value.nowIsInsideRange)
        XCTAssertEqual(blocks(value), ["지금 18:00", "제한 끝", "18:00에 끝났어요", "다음 제한", "내일 08:00", nil])
        // The next day's first restricted span, not the range start, when a window opens the range; a later day goes by its weekday.
        let weekdaysOnly = plan(480, 1080, [window(480, 510)], weekdays: [2, 3, 4, 5, 6])
        XCTAssertEqual(try today(weekdaysOnly, at: "2026-11-27 20:00").right.value, "월요일 08:30")
        XCTAssertEqual(try today(weekdaysOnly, at: "2026-11-25 20:00").right.value, "내일 08:30")
    }
    func testARangeThatEndsAt2355NamesTheFirstRestrictionDayAfterIt() throws {
        let late = plan(1300, 1435, weekdays: [4])
        let value = try today(late, at: "2026-11-25 23:57")
        XCTAssertEqual(value.now, 1435)
        XCTAssertEqual(blocks(value), ["지금 23:55", "제한 끝", "23:55에 끝났어요", "다음 제한", "수요일 21:40", nil])
    }
    func testDurationsOfAnHourOrMore() {
        XCTAssertEqual(EverydayPlanFile.duration(30), "30분")
        XCTAssertEqual(EverydayPlanFile.duration(60), "1시간")
        XCTAssertEqual(EverydayPlanFile.duration(90), "1시간 30분")
    }

    // MARK: States

    func testEachEmptyState() throws {
        let at = date("2026-11-25 10:00")
        func state(_ read: TodaySnapshotRead) -> EverydayPlanState { EverydayPlanFile.display(read, at: at, calendar: calendar).state }
        XCTAssertEqual(state(.missing), .noSchedule)
        XCTAssertEqual(state(try read(nil)), .noSchedule)
        XCTAssertEqual(state(.unreadable), .check)
        XCTAssertEqual(state(.data(Data("{".utf8))), .check)
        XCTAssertEqual(state(.data(Data(#"{"needsCheck":false,"schemaVersion":2}"#.utf8))), .check)
        XCTAssertEqual(state(try read(.sample, needsCheck: true)), .check)
        XCTAssertEqual(state(try read(plan(480, 1080, [window(400, 500)]))), .check, "a damaged plan")
        XCTAssertEqual(state(try read(plan(enabled: false))), .off)
        XCTAssertEqual(state(try read(plan(weekdays: [1, 7]))), .dayOff)
        XCTAssertEqual(state(try read(plan(offDay: "2026-11-25"))), .offToday)
        if case .today = state(try read(plan(offDay: "2026-11-24"))) {} else { XCTFail("an off day of another day") }
        XCTAssertEqual(state(.missing).line, "앱에서 매일 제한을 정해 보세요")
        XCTAssertEqual(state(.unreadable).line, "앱에서 확인해 주세요")
        XCTAssertEqual(EverydayPlanState.off.line, "매일 제한이 꺼져 있어요")
        XCTAssertEqual(EverydayPlanState.dayOff.line, "오늘은 제한하지 않는 요일이에요")
        XCTAssertEqual(EverydayPlanState.offToday.line, "오늘은 매일 제한을 꺼 두었어요")
        XCTAssertEqual(EverydayPlanFile.display(.missing, at: at, calendar: calendar).accessibilityText, "오늘의 제한 계획, 앱에서 매일 제한을 정해 보세요")
        XCTAssertEqual(EverydayPlanFile.display(try read(plan(weekdays: [2, 3, 4, 5, 6])), at: at, calendar: calendar).weekdays, "평일")
    }
    func testWeekdaySummaryInEachFirstWeekday() {
        func gregorian(firstWeekday: Int) -> Calendar { var other = calendar; other.firstWeekday = firstWeekday; return other }
        for first in [1, 2] {
            let calendar = gregorian(firstWeekday: first)
            XCTAssertEqual(EverydayPlan.weekdaySummary(EverydaySchedule.allWeekdays, calendar: calendar), "매일")
            XCTAssertEqual(EverydayPlan.weekdaySummary(Set(2...6), calendar: calendar), "평일")
            XCTAssertEqual(EverydayPlan.weekdaySummary([1, 7], calendar: calendar), "주말")
            XCTAssertEqual(EverydayPlan.weekdaySummary([], calendar: calendar), "요일 없음")
            XCTAssertEqual(EverydayPlan.weekdaySummary([2, 4, 6], calendar: calendar), "월, 수, 금")
        }
        XCTAssertEqual(EverydayPlan.weekdaySummary([1, 2, 7], calendar: gregorian(firstWeekday: 1)), "일, 월, 토")
        XCTAssertEqual(EverydayPlan.weekdaySummary([1, 2, 7], calendar: gregorian(firstWeekday: 2)), "월, 토, 일")
    }
    func testDayKeyIsSharedWithTheSchedule() {
        let at = date("2026-11-25 23:59")
        XCTAssertEqual(EverydayPlan.dayKey(of: at, calendar: calendar), "2026-11-25")
        XCTAssertEqual(EverydaySchedule.dayKey(of: at, calendar: calendar), EverydayPlan.dayKey(of: at, calendar: calendar))
    }

    // MARK: Timeline

    func testEntriesEveryFiveMinutesUntilTheNextMidnight() throws {
        let now = date("2026-11-25 14:22"), entries = EverydayPlanFile.entries(try read(.sample), now: now, calendar: calendar)
        XCTAssertEqual(entries.first?.date, now)
        XCTAssertEqual(entries[1].date, date("2026-11-25 14:25"))
        XCTAssertEqual(entries.last?.date, date("2026-11-26 00:00"))
        // 14:25 to 23:55 every 5 minutes, after now and before midnight.
        XCTAssertEqual(entries.count, 1 + 115 + 1)
        let dates = entries.map(\.date)
        for boundary in ["16:00", "16:30", "18:00"] { XCTAssertTrue(dates.contains(date("2026-11-25 \(boundary)")), boundary) }
        // The midnight entry is computed for the new day without the app.
        guard case .today(let midnight) = entries.last!.display.state else { return XCTFail("midnight") }
        XCTAssertEqual(blocks(midnight), ["지금 00:00", "제한 전", "08:00부터", "제한", "08:00부터", "12:00까지"])
        XCTAssertEqual(EverydayPlanFile.entries(try read(.sample), now: date("2026-11-25 00:00"), calendar: calendar).count, 288 + 1)
    }
    func testEntriesOfA25HourDayReachTheLastHour() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let formatter = DateFormatter()
        formatter.calendar = newYork; formatter.timeZone = newYork.timeZone; formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        // Daylight saving time ends on 2026-11-01 in New York, so that local day has 25 hours.
        let now = formatter.date(from: "2026-11-01 00:00")!, entries = EverydayPlanFile.entries(try read(plan(1300, 1435)), now: now, calendar: newYork)
        let dates = entries.map(\.date)
        XCTAssertTrue(dates.contains(formatter.date(from: "2026-11-01 23:55")!), "the range end at 23:55")
        XCTAssertEqual(dates.last, formatter.date(from: "2026-11-02 00:00"))
        XCTAssertEqual(entries.count, 1 + 299 + 1)
    }
    func testADayWithoutRestrictionHasTwoEntries() throws {
        let now = date("2026-11-25 10:00")
        let entries = EverydayPlanFile.entries(try read(plan(weekdays: [5])), now: now, calendar: calendar)
        XCTAssertEqual(entries.map(\.date), [now, date("2026-11-26 00:00")])
        XCTAssertEqual(entries.map(\.display.state.line), ["오늘은 제한하지 않는 요일이에요", nil], "Thursday is a chosen weekday")
    }

    // MARK: The writer's table

    func testEachAppReadGivesItsPlanFile() {
        let schedule = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 480, rangeEnd: 1080, windows: [EverydaySchedule.template(.lunch)!],
                                        offDay: "2026-11-25", weekdays: [2, 3, 4, 5, 6])
        let expected = EverydayPlan(enabled: true, rangeStart: 480, rangeEnd: 1080, windows: [EverydaySchedule.template(.lunch)!], weekdays: [2, 3, 4, 5, 6], offDay: "2026-11-25")
        func status(_ schedule: EverydaySchedule?, _ issue: EverydayIssue?) -> EverydayStatus {
            EverydayStatus(schedule: schedule, blocksNow: false, nextChange: nil, issue: issue)
        }
        XCTAssertEqual(EverydayPlanFile.written(for: status(schedule, nil), access: .approved), EverydayPlanFile(plan: expected, needsCheck: false))
        XCTAssertEqual(EverydayPlanFile.written(for: status(schedule, nil), access: .unknown), EverydayPlanFile(plan: expected, needsCheck: false))
        for issue in [EverydayIssue.registrationFailed, .notApplied, .notCleared] {
            XCTAssertEqual(EverydayPlanFile.written(for: status(schedule, issue), access: .approved), EverydayPlanFile(plan: expected, needsCheck: true), "\(issue)")
        }
        XCTAssertEqual(EverydayPlanFile.written(for: status(schedule, nil), access: .denied), EverydayPlanFile(plan: expected, needsCheck: true))
        XCTAssertEqual(EverydayPlanFile.written(for: status(nil, nil), access: .approved), EverydayPlanFile(plan: nil, needsCheck: false))
        XCTAssertNil(EverydayPlanFile.written(for: status(nil, .unreadable), access: .approved), "a read or decode error writes nothing")
        XCTAssertNil(EverydayPlanFile.written(for: status(schedule, .unchecked), access: .approved))
    }
    func testThePlanFileHoldsOnlyThePlanFields() throws {
        let schedule = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: 480, rangeEnd: 1080, windows: [])
        let data = try XCTUnwrap(EverydayPlanFile.written(for: EverydayStatus(schedule: schedule, blocksNow: true, nextChange: nil, issue: nil), access: .approved)).encoded()
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["needsCheck", "plan", "schemaVersion"])
        let plan = try XCTUnwrap(object["plan"] as? [String: Any])
        XCTAssertEqual(Set(plan.keys), ["enabled", "rangeEnd", "rangeStart", "windows"])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(schedule.revision.uuidString))
    }
}
