import Foundation
import Observation

/// The notification permission as the review reads it.
enum ReviewPermission: Equatable { case notDetermined, denied, authorized }

/// The notification calls of the weekly review, so that tests and UI fixtures replace them; only the app target has an implementation that reaches the system.
@MainActor protocol ReviewNotificationScheduling {
    func permission() async -> ReviewPermission
    /// Shows the system prompt. The review calls it only after its own explanation, or from the notification row.
    func requestPermission() async
    /// Removes the pending review notification and adds the one of `plan`, if any; `false` when the add failed.
    func replace(with plan: ReviewNotificationPlan, calendar: Calendar) async -> Bool
}

/// A request to show the review of the period that holds `day`, from the calendar entry or a notification tap.
struct ReviewRequest: Equatable, Identifiable {
    let id = UUID()
    let day: ReviewDay
}

/// What the open review shows.
struct ReviewPage: Equatable {
    var period: ReviewPeriod
    var today: ReviewDay
    var summary: ReviewSummary
    var sentence: String
    var moment: String?
    /// The note of the period just before; `nil` when there is none.
    var lastNote: String?
    var note: String
    var noteEditable: Bool
    /// `true` while today is on or before the last day of the period.
    var inProgress: Bool { today <= period.last }
}

/// The weekly review's values in the app's own defaults, never in the App Group: the periods and the notification settings, the notes, the first run and the explanation flag.
@MainActor struct WeeklyReviewStore {
    let defaults: UserDefaults
    var schedule: ReviewSchedule? {
        get { defaults.data(forKey: Keys.schedule).flatMap { try? JSONDecoder().decode(ReviewSchedule.self, from: $0) } }
        nonmutating set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Keys.schedule) }
    }
    /// The local day on which a build with the review first ran: day 1 of an earlier user and of every person while the gate is off.
    var firstRun: ReviewDay? {
        get { defaults.data(forKey: Keys.firstRun).flatMap { try? JSONDecoder().decode(ReviewDay.self, from: $0) } }
        nonmutating set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Keys.firstRun) }
    }
    /// The explanation before the permission prompt shows once.
    var explanationShown: Bool {
        get { defaults.bool(forKey: Keys.explanation) }
        nonmutating set { defaults.set(newValue, forKey: Keys.explanation) }
    }
    private var notes: [String: String] { defaults.dictionary(forKey: Keys.notes) as? [String: String] ?? [:] }
    /// One note per period, keyed by its first day, which no weekday change moves.
    func note(for period: ReviewPeriod) -> String? { notes[period.first.key] }
    /// An empty note is not stored.
    func setNote(_ text: String, for period: ReviewPeriod) {
        var notes = notes
        notes[period.first.key] = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        defaults.set(notes, forKey: Keys.notes)
    }
    /// Moves each note of a `provisional` period up to `today` to the period of `fixed` that holds the provisional period's last day, or today when that is earlier.
    /// A newer note wins when two provisional periods fall into one fixed period; a note already under the fixed period stays.
    func moveNotes(from provisional: ReviewSchedule, to fixed: ReviewSchedule, today: ReviewDay, calendar: Calendar) {
        let original = notes
        var notes = original, period = provisional.period(containing: today, calendar: calendar)
        var moves: [(target: String, text: String)] = []
        while true {
            let target = fixed.period(containing: min(period.last, today), calendar: calendar).first.key
            if target != period.first.key, let text = original[period.first.key] {
                notes[period.first.key] = nil; moves.append((target, text))
            }
            guard let earlier = provisional.period(before: period, calendar: calendar) else { break }
            period = earlier
        }
        // `moves` runs from the newest provisional period to the oldest.
        for move in moves where notes[move.target] == nil { notes[move.target] = move.text }
        guard notes != original else { return }
        defaults.set(notes, forKey: Keys.notes)
    }
    private enum Keys {
        static let explanation = "weeklyReviewExplanationShown", firstRun = "weeklyReviewFirstRun", notes = "weeklyReviewNotes", schedule = "weeklyReviewSchedule"
    }
}

/// The weekly review (docs/specs/2026-11-25-weekly-review-design.md): its periods, notes, notification and the open review.
@MainActor @Observable final class WeeklyReviewModel {
    @ObservationIgnored let store: WeeklyReviewStore
    @ObservationIgnored private let center: any ReviewNotificationScheduling
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: () -> Calendar
    @ObservationIgnored private var kind: ReviewAccessKind = .none
    @ObservationIgnored private var trialEnd: Date?
    /// The last plan handed to the center in this process, so a refresh that changes nothing does not replace the pending notification.
    @ObservationIgnored private var appliedPlan: ReviewNotificationPlan?
    private(set) var schedule: ReviewSchedule?
    private(set) var permission: ReviewPermission = .notDetermined
    /// The explanation before the permission prompt is due; the idle screen shows it as a sheet.
    private(set) var explanationDue = false
    /// The review to show; the idle screen presents it when no session runs.
    private(set) var request: ReviewRequest?
    /// The request that the review sheet showed last. The open sheet shows this request, not `request`, which a notification tap can replace while the sheet is open;
    /// it stays set after the sheet closes, so that a closed review's request does not open again when `onDismiss` runs before `onDisappear`.
    private(set) var presented: ReviewRequest?
    private(set) var page: ReviewPage?
    /// The history read of the open review failed.
    private(set) var loadFailed = false

    init(store: WeeklyReviewStore, center: any ReviewNotificationScheduling, now: @escaping () -> Date = Date.init, calendar: @escaping () -> Calendar = { .current }) {
        self.store = store; self.center = center; self.now = now; self.calendar = calendar
        schedule = store.schedule
        // The runtime makes the model at launch, before onboarding shows the idle screen, so the first run is the launch day.
        if store.firstRun == nil { store.firstRun = ReviewDay(now(), calendar: calendar()) }
    }

    /// Launch, foreground and every change of paid access. Day 1 is fixed the first time access reads `granted`; `unknown` and `locked` schedule nothing,
    /// so a trial end or a refund removes the pending notification here.
    func refresh(state: PaidAccessState, configuration: PaidAccessConfiguration, facts: PaidAccessFacts?) async {
        let now = now(), calendar = calendar(), today = ReviewDay(now, calendar: calendar)
        if store.firstRun == nil { store.firstRun = today }
        if schedule == nil, state == .granted {
            let firstRun = (store.firstRun ?? today).start(in: calendar)
            let dayOne = ReviewDay(PaidAccess.reviewDayOne(configuration: configuration, facts: facts, firstRun: firstRun), calendar: calendar)
            let start = ReviewSchedule.start(dayOne: dayOne, calendar: calendar)
            // A note written while access read `unknown` is under a period of the provisional schedule from the first run.
            store.moveNotes(from: .start(dayOne: store.firstRun ?? today, calendar: calendar), to: start, today: today, calendar: calendar)
            schedule = start; store.schedule = start
        }
        // Every refresh reads the open review again: a session completed since it opened, a new day that ends its period
        // (no "지금까지", a closed note) or a time zone change that moves the local days.
        if page != nil, let loadedDay { reload(day: loadedDay) }
        kind = PaidAccess.reviewAccessKind(state: state, configuration: configuration, facts: facts, now: now)
        trialEnd = PaidAccess.grantingTrialEnd(configuration: configuration, facts: facts, now: now)
        permission = await center.permission()
        await applyPlan()
        explanationDue = state == .granted && permission == .notDetermined && !store.explanationShown && schedule.map { today >= $0.dayOne } == true
    }
    /// The last replacement handed to the center. A replacement suspends between its remove and its adds, so each one waits for the one before it;
    /// otherwise an older call's remaining adds could follow a newer call's remove and leave a stale notification.
    @ObservationIgnored private var planReplacement: Task<Void, Never>?
    private func applyPlan() async {
        let previous = planReplacement
        let replacement = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            // The plan is read when the replacement runs, so the newest settings win.
            let plan = permission == .authorized ? WeeklyReview.notificationPlan(kind: kind, schedule: schedule, now: now(), trialEnd: trialEnd, calendar: calendar()) : .none
            guard plan != appliedPlan else { return }
            // A failed add leaves no notification, so the next refresh must try the same plan again.
            appliedPlan = await center.replace(with: plan, calendar: calendar()) ? plan : nil
        }
        planReplacement = replacement
        await replacement.value
    }

    // MARK: Explanation and notification row

    /// "알림 받기" of the explanation: the system prompt shows only after it.
    func allowNotifications() async {
        store.explanationShown = true; explanationDue = false
        await center.requestPermission()
        permission = await center.permission()
        await applyPlan()
    }
    /// Closing the explanation; it never shows again, and the notification row can still turn the notification on.
    func dismissExplanation() {
        guard !explanationSuspended else { explanationSuspended = false; return }
        store.explanationShown = true; explanationDue = false
    }
    /// A session that starts while the explanation shows closes it without an answer, so it stays due and shows again after the session.
    func suspendExplanation() { explanationSuspended = true }
    @ObservationIgnored private var explanationSuspended = false
    /// The switch of the notification row. Turning it on asks for the permission once, when it was never asked; a denied permission is never asked again.
    /// The system prompt never shows before the explanation: while the explanation has not shown, the switch only saves, and the explanation stays due.
    func setNotificationsOn(_ on: Bool) async {
        guard var schedule else { return }
        schedule.notificationsOn = on; save(schedule)
        if on, permission == .notDetermined, store.explanationShown {
            await center.requestPermission()
            permission = await center.permission()
        }
        await applyPlan()
    }
    /// A new weekday replaces the pending notification and can end the current period early (spec "Review period").
    func setWeekday(_ weekday: Int) async {
        guard var schedule else { return }
        schedule.changeWeekday(to: weekday, today: ReviewDay(now(), calendar: calendar()), calendar: calendar()); save(schedule)
        if let page { reload(day: page.today > page.period.last ? page.period.last : page.today) }
        await applyPlan()
    }
    func setMinute(_ minute: Int) async {
        guard var schedule, (0..<1440).contains(minute) else { return }
        schedule.minute = minute; save(schedule)
        await applyPlan()
    }
    private func save(_ schedule: ReviewSchedule) { self.schedule = schedule; store.schedule = schedule }

    // MARK: Open review

    func requestOpen(day: ReviewDay) { request = ReviewRequest(day: day) }
    /// The calendar entry: the review of the current period (contract item 5). An ended period opens from its notification.
    func requestOpenCurrent() { requestOpen(day: ReviewDay(now(), calendar: calendar())) }
    /// The idle screen presents the current request; `false` when the sheet already showed it.
    func presentRequest() -> Bool {
        guard let request, request.id != presented?.id else { return false }
        presented = request
        return true
    }
    /// A tap on a notification opens the review of the period that it announced, also after a time zone change moved the local day of its fire date.
    /// Only a fixed schedule has a notification; without one, the review opens on the local day of the fire date.
    func openFromNotification(at date: Date) {
        let calendar = calendar()
        requestOpen(day: schedule?.announcedPeriod(firedAt: date, calendar: calendar).last ?? ReviewDay(date, calendar: calendar))
    }
    /// A session that starts while the review shows closes it; its request stays and the review opens again after the session.
    func suspendOpenReview() { reviewSuspended = true }
    @ObservationIgnored private var reviewSuspended = false
    /// Closes the open review. With `id`, only while that request is still the current one: a notification tap during an open review replaced it, and its review opens next.
    func close(request id: UUID? = nil) {
        if reviewSuspended {
            reviewSuspended = false; presented = nil; page = nil; loadFailed = false; loadedDay = nil
            return
        }
        guard id == nil || request?.id == id else { return }
        request = nil; page = nil; loadFailed = false; loadedDay = nil
    }

    @ObservationIgnored private var read: ((DateInterval) throws -> [ReviewEntry])?
    /// The day of the open review, which can differ from `request` while a newer request waits for the open review to close.
    @ObservationIgnored private var loadedDay: ReviewDay?
    /// Reads the period's completed sessions; before day 1 is fixed (access `unknown`), the first run gives a provisional day 1 that is not stored.
    func load(day: ReviewDay, read: @escaping (DateInterval) throws -> [ReviewEntry]) {
        self.read = read; loadedDay = day
        reload(day: day)
    }
    private func reload(day: ReviewDay) {
        guard let read else { return }
        let now = now(), calendar = calendar(), today = ReviewDay(now, calendar: calendar)
        let schedule = schedule ?? .start(dayOne: store.firstRun ?? today, calendar: calendar)
        let period = schedule.period(containing: day, calendar: calendar)
        let interval = DateInterval(start: period.first.start(in: calendar), end: period.last.adding(1, calendar: calendar).start(in: calendar))
        do {
            let entries = try read(interval)
            let summary = ReviewSummary(entries: entries, period: period, today: today, calendar: calendar)
            let lastNote = schedule.period(before: period, calendar: calendar).flatMap(store.note(for:))
            page = ReviewPage(period: period, today: today, summary: summary, sentence: WeeklyReview.sentence(summary, inProgress: today <= period.last),
                              moment: WeeklyReview.moment(entries: entries, period: period, calendar: calendar).map { WeeklyReview.text($0, calendar: calendar) },
                              lastNote: lastNote, note: store.note(for: period) ?? "", noteEditable: schedule.isNoteEditable(period, today: today, calendar: calendar))
            loadFailed = false
        } catch {
            page = nil; loadFailed = true
        }
    }
    /// Reads the history again after a failure.
    func retry() { if let loadedDay { reload(day: loadedDay) } }
    func updateNote(_ text: String) {
        guard let page, page.noteEditable else { return }
        // A review left open past midnight can reach the end of the edit window; the check runs again at each save.
        let calendar = calendar(), today = ReviewDay(now(), calendar: calendar)
        let schedule = schedule ?? .start(dayOne: store.firstRun ?? today, calendar: calendar)
        guard schedule.isNoteEditable(page.period, today: today, calendar: calendar) else { self.page?.noteEditable = false; return }
        store.setNote(text, for: page.period)
        self.page?.note = text
    }
}
