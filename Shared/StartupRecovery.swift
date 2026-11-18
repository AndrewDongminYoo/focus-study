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
        let envelope = try engine.snapshot()
        guard let current = envelope.session, current.phase != .terminal else { return }
        // An open session takes `finish`'s open rule, which checks the registration, the deadline and the base length; a stale chunk end or a lost
        // bound end is never a timed `.expired` here (2026-11-18 single-interval amendment, decisions 9 and 17).
        let timed = envelope.sessionIsOpen ? nil : current.timedEnd(at: now, timing: engine.timing)
        try engine.finish(id: current.id, reason: current.reason ?? timed ?? .earlyExit, now: now, endedAt: current.observedAt)
    }
}
