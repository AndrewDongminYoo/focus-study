import Foundation
import SwiftData
#if SWIFT_PACKAGE
import FocusCore
#endif

@Model final class SessionRecord {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var expiresAt: Date
    var endedAt: Date
    var observedAt: Date
    var reasonRaw: String
    var reason: EndReason { EndReason(rawValue: reasonRaw) ?? .recoveryInterrupted }
    var duration: TimeInterval { max(0, min(1500, endedAt.timeIntervalSince(startedAt))) }
    init(session: ControlSession) {
        id = session.id; startedAt = session.startedAt; expiresAt = session.expiresAt
        endedAt = session.recordedEnd ?? session.startedAt
        observedAt = session.observedAt ?? session.startedAt
        reasonRaw = (session.reason ?? .recoveryInterrupted).rawValue
    }
}
@MainActor protocol SessionHistoryProviding {
    func importTerminal(_ session: ControlSession) throws
    func records(on date: Date, calendar: Calendar) throws -> [SessionRecord]
}
@MainActor final class SessionHistory: SessionHistoryProviding {
    private let context: ModelContext
    private let acknowledge: (UUID) throws -> Void
    private let save: () throws -> Void
    init(context: ModelContext, acknowledge: @escaping (UUID) throws -> Void, save: (() throws -> Void)? = nil) {
        self.context = context; self.acknowledge = acknowledge; self.save = save ?? { try context.save() }
        context.autosaveEnabled = false
    }
    func importTerminal(_ session: ControlSession) throws {
        guard session.phase == .terminal, session.reason != nil, session.observedAt != nil else { throw HistoryIssue.invalidTerminal }
        let id = session.id
        let query = FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.id == id })
        if try context.fetch(query).isEmpty {
            context.insert(SessionRecord(session: session))
            do { try save() } catch { context.rollback(); throw error }
        }
        try acknowledge(id)
    }
    func records(on date: Date, calendar: Calendar = .current) throws -> [SessionRecord] {
        let interval = TimeRules.today(now: date, calendar: calendar), start = interval.start, end = interval.end
        return try context.fetch(FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.startedAt >= start && $0.startedAt < end }, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
    }
}
enum HistoryIssue: Error { case invalidTerminal }
