#if DEBUG
import Foundation
import FamilyControls
import ManagedSettings
import Observation
import SwiftData
import SwiftUI

@MainActor @Observable final class FixtureAuthorization: AuthorizationProviding {
    var status: AccessStatus
    init(denied: Bool, notRequested: Bool = false) { status = notRequested ? .notRequested : denied ? .denied : .approved }
    func requestIndividual() async { status = .approved }
    func refresh() {}
    func hasAccessNow() -> Bool { status == .approved }
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
        // the standard grace still admits a late automatic break start, and the 15-second slack keeps the deadline notice counting.
        var timing = BreakTiming.standard
        if let index = arguments.firstIndex(of: "--break-timing"), index + 1 < arguments.count, arguments[index + 1] == "short" {
            timing = BreakTiming(waits: [1, 2, 4], breakLength: 3, slack: 15, staleWaitGrace: BreakTiming.standard.staleWaitGrace)
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
        if let index = arguments.firstIndex(of: "--everyday-fixture"), index + 1 < arguments.count, ["preview", "off"].contains(arguments[index + 1]) {
            everyday.schedule = EverydaySchedule(revision: UUID(), enabled: arguments[index + 1] == "preview", rangeStart: 480, rangeEnd: 1080, windows: [EverydaySchedule.template(.lunch)!])
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
        let engine = SessionControl(store: store, monitoring: monitoring, shield: FixtureShield(), breakSelection: breakSelection, everyday: everyday, timing: timing, calendar: calendar)
        let onboarding = arguments.contains("onboarding")
        var services = FocusServices(authorization: FixtureAuthorization(denied: arguments.contains("denied"), notRequested: arguments.contains("not-requested") || onboarding), selection: FixtureSelection(selected: arguments.contains("--selected") && !onboarding), engine: engine, applySelection: { _ in }, matchesSelection: { _ in true }, isFixture: true)
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
extension FocusRuntime {
    static func fixture(arguments: [String]) throws -> FocusRuntime {
        let services = FocusServices.fixture(arguments: arguments)
        if arguments.contains("startup-failure") {
            _ = try services.engine.start(now: Date(), authorized: { true }, apply: {}, matches: { true })
        }
        if arguments.contains("expiring") {
            // A session with the configured length that started 3 seconds before its end, so the UI test sees the real expiry path.
            let length = services.settings.lengthSeconds
            _ = try services.engine.start(now: Date().addingTimeInterval(-(length - 3)), length: length, authorized: { true }, apply: {}, matches: { true })
        }
        var attempts = 0
        return FocusRuntime(recovery: StartupRecovery(engine: services.engine), hasAccess: services.authorization.hasAccessNow, holder: FocusRuntimeHolder(engine: services.engine, authorization: services.authorization, settings: services.settings, activityDidChange: services.activityDidChange) {
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
            return (services, container)
        })
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
