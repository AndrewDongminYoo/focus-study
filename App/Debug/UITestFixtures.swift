#if DEBUG
import Foundation
import FamilyControls
import ManagedSettings
import Observation
import SwiftData
import SwiftUI

@MainActor @Observable final class FixtureAuthorization: AuthorizationProviding {
    var status: AccessStatus
    /// `checking` stays until a request: the fixture of a cold launch whose published value has not settled yet.
    /// `declines`: the next request is declined, as the person's "Don't Allow" (#38).
    private var declines: Bool
    init(denied: Bool, notRequested: Bool = false, checking: Bool = false, declines: Bool = false) {
        status = notRequested ? .notRequested : checking ? .checking : denied ? .denied : .approved; self.declines = declines
    }
    func requestIndividual() async {
        if declines { declines = false; status = .declined } else { status = .approved }
    }
    func refresh() {}
    func accessState() -> AccessState {
        switch status {
        case .approved: .approved
        case .denied: .denied
        case .notRequested, .checking, .declined: .unknown
        }
    }
}
@MainActor @Observable final class FixtureSelection: SelectionStoring {
    var selected: Bool
    var selection = FamilyActivitySelection()
    var counts: (apps: Int, websites: Int, categories: Int) { (selected ? 1 : 0, 0, 0) }
    init(selected: Bool) { self.selected = selected }
    func save(_ selection: FamilyActivitySelection) throws { self.selection = selection }
}
private final class FixtureMonitoring: MonitoringClient {
    var registeredSessionIDs: [UUID] { Array(registered) }
    var registered = Set<UUID>()
    let fail: Bool
    let startDelay: TimeInterval
    init(fail: Bool, startDelay: TimeInterval = 0) { self.fail = fail; self.startDelay = startDelay }
    func register(id: UUID, start: Date, end: Date) throws {
        // Deliberately blocks the same synchronous path as the real adapter; no real Screen Time call runs.
        if startDelay > 0 { Thread.sleep(forTimeInterval: startDelay) }
        if fail { throw ControlIssue.io }
        registered.insert(id)
    }
    func isRegistered(id: UUID) -> Bool { registered.contains(id) }
    func stop(id: UUID) { registered.remove(id); breaks.removeAll { $0.id == id } }
    /// Break registrations stay in memory; the fixture has no Monitor, so the app's timer tick re-blocks.
    var breaks: [(id: UUID, index: Int)] = []
    func registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws { breaks.append((id, index)) }
    func isBreakRegistered(id: UUID, index: Int) -> Bool { breaks.contains { $0.id == id && $0.index == index } }
    var registeredBreaks: [(id: UUID, index: Int)] { breaks }
    func stopBreak(id: UUID, index: Int) { breaks.removeAll { $0.id == id && $0.index == index } }
    /// Everyday registrations stay in memory; nothing reaches `DeviceActivityCenter`.
    var everyday: [(revision: UUID, part: EverydayPart)] = []
    func registerEveryday(revision: UUID, part: EverydayPart, start: Int, end: Int) throws {
        if !everyday.contains(where: { $0.revision == revision && $0.part == part }) { everyday.append((revision, part)) }
    }
    var registeredEveryday: [(revision: UUID, part: EverydayPart)] { everyday }
    func stopEveryday(revision: UUID, part: EverydayPart) { everyday.removeAll { $0.revision == revision && $0.part == part } }
}
private final class FixtureShield: ShieldClient { func clear() {} }
/// The everyday file and store in memory, with a synthetic shield flag; it never touches real restrictions.
final class FixtureEverydayLayer: EverydayLayerStore {
    var schedule: EverydaySchedule?
    var selection = FamilyActivitySelection(includeEntireCategory: true)
    private(set) var shieldOn = false
    func load() throws -> EverydaySchedule? { schedule }
    func storeMatches() -> Bool { shieldOn }
    func applyStored() -> Bool { shieldOn = schedule != nil; return shieldOn }
    var hasShield: Bool { shieldOn }
    func clearShield() { shieldOn = false }
    func contains(_ new: FamilyActivitySelection) -> Bool {
        selection.applicationTokens.isSubset(of: new.applicationTokens) && selection.webDomainTokens.isSubset(of: new.webDomainTokens)
    }
    func write(_ schedule: EverydaySchedule, selection: FamilyActivitySelection) { self.schedule = schedule; self.selection = selection }
    /// The off-for-today write keeps the synthetic selection, as the real file keeps its tokens.
    func writeOffDay(_ schedule: EverydaySchedule) throws {
        guard self.schedule?.revision == schedule.revision else { throw ControlIssue.invalidState }
        self.schedule = schedule
    }
    /// One synthetic app token, decoded from opaque bytes; it is never applied to a real store.
    static func sampleSelection() -> FamilyActivitySelection {
        var selection = FamilyActivitySelection(includeEntireCategory: true)
        if let token = try? JSONDecoder().decode(ApplicationToken.self, from: JSONEncoder().encode(["data": Data([7])])) { selection.applicationTokens = [token] }
        return selection
    }
    /// `--everyday-fixture blocking`: a layer whose range started 5 minutes before launch on the 5-minute grid and lasts 2 hours.
    static func blocking(now: Date, calendar: Calendar) -> FixtureEverydayLayer {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let start = max(0, min(minute / EverydaySchedule.grid * EverydaySchedule.grid - 5, EverydaySchedule.latestRangeEnd - 120))
        let layer = FixtureEverydayLayer()
        layer.schedule = EverydaySchedule(revision: UUID(), enabled: true, rangeStart: start, rangeEnd: start + 120, windows: [])
        layer.selection = sampleSelection()
        return layer
    }
    /// A fixed-offset calendar in which launch falls between 12:00 and 12:30, so that a fixture range never reaches 23:55 or midnight, whatever the wall clock.
    /// The 30-minute margin keeps a test that starts in the `preview` lunch window inside it until 13:00.
    static func noonCalendar(now: Date) -> Calendar {
        let seconds = Int(now.timeIntervalSince1970) % 86_400
        let utcHour = seconds / 3600, lateHalf = seconds % 3600 >= 1800
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: (12 - utcHour) * 3600 - (lateHalf ? 1800 : 0)) ?? .gmt
        return calendar
    }
}
/// `history-failure`: every read of today's records fails, so the history error state survives each refresh.
/// A terminal session is still imported and acknowledged, so an ended session never stays in the control file.
@MainActor private final class FixtureFailingHistory: SessionHistoryProviding {
    private let base: any SessionHistoryProviding
    init(base: any SessionHistoryProviding) { self.base = base }
    func importTerminal(_ session: ControlSession) throws { try base.importTerminal(session) }
    func records(on date: Date, calendar: Calendar) throws -> [SessionRecord] { throw ControlIssue.io }
    func records(in interval: DateInterval) throws -> [SessionRecord] { throw ControlIssue.io }
    func streak(at date: Date, calendar: Calendar) throws -> Int { throw ControlIssue.io }
}
/// In-memory selection copies; a restore never touches real restrictions.
private final class FixtureBreakSelection: BreakSelectionStore {
    var copies = Set<UUID>()
    func restoreShield(id: UUID) -> Bool { copies.contains(id) }
    func exists(id: UUID) -> Bool { copies.contains(id) }
    func remove(id: UUID) { copies.remove(id) }
    func removeAll(except id: UUID?) { copies = copies.filter { $0 == id } }
}
extension FocusServices {
    static func fixture(arguments: [String]) -> FocusServices {
        let probeID: UUID?
        if let index = arguments.firstIndex(of: "--live-activity-probe"), index + 1 < arguments.count {
            probeID = UUID(uuidString: arguments[index + 1])
        } else { probeID = nil }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(probeID.map { "FocusActivityProbe-\($0.uuidString)" } ?? "FocusFixture-\(UUID().uuidString)")
        var startDelay: TimeInterval = 0
        if let index = arguments.firstIndex(of: "--start-delay"), index + 1 < arguments.count,
           let requested = TimeInterval(arguments[index + 1]), requested.isFinite, requested >= 0 {
            startDelay = min(requested, 3)
        }
        // `--break-timing short` shortens waits, the break and the slack, but not the focus length or the stale-wait grace.
        // One accessibility query on a slow CI runner can take several seconds and delays the app's timer ticks:
        // the standard grace admits a late automatic break start, and the 15-second slack keeps the deadline notice counting, only up to those lengths.
        // `--break-timing short-lenient` is for a test that never reaches the deadline: the same waits and break with the standard slack
        // and a 5-minute grace, so no single query can make the engine refuse the automatic start or stop the notice.
        // The refusal rule keeps its host test, `BreakControlTests.testStartBreakAfterGraceThrowsBreakUnavailable`.
        var timing = BreakTiming.standard
        if let index = arguments.firstIndex(of: "--break-timing"), index + 1 < arguments.count {
            switch arguments[index + 1] {
            case "short": timing = BreakTiming(waits: [1, 2, 4], breakLength: 3, slack: 15, staleWaitGrace: BreakTiming.standard.staleWaitGrace)
            case "short-lenient": timing = BreakTiming(waits: [1, 2, 4], breakLength: 3, slack: BreakTiming.standard.slack, staleWaitGrace: 300)
            default: break
            }
        }
        // `--everyday-off-wait <seconds>` shortens the off-for-today wait, bounded to 1-30 seconds; the grace stays as the timing gives it.
        if let index = arguments.firstIndex(of: "--everyday-off-wait"), index + 1 < arguments.count,
           let requested = TimeInterval(arguments[index + 1]), requested.isFinite {
            timing.everydayOffWait = min(max(requested, 1), 30)
        }
        let breakSelection = FixtureBreakSelection()
        var everyday = FixtureEverydayLayer()
        // The engine and the status line read the layer in this calendar, not the device time zone.
        let now = Date(), calendar = FixtureEverydayLayer.noonCalendar(now: now)
        if let index = arguments.firstIndex(of: "--everyday-fixture"), index + 1 < arguments.count, arguments[index + 1] == "blocking" {
            everyday = .blocking(now: now, calendar: calendar)
        }
        // `off` stores the `preview` schedule with the layer turned off.
        // `weekday-off` stores it on, on every weekday except the launch day's weekday in the fixture calendar, so launch is always on a day that is off.
        if let index = arguments.firstIndex(of: "--everyday-fixture"), index + 1 < arguments.count, ["preview", "off", "weekday-off"].contains(arguments[index + 1]) {
            everyday.schedule = EverydaySchedule(revision: UUID(), enabled: arguments[index + 1] != "off", rangeStart: 480, rangeEnd: 1080, windows: [EverydaySchedule.template(.lunch)!])
            if arguments[index + 1] == "weekday-off" {
                everyday.schedule?.setWeekdays(EverydaySchedule.allWeekdays.subtracting([EverydaySchedule.weekday(of: now, calendar: calendar)]))
            }
            everyday.selection = FixtureEverydayLayer.sampleSelection()
        }
        let store = SharedControlStore(directory: directory)
        let monitoring = FixtureMonitoring(fail: arguments.contains("registration-failure"), startDelay: startDelay)
        // The explicit display probe can relaunch the same temporary synthetic session.
        // Recreate its in-memory registrations/copy, never any system monitoring or shield.
        if probeID != nil, let session = try? store.withExclusiveAccess({ try $0.load().session }), session.phase == .active || session.isPaused {
            monitoring.registered.insert(session.id)
            if session.phase == .onBreak {
                monitoring.breaks.append((session.id, session.breaksTaken ?? 1))
                breakSelection.copies.insert(session.id)
            }
        }
        let engine = SessionControl(store: store, monitoring: monitoring, shield: FixtureShield(), breakSelection: breakSelection, everyday: everyday, timing: timing, calendar: calendar,
                                    // Fixtures start only manual sessions, which never have a pending shield.
                                    role: .appContainer(applyFocusSelection: { false }))
        let onboarding = arguments.contains("onboarding")
        var services = FocusServices(authorization: FixtureAuthorization(denied: arguments.contains("denied"), notRequested: arguments.contains("not-requested") || onboarding, checking: arguments.contains("checking"), declines: arguments.contains("declines")), selection: FixtureSelection(selected: arguments.contains("--selected") && !onboarding), engine: engine, applySelection: { _ in }, matchesSelection: { _ in true }, isFixture: true)
        services.saveBreakSelection = { _, id in breakSelection.copies.insert(id) }
        services.everydaySelection = { everyday.schedule == nil ? nil : everyday.selection }
        services.everydayContains = { everyday.contains($0) }
        services.writeEveryday = { everyday.write($0, selection: $1) }
        services.writeEverydayOffDay = { try everyday.writeOffDay($0) }
        // `--break-delay <seconds>`: the break feedback stays up to 5 seconds before the transition runs, so a UI test can read it.
        // It does not block the main thread, because the accessibility queries of a UI test need it.
        if let index = arguments.firstIndex(of: "--break-delay"), index + 1 < arguments.count,
           let requested = TimeInterval(arguments[index + 1]), requested.isFinite, requested >= 0 {
            services.fixtureBreakHold = min(requested, 5)
        }
        // `ending-soon`: the start button begins a session with 10 seconds of focus left, so the test's own tap, not launch, starts the clock.
        if arguments.contains("ending-soon") { services.fixtureFocusLeft = 10 }
        if arguments.contains("history-failure") { services.fixtureHistory = { FixtureFailingHistory(base: $0) } }
        // In-memory settings: `onboarding` starts a new person; every other mode is a person who finished onboarding.
        let settings = FocusSettings(defaults: UserDefaults(suiteName: "FocusFixture-\(UUID().uuidString)")!)
        if let index = arguments.firstIndex(of: "--length"), index + 1 < arguments.count, let minutes = Int(arguments[index + 1]) { settings.lengthMinutes = minutes }
        settings.hasCompletedOnboarding = !onboarding
        // `--focus-filter-refusal <reason>`: a stored refusal for the settings guide; no Focus call runs.
        if let index = arguments.firstIndex(of: "--focus-filter-refusal"), index + 1 < arguments.count, let reason = FocusFilterRefusal(rawValue: arguments[index + 1]) {
            settings.recordFilterRefusal(reason, at: now)
        }
        services.settings = settings
        if let probeID {
            services.activityDidChange = FocusActivityRuntime.hook(engine: engine, defaults: UserDefaults(suiteName: "FocusActivityProbe-\(probeID.uuidString)")!)
        }
        return services
    }
}
#endif

#if DEBUG
/// Synthetic StoreKit for `--paid-access`: purchases stay in memory and nothing reaches the App Store.
/// The price is a synthetic string for the paywall; the app's real price always comes from the store.
@MainActor final class FixturePaidAccessStoreKit: PaidAccessStoreKit {
    private var bought: [String: PaidPurchase] = [:]
    /// `--paid-price loading`: the store returns no price, also on a retry.
    var priceLoads = true
    /// `--paid-purchase pending`: every purchase and trial start is pending (Ask to Buy), and its approval arrives 3 seconds later
    /// through the `Transaction.updates` listener, whether the paywall is still open or not.
    var purchasesPend = false
    /// `--paid-purchase pending-later`: every purchase and trial start is pending, and its approval arrives only when the app next returns
    /// to the foreground (the refresh of `didBecomeActive`), through the `Transaction.updates` listener; no timer races the test's taps.
    var approvesOnReturn = false
    private var held: [(String, PaidPurchase)] = []
    /// `--paid-restore owned`: a restore finds the unlock that the person bought on another device.
    var restoreFindsUnlock = false
    private var handle: (@MainActor (String, PaidPurchase) async -> Void)?
    func originalAppVersion() async -> String? {
        // Only a refresh reads the version, so a held approval arrives with the first refresh after the purchase.
        if !held.isEmpty {
            let approvals = held; held = []
            Task { @MainActor in
                for (productID, purchase) in approvals { self.bought[productID] = purchase; await self.handle?(productID, purchase) }
            }
        }
        return "99"
    }
    func read(_ productID: String) async -> PaidAccess.ProductRead { bought[productID].map { .transaction($0) } ?? .noSignal }
    func firstPurchaseDate(_ productID: String) async -> Date? { bought[productID]?.purchaseDate }
    func displayPrice(_ productID: String) async -> String? { priceLoads ? "₩14,000" : nil }
    func purchase(_ productID: String) async throws -> PaidPurchaseOutcome {
        let purchase = bought[productID] ?? PaidPurchase(purchaseDate: Date())
        if approvesOnReturn { held.append((productID, purchase)); return .pending }
        guard !purchasesPend else {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                self.bought[productID] = purchase
                await self.handle?(productID, purchase)
            }
            return .pending
        }
        bought[productID] = purchase
        return .purchased(purchase)
    }
    func sync() async throws {
        if restoreFindsUnlock, bought[PaidAccess.unlockProductID] == nil { bought[PaidAccess.unlockProductID] = PaidPurchase(purchaseDate: Date()) }
    }
    func listen(_ handle: @escaping @MainActor (String, PaidPurchase) async -> Void) -> Task<Void, Never> { self.handle = handle; return Task {} }
    /// `--paid-access locked`: a person who downloaded the paid build and bought nothing.
    /// `--paid-access trial`: the same person 48 hours into the 3-day trial, so day 1 of the weekly review is two days before today.
    /// `--paid-access trial-ended`: the same person whose trial started 4 days ago and ended, with no purchase.
    /// Every other fixture keeps the gate off.
    static func store(arguments: [String]) -> PaidAccessStore {
        let kit = FixturePaidAccessStoreKit()
        kit.priceLoads = value(of: "--paid-price", in: arguments) != "loading"
        kit.purchasesPend = value(of: "--paid-purchase", in: arguments) == "pending"
        kit.approvesOnReturn = value(of: "--paid-purchase", in: arguments) == "pending-later"
        kit.restoreFindsUnlock = value(of: "--paid-restore", in: arguments) == "owned"
        guard let mode = value(of: "--paid-access", in: arguments), ["locked", "trial", "trial-ended"].contains(mode) else {
            return PaidAccessStore(configuration: .disabled, cache: nil, kit: kit)
        }
        let cache = PaidAccessCache(container: FileManager.default.temporaryDirectory.appendingPathComponent("FocusPaidFixture-\(UUID().uuidString)"))
        let trialStart: Date? = switch mode {
        case "trial": Date().addingTimeInterval(-48 * 3600)
        case "trial-ended": Date().addingTimeInterval(-96 * 3600)
        default: nil
        }
        let trial = trialStart.map { PaidPurchase(purchaseDate: $0) }
        try? cache.save(PaidAccessFacts(originalAppVersion: "99", unlock: nil, trial: trial, trialStartedAt: trial?.purchaseDate, confirmedAt: Date()))
        return PaidAccessStore(configuration: PaidAccessConfiguration(enabled: true, firstPaidBuild: 3), cache: cache, kit: kit)
    }
    private static func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
extension FocusRuntime {
    static func fixture(arguments: [String]) throws -> FocusRuntime {
        var services = FocusServices.fixture(arguments: arguments)
        let paidAccess = FixturePaidAccessStoreKit.store(arguments: arguments)
        services.paidAccess = { paidAccess.state }
        let review = FixtureReviewNotificationCenter.model(arguments: arguments)
        if arguments.contains("startup-failure") {
            _ = try services.engine.start(now: Date(), authorized: { .approved }, apply: {}, matches: { true })
        }
        if arguments.contains("expiring") {
            // A session with the configured length that started 3 seconds before its end, so the UI test sees the real expiry path.
            let length = services.settings.lengthSeconds
            _ = try services.engine.start(now: Date().addingTimeInterval(-(length - 3)), length: length, authorized: { .approved }, apply: {}, matches: { true })
        }
        if arguments.contains("open-focus") {
            // A Focus filter session two minutes past its base length; the launch refresh rolls it over and the timer counts up (2026-11-16 extension design).
            let length = services.settings.lengthSeconds
            _ = try services.engine.startFromFocusFilter(now: Date().addingTimeInterval(-(length + 120)), length: length, authorized: { .approved }, selectionReady: true,
                                                         apply: {}, matches: { true })
        }
        var attempts = 0
        return FocusRuntime(recovery: StartupRecovery(engine: services.engine), accessState: services.authorization.accessState, paidAccess: paidAccess, review: review, holder: FocusRuntimeHolder(engine: services.engine, authorization: services.authorization, settings: services.settings, activityDidChange: services.activityDidChange) {
            attempts += 1
            if arguments.contains("startup-failure"), attempts == 1 { throw ControlIssue.io }
            let container = try ModelContainer(for: SessionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            if let index = arguments.firstIndex(of: "--ui-testing"), index + 1 < arguments.count, arguments[index + 1] == "history" {
                // Seed today's records directly so completion rows do not depend on a backdated timer crossing midnight.
                let history = SessionHistory(context: ModelContext(container), acknowledge: { _ in })
                let now = Date(), start = max(Calendar.current.startOfDay(for: now), now.addingTimeInterval(-7200))
                let samples: [(TimeInterval, EndReason)] = [(1500, .expired), (3000, .expired), (1500, .earlyExit), (1500, .deadlineMissed)]
                for (index, sample) in samples.enumerated() {
                    var session = ControlSession(startedAt: start.addingTimeInterval(Double(index) * 60), length: sample.0)
                    session.phase = .terminal; session.reason = sample.1; session.observedAt = session.expiresAt
                    try history.importTerminal(session)
                }
            }
            if let index = arguments.firstIndex(of: "--ui-testing"), index + 1 < arguments.count, arguments[index + 1] == "streak" {
                // Completed records on today and the 2 days before it, a day whose only session was ended early, and an older completed day: the streak is 3.
                // Just after midnight the run ends yesterday, so the number stays 3.
                let history = SessionHistory(context: ModelContext(container), acknowledge: { _ in })
                let calendar = Calendar.current, now = Date(), today = calendar.startOfDay(for: now)
                let samples: [(Int, EndReason)] = [(0, .expired), (1, .expired), (1, .expired), (2, .expired), (3, .earlyExit), (4, .expired)]
                for (index, sample) in samples.enumerated() {
                    // Today's record keeps the rule of the `history` seed; an earlier day's records start after its noon.
                    let day = calendar.date(byAdding: .day, value: -sample.0, to: today) ?? today
                    let start = sample.0 == 0 ? max(today, now.addingTimeInterval(-7200)) : calendar.startOfDay(for: day).addingTimeInterval(43_200 + Double(index) * 60)
                    var session = ControlSession(startedAt: start, length: 1500)
                    session.phase = .terminal; session.reason = sample.1; session.observedAt = session.expiresAt
                    try history.importTerminal(session)
                }
            }
            if let index = arguments.firstIndex(of: "--ui-testing"), index + 1 < arguments.count, arguments[index + 1] == "review" {
                try FixtureReviewNotificationCenter.seed(SessionHistory(context: ModelContext(container), acknowledge: { _ in }))
            }
            return (services, container)
        })
    }
}
#endif

#if DEBUG
/// The weekly review's notification center in memory: it never shows a permission prompt and never schedules a real notification.
@MainActor final class FixtureReviewNotificationCenter: ReviewNotificationScheduling {
    private var status: ReviewPermission
    private(set) var plan: ReviewNotificationPlan = .none
    init(status: ReviewPermission) { self.status = status }
    func permission() async -> ReviewPermission { status }
    func requestPermission() async { if status == .notDetermined { status = .authorized } }
    func replace(with plan: ReviewNotificationPlan, calendar: Calendar) async -> Bool { self.plan = plan; return true }

    /// In-memory defaults. Every fixture has seen the explanation and allowed notifications, so the explanation sheet never shows in the existing flows;
    /// `--review-explanation` is a person who has not been asked yet. Without `--paid-access trial`, `--ui-testing review` stores day 1 seven days before today,
    /// so the current period runs from 4 days before today to 2 days after it, and a note in the previous period.
    static func model(arguments: [String]) -> WeeklyReviewModel {
        let store = WeeklyReviewStore(defaults: UserDefaults(suiteName: "FocusReviewFixture-\(UUID().uuidString)")!)
        let explains = arguments.contains("--review-explanation")
        store.explanationShown = !explains
        let reviewMode = arguments.firstIndex(of: "--ui-testing").map { $0 + 1 < arguments.count && arguments[$0 + 1] == "review" } ?? false
        let trial = arguments.firstIndex(of: "--paid-access").map { $0 + 1 < arguments.count && arguments[$0 + 1] == "trial" } ?? false
        if reviewMode, !trial {
            let calendar = Calendar.current, today = ReviewDay(Date(), calendar: calendar)
            let schedule = ReviewSchedule.start(dayOne: today.adding(-7, calendar: calendar), calendar: calendar)
            store.schedule = schedule; store.firstRun = schedule.dayOne
            store.setNote("월요일 아침, 영어 단어부터 다시 시작하기", for: schedule.period(containing: schedule.dayOne, calendar: calendar))
        }
        return WeeklyReviewModel(store: store, center: FixtureReviewNotificationCenter(status: explains ? .notDetermined : .authorized))
    }
    /// `--ui-testing review`: completed sessions whose first starts give a repetition within 60 minutes, a day without a record, a session ended early, and one in the previous period.
    /// Today's sessions start no later than one hour before launch, so they stay on today.
    static func seed(_ history: SessionHistory) throws {
        let calendar = Calendar.current, now = Date(), today = calendar.startOfDay(for: now)
        let samples: [(day: Int, hour: Int, minute: Int, length: TimeInterval, reason: EndReason)] = [
            (-6, 9, 0, 1500, .expired), (-4, 19, 10, 1500, .expired), (-4, 21, 0, 1500, .expired), (-2, 19, 40, 3000, .expired),
            (-1, 8, 0, 1500, .expired), (0, 9, 0, 1500, .expired), (0, 10, 0, 1500, .earlyExit),
        ]
        for sample in samples {
            let day = calendar.date(byAdding: .day, value: sample.day, to: today) ?? today
            var start = calendar.startOfDay(for: day).addingTimeInterval(TimeInterval(sample.hour * 3600 + sample.minute * 60))
            if sample.day == 0 { start = max(today, min(start, now.addingTimeInterval(-3600 - TimeInterval(sample.hour - 9) * 600))) }
            var session = ControlSession(startedAt: start, length: sample.length)
            session.phase = .terminal; session.reason = sample.reason; session.observedAt = session.expiresAt
            try history.importTerminal(session)
        }
    }
}
#endif

#if DEBUG
struct FixtureUsageReportHost: View {
    var body: some View {
        UsageReportContainer { _ in
            if ProcessInfo.processInfo.arguments.contains("report-waiting") { Color.clear }
            else if ProcessInfo.processInfo.arguments.contains("report-empty") { List { UsageSummarySection(total: nil) } }
            else if ProcessInfo.processInfo.arguments.contains("report-zero") { List { UsageSummarySection(total: 0) } }
            else { FixtureReportProbe() }
        }
    }
}
private struct FixtureReportProbe: View {
    @State private var instanceID = UUID()
    var body: some View { Text(instanceID.uuidString).accessibilityIdentifier("reportGeneration") }
}
#endif
