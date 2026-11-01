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
    init(fail: Bool) { self.fail = fail }
    func register(id: UUID, start: Date, end: Date) throws { if fail { throw ControlIssue.io }; registered.insert(id) }
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
    /// A fixed-offset calendar in which launch falls between 12:00 and 13:00, so that a fixture range never reaches 23:55 or midnight, whatever the wall clock.
    static func noonCalendar(now: Date) -> Calendar {
        let utcHour = Int(now.timeIntervalSince1970) % 86_400 / 3600
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: (12 - utcHour) * 3600) ?? .gmt
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FocusFixture-\(UUID().uuidString)")
        // `--break-timing short` shortens waits, the break, the slack and the grace, but not the focus length.
        var timing = BreakTiming.standard
        if let index = arguments.firstIndex(of: "--break-timing"), index + 1 < arguments.count, arguments[index + 1] == "short" {
            timing = BreakTiming(waits: [1, 2, 4], breakLength: 3, slack: 5, staleWaitGrace: 2)
        }
        let breakSelection = FixtureBreakSelection()
        var everyday = FixtureEverydayLayer()
        // The engine and the status line read the layer in this calendar, not the device time zone.
        let now = Date(), calendar = FixtureEverydayLayer.noonCalendar(now: now)
        if let index = arguments.firstIndex(of: "--everyday-fixture"), index + 1 < arguments.count, arguments[index + 1] == "blocking" {
            everyday = .blocking(now: now, calendar: calendar)
        }
        let engine = SessionControl(store: SharedControlStore(directory: directory), monitoring: FixtureMonitoring(fail: arguments.contains("registration-failure")), shield: FixtureShield(), breakSelection: breakSelection, everyday: everyday, timing: timing, calendar: calendar)
        let onboarding = arguments.contains("onboarding")
        var services = FocusServices(authorization: FixtureAuthorization(denied: arguments.contains("denied"), notRequested: arguments.contains("not-requested") || onboarding), selection: FixtureSelection(selected: arguments.contains("--selected") && !onboarding), engine: engine, applySelection: { _ in }, matchesSelection: { _ in true }, isFixture: true)
        services.saveBreakSelection = { _, id in breakSelection.copies.insert(id) }
        services.everydaySelection = { everyday.schedule == nil ? nil : everyday.selection }
        services.everydayContains = { everyday.contains($0) }
        services.writeEveryday = { everyday.write($0, selection: $1) }
        // In-memory settings: `onboarding` starts a new person; every other mode is a person who finished onboarding.
        let settings = FocusSettings(defaults: UserDefaults(suiteName: "FocusFixture-\(UUID().uuidString)")!)
        if let index = arguments.firstIndex(of: "--length"), index + 1 < arguments.count, let minutes = Int(arguments[index + 1]) { settings.lengthMinutes = minutes }
        settings.hasCompletedOnboarding = !onboarding
        services.settings = settings
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
        if arguments.contains("ending-soon") {
            // 10 seconds of focus left, so that a break taken at once reaches the short-timing deadline in about 19 seconds.
            let length = services.settings.lengthSeconds
            _ = try services.engine.start(now: Date().addingTimeInterval(-(length - 10)), length: length, authorized: { true }, apply: {}, matches: { true })
        }
        var attempts = 0
        return FocusRuntime(recovery: StartupRecovery(engine: services.engine), hasAccess: services.authorization.hasAccessNow, loadStorage: {
            attempts += 1
            if arguments.contains("startup-failure"), attempts == 1 { throw ControlIssue.io }
            let container = try ModelContainer(for: SessionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
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
