import Foundation
/// Session safety does not depend on selection or history storage being available.
final class StartupRecovery {
    let engine: SessionControl
    init(engine: SessionControl) { self.engine = engine }
    func prepare(now: Date, authorized: AccessState, loadStorage: () throws -> Void) throws {
        try engine.reconcile(now: now, authorized: authorized)
        try loadStorage()
    }
    func endCurrent(now: Date) throws {
        // The pure catch-up first, so that an open session past a chunk end has no stale timed end (2026-11-18 single-interval amendment, decision 9).
        guard let current = try engine.snapshot().caughtUp(at: now, timing: engine.timing).session, current.phase != .terminal else { return }
        try engine.finish(id: current.id, reason: current.reason ?? current.timedEnd(at: now, timing: engine.timing) ?? .earlyExit, now: now, endedAt: current.observedAt)
    }
}
