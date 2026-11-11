import XCTest
@testable import FocusCore

final class EverydayScheduleTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!; return calendar
    }()
    /// 2026-11-02 at the given local time in Seoul.
    private func at(_ hour: Int, _ minute: Int, _ second: Int = 0, day: Int = 2) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second))!
    }
    private func layer(_ start: Int = 8 * 60, _ end: Int = 18 * 60, windows: [EverydayWindow] = [], enabled: Bool = true) -> EverydaySchedule {
        EverydaySchedule(revision: UUID(), enabled: enabled, rangeStart: start, rangeEnd: end, windows: windows)
    }
    private let lunch = EverydayWindow(kind: .lunch, start: 12 * 60, end: 13 * 60)
    private func window(_ start: Int, _ end: Int) -> EverydayWindow { EverydayWindow(kind: .custom, start: start, end: end) }

    func testValidationAcceptsTheSpecLimitsAndRejectsEachBreach() {
        XCTAssertTrue(layer().isValid)
        XCTAssertTrue(layer(0, 60).isValid)
        XCTAssertTrue(layer(0, 23 * 60 + 55).isValid)
        XCTAssertTrue(layer(windows: [lunch, window(13 * 60, 13 * 60 + 15), window(15 * 60, 17 * 60)]).isValid, "touching windows")
        let breaches: [(String, EverydaySchedule)] = [
            ("range 59 minutes", layer(8 * 60, 8 * 60 + 55 + 4)),
            ("range 55 minutes", layer(8 * 60, 8 * 60 + 55)),
            ("range end 23:56", layer(22 * 60, 23 * 60 + 56)),
            ("range end 24:00", layer(22 * 60, 24 * 60)),
            ("start after end", layer(18 * 60, 8 * 60)),
            ("negative start", layer(-5, 60)),
            ("4 windows", layer(windows: [window(9 * 60, 9 * 60 + 15), window(10 * 60, 10 * 60 + 15), window(11 * 60, 11 * 60 + 15), lunch])),
            ("10-minute window", layer(windows: [window(12 * 60, 12 * 60 + 10)])),
            ("125-minute window", layer(windows: [window(12 * 60, 14 * 60 + 5)])),
            ("window before the range", layer(windows: [window(7 * 60 + 45, 8 * 60 + 15)])),
            ("window after the range", layer(windows: [window(17 * 60 + 45, 18 * 60 + 15)])),
            ("overlapping windows", layer(windows: [lunch, window(12 * 60 + 30, 13 * 60 + 30)])),
            ("windows cover the range", layer(8 * 60, 10 * 60, windows: [window(8 * 60, 9 * 60), window(9 * 60, 10 * 60)])),
            ("off the 5-minute grid", layer(8 * 60 + 1, 18 * 60)),
            ("window off the grid", layer(windows: [window(12 * 60 + 2, 13 * 60 + 2)])),
        ]
        for (name, schedule) in breaches { XCTAssertFalse(schedule.isValid, name) }
    }
    func testIssueNamesTheFirstBrokenRule() {
        XCTAssertNil(layer().issue)
        XCTAssertNil(layer(windows: [lunch, window(13 * 60, 13 * 60 + 15)]).issue, "touching windows")
        let breaches: [(String, EverydaySchedule, EverydayScheduleIssue)] = [
            ("range 59 minutes", layer(8 * 60, 8 * 60 + 59), .offGrid),
            ("window off the grid", layer(windows: [window(12 * 60 + 2, 13 * 60 + 2)]), .offGrid),
            ("negative start", layer(-5, 60), .outOfDay),
            ("range end 24:00", layer(22 * 60, 24 * 60), .outOfDay),
            ("range 55 minutes", layer(8 * 60, 8 * 60 + 55), .rangeTooShort),
            ("range 30 minutes without windows", layer(8 * 60, 8 * 60 + 30), .rangeTooShort),
            ("start after end", layer(18 * 60, 8 * 60), .rangeTooShort),
            ("4 windows", layer(windows: [window(9 * 60, 9 * 60 + 15), window(10 * 60, 10 * 60 + 15), window(11 * 60, 11 * 60 + 15), lunch]), .tooManyWindows),
            ("10-minute window", layer(windows: [window(12 * 60, 12 * 60 + 10)]), .windowLength),
            ("125-minute window", layer(windows: [window(12 * 60, 14 * 60 + 5)]), .windowLength),
            ("window that ends before it starts", layer(windows: [window(13 * 60, 12 * 60)]), .windowLength),
            ("window before the range", layer(windows: [window(7 * 60 + 45, 8 * 60 + 15)]), .windowOutsideRange),
            ("window after the range", layer(windows: [window(17 * 60 + 45, 18 * 60 + 15)]), .windowOutsideRange),
            ("overlapping windows", layer(windows: [lunch, window(12 * 60 + 30, 13 * 60 + 30)]), .windowsOverlap),
            ("windows cover the range", layer(8 * 60, 10 * 60, windows: [window(8 * 60, 9 * 60), window(9 * 60, 10 * 60)]), .windowsCoverRange),
        ]
        for (name, schedule, issue) in breaches {
            XCTAssertEqual(schedule.issue, issue, name)
            XCTAssertFalse(schedule.isValid, name)
        }
        XCTAssertEqual(Set(breaches.map { "\($0.2)" }).count, EverydayScheduleIssue.allCases.count, "every issue has a case")
    }
    func testBlocksUsesHalfOpenIntervals() {
        let schedule = layer(windows: [lunch])
        let expected: [(Date, Bool)] = [
            (at(7, 59, 59), false), (at(8, 0), true), (at(11, 59, 59), true), (at(12, 0), false),
            (at(12, 59, 59), false), (at(13, 0), true), (at(17, 59, 59), true), (at(18, 0), false),
        ]
        for (time, blocks) in expected { XCTAssertEqual(schedule.blocks(at: time, calendar: calendar), blocks, "\(time)") }
        var off = schedule; off.enabled = false
        for (time, _) in expected { XCTAssertFalse(off.blocks(at: time, calendar: calendar)) }
    }
    func testWindowThatStartsAtRangeStartAndWindowThatEndsAtRangeEnd() {
        let schedule = layer(windows: [window(8 * 60, 8 * 60 + 30), window(17 * 60 + 30, 18 * 60)])
        XCTAssertTrue(schedule.isValid)
        XCTAssertFalse(schedule.blocks(at: at(8, 0), calendar: calendar))
        XCTAssertTrue(schedule.blocks(at: at(8, 30), calendar: calendar))
        XCTAssertTrue(schedule.blocks(at: at(17, 29, 59), calendar: calendar))
        XCTAssertFalse(schedule.blocks(at: at(17, 30), calendar: calendar))
        XCTAssertFalse(schedule.blocks(at: at(18, 0), calendar: calendar))
        XCTAssertEqual(schedule.nextChange(after: at(7, 0), calendar: calendar), at(8, 30))
        XCTAssertEqual(schedule.nextChange(after: at(9, 0), calendar: calendar), at(17, 30))
    }
    func testNextChangeGivesTheNextEdgeAndTheNextDayAfterTheRange() {
        let schedule = layer(windows: [lunch])
        XCTAssertEqual(schedule.nextChange(after: at(6, 0), calendar: calendar), at(8, 0))
        XCTAssertEqual(schedule.nextChange(after: at(8, 0), calendar: calendar), at(12, 0))
        XCTAssertEqual(schedule.nextChange(after: at(12, 30), calendar: calendar), at(13, 0))
        XCTAssertEqual(schedule.nextChange(after: at(13, 0), calendar: calendar), at(18, 0))
        XCTAssertEqual(schedule.nextChange(after: at(18, 0), calendar: calendar), at(8, 0, day: 3))
        XCTAssertEqual(schedule.nextChange(after: at(23, 59, 59), calendar: calendar), at(8, 0, day: 3))
        var off = schedule; off.enabled = false
        XCTAssertNil(off.nextChange(after: at(6, 0), calendar: calendar))
    }
    func testBreakLiftsTheLayerOnlyBeforeBreakEndsAt() {
        let schedule = layer(), now = at(10, 0)
        var session = ControlSession(startedAt: now.addingTimeInterval(-300)); session.phase = .onBreak; session.breakEndsAt = now
        XCTAssertFalse(EverydayRules.blocks(schedule: schedule, session: session, authorized: .approved, now: now.addingTimeInterval(-1), calendar: calendar))
        XCTAssertTrue(EverydayRules.blocks(schedule: schedule, session: session, authorized: .approved, now: now, calendar: calendar))
        for phase in [SessionPhase.preparing, .active, .waiting, .breakOver, .ending, .terminal] {
            var other = session; other.phase = phase
            XCTAssertTrue(EverydayRules.blocks(schedule: schedule, session: other, authorized: .approved, now: now.addingTimeInterval(-1), calendar: calendar), "\(phase)")
            XCTAssertFalse(EverydayRules.blocks(schedule: schedule, session: other, authorized: .approved, now: at(7, 0), calendar: calendar), "\(phase)")
        }
        XCTAssertTrue(EverydayRules.blocks(schedule: schedule, session: nil, authorized: .approved, now: now, calendar: calendar))
        XCTAssertFalse(EverydayRules.blocks(schedule: nil, session: nil, authorized: .approved, now: now, calendar: calendar))
    }
    func testUnauthorizedNeverBlocksAndUnknownAccessFollowsTheSchedule() {
        let schedule = layer()
        XCTAssertFalse(EverydayRules.blocks(schedule: schedule, session: nil, authorized: .denied, now: at(10, 0), calendar: calendar))
        XCTAssertTrue(EverydayRules.blocks(schedule: schedule, session: nil, authorized: .unknown, now: at(10, 0), calendar: calendar))
        XCTAssertFalse(EverydayRules.blocks(schedule: schedule, session: nil, authorized: .unknown, now: at(19, 0), calendar: calendar))
    }
    func testStricterEditsAreAcceptedInsideTheRange() {
        let stored = layer(windows: [lunch]), now = at(10, 0)
        let stricter: [(String, EverydaySchedule)] = [
            ("remove the lunch window", layer()),
            ("shorten lunch", layer(windows: [window(12 * 60, 12 * 60 + 30)])),
            ("move the range end later", layer(8 * 60, 19 * 60, windows: [lunch])),
            ("move the range start earlier", layer(7 * 60, 18 * 60, windows: [lunch])),
            ("add a window that ends before 10:00", layer(windows: [window(9 * 60, 10 * 60), lunch])),
            ("same settings", stored),
        ]
        for (name, schedule) in stricter { XCTAssertTrue(schedule.isAtLeastAsStrict(as: stored, from: now, calendar: calendar), name) }
    }
    func testLooserEditsAreRejectedInsideTheRange() {
        let stored = layer(windows: [lunch])
        let looser: [(String, EverydaySchedule, Date)] = [
            ("turn off", layer(windows: [lunch], enabled: false), at(10, 0)),
            ("lengthen lunch", layer(windows: [window(12 * 60, 13 * 60 + 30)]), at(10, 0)),
            ("add a window at 15:00", layer(windows: [lunch, window(15 * 60, 15 * 60 + 30)]), at(10, 0)),
            ("move the range end earlier", layer(8 * 60, 17 * 60, windows: [lunch]), at(10, 0)),
            ("lengthen lunch during lunch", layer(windows: [window(12 * 60, 13 * 60 + 30)]), at(12, 30)),
            ("a window that starts now", layer(windows: [window(10 * 60, 10 * 60 + 15), lunch]), at(10, 0)),
        ]
        for (name, schedule, now) in looser { XCTAssertFalse(schedule.isAtLeastAsStrict(as: stored, from: now, calendar: calendar), name) }
    }
    func testEveryEditIsAcceptedOutsideTheRangeOrWhenNothingIsOn() {
        let stored = layer(windows: [lunch])
        for now in [at(7, 0), at(18, 0)] {
            XCTAssertTrue(layer(windows: [lunch], enabled: false).isAtLeastAsStrict(as: stored, from: now, calendar: calendar))
            XCTAssertTrue(layer(windows: [lunch, window(15 * 60, 15 * 60 + 30)]).isAtLeastAsStrict(as: stored, from: now, calendar: calendar))
        }
        let off = layer(windows: [lunch], enabled: false)
        XCTAssertTrue(layer(8 * 60, 9 * 60).isAtLeastAsStrict(as: off, from: at(10, 0), calendar: calendar))
        XCTAssertTrue(layer(enabled: false).isAtLeastAsStrict(as: off, from: at(10, 0), calendar: calendar))
    }
    func testDecodingTheStoredShapeRoundTrips() throws {
        let schedule = layer(windows: [lunch, EverydayWindow(kind: .toSchool, start: 8 * 60, end: 8 * 60 + 30)])
        let data = try JSONEncoder().encode(schedule)
        XCTAssertEqual(try JSONDecoder().decode(EverydaySchedule.self, from: data), schedule)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["revision", "enabled", "rangeStart", "rangeEnd", "windows"])
        XCTAssertEqual(((object["windows"] as? [[String: Any]])?.first?["kind"]) as? String, "lunch")
        XCTAssertEqual(EverydaySchedule.standard.enabled, false)
        XCTAssertEqual(EverydaySchedule.standard.rangeStart, 480); XCTAssertEqual(EverydaySchedule.standard.rangeEnd, 1080)
        XCTAssertEqual(EverydaySchedule.template(.lunch), lunch)
        XCTAssertEqual(EverydaySchedule.template(.toSchool)?.start, 480); XCTAssertEqual(EverydaySchedule.template(.fromSchool)?.end, 990)
        XCTAssertNil(EverydaySchedule.template(.custom))
    }
    // MARK: Off for today

    private func off(_ schedule: EverydaySchedule, day: Int = 2) -> EverydaySchedule {
        var schedule = schedule; schedule.offDay = EverydaySchedule.dayKey(of: at(12, 0, day: day), calendar: calendar); return schedule
    }
    func testDayKeyIsTheLocalCalendarDayInTheEngineCalendar() {
        XCTAssertEqual(EverydaySchedule.dayKey(of: at(0, 0), calendar: calendar), "2026-11-02")
        XCTAssertEqual(EverydaySchedule.dayKey(of: at(23, 59, 59), calendar: calendar), "2026-11-02")
        XCTAssertEqual(EverydaySchedule.dayKey(of: at(0, 0, day: 3), calendar: calendar), "2026-11-03")
        // 08:00 in Seoul is 23:00 of the day before in UTC, so a time zone change recomputes the key.
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(EverydaySchedule.dayKey(of: at(8, 0), calendar: utc), "2026-11-01")
        let january = calendar.date(from: DateComponents(year: 2027, month: 1, day: 5, hour: 9))!
        XCTAssertEqual(EverydaySchedule.dayKey(of: january, calendar: calendar), "2027-01-05")
    }
    func testAnOffDayBlocksNothingThatDayAndTheScheduleAgainTheNextDay() {
        let schedule = off(layer(windows: [lunch]))
        for time in [at(8, 0), at(10, 0), at(13, 0), at(17, 59, 59)] { XCTAssertFalse(schedule.blocks(at: time, calendar: calendar), "\(time)") }
        for time in [at(8, 0, day: 3), at(13, 0, day: 3)] { XCTAssertTrue(schedule.blocks(at: time, calendar: calendar), "\(time)") }
        XCTAssertTrue(schedule.isOff(at: at(10, 0), calendar: calendar)); XCTAssertFalse(schedule.isOff(at: at(10, 0, day: 3), calendar: calendar))
        XCTAssertTrue(schedule.isInsideRange(at: at(10, 0), calendar: calendar), "the range does not read the off day")
        // A malformed or earlier key matches no day, so the layer blocks by its schedule.
        for key in ["2026-11-2", "garbage", "2026-11-01"] {
            var other = schedule; other.offDay = key
            XCTAssertTrue(other.blocks(at: at(10, 0), calendar: calendar), key)
        }
    }
    func testTheWholeRuleReadsTheOffDayAlsoForTheReBlockAndAfterABreak() {
        let schedule = off(layer()), now = at(10, 0)
        var session = ControlSession(startedAt: now.addingTimeInterval(-300)); session.phase = .onBreak; session.breakEndsAt = now
        // The re-block evaluates the rule without its break line (`session: nil`); the session end evaluates it with the stored `ending` phase.
        XCTAssertFalse(EverydayRules.blocks(schedule: schedule, session: nil, authorized: .unknown, now: now, calendar: calendar))
        for phase in [SessionPhase.onBreak, .breakOver, .ending, .terminal] {
            var other = session; other.phase = phase
            XCTAssertFalse(EverydayRules.blocks(schedule: schedule, session: other, authorized: .approved, now: now, calendar: calendar), "\(phase)")
        }
        XCTAssertEqual(EverydayRules.nextChange(schedule: schedule, session: session, authorized: .approved, now: now.addingTimeInterval(-60), calendar: calendar),
                       at(8, 0, day: 3), "a break that ends on a day that is off changes nothing that day")
    }
    func testNextChangeOnADayThatIsOffIsTheNextDaysFirstBlockedTime() {
        XCTAssertEqual(off(layer(windows: [lunch])).nextChange(after: at(10, 0), calendar: calendar), at(8, 0, day: 3))
        XCTAssertEqual(off(layer(windows: [lunch])).nextChange(after: at(12, 30), calendar: calendar), at(8, 0, day: 3), "skips the window end")
        XCTAssertEqual(off(layer(windows: [lunch])).nextChange(after: at(19, 0), calendar: calendar), at(8, 0, day: 3))
        // A chain of touching windows at the range start: the end of the last one.
        let chain = off(layer(windows: [window(8 * 60, 8 * 60 + 30), window(8 * 60 + 30, 9 * 60)]))
        XCTAssertEqual(chain.nextChange(after: at(10, 0), calendar: calendar), at(9, 0, day: 3))
        XCTAssertEqual(off(layer(windows: [window(8 * 60, 8 * 60 + 30)])).nextChange(after: at(10, 0), calendar: calendar), at(8, 30, day: 3))
        // A range that starts at 00:00 blocks again at midnight.
        XCTAssertEqual(off(layer(0, 10 * 60)).nextChange(after: at(9, 0), calendar: calendar), at(0, 0, day: 3))
        // A day that is not off keeps the existing edges.
        XCTAssertEqual(off(layer(windows: [lunch]), day: 1).nextChange(after: at(10, 0), calendar: calendar), at(12, 0))
    }
    func testLockReasonNamesTheFirstFailedConditionInTheSpecOrder() {
        let stored = layer(windows: [lunch]), now = at(10, 0)
        let cases: [(String, EverydaySchedule, Date, EverydayLockReason?)] = [
            ("turn off, also with a shorter range", layer(8 * 60, 17 * 60, windows: [lunch], enabled: false), now, .turnsOff),
            ("range starts after now, also ends earlier", layer(11 * 60, 17 * 60, windows: [lunch]), now, .rangeExcludesNow),
            ("range ends before now", layer(6 * 60, 9 * 60, windows: []), now, .rangeExcludesNow),
            ("range ends earlier, also with a new window", layer(8 * 60, 17 * 60, windows: [lunch, window(15 * 60, 15 * 60 + 30)]), now, .rangeEndsEarlier),
            ("a new window", layer(windows: [lunch, window(15 * 60, 15 * 60 + 30)]), now, .unblocksTime),
            ("a longer window", layer(windows: [window(12 * 60, 13 * 60 + 30)]), now, .unblocksTime),
            ("a window moved into blocked time", layer(windows: [window(14 * 60, 15 * 60)]), now, .unblocksTime),
            ("stricter", layer(7 * 60, 19 * 60), now, nil),
            ("outside the range", layer(enabled: false), at(19, 0), nil),
        ]
        for (name, schedule, time, reason) in cases {
            XCTAssertEqual(schedule.lockReason(against: stored, at: time, calendar: calendar), reason, name)
            // The conditions compare with the stored schedule without its off day.
            XCTAssertEqual(schedule.lockReason(against: off(stored), at: time, calendar: calendar), reason, "off for today: \(name)")
        }
        XCTAssertEqual(EverydayLockReason.allCases, [.turnsOff, .rangeExcludesNow, .rangeEndsEarlier, .unblocksTime, .removesSelection])
    }
    func testAScheduleWithoutOffDayDecodesWithNoOffDay() throws {
        let json = #"{"revision":"\#(UUID().uuidString)","enabled":true,"rangeStart":480,"rangeEnd":1080,"windows":[]}"#
        XCTAssertNil(try JSONDecoder().decode(EverydaySchedule.self, from: Data(json.utf8)).offDay)
        let keyed = off(layer())
        XCTAssertEqual(try JSONDecoder().decode(EverydaySchedule.self, from: JSONEncoder().encode(keyed)), keyed)
    }
}
