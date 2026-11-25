import XCTest
@testable import FocusCore

/// The weekly review rules (docs/specs/2026-11-25-weekly-review-design.md, "Data rules" and contract item 6).
final class WeeklyReviewTests: XCTestCase {
    private func calendar(_ zone: String = "Asia/Seoul") -> Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: zone)!; return calendar
    }
    private func day(_ month: Int, _ day: Int) -> ReviewDay { ReviewDay(year: 2026, month: month, day: day) }
    private func at(_ day: ReviewDay, _ hour: Int, _ minute: Int = 0) -> Date {
        day.start(in: calendar()).addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }
    private func entry(_ day: ReviewDay, _ hour: Int, _ minute: Int = 0, minutes: Int = 25) -> ReviewEntry {
        ReviewEntry(startedAt: at(day, hour, minute), focusDuration: TimeInterval(minutes * 60))
    }

    // MARK: Days

    func testReviewDayStepsAcrossMonthsAndKnowsItsWeekday() {
        let calendar = calendar()
        XCTAssertEqual(day(11, 30).adding(1, calendar: calendar), day(12, 1))
        XCTAssertEqual(day(12, 1).adding(-1, calendar: calendar), day(11, 30))
        XCTAssertEqual(day(11, 23).weekday(calendar: calendar), 2, "2026-11-23 is a Monday")
        XCTAssertEqual(day(11, 23).next(weekday: 2, calendar: calendar), day(11, 23))
        XCTAssertEqual(day(11, 23).next(weekday: 1, calendar: calendar), day(11, 29))
        XCTAssertEqual(day(11, 23).days(to: day(12, 1), calendar: calendar), 8)
        XCTAssertEqual(day(3, 5).key, "2026-03-05")
    }
    func testReviewDayIsGregorianWhateverTheDeviceCalendar() {
        let seoul = calendar(), date = at(day(11, 25), 10)
        for identifier in [Calendar.Identifier.buddhist, .japanese] {
            var device = Calendar(identifier: identifier); device.timeZone = seoul.timeZone
            XCTAssertEqual(ReviewDay(date, calendar: device), day(11, 25), "\(identifier) stores the Gregorian day")
            XCTAssertEqual(day(11, 25).start(in: device), day(11, 25).start(in: seoul))
            XCTAssertEqual(day(11, 25).adding(7, calendar: device), day(12, 2))
            XCTAssertEqual(day(11, 25).weekday(calendar: device), 4, "2026-11-25 is a Wednesday")
        }
    }
    func testReviewDayKeepsItsDateAcrossADaylightSavingChange() {
        let calendar = calendar("America/New_York")
        // 2026-03-08 has 23 hours in New York.
        XCTAssertEqual(day(3, 7).adding(1, calendar: calendar), day(3, 8))
        XCTAssertEqual(day(3, 7).adding(2, calendar: calendar), day(3, 9))
        XCTAssertEqual(day(3, 9).days(to: day(3, 7), calendar: calendar), -2)
        // A step that starts or ends on the 23-hour day still counts calendar days.
        XCTAssertEqual(day(3, 8).days(to: day(3, 9), calendar: calendar), 1)
        XCTAssertEqual(day(3, 9).days(to: day(3, 8), calendar: calendar), -1)
        XCTAssertEqual(day(3, 8).weekday(calendar: calendar), 1, "2026-03-08 is a Sunday")
        XCTAssertEqual(ReviewPeriod(first: day(3, 8), last: day(3, 9)).days(calendar: calendar), [day(3, 8), day(3, 9)])
        // 2026-11-01 has 25 hours in New York.
        XCTAssertEqual(day(11, 1).days(to: day(11, 2), calendar: calendar), 1)
        XCTAssertEqual(day(11, 2).days(to: day(11, 1), calendar: calendar), -1)
        XCTAssertEqual(ReviewPeriod(first: day(10, 31), last: day(11, 2)).days(calendar: calendar), [day(10, 31), day(11, 1), day(11, 2)])
    }
    func testWallClockTimeKeepsTheClockOnADaylightSavingDay() {
        let calendar = calendar("America/New_York")
        for (date, hour) in [(day(3, 8), 20), (day(11, 1), 20), (day(3, 8), 7)] {
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date.date(atMinute: hour * 60 + 5, in: calendar))
            XCTAssertEqual(parts, DateComponents(year: 2026, month: date.month, day: date.day, hour: hour, minute: 5))
        }
    }

    // MARK: Periods

    func testFirstPeriodRunsFromDayOneToDayThreeAndLaterPeriodsAreSevenDays() {
        let calendar = calendar()
        // A trial that started on Monday 2026-11-23: day 3 is Wednesday.
        let schedule = ReviewSchedule.start(dayOne: day(11, 23), calendar: calendar)
        XCTAssertEqual(schedule.weekday, 4)
        XCTAssertEqual(schedule.minute, 1200)
        XCTAssertEqual(schedule.period(containing: day(11, 24), calendar: calendar), ReviewPeriod(first: day(11, 23), last: day(11, 25)))
        XCTAssertEqual(schedule.period(containing: day(11, 26), calendar: calendar), ReviewPeriod(first: day(11, 26), last: day(12, 2)))
        XCTAssertEqual(schedule.period(containing: day(12, 2), calendar: calendar), ReviewPeriod(first: day(11, 26), last: day(12, 2)))
        XCTAssertEqual(schedule.period(containing: day(12, 3), calendar: calendar), ReviewPeriod(first: day(12, 3), last: day(12, 9)))
        XCTAssertEqual(schedule.period(containing: ReviewDay(year: 2027, month: 2, day: 10), calendar: calendar).last.weekday(calendar: calendar), 4)
        // A day before day 1, after the clock moved back, belongs to the first period.
        XCTAssertEqual(schedule.period(containing: day(11, 20), calendar: calendar), ReviewPeriod(first: day(11, 23), last: day(11, 25)))
    }
    func testPeriodBeforeAndAfter() {
        let calendar = calendar(), schedule = ReviewSchedule.start(dayOne: day(11, 23), calendar: calendar)
        let first = schedule.period(containing: day(11, 23), calendar: calendar), second = schedule.period(after: first, calendar: calendar)
        XCTAssertNil(schedule.period(before: first, calendar: calendar))
        XCTAssertEqual(schedule.period(before: second, calendar: calendar), first)
        XCTAssertEqual(second, ReviewPeriod(first: day(11, 26), last: day(12, 2)))
    }
    func testWeekdayInsideTheCurrentPeriodEndsItEarlyOnce() {
        let calendar = calendar()
        var schedule = ReviewSchedule.start(dayOne: day(11, 23), calendar: calendar)
        // On Friday 11-27, inside 11-26...12-2, the new weekday Sunday comes on 11-29.
        schedule.changeWeekday(to: 1, today: day(11, 27), calendar: calendar)
        XCTAssertEqual(schedule.weekday, 1)
        XCTAssertEqual(schedule.period(containing: day(11, 27), calendar: calendar), ReviewPeriod(first: day(11, 26), last: day(11, 29)))
        XCTAssertEqual(schedule.period(containing: day(11, 30), calendar: calendar), ReviewPeriod(first: day(11, 30), last: day(12, 6)))
        XCTAssertEqual(schedule.period(containing: day(11, 24), calendar: calendar), ReviewPeriod(first: day(11, 23), last: day(11, 25)), "an ended period keeps its days")
    }
    func testWeekdayOnTodayEndsTheCurrentPeriodToday() {
        let calendar = calendar()
        var schedule = ReviewSchedule.start(dayOne: day(11, 23), calendar: calendar)
        // Friday 11-27 is weekday 6.
        schedule.changeWeekday(to: 6, today: day(11, 27), calendar: calendar)
        XCTAssertEqual(schedule.period(containing: day(11, 27), calendar: calendar), ReviewPeriod(first: day(11, 26), last: day(11, 27)))
        XCTAssertEqual(schedule.period(containing: day(11, 28), calendar: calendar), ReviewPeriod(first: day(11, 28), last: day(12, 4)))
    }
    func testWeekdayAfterTheCurrentPeriodKeepsItsLastDayAndShortensTheNext() {
        let calendar = calendar()
        var schedule = ReviewSchedule.start(dayOne: day(11, 23), calendar: calendar)
        // On Monday 11-30, inside 11-26...12-2 (ends Wednesday), the new weekday Thursday next comes on 12-3, after the period.
        schedule.changeWeekday(to: 5, today: day(11, 30), calendar: calendar)
        XCTAssertEqual(schedule.period(containing: day(11, 30), calendar: calendar), ReviewPeriod(first: day(11, 26), last: day(12, 2)))
        XCTAssertEqual(schedule.period(containing: day(12, 3), calendar: calendar), ReviewPeriod(first: day(12, 3), last: day(12, 3)), "one to seven days")
        XCTAssertEqual(schedule.period(containing: day(12, 4), calendar: calendar), ReviewPeriod(first: day(12, 4), last: day(12, 10)))
    }
    func testWeekdayChangeInTheFirstPeriod() {
        let calendar = calendar()
        var schedule = ReviewSchedule.start(dayOne: day(11, 23), calendar: calendar)
        // On day 1 (Monday), Tuesday comes before day 3, but the first period still ends on day 3, so the trial's day 3 notification opens the first review.
        schedule.changeWeekday(to: 3, today: day(11, 23), calendar: calendar)
        XCTAssertEqual(schedule.weekday, 3)
        XCTAssertEqual(schedule.period(containing: day(11, 23), calendar: calendar), ReviewPeriod(first: day(11, 23), last: day(11, 25)))
        XCTAssertEqual(schedule.period(containing: day(11, 26), calendar: calendar), ReviewPeriod(first: day(11, 26), last: day(12, 1)))
        XCTAssertNil(schedule.period(before: schedule.period(containing: day(11, 23), calendar: calendar), calendar: calendar))
    }
    func testWeekdayOfTodayInTheFirstPeriodKeepsDayThree() {
        let calendar = calendar()
        // Day 1 and day 2, with today's own weekday: the first period still holds day 3.
        for today in [day(11, 23), day(11, 24)] {
            var schedule = ReviewSchedule.start(dayOne: day(11, 23), calendar: calendar)
            schedule.changeWeekday(to: today.weekday(calendar: calendar), today: today, calendar: calendar)
            let first = schedule.period(containing: day(11, 23), calendar: calendar)
            XCTAssertEqual(first, ReviewPeriod(first: day(11, 23), last: day(11, 25)))
            XCTAssertEqual(schedule.period(containing: day(11, 25), calendar: calendar), first, "the day 3 notification opens the first review")
            let next = schedule.period(after: first, calendar: calendar)
            XCTAssertEqual(next.first, day(11, 26))
            XCTAssertEqual(next.last.weekday(calendar: calendar), today.weekday(calendar: calendar))
        }
    }
    func testTheSameWeekdayChangesNothing() {
        let calendar = calendar()
        var schedule = ReviewSchedule.start(dayOne: day(11, 23), calendar: calendar)
        let before = schedule
        schedule.changeWeekday(to: 4, today: day(11, 27), calendar: calendar)
        schedule.changeWeekday(to: 0, today: day(11, 27), calendar: calendar)
        XCTAssertEqual(schedule, before)
    }
    /// A sequence of changes never leaves a gap, an overlap or a period longer than seven days, and never moves a period that ended.
    func testChangesNeverLeaveAGapOrAnOverlap() {
        let calendar = calendar()
        var schedule = ReviewSchedule.start(dayOne: day(11, 23), calendar: calendar)
        var generator = SystemRandomNumberGenerator()
        var today = day(11, 23)
        var ended: [ReviewPeriod] = []
        for _ in 0..<200 {
            today = today.adding(Int.random(in: 0...3, using: &generator), calendar: calendar)
            let current = schedule.period(containing: today, calendar: calendar)
            schedule.changeWeekday(to: Int.random(in: 1...7, using: &generator), today: today, calendar: calendar)
            for period in ended { XCTAssertEqual(schedule.period(containing: period.first, calendar: calendar), period, "an ended period moved") }
            if let previous = schedule.period(before: current, calendar: calendar) { ended.append(previous) }
            var period = schedule.period(containing: day(11, 23), calendar: calendar)
            XCTAssertEqual(period.first, day(11, 23))
            while period.last < today.adding(21, calendar: calendar) {
                let length = period.first.days(to: period.last, calendar: calendar) + 1
                XCTAssertTrue((1...7).contains(length), "\(period)")
                let next = schedule.period(after: period, calendar: calendar)
                XCTAssertEqual(next.first, period.last.adding(1, calendar: calendar))
                XCTAssertEqual(schedule.period(containing: period.last, calendar: calendar), period)
                period = next
            }
        }
    }
    func testANoteStaysEditableUntilTheEndOfTheNextPeriod() {
        let calendar = calendar(), schedule = ReviewSchedule.start(dayOne: day(11, 23), calendar: calendar)
        let first = schedule.period(containing: day(11, 23), calendar: calendar)
        XCTAssertTrue(schedule.isNoteEditable(first, today: day(11, 25), calendar: calendar))
        XCTAssertTrue(schedule.isNoteEditable(first, today: day(11, 26), calendar: calendar), "the morning after the notification")
        XCTAssertTrue(schedule.isNoteEditable(first, today: day(12, 2), calendar: calendar))
        XCTAssertFalse(schedule.isNoteEditable(first, today: day(12, 3), calendar: calendar))
    }
    func testScheduleRoundTripsThroughJSON() throws {
        let calendar = calendar()
        var schedule = ReviewSchedule.start(dayOne: day(11, 23), calendar: calendar)
        schedule.changeWeekday(to: 1, today: day(11, 27), calendar: calendar); schedule.minute = 21 * 60 + 30; schedule.notificationsOn = false
        XCTAssertEqual(try JSONDecoder().decode(ReviewSchedule.self, from: JSONEncoder().encode(schedule)), schedule)
    }

    // MARK: What I did

    func testSummaryCountsDaysAndSessionsAndLeavesFutureDaysWithoutAValue() {
        let calendar = calendar(), period = ReviewPeriod(first: day(11, 23), last: day(11, 25))
        let entries = [entry(day(11, 23), 9), entry(day(11, 23), 23, 50, minutes: 50), entry(day(11, 24), 7), entry(day(11, 22), 9)]
        let summary = ReviewSummary(entries: entries, period: period, today: day(11, 24), calendar: calendar)
        XCTAssertEqual(summary.days.map(\.day), [day(11, 23), day(11, 24), day(11, 25)])
        XCTAssertEqual(summary.days.map(\.focusDuration), [75 * 60, 25 * 60, nil])
        XCTAssertEqual(summary.recordedDays, 2)
        XCTAssertEqual(summary.completedCount, 3, "a session belongs to the day of its start, also when it ends after midnight")
        XCTAssertEqual(summary.focusDuration, 100 * 60)
    }
    func testSentenceUsesNativeKoreanDayWords() {
        let calendar = calendar(), period = ReviewPeriod(first: day(11, 23), last: day(11, 29))
        func sentence(_ days: Int, sessions: Int, inProgress: Bool) -> String {
            var entries: [ReviewEntry] = []
            for index in 0..<sessions { entries.append(entry(day(11, 23).adding(index % days, calendar: calendar), 9, index)) }
            return WeeklyReview.sentence(ReviewSummary(entries: entries, period: period, today: day(11, 29), calendar: calendar), inProgress: inProgress)
        }
        XCTAssertEqual(sentence(2, sessions: 5, inProgress: true), "이번 주 지금까지, 이틀에 걸쳐 5번 집중했어요.")
        XCTAssertEqual(sentence(2, sessions: 5, inProgress: false), "이번 주 이틀에 걸쳐 5번 집중했어요.")
        XCTAssertEqual(sentence(1, sessions: 1, inProgress: true), "이번 주 지금까지, 하루 동안 1번 집중했어요.")
        XCTAssertEqual(sentence(3, sessions: 3, inProgress: false), "이번 주 사흘에 걸쳐 3번 집중했어요.")
        XCTAssertEqual(sentence(4, sessions: 4, inProgress: false), "이번 주 나흘에 걸쳐 4번 집중했어요.")
        XCTAssertEqual(sentence(5, sessions: 5, inProgress: false), "이번 주 닷새에 걸쳐 5번 집중했어요.")
        XCTAssertEqual(sentence(6, sessions: 9, inProgress: false), "이번 주 엿새에 걸쳐 9번 집중했어요.")
        XCTAssertEqual(sentence(7, sessions: 12, inProgress: false), "이번 주 일주일 내내 12번 집중했어요.")
    }
    func testAnEmptyPeriodGetsTheMessageThatDoesNotBlame() {
        let calendar = calendar(), period = ReviewPeriod(first: day(11, 23), last: day(11, 25))
        let summary = ReviewSummary(entries: [], period: period, today: day(11, 25), calendar: calendar)
        XCTAssertEqual(WeeklyReview.sentence(summary, inProgress: true), "집중이 기록되지 않았더라도 괜찮아요. 다음엔 온:공과 함께해요.")
    }
    func testClockAndWeekdayNamesDoNotDependOnTheLocale() {
        let calendar = calendar()
        XCTAssertEqual(WeeklyReview.clock(at(day(11, 25), 19, 10), calendar: calendar), "오후 7시 10분")
        XCTAssertEqual(WeeklyReview.clock(at(day(11, 25), 16, 0), calendar: calendar), "오후 4시")
        XCTAssertEqual(WeeklyReview.clock(at(day(11, 25), 0, 5), calendar: calendar), "오전 12시 5분")
        XCTAssertEqual(WeeklyReview.clock(at(day(11, 25), 12, 0), calendar: calendar), "오후 12시")
        XCTAssertEqual(WeeklyReview.clock(at(day(11, 25), 9, 30), calendar: calendar), "오전 9시 30분")
        XCTAssertEqual(WeeklyReview.weekdayName(day(11, 25), calendar: calendar), "수요일")
        XCTAssertEqual(WeeklyReview.weekdayName(day(11, 29), calendar: calendar), "일요일")
    }

    // MARK: Moment rule

    private let week = ReviewPeriod(first: ReviewDay(year: 2026, month: 11, day: 23), last: ReviewDay(year: 2026, month: 11, day: 29))
    func testRepetitionUsesOnlyTheFirstSessionOfEachDay() {
        let calendar = calendar()
        // Wednesday 19:10 and Friday 19:40 are first sessions; Monday's 19:20 is a later session of a day that started at 08:00.
        let entries = [entry(day(11, 23), 8), entry(day(11, 23), 19, 20), entry(day(11, 25), 19, 10), entry(day(11, 27), 19, 40)]
        let moment = WeeklyReview.moment(entries: entries, period: week, today: week.last, calendar: calendar)
        XCTAssertEqual(moment, .repetition(first: day(11, 25), firstStart: at(day(11, 25), 19, 10), second: day(11, 27), secondStart: at(day(11, 27), 19, 40)))
        XCTAssertEqual(WeeklyReview.text(moment!, calendar: calendar), "수요일 오후 7시 10분, 금요일 오후 7시 40분에 그날 첫 집중을 시작했어요.")
    }
    func testRepetitionAllowsExactlySixtyMinutesAndNeverWrapsMidnight() {
        let calendar = calendar()
        XCTAssertEqual(WeeklyReview.moment(entries: [entry(day(11, 23), 8), entry(day(11, 24), 9)], period: week, today: week.last, calendar: calendar),
                       .repetition(first: day(11, 23), firstStart: at(day(11, 23), 8, 0), second: day(11, 24), secondStart: at(day(11, 24), 9, 0)))
        XCTAssertNil(WeeklyReview.moment(entries: [entry(day(11, 23), 8), entry(day(11, 24), 9, 1)], period: week, today: week.last, calendar: calendar))
        // 23:50 and 00:10 are 20 minutes apart across midnight, but the rule does not wrap.
        XCTAssertNil(WeeklyReview.moment(entries: [entry(day(11, 23), 23, 50), entry(day(11, 24), 0, 10)], period: week, today: week.last, calendar: calendar))
    }
    func testRepetitionTakesTheSmallestDifferenceThenTheMoreRecentLaterDay() {
        let calendar = calendar()
        // Mon 9:00, Tue 9:30, Thu 20:00, Sat 20:30: two pairs of 30 minutes; the pair that ends on Saturday wins.
        let entries = [entry(day(11, 23), 9), entry(day(11, 24), 9, 30), entry(day(11, 26), 20), entry(day(11, 28), 20, 30)]
        XCTAssertEqual(WeeklyReview.moment(entries: entries, period: week, today: week.last, calendar: calendar),
                       .repetition(first: day(11, 26), firstStart: at(day(11, 26), 20, 0), second: day(11, 28), secondStart: at(day(11, 28), 20, 30)))
        // A 10-minute pair beats them.
        let closer = entries + [entry(day(11, 25), 9, 10)]
        XCTAssertEqual(WeeklyReview.moment(entries: closer, period: week, today: week.last, calendar: calendar),
                       .repetition(first: day(11, 23), firstStart: at(day(11, 23), 9, 0), second: day(11, 25), secondStart: at(day(11, 25), 9, 10)))
    }
    func testReturnAfterGapTakesTheMostRecentDay() {
        let calendar = calendar()
        // Mon 8:00, (Tue none), Wed 13:00, (Thu none), Fri 16:00: no repetition; Friday returns after Thursday.
        let entries = [entry(day(11, 23), 8), entry(day(11, 25), 13), entry(day(11, 27), 16)]
        let moment = WeeklyReview.moment(entries: entries, period: week, today: week.last, calendar: calendar)
        XCTAssertEqual(moment, .returnAfterGap(gap: day(11, 26), day: day(11, 27), start: at(day(11, 27), 16, 0)))
        XCTAssertEqual(WeeklyReview.text(moment!, calendar: calendar), "목요일엔 온:공 기록이 없었고, 금요일 오후 4시에 시작한 세션을 마쳤어요.")
    }
    func testTheGapDayMustBeInsideThePeriod() {
        let calendar = calendar()
        // Only the first day of the period has a session: its previous day is outside the period.
        XCTAssertNil(WeeklyReview.moment(entries: [entry(day(11, 23), 8), entry(day(11, 22), 8)], period: week, today: week.last, calendar: calendar))
        // Consecutive days far apart in time and no gap: nothing.
        XCTAssertNil(WeeklyReview.moment(entries: [entry(day(11, 23), 8), entry(day(11, 24), 13), entry(day(11, 25), 20)], period: week, today: week.last, calendar: calendar))
        XCTAssertNil(WeeklyReview.moment(entries: [], period: week, today: week.last, calendar: calendar))
    }
    func testMomentLeavesOutDaysAfterToday() {
        let calendar = calendar()
        // After a clock rollback, Friday 8:10 is after today (Wednesday): the summary hides it, so the moment must not pair it with Monday 8:00.
        let entries = [entry(day(11, 23), 8), entry(day(11, 25), 13), entry(day(11, 27), 8, 10)]
        XCTAssertEqual(WeeklyReview.moment(entries: entries, period: week, today: day(11, 25), calendar: calendar),
                       .returnAfterGap(gap: day(11, 24), day: day(11, 25), start: at(day(11, 25), 13, 0)))
        XCTAssertNil(WeeklyReview.moment(entries: [entry(day(11, 23), 8), entry(day(11, 27), 16)], period: week, today: day(11, 25), calendar: calendar))
    }

    // MARK: Notification plan and paid access

    func testTrialGetsOnlyTheDayThreeNotificationBeforeTheTrialEnd() {
        let calendar = calendar()
        let start = at(day(11, 23), 21, 30), schedule = ReviewSchedule.start(dayOne: day(11, 23), calendar: calendar)
        let end = start.addingTimeInterval(72 * 3600), fire = at(day(11, 25), 20, 0)
        XCTAssertEqual(WeeklyReview.notificationPlan(kind: .trial, schedule: schedule, now: start, trialEnd: end, calendar: calendar), .once(fire))
        XCTAssertEqual(WeeklyReview.notificationPlan(kind: .trial, schedule: schedule, now: fire, trialEnd: end, calendar: calendar), .none, "a passed notification is not scheduled again")
        // A trial that started at 00:00 on day 1 still ends after day 3 at 20:00.
        XCTAssertLessThan(fire, at(day(11, 23), 0, 0).addingTimeInterval(72 * 3600))
    }
    func testTheDayThreeNotificationKeepsItsClockTimeOnADaylightSavingDay() {
        let calendar = calendar("America/New_York")
        for dayOne in [day(3, 6), day(10, 30)] {
            let schedule = ReviewSchedule.start(dayOne: dayOne, calendar: calendar)
            let now = dayOne.start(in: calendar)
            guard case let .once(fire) = WeeklyReview.notificationPlan(kind: .trial, schedule: schedule, now: now, trialEnd: nil, calendar: calendar) else { return XCTFail("no day 3 notification") }
            let parts = calendar.dateComponents([.hour, .minute], from: fire)
            XCTAssertEqual(parts.hour, 20, "day 3 of \(dayOne.key) is a daylight saving day; the notification stays at 20:00")
            XCTAssertEqual(parts.minute, 0)
        }
    }
    func testOngoingAccessGetsOneRepeatingNotificationAndNoneElseGetsNothing() {
        let calendar = calendar()
        var schedule = ReviewSchedule.start(dayOne: day(11, 23), calendar: calendar)
        let now = at(day(11, 23), 10, 0)
        XCTAssertEqual(WeeklyReview.notificationPlan(kind: .ongoing, schedule: schedule, now: now, trialEnd: nil, calendar: calendar), .repeating(weekday: 4, minute: 1200))
        XCTAssertEqual(WeeklyReview.notificationPlan(kind: .none, schedule: schedule, now: now, trialEnd: nil, calendar: calendar), .none)
        XCTAssertEqual(WeeklyReview.notificationPlan(kind: .ongoing, schedule: nil, now: now, trialEnd: nil, calendar: calendar), .none)
        schedule.minute = 7 * 60
        schedule.changeWeekday(to: 1, today: day(11, 27), calendar: calendar)
        XCTAssertEqual(WeeklyReview.notificationPlan(kind: .ongoing, schedule: schedule, now: at(day(11, 27), 10, 0), trialEnd: nil, calendar: calendar), .repeating(weekday: 1, minute: 420))
        schedule.notificationsOn = false
        XCTAssertEqual(WeeklyReview.notificationPlan(kind: .ongoing, schedule: schedule, now: now, trialEnd: nil, calendar: calendar), .none)
    }
    func testAWeekdayChangeInTheFirstPeriodNeverFiresInsideItAndKeepsDayThree() {
        let calendar = calendar()
        // Day 1 is Monday 2026-11-23; the first period ends on Wednesday 2026-11-25.
        var schedule = ReviewSchedule.start(dayOne: day(11, 23), calendar: calendar)
        let now = at(day(11, 23), 10, 0), firstEnd = at(day(11, 25), 20, 0)
        schedule.changeWeekday(to: 3, today: day(11, 23), calendar: calendar)
        XCTAssertEqual(schedule.period(containing: day(11, 24), calendar: calendar).last, day(11, 25), "the first period still ends on day 3")
        // A repeating Tuesday notification would fire on 11-24, inside the first period, so the period ends are scheduled one by one.
        guard case let .dates(dates) = WeeklyReview.notificationPlan(kind: .ongoing, schedule: schedule, now: now, trialEnd: nil, calendar: calendar) else {
            return XCTFail("no dates")
        }
        XCTAssertEqual(dates.count, WeeklyReview.pendingDates)
        XCTAssertLessThan(WeeklyReview.pendingDates, 64, "the system keeps at most 64 pending requests per app")
        XCTAssertEqual(Array(dates.prefix(3)), [firstEnd, at(day(12, 1), 20, 0), at(day(12, 8), 20, 0)])
        XCTAssertEqual(dates.last, at(day(11, 24), 20, 0).addingTimeInterval(TimeInterval(7 * 86_400 * (WeeklyReview.pendingDates - 1))),
                       "every later date is a Tuesday at 20:00; Seoul has no daylight saving change")
        XCTAssertEqual(WeeklyReview.notificationPlan(kind: .ongoing, schedule: schedule, now: at(day(11, 24), 19, 0), trialEnd: nil, calendar: calendar), .dates(dates),
                       "the dates follow from the first period, so a later refresh gives the same plan")
        XCTAssertEqual(WeeklyReview.notificationPlan(kind: .ongoing, schedule: schedule, now: at(day(11, 25), 9, 0), trialEnd: nil, calendar: calendar),
                       .onceThenRepeating(firstEnd, weekday: 3, minute: 1200), "the Tuesday inside the first period has passed; day 3 still gets its notification")
        XCTAssertEqual(WeeklyReview.notificationPlan(kind: .ongoing, schedule: schedule, now: firstEnd, trialEnd: nil, calendar: calendar), .repeating(weekday: 3, minute: 1200),
                       "after the first period the new weekday repeats")
        // A new weekday whose next occurrence is after day 3 repeats at once, after the day 3 notification.
        schedule.changeWeekday(to: 6, today: day(11, 23), calendar: calendar)
        XCTAssertEqual(WeeklyReview.notificationPlan(kind: .ongoing, schedule: schedule, now: now, trialEnd: nil, calendar: calendar),
                       .onceThenRepeating(firstEnd, weekday: 6, minute: 1200))
    }
    func testANotificationTapOpensTheAnnouncedPeriodAfterATimeZoneChange() {
        let seoul = calendar()
        var schedule = ReviewSchedule.start(dayOne: day(11, 23), calendar: seoul)
        let first = ReviewPeriod(first: day(11, 23), last: day(11, 25)), second = ReviewPeriod(first: day(11, 26), last: day(12, 2))
        let fire = at(day(11, 25), 20, 0)
        XCTAssertEqual(schedule.announcedPeriod(firedAt: fire, calendar: seoul), first)
        // In UTC+14 the fire is 2026-11-26 01:00: the day after the period's last day.
        XCTAssertEqual(ReviewDay(fire, calendar: calendar("Pacific/Kiritimati")), day(11, 26))
        XCTAssertEqual(schedule.announcedPeriod(firedAt: fire, calendar: calendar("Pacific/Kiritimati")), first)
        XCTAssertEqual(schedule.announcedPeriod(firedAt: at(day(12, 2), 20, 0), calendar: calendar("Pacific/Kiritimati")), second)
        // A fire at 00:30 in Seoul is the previous day in Los Angeles, inside the same period.
        schedule.minute = 30
        let early = at(day(11, 25), 0, 30)
        XCTAssertEqual(ReviewDay(early, calendar: calendar("America/Los_Angeles")), day(11, 24))
        XCTAssertEqual(schedule.announcedPeriod(firedAt: early, calendar: calendar("America/Los_Angeles")), first)
        // A day inside a period gives that period, and a day before day 1 gives the first period.
        XCTAssertEqual(schedule.announcedPeriod(firedAt: at(day(11, 28), 12, 0), calendar: seoul), second)
        XCTAssertEqual(schedule.announcedPeriod(firedAt: at(day(11, 22), 12, 0), calendar: seoul), first)
    }
    func testATapAfterATimeZoneChangeIntoAOneDayPeriodOpensThePeriodBefore() {
        let seoul = calendar(), kiritimati = calendar("Pacific/Kiritimati")
        var schedule = ReviewSchedule.start(dayOne: day(11, 23), calendar: seoul)
        // On Thursday 11-26, the first day of the second period, the weekday becomes Thursday: the second period ends that day.
        schedule.changeWeekday(to: 5, today: day(11, 26), calendar: seoul)
        let first = ReviewPeriod(first: day(11, 23), last: day(11, 25)), oneDay = ReviewPeriod(first: day(11, 26), last: day(11, 26))
        XCTAssertEqual(schedule.period(containing: day(11, 26), calendar: seoul), oneDay)
        // The first period's notification, read in UTC+14, falls on the one-day period.
        let fire = at(day(11, 25), 20, 0)
        XCTAssertEqual(ReviewDay(fire, calendar: kiritimati), day(11, 26))
        XCTAssertEqual(schedule.announcedPeriod(firedAt: fire, calendar: kiritimati), first)
        // The one-day period's own notification opens it.
        XCTAssertEqual(schedule.announcedPeriod(firedAt: at(day(11, 26), 20, 0), calendar: seoul), oneDay)
    }
    func testDayOneAndFormFollowPaidAccess() {
        let enabled = PaidAccessConfiguration(enabled: true, firstPaidBuild: 3)
        let firstRun = Date(timeIntervalSince1970: 1_000_000), trialStart = Date(timeIntervalSince1970: 2_000_000), bought = Date(timeIntervalSince1970: 3_000_000)
        let trial = PaidAccessFacts(originalAppVersion: "5", unlock: nil, trial: PaidPurchase(purchaseDate: trialStart), trialStartedAt: trialStart)
        let during = trialStart.addingTimeInterval(3600), after = trialStart.addingTimeInterval(73 * 3600)
        XCTAssertEqual(PaidAccess.reviewDayOne(configuration: enabled, facts: trial, firstRun: firstRun), trialStart)
        XCTAssertEqual(PaidAccess.reviewForm(configuration: enabled, facts: trial, now: during), .pages)
        XCTAssertEqual(PaidAccess.reviewAccessKind(state: .granted, configuration: enabled, facts: trial, now: during), .trial)
        XCTAssertEqual(PaidAccess.grantingTrialEnd(configuration: enabled, facts: trial, now: during), trialStart.addingTimeInterval(72 * 3600))
        XCTAssertEqual(PaidAccess.reviewAccessKind(state: .locked, configuration: enabled, facts: trial, now: after), .none)
        // A trial person who buys keeps day 1 and gets form A.
        var both = trial; both.unlock = PaidPurchase(purchaseDate: bought)
        XCTAssertEqual(PaidAccess.reviewDayOne(configuration: enabled, facts: both, firstRun: firstRun), trialStart)
        XCTAssertEqual(PaidAccess.reviewForm(configuration: enabled, facts: both, now: during), .sheet)
        XCTAssertEqual(PaidAccess.reviewAccessKind(state: .granted, configuration: enabled, facts: both, now: during), .ongoing)
        // The unlock without a trial: its purchase day.
        let unlock = PaidAccessFacts(originalAppVersion: "5", unlock: PaidPurchase(purchaseDate: bought))
        XCTAssertEqual(PaidAccess.reviewDayOne(configuration: enabled, facts: unlock, firstRun: firstRun), bought)
        // An earlier user, and every person while the gate is off: the first run.
        let earlier = PaidAccessFacts(originalAppVersion: "2")
        XCTAssertEqual(PaidAccess.reviewDayOne(configuration: enabled, facts: earlier, firstRun: firstRun), firstRun)
        XCTAssertEqual(PaidAccess.reviewDayOne(configuration: .disabled, facts: trial, firstRun: firstRun), firstRun)
        XCTAssertEqual(PaidAccess.reviewForm(configuration: .disabled, facts: trial, now: during), .sheet)
        XCTAssertEqual(PaidAccess.reviewAccessKind(state: .unknown, configuration: enabled, facts: nil, now: during), .none)
    }
}
