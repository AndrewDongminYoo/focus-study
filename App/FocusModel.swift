import Foundation
import SwiftData
import FamilyControls
import Observation

@MainActor struct FocusServices {
    let authorization: any AuthorizationProviding
    let selection: any SelectionStoring
    let engine: SessionControl
    let applySelection: (FamilyActivitySelection) -> Void
    let matchesSelection: (FamilyActivitySelection) -> Bool
    var isFixture = false
    static func real() throws -> FocusServices {
        let shield = ScreenTimeShield()
        let engine = SessionControl(store: SharedControlStore(directory: try GroupConfiguration.directory()), monitoring: ScreenTimeMonitoring(), shield: shield)
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("PrivateSelection")
        return FocusServices(authorization: AuthorizationService(), selection: try SelectionRepository(directory: directory), engine: engine, applySelection: shield.apply, matchesSelection: shield.matches)
    }
}
@MainActor @Observable final class FocusModel {
    let services: FocusServices
    private let history: SessionHistory
    private(set) var current: ControlSession?
    private(set) var records: [SessionRecord] = []
    private(set) var errorMessage: String?
    private(set) var isStarting = false
    private(set) var now = Date()
    var access: AccessStatus { services.authorization.status }
    var isActive: Bool { current?.phase == .active }
    var counts: (apps: Int, websites: Int, categories: Int) { services.selection.counts }
    var canStart: Bool { access == .approved && current == nil && !isStarting && errorMessage == nil && counts.apps + counts.websites > 0 }
    var remaining: Int { current.map { TimeRules.remaining(expiresAt: $0.expiresAt, now: now) } ?? 1500 }
    init(services: FocusServices, context: ModelContext) {
        self.services = services
        history = SessionHistory(context: context, acknowledge: services.engine.acknowledgeTerminal)
    }
    func refresh(clockChanged: Bool = false) {
        services.authorization.refresh(); now = Date()
        do {
            let envelope = try services.engine.reconcile(now: now, authorized: access == .approved, clockChanged: clockChanged)
            if let terminal = envelope.session, terminal.phase == .terminal { try history.importTerminal(terminal) }
            current = try services.engine.snapshot().session
            records = try history.records(on: now)
            errorMessage = nil
        } catch { current = nil; errorMessage = "상태를 확인하지 못했습니다. 다시 확인한 후 시작해 주세요." }
    }
    func start() {
        guard canStart else { return }
        isStarting = true; defer { isStarting = false }
        refresh()
        guard errorMessage == nil, access == .approved, current == nil else { return }
        do {
            let counts = services.selection.counts
            try SelectionValidator.validate(appCount: counts.apps, webCount: counts.websites, categoryCount: counts.categories)
            let frozen = services.selection.selection
            _ = try services.engine.start(now: Date(), authorized: { self.services.authorization.hasAccessNow() }, apply: { self.services.applySelection(frozen) }, matches: { self.services.matchesSelection(frozen) })
            refresh()
        } catch {
            refresh()
            errorMessage = "세션을 시작하지 못했습니다. 상태를 다시 확인해 주세요."
        }
    }
    func end() {
        guard let id = current?.id else { return }
        do { try services.engine.finish(id: id, reason: .earlyExit, now: Date()); refresh() }
        catch { current = nil; errorMessage = "종료 상태를 저장하지 못했습니다. 다시 확인해 주세요." }
    }
    func tick() {
        now = Date()
        if let current, now >= current.expiresAt { refresh() }
    }
    func saveSelection(_ selection: FamilyActivitySelection) throws {
        guard !isActive, !isStarting else { throw ControlIssue.busy }
        try services.selection.save(selection)
    }
}
