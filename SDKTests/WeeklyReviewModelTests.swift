import XCTest

/// A recording notification center: it never reaches `UNUserNotificationCenter`.
@MainActor private final class RecordingCenter: ReviewNotificationScheduling {
    var status: ReviewPermission
    /// The status that a request leaves; `authorized` unless a test makes the person deny it.
    var answer: ReviewPermission = .authorized
    private(set) var requests = 0
    private(set) var plans: [ReviewNotificationPlan] = []
    init(status: ReviewPermission) { self.status = status }
    func permission() async -> ReviewPermission { status }
    func requestPermission() async { requests += 1; if status == .notDetermined { status = answer } }
    /// `false` makes the next add fail, as a failed `UNUserNotificationCenter.add` does.
    var addSucceeds = true
    func replace(with plan: ReviewNotificationPlan, calendar: Calendar) async -> Bool { plans.append(plan); return addSucceeds }
}

/// A center whose first replacement waits between its remove and its add until the test releases it.
@MainActor private final class GatedCenter: ReviewNotificationScheduling {
    private(set) var events: [String] = []
    private(set) var plans: [ReviewNotificationPlan] = []
    private var gate: CheckedContinuation<Void, Never>?
    private var holdNext = true
    var isHeld: Bool { gate != nil }
    func permission() async -> ReviewPermission { .authorized }
    func requestPermission() async {}
    func replace(with plan: ReviewNotificationPlan, calendar: Calendar) async -> Bool {
        events.append("remove"); plans.append(plan)
        if holdNext { holdNext = false; await withCheckedContinuation { gate = $0 } }
        events.append("add")
        return true
    }
    func release() { gate?.resume(); gate = nil }
}

/// A center whose permission reads wait until the test resumes them, in any order.
@MainActor private final class HeldPermissionCenter: ReviewNotificationScheduling {
    private(set) var held: [CheckedContinuation<ReviewPermission, Never>] = []
    func permission() async -> ReviewPermission { await withCheckedContinuation { held.append($0) } }
    func requestPermission() async {}
    func replace(with plan: ReviewNotificationPlan, calendar: Calendar) async -> Bool { true }
    func resume(_ index: Int, with permission: ReviewPermission) { held[index].resume(returning: permission) }
}

/// The weekly review's store, notification and open review (docs/specs/2026-11-25-weekly-review-design.md, contract items 1, 6 and 8).
@MainActor final class WeeklyReviewModelTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!; return calendar
    }()
    private let enabled = PaidAccessConfiguration(enabled: true, firstPaidBuild: 3)
    private func store() -> WeeklyReviewStore { WeeklyReviewStore(defaults: UserDefaults(suiteName: "WeeklyReviewModelTests-\(UUID().uuidString)")!) }
    private func day(_ month: Int, _ day: Int) -> ReviewDay { ReviewDay(year: 2026, month: month, day: day) }
    private func at(_ day: ReviewDay, _ hour: Int, _ minute: Int = 0) -> Date { day.start(in: calendar).addingTimeInterval(TimeInterval(hour * 3600 + minute * 60)) }
    private func model(_ store: WeeklyReviewStore, _ center: RecordingCenter, now: @escaping () -> Date) -> WeeklyReviewModel {
        let calendar = calendar
        return WeeklyReviewModel(store: store, center: center, now: now, calendar: { calendar })
    }
    /// A trial that started on Monday 2026-11-23 at 21:30.
    private var trialFacts: PaidAccessFacts {
        let start = at(day(11, 23), 21, 30)
        return PaidAccessFacts(originalAppVersion: "5", unlock: nil, trial: PaidPurchase(purchaseDate: start), trialStartedAt: start)
    }

    func testTrialFixesDayOneAndSchedulesOnlyTheDayThreeNotification() async {
        let store = store(), center = RecordingCenter(status: .authorized)
        let model = model(store, center) { self.at(self.day(11, 24), 10) }
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        XCTAssertEqual(model.schedule?.dayOne, day(11, 23))
        XCTAssertEqual(store.schedule, model.schedule, "day 1 is stored in the app's own defaults")
        XCTAssertEqual(center.plans, [.once(at(day(11, 25), 20))])
        // A second refresh with the same plan does not replace the pending notification again.
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        XCTAssertEqual(center.plans.count, 1)
    }
    func testAFailedAddIsTriedAgainOnTheNextRefresh() async {
        let store = store(), center = RecordingCenter(status: .authorized)
        let model = model(store, center) { self.at(self.day(11, 24), 10) }
        center.addSucceeds = false
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        center.addSucceeds = true
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        XCTAssertEqual(center.plans, [.once(at(day(11, 25), 20)), .once(at(day(11, 25), 20))], "the failed plan is replaced again")
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        XCTAssertEqual(center.plans.count, 2, "a plan that was added is not replaced again")
    }
    func testLockedAccessRemovesThePendingNotificationAndKeepsDayOne() async {
        let store = store(), center = RecordingCenter(status: .authorized)
        var now = at(day(11, 24), 10)
        let model = model(store, center) { now }
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        now = at(day(11, 27), 10)
        await model.refresh(state: .locked, configuration: enabled, facts: trialFacts)
        XCTAssertEqual(center.plans.last, ReviewNotificationPlan.none)
        XCTAssertEqual(model.schedule?.dayOne, day(11, 23))
    }
    func testUnknownAccessFixesNothingAndSchedulesNothing() async {
        let store = store(), center = RecordingCenter(status: .authorized)
        let model = model(store, center) { self.at(self.day(11, 24), 10) }
        await model.refresh(state: .unknown, configuration: enabled, facts: nil)
        XCTAssertNil(model.schedule)
        XCTAssertEqual(store.firstRun, day(11, 24), "the first run is recorded for a later day 1")
        XCTAssertEqual(center.plans, [.none])
    }
    func testGateOffUsesTheFirstRunAndOneRepeatingNotification() async {
        let store = store(), center = RecordingCenter(status: .authorized)
        var now = at(day(11, 24), 10)
        let model = model(store, center) { now }
        await model.refresh(state: .unknown, configuration: enabled, facts: nil)
        now = at(day(11, 26), 10)
        await model.refresh(state: .granted, configuration: .disabled, facts: nil)
        XCTAssertEqual(model.schedule?.dayOne, day(11, 24), "day 1 is the first run, not the day access first read granted")
        XCTAssertEqual(center.plans.last, .repeating(weekday: day(11, 26).weekday(calendar: calendar), minute: 1200))
    }
    func testNotificationReplacementsRunOneAtATime() async {
        let store = store(), center = GatedCenter(), calendar = calendar, facts = trialFacts, enabled = enabled
        let model = WeeklyReviewModel(store: store, center: center, now: { self.at(self.day(11, 24), 10) }, calendar: { calendar })
        let first = Task { await model.refresh(state: .granted, configuration: enabled, facts: facts) }
        while !center.isHeld { await Task.yield() }
        // The notification is turned off while the first replacement waits between its remove and its add.
        let second = Task { await model.setNotificationsOn(false) }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(center.events, ["remove"], "the second replacement waits for the first")
        center.release()
        await first.value
        await second.value
        XCTAssertEqual(center.events, ["remove", "add", "remove", "add"])
        XCTAssertEqual(center.plans, [.once(at(day(11, 25), 20)), .none], "the newest settings are the last ones applied")
    }
    func testTheCalendarEntryOpensTheCurrentPeriodAlsoOnDayFourOfTheTrial() async {
        let store = store(), center = RecordingCenter(status: .authorized)
        // Thursday 10:00 is day 4, before the trial ends at 21:30; the first period ended on day 3.
        let model = model(store, center) { self.at(self.day(11, 26), 10) }
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        model.requestOpenCurrent()
        XCTAssertEqual(model.request?.day, day(11, 26), "the calendar opens the current period; the ended one opens from its notification")
    }
    func testTheFirstRunIsTheLaunchDayAlsoWhenTheFirstRefreshComesLater() async {
        let store = store(), center = RecordingCenter(status: .authorized)
        var now = at(day(11, 24), 10)
        let model = model(store, center) { now }
        XCTAssertEqual(store.firstRun, day(11, 24), "the model records the first run when the runtime makes it at launch")
        // Onboarding ends the next day, so the idle screen and its first refresh come then.
        now = at(day(11, 25), 10)
        await model.refresh(state: .granted, configuration: .disabled, facts: nil)
        XCTAssertEqual(model.schedule?.dayOne, day(11, 24))
    }
    func testTheCalendarEntryOpensTheCurrentPeriodOtherwise() async {
        let store = store(), center = RecordingCenter(status: .authorized)
        let model = model(store, center) { self.at(self.day(11, 26), 10) }
        await model.refresh(state: .granted, configuration: .disabled, facts: nil)
        model.requestOpenCurrent()
        XCTAssertEqual(model.request?.day, day(11, 26))
    }
    func testExplanationIsDueOnceAndTheSystemPromptFollowsIt() async {
        let store = store(), center = RecordingCenter(status: .notDetermined)
        let model = model(store, center) { self.at(self.day(11, 24), 10) }
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        XCTAssertTrue(model.explanationDue)
        XCTAssertEqual(center.requests, 0, "the system prompt never shows before the explanation")
        XCTAssertEqual(center.plans, [.none], "nothing is scheduled without the permission")
        await model.allowNotifications()
        XCTAssertEqual(center.requests, 1)
        XCTAssertFalse(model.explanationDue)
        XCTAssertEqual(center.plans.last, .once(at(day(11, 25), 20)))
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        XCTAssertFalse(model.explanationDue)
    }
    func testClosedExplanationNeverShowsAgainAndTheRowAsksOnce() async {
        let store = store(), center = RecordingCenter(status: .notDetermined)
        center.answer = .denied
        let model = model(store, center) { self.at(self.day(11, 24), 10) }
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        model.dismissExplanation()
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        XCTAssertFalse(model.explanationDue)
        XCTAssertEqual(center.requests, 0)
        await model.setNotificationsOn(true)
        XCTAssertEqual(center.requests, 1)
        XCTAssertEqual(model.permission, .denied)
        await model.setNotificationsOn(true)
        XCTAssertEqual(center.requests, 1, "a denied permission is never asked again")
    }
    func testTheRowSwitchNeverAsksBeforeTheExplanation() async {
        let store = store(), center = RecordingCenter(status: .notDetermined)
        let model = model(store, center) { self.at(self.day(11, 24), 10) }
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        XCTAssertTrue(model.explanationDue)
        await model.setNotificationsOn(false)
        await model.setNotificationsOn(true)
        XCTAssertEqual(center.requests, 0, "the system prompt never shows before the explanation")
        XCTAssertTrue(model.explanationDue, "the explanation still shows when the idle screen is free")
        XCTAssertFalse(store.explanationShown)
        XCTAssertEqual(model.schedule?.notificationsOn, true)
        await model.allowNotifications()
        XCTAssertEqual(center.requests, 1)
        XCTAssertEqual(center.plans.last, .once(at(day(11, 25), 20)))
    }
    func testExplanationIsNotDueWithoutGrantedAccess() async {
        let center = RecordingCenter(status: .notDetermined)
        let model = model(store(), center) { self.at(self.day(11, 24), 10) }
        await model.refresh(state: .locked, configuration: enabled, facts: nil)
        XCTAssertFalse(model.explanationDue)
    }
    func testAnOlderRefreshThatResumesLastDoesNotMakeTheExplanationDue() async {
        let center = HeldPermissionCenter(), calendar = calendar, facts = trialFacts, enabled = enabled
        let model = WeeklyReviewModel(store: store(), center: center, now: { self.at(self.day(11, 24), 10) }, calendar: { calendar })
        let older = Task { await model.refresh(state: .granted, configuration: enabled, facts: facts) }
        while center.held.count < 1 { await Task.yield() }
        // A refund makes access read locked while the older refresh waits for its permission read.
        let newer = Task { await model.refresh(state: .locked, configuration: enabled, facts: facts) }
        while center.held.count < 2 { await Task.yield() }
        center.resume(1, with: .notDetermined)
        await newer.value
        center.resume(0, with: .notDetermined)
        await older.value
        XCTAssertFalse(model.explanationDue, "the explanation shows only while access reads granted")
    }
    func testWeekdayTimeAndSwitchReplaceThePendingNotification() async {
        let center = RecordingCenter(status: .authorized)
        let model = model(store(), center) { self.at(self.day(11, 27), 10) }
        await model.refresh(state: .granted, configuration: .disabled, facts: nil)
        // Day 1 is 2026-11-27, so the first period ends on Sunday 11-29, which keeps its notification before the Tuesdays.
        await model.setWeekday(3)
        XCTAssertEqual(center.plans.last, .onceThenRepeating(at(day(11, 29), 20), weekday: 3, minute: 1200))
        await model.setMinute(7 * 60 + 30)
        XCTAssertEqual(center.plans.last, .onceThenRepeating(at(day(11, 29), 7, 30), weekday: 3, minute: 450))
        await model.setNotificationsOn(false)
        XCTAssertEqual(center.plans.last, ReviewNotificationPlan.none)
        XCTAssertEqual(model.schedule?.notificationsOn, false)
    }
    func testOpenReviewShowsWhatIDidTheMomentAndTheLastNote() async throws {
        let store = store(), center = RecordingCenter(status: .authorized)
        var now = at(day(11, 24), 10)
        let model = model(store, center) { now }
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        let entries = [ReviewEntry(startedAt: at(day(11, 23), 22), focusDuration: 1500), ReviewEntry(startedAt: at(day(11, 24), 7), focusDuration: 1500)]
        var intervals: [DateInterval] = []
        model.load(day: day(11, 24)) { interval in intervals.append(interval); return entries }
        let first = try XCTUnwrap(model.page)
        XCTAssertEqual(intervals, [DateInterval(start: day(11, 23).start(in: calendar), end: day(11, 26).start(in: calendar))])
        XCTAssertEqual(first.sentence, "이번 주 지금까지, 이틀에 걸쳐 2번 집중했어요.")
        XCTAssertNil(first.moment, "22:00 and 07:00 are not within 60 minutes, and no day without a record lies between them")
        XCTAssertNil(first.lastNote)
        XCTAssertTrue(first.noteEditable)
        model.updateNote("  ")
        XCTAssertNil(store.note(for: first.period), "an empty note is not stored")
        model.updateNote("월요일 아침, 수학부터")
        model.close()
        // The next period shows that note as its last note.
        now = at(day(11, 26), 9)
        model.load(day: day(11, 26)) { _ in [] }
        let second = try XCTUnwrap(model.page)
        XCTAssertEqual(second.lastNote, "월요일 아침, 수학부터")
        XCTAssertEqual(second.sentence, WeeklyReview.emptyMessage)
        // The ended period's note is still editable until the end of the next period.
        model.close(); model.load(day: day(11, 25)) { _ in entries }
        XCTAssertEqual(model.page?.noteEditable, true)
        XCTAssertEqual(model.page?.note, "월요일 아침, 수학부터")
        now = at(day(12, 3), 9)
        model.close(); model.load(day: day(11, 25)) { _ in entries }
        XCTAssertEqual(model.page?.noteEditable, false)
        model.updateNote("바꾼 말")
        XCTAssertEqual(store.note(for: first.period), "월요일 아침, 수학부터", "an older note is read-only")
    }
    func testNotificationTapOpensThePeriodOfItsDay() {
        let model = model(store(), RecordingCenter(status: .authorized)) { self.at(self.day(11, 26), 9) }
        model.openFromNotification(at: at(day(11, 25), 20))
        XCTAssertEqual(model.request?.day, day(11, 25))
        model.close()
        XCTAssertNil(model.request)
    }
    func testNotificationTapAfterATimeZoneChangeOpensTheAnnouncedPeriod() async {
        var zone = calendar
        let model = WeeklyReviewModel(store: store(), center: RecordingCenter(status: .authorized), now: { self.at(self.day(11, 26), 9) }, calendar: { zone })
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        // The day 3 notification fired at 20:00 in Seoul; the tap comes after a move to UTC+14, where that time is 2026-11-26.
        zone.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
        model.openFromNotification(at: at(day(11, 25), 20))
        XCTAssertEqual(model.request?.day, day(11, 25), "the first period, whose note is still editable")
    }
    func testOpenReviewReloadsWhenTheDayChanges() async throws {
        let store = store(), center = RecordingCenter(status: .authorized)
        var now = at(day(11, 25), 10)
        let model = model(store, center) { now }
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        model.load(day: day(11, 25)) { _ in [ReviewEntry(startedAt: self.at(self.day(11, 24), 7), focusDuration: 1500)] }
        XCTAssertEqual(model.page?.inProgress, true)
        XCTAssertEqual(model.page?.sentence, "이번 주 지금까지, 하루 동안 1번 집중했어요.")
        // The review stays open past midnight; the first period has ended.
        now = at(day(11, 26), 0, 5)
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        let page = try XCTUnwrap(model.page)
        XCTAssertEqual(page.today, day(11, 26))
        XCTAssertFalse(page.inProgress)
        XCTAssertEqual(page.sentence, "이번 주 하루 동안 1번 집중했어요.")
        XCTAssertEqual(page.period.last, day(11, 25), "the open review keeps its period")
    }
    func testASessionStartKeepsTheOpenReviewForAfterTheSession() throws {
        let model = model(store(), RecordingCenter(status: .authorized)) { self.at(self.day(11, 26), 9) }
        model.requestOpen(day: day(11, 26))
        XCTAssertTrue(model.presentRequest())
        let request = try XCTUnwrap(model.presented)
        model.load(day: request.day) { _ in [] }
        // A Focus filter session starts: the sheet closes, and its `onDisappear` closes the review.
        model.suspendOpenReview()
        model.close(request: request.id)
        XCTAssertEqual(model.request, request, "the request stays")
        XCTAssertNil(model.page)
        XCTAssertTrue(model.presentRequest(), "the review shows again after the session")
        // A close by the student after that ends the request.
        model.close(request: request.id)
        XCTAssertNil(model.request)
    }
    func testASessionStartKeepsTheExplanationDue() async {
        let store = store(), center = RecordingCenter(status: .notDetermined)
        let model = model(store, center) { self.at(self.day(11, 24), 10) }
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        XCTAssertTrue(model.explanationDue)
        XCTAssertTrue(model.presentExplanation())
        // A Focus filter session starts: the sheet closes, and its `onDisappear` calls `dismissExplanation()`.
        model.suspendExplanation()
        model.dismissExplanation()
        XCTAssertTrue(model.explanationDue)
        XCTAssertFalse(store.explanationShown)
        // After the session the explanation shows again; closing it then marks it shown.
        XCTAssertTrue(model.presentExplanation(), "the explanation shows again after the session")
        model.dismissExplanation()
        XCTAssertFalse(model.explanationDue)
        XCTAssertTrue(store.explanationShown)
        XCTAssertEqual(center.requests, 0)
    }
    func testASwipedExplanationDoesNotOpenAgainWhenOnDismissRunsFirst() async {
        let store = store(), center = RecordingCenter(status: .notDetermined)
        let model = model(store, center) { self.at(self.day(11, 24), 10) }
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        XCTAssertTrue(model.presentExplanation())
        // A swipe down: the sheet's `onDismiss` asks to present again before the view's `onDisappear` closes the explanation.
        XCTAssertFalse(model.presentExplanation(), "a dismissed explanation never presents again")
        model.dismissExplanation()
        XCTAssertFalse(model.explanationDue)
        XCTAssertTrue(store.explanationShown)
    }
    func testANoteSavedAfterTheEditWindowClosedIsNotStored() async throws {
        let store = store(), center = RecordingCenter(status: .authorized)
        var now = at(day(11, 24), 10)
        let model = model(store, center) { now }
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        model.load(day: day(11, 24)) { _ in [] }
        let period = try XCTUnwrap(model.page?.period)
        model.updateNote("처음 쓴 말")
        // The review stays open past the end of the next period (2026-12-02); the edit window closed at midnight.
        now = at(day(12, 3), 0, 5)
        model.updateNote("자정 뒤에 쓴 말")
        XCTAssertEqual(store.note(for: period), "처음 쓴 말")
        XCTAssertEqual(model.page?.noteEditable, false)
    }
    func testClosingAnOlderReviewKeepsTheNewerRequest() throws {
        let model = model(store(), RecordingCenter(status: .authorized)) { self.at(self.day(11, 26), 9) }
        model.requestOpen(day: day(11, 26))
        let older = try XCTUnwrap(model.request)
        // A notification tap arrives while the older review is open.
        model.openFromNotification(at: at(day(11, 25), 20))
        model.close(request: older.id)
        XCTAssertEqual(model.request?.day, day(11, 25), "the notified period opens next")
        let newer = try XCTUnwrap(model.request)
        model.close(request: newer.id)
        XCTAssertNil(model.request)
    }
    func testOpenSheetKeepsItsRequestAndTheNewerOneShowsAfterIt() throws {
        let model = model(store(), RecordingCenter(status: .authorized)) { self.at(self.day(11, 26), 9) }
        model.requestOpen(day: day(11, 26))
        XCTAssertTrue(model.presentRequest())
        let older = try XCTUnwrap(model.presented)
        XCTAssertFalse(model.presentRequest(), "the open sheet's request does not show twice")
        // A notification tap arrives while the older review is open: the sheet keeps the older request.
        model.openFromNotification(at: at(day(11, 25), 20))
        XCTAssertEqual(model.presented, older)
        model.close(request: older.id)
        XCTAssertTrue(model.presentRequest())
        XCTAssertEqual(model.presented?.day, day(11, 25))
    }
    func testRetryReadsTheOpenReviewNotANewerRequest() async throws {
        let store = store(), center = RecordingCenter(status: .authorized)
        let model = model(store, center) { self.at(self.day(11, 26), 9) }
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        model.requestOpen(day: day(11, 26))
        var fails = true
        model.load(day: day(11, 26)) { _ in if fails { throw ControlIssue.io }; return [] }
        XCTAssertTrue(model.loadFailed)
        // A notification tap of the first period arrives while the review of the second period is open.
        model.openFromNotification(at: at(day(11, 25), 20))
        fails = false
        model.retry()
        XCTAssertEqual(model.page?.period.first, day(11, 26), "the open review keeps its own period")
    }
    func testNoteWrittenWhileAccessIsUnknownStaysWithItsReviewAfterDayOneIsFixed() async throws {
        let store = store(), center = RecordingCenter(status: .authorized)
        let model = model(store, center) { self.at(self.day(11, 24), 22) }
        await model.refresh(state: .unknown, configuration: enabled, facts: nil)
        model.requestOpen(day: day(11, 24))
        model.load(day: day(11, 24)) { _ in [] }
        XCTAssertEqual(model.page?.period.first, day(11, 24), "the provisional day 1 is the first run")
        model.updateNote("수요일엔 영어부터")
        // Access reads granted: the trial started on 2026-11-23 on another device.
        await model.refresh(state: .granted, configuration: enabled, facts: trialFacts)
        let period = try XCTUnwrap(model.page?.period)
        XCTAssertEqual(period.first, day(11, 23))
        XCTAssertEqual(store.note(for: period), "수요일엔 영어부터")
        XCTAssertEqual(model.page?.note, "수요일엔 영어부터", "the open review shows the moved note")
    }
    func testMovedNotesKeepANoteAlreadyUnderTheFixedPeriod() {
        let store = store()
        let provisional = ReviewSchedule.start(dayOne: day(11, 24), calendar: calendar), fixed = ReviewSchedule.start(dayOne: day(11, 23), calendar: calendar)
        store.setNote("이미 있던 말", for: fixed.period(containing: day(11, 23), calendar: calendar))
        store.setNote("임시로 쓴 말", for: provisional.period(containing: day(11, 24), calendar: calendar))
        store.moveNotes(from: provisional, to: fixed, today: day(11, 24), calendar: calendar)
        XCTAssertEqual(store.note(for: fixed.period(containing: day(11, 24), calendar: calendar)), "이미 있던 말")
        XCTAssertNil(store.note(for: provisional.period(containing: day(11, 24), calendar: calendar)))
    }
    func testFailedReadShowsTheErrorAndNoPage() {
        let model = model(store(), RecordingCenter(status: .authorized)) { self.at(self.day(11, 26), 9) }
        model.requestOpen(day: day(11, 26))
        model.load(day: day(11, 26)) { _ in throw ControlIssue.io }
        XCTAssertTrue(model.loadFailed)
        XCTAssertNil(model.page)
    }
}
