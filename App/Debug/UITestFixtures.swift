#if DEBUG
import Foundation
import FamilyControls
import Observation
import SwiftData
import SwiftUI

@MainActor @Observable final class FixtureAuthorization: AuthorizationProviding {
    var status: AccessStatus
    init(denied: Bool) { status = denied ? .denied : .approved }
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
    func stop(id: UUID) { registered.remove(id) }
}
private final class FixtureShield: ShieldClient { func clear() {} }
extension FocusServices {
    static func fixture(arguments: [String]) -> FocusServices {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FocusFixture-\(UUID().uuidString)")
        let engine = SessionControl(store: SharedControlStore(directory: directory), monitoring: FixtureMonitoring(fail: arguments.contains("registration-failure")), shield: FixtureShield())
        return FocusServices(authorization: FixtureAuthorization(denied: arguments.contains("denied")), selection: FixtureSelection(selected: arguments.contains("--selected")), engine: engine, applySelection: { _ in }, matchesSelection: { _ in true }, isFixture: true)
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
