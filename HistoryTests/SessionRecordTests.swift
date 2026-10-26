import XCTest
import SwiftData
import FocusCore
@testable import FocusHistory
@MainActor final class SessionRecordTests: XCTestCase {
    func fixture(ack: @escaping (UUID) throws -> Void = { _ in }) throws -> (ModelContext, SessionHistory) {
        let container = try ModelContainer(for: SessionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        return (context, SessionHistory(context: context, acknowledge: ack))
    }
    func terminal() -> ControlSession {
        var s = ControlSession(startedAt: Date(timeIntervalSince1970: 1000)); s.phase = .terminal; s.reason = .expired; s.observedAt = Date(timeIntervalSince1970: 2510); return s
    }
    func testRepeatedImportIsOneRecordAndKeepsScheduledEndSeparateFromObservation() throws {
        let (context, history) = try fixture(); let s = terminal()
        try history.importTerminal(s); try history.importTerminal(s)
        let rows = try context.fetch(FetchDescriptor<SessionRecord>())
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.first?.endedAt, Date(timeIntervalSince1970: 2500)); XCTAssertEqual(rows.first?.observedAt, Date(timeIntervalSince1970: 2510))
    }
    func testSaveFailureDoesNotAcknowledgeOrLeaveUnsavedRow() throws {
        var acknowledged = false
        let (context, _) = try fixture()
        let history = SessionHistory(context: context, acknowledge: { _ in acknowledged = true }, save: { throw HistoryTestError.injected })
        XCTAssertThrowsError(try history.importTerminal(terminal()))
        XCTAssertFalse(acknowledged); XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionRecord>()), 0)
    }
    func testAcknowledgementFailureCanRetryWithoutDuplicate() throws {
        let (context, history) = try fixture(ack: { _ in throw HistoryTestError.injected })
        let s = terminal()
        XCTAssertThrowsError(try history.importTerminal(s)); XCTAssertThrowsError(try history.importTerminal(s))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionRecord>()), 1)
    }
    func testActiveSessionCannotBeRecorded() throws {
        let (context, history) = try fixture()
        XCTAssertThrowsError(try history.importTerminal(ControlSession(startedAt: Date())))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionRecord>()), 0)
    }
    func testTodayUsesStartDateAcrossMidnight() throws {
        let (_, history) = try fixture(); var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var s = ControlSession(startedAt: ISO8601DateFormatter().date(from: "2026-10-25T23:50:00Z")!); s.phase = .terminal; s.reason = .expired; s.observedAt = s.expiresAt
        try history.importTerminal(s)
        XCTAssertEqual(try history.records(on: s.startedAt, calendar: calendar).count, 1)
        XCTAssertEqual(try history.records(on: s.expiresAt, calendar: calendar).count, 0)
    }
}
enum HistoryTestError: Error { case injected }
