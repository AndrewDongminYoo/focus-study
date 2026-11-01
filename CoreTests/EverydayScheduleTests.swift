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
        XCTAssertFalse(EverydayRules.blocks(schedule: schedule, session: session, authorized: true, now: now.addingTimeInterval(-1), calendar: calendar))
        XCTAssertTrue(EverydayRules.blocks(schedule: schedule, session: session, authorized: true, now: now, calendar: calendar))
        for phase in [SessionPhase.preparing, .active, .waiting, .breakOver, .ending, .terminal] {
            var other = session; other.phase = phase
            XCTAssertTrue(EverydayRules.blocks(schedule: schedule, session: other, authorized: true, now: now.addingTimeInterval(-1), calendar: calendar), "\(phase)")
            XCTAssertFalse(EverydayRules.blocks(schedule: schedule, session: other, authorized: true, now: at(7, 0), calendar: calendar), "\(phase)")
        }
        XCTAssertTrue(EverydayRules.blocks(schedule: schedule, session: nil, authorized: true, now: now, calendar: calendar))
        XCTAssertFalse(EverydayRules.blocks(schedule: nil, session: nil, authorized: true, now: now, calendar: calendar))
    }
    func testUnauthorizedNeverBlocksAndUnknownAccessFollowsTheSchedule() {
        let schedule = layer()
        XCTAssertFalse(EverydayRules.blocks(schedule: schedule, session: nil, authorized: false, now: at(10, 0), calendar: calendar))
        XCTAssertTrue(EverydayRules.blocks(schedule: schedule, session: nil, authorized: nil, now: at(10, 0), calendar: calendar))
        XCTAssertFalse(EverydayRules.blocks(schedule: schedule, session: nil, authorized: nil, now: at(19, 0), calendar: calendar))
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
}
