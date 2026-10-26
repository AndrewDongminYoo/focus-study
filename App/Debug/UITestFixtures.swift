#if DEBUG
import Foundation
import FamilyControls
import Observation

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
