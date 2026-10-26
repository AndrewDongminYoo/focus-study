import Foundation
/// Session safety does not depend on selection or history storage being available.
final class StartupRecovery {
    let engine: SessionControl
    init(engine: SessionControl) { self.engine = engine }
    func prepare(now: Date, authorized: Bool, loadStorage: () throws -> Void) throws {
        try engine.reconcile(now: now, authorized: authorized)
        try loadStorage()
    }
    func endCurrent(now: Date) throws {
        guard let current = try engine.snapshot().session, current.phase != .terminal else { return }
        try engine.finish(id: current.id, reason: current.reason ?? (now >= current.expiresAt ? .expired : .earlyExit), now: current.observedAt ?? now)
    }
}
