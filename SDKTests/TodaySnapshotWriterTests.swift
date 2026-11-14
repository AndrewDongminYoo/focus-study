import XCTest
import FamilyControls

/// A history that keeps imported terminal sessions as records, so that `refresh()` and the Focus on call read real numbers.
@MainActor final class SnapshotTestHistory: SessionHistoryProviding {
    var failFetch = false
    private(set) var stored: [SessionRecord] = []
    let acknowledge: (UUID) throws -> Void
    init(acknowledge: @escaping (UUID) throws -> Void) { self.acknowledge = acknowledge }
    func importTerminal(_ session: ControlSession) throws {
        if !stored.contains(where: { $0.id == session.id }) { stored.append(SessionRecord(session: session)) }
        try acknowledge(session.id)
    }
    func records(on date: Date, calendar: Calendar) throws -> [SessionRecord] {
        if failFetch { throw ModelTestError.storage }
        let day = TimeRules.today(now: date, calendar: calendar)
        return stored.filter { day.contains($0.startedAt) && $0.startedAt < day.end }
    }
    func streak(at date: Date, calendar: Calendar) throws -> Int { 0 }
}

@MainActor final class TodaySnapshotWriterTests: XCTestCase {
    final class Box<T> { var value: T; init(_ value: T) { self.value = value } }
    private var directories: [URL] = []
    override func tearDown() async throws {
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        directories = []
    }
    private func container() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TodaySnapshotWriterTests-\(UUID().uuidString)")
        directories.append(url)
        return url
    }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    // MARK: The write check and the reload requests

    func testWritesTheFileOfTheContainerWithTheControlFileOptions() throws {
        let root = container(), options = Box<[Data.WritingOptions]>([]), reloads = Box(0)
        let writer = TodaySnapshotWriter(container: root, store: { data, url, option in options.value.append(option); try TodaySnapshotWriter.replace(data, at: url, options: []) },
                                         reload: { reloads.value += 1 })
        XCTAssertEqual(writer.url, root.appendingPathComponent("TodaySnapshot/today.json"))
        let snapshot = TodaySnapshot(dayStart: today, completedCount: 1, focusSeconds: 1500)
        try writer.write(snapshot)
        XCTAssertEqual(options.value, [SharedControlStore.fileWritingOptions])
        XCTAssertEqual(TodaySnapshot.decode(try Data(contentsOf: writer.url)), snapshot)
        XCTAssertEqual(reloads.value, 1)
    }
    func testUnchangedContentWritesNothingAndAsksForNoReload() throws {
        let root = container(), writes = Box(0), reloads = Box(0)
        let writer = TodaySnapshotWriter(container: root, store: { writes.value += 1; try TodaySnapshotWriter.replace($0, at: $1, options: $2) }, reload: { reloads.value += 1 })
        let snapshot = TodaySnapshot(dayStart: today, completedCount: 1, focusSeconds: 1500)
        try writer.write(snapshot); try writer.write(snapshot)
        XCTAssertEqual(writes.value, 1); XCTAssertEqual(reloads.value, 1)
        try writer.write(TodaySnapshot(dayStart: today, completedCount: 2, focusSeconds: 3000))
        XCTAssertEqual(writes.value, 2); XCTAssertEqual(reloads.value, 2, "a changed write asks again")
    }
    func testTheFirstCheckOfAProcessAsksOnceWhenTheFileIsAlreadyCorrect() throws {
        let root = container(), snapshot = TodaySnapshot(dayStart: today, completedCount: 1, focusSeconds: 1500)
        try TodaySnapshotWriter(container: root, reload: {}).write(snapshot)
        // A new process: the file is already correct, so nothing is written, and the first check still asks once.
        let writes = Box(0), reloads = Box(0)
        let writer = TodaySnapshotWriter(container: root, store: { _, _, _ in writes.value += 1 }, reload: { reloads.value += 1 })
        try writer.write(snapshot)
        XCTAssertEqual(writes.value, 0); XCTAssertEqual(reloads.value, 1)
        try writer.write(snapshot)
        XCTAssertEqual(writes.value, 0); XCTAssertEqual(reloads.value, 1, "every later check that writes nothing asks for nothing")
    }
    func testAnUnreadableOrInvalidFileIsWrittenAgain() throws {
        let root = container(), snapshot = TodaySnapshot(dayStart: today, completedCount: 1, focusSeconds: 1500)
        let writer = TodaySnapshotWriter(container: root, reload: {})
        try FileManager.default.createDirectory(at: writer.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("damaged".utf8).write(to: writer.url)
        try writer.write(snapshot)
        XCTAssertEqual(TodaySnapshot.decode(try Data(contentsOf: writer.url)), snapshot)
        // The file now holds the same content, but a read that fails writes again.
        let writes = Box(0)
        let unreadable = TodaySnapshotWriter(container: root, read: { _ in throw CocoaError(.fileReadNoPermission) }, store: { _, _, _ in writes.value += 1 }, reload: {})
        try unreadable.write(snapshot)
        XCTAssertEqual(writes.value, 1)
    }
    func testAThrownWriteAsksForNoReloadAndTheNextCheckWritesAndAsks() throws {
        let root = container(), fail = Box(true), reloads = Box(0)
        let writer = TodaySnapshotWriter(container: root, store: { data, url, options in
            if fail.value { throw CocoaError(.fileWriteOutOfSpace) }
            try TodaySnapshotWriter.replace(data, at: url, options: options)
        }, reload: { reloads.value += 1 })
        let snapshot = TodaySnapshot(dayStart: today, completedCount: 1, focusSeconds: 1500)
        XCTAssertThrowsError(try writer.write(snapshot))
        XCTAssertEqual(reloads.value, 0)
        fail.value = false
        try writer.write(snapshot)
        XCTAssertEqual(reloads.value, 1)
        XCTAssertEqual(TodaySnapshot.decode(try Data(contentsOf: writer.url)), snapshot)
    }

    // MARK: The model's write point

    private func model(writes: Box<[TodaySnapshot]>, fail: Box<Bool> = Box(false)) -> (FocusModel, SnapshotTestHistory, SessionControl) {
        let shield = ModelTestShield()
        let engine = SessionControl(store: ModelTestStore(), monitoring: ModelTestMonitoring(), shield: shield, breakSelection: ModelTestBreakSelection(), everyday: ModelTestEverydayLayer())
        var services = FocusServices(authorization: ModelTestAuthorization(), selection: ModelTestSelection(), engine: engine,
                                     applySelection: { _ in shield.applied = true }, matchesSelection: { _ in shield.applied }, isFixture: true)
        services.settings = FocusSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        services.writeTodaySnapshot = { snapshot in
            if fail.value { throw ModelTestError.storage }
            writes.value.append(snapshot)
        }
        let history = SnapshotTestHistory(acknowledge: engine.acknowledgeTerminal)
        return (FocusModel(services: services, history: history), history, engine)
    }
    func testRefreshWritesAfterAnImportWithTheNumbersOfTheSummary() throws {
        let writes = Box<[TodaySnapshot]>([])
        let (model, history, engine) = model(writes: writes)
        // A session that started 1500 seconds ago reached its end; the refresh imports it as completed.
        let started = Date().addingTimeInterval(-1501)
        try XCTSkipIf(Calendar.current.startOfDay(for: started) != today, "the session would start yesterday")
        _ = try engine.start(now: started, authorized: { .approved }, apply: {}, matches: { true })
        model.refresh()
        XCTAssertEqual(history.stored.count, 1)
        let summary = SessionSummary(records: model.records)
        XCTAssertEqual(summary.completedCount, 1)
        XCTAssertEqual(writes.value.last, TodaySnapshot(dayStart: today, completedCount: summary.completedCount, focusSeconds: summary.focusDuration))
        XCTAssertEqual(writes.value.last?.focusSeconds, 1500)
    }
    func testRefreshAfterADayChangeReplacesTheFileOfAnEarlierDay() throws {
        let root = container(), reloads = Box(0)
        let writer = TodaySnapshotWriter(container: root, reload: { reloads.value += 1 })
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        try TodaySnapshotWriter(container: root, reload: {}).write(TodaySnapshot(dayStart: yesterday, completedCount: 2, focusSeconds: 3000))
        let writes = Box<[TodaySnapshot]>([])
        let (model, _, _) = model(writes: writes)
        var services = model.services
        services.writeTodaySnapshot = { try writer.write($0) }
        let relaunched = FocusModel(services: services, history: SnapshotTestHistory(acknowledge: services.engine.acknowledgeTerminal))
        relaunched.refresh()
        XCTAssertEqual(TodaySnapshot.decode(try Data(contentsOf: writer.url)), TodaySnapshot(dayStart: today, completedCount: 0, focusSeconds: 0))
        XCTAssertEqual(reloads.value, 1)
    }
    func testAFailedHistoryReadWritesNothing() {
        let writes = Box<[TodaySnapshot]>([])
        let (model, history, _) = model(writes: writes)
        history.failFetch = true
        model.refresh()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(writes.value.isEmpty)
    }
    func testAThrownWriteChangesNeitherTheErrorNorTheRecordsAndTheNextRefreshWritesAgain() throws {
        let writes = Box<[TodaySnapshot]>([]), fail = Box(true)
        let (model, history, engine) = model(writes: writes, fail: fail)
        let started = Date().addingTimeInterval(-1501)
        try XCTSkipIf(Calendar.current.startOfDay(for: started) != today, "the session would start yesterday")
        _ = try engine.start(now: started, authorized: { .approved }, apply: {}, matches: { true })
        model.refresh()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.records.map(\.id), history.stored.map(\.id))
        XCTAssertEqual(model.records.count, 1)
        XCTAssertTrue(writes.value.isEmpty)
        fail.value = false
        model.refresh()
        XCTAssertEqual(writes.value, [TodaySnapshot(dayStart: today, completedCount: 1, focusSeconds: 1500)])
    }
    /// What this establishes: the default closure of `FocusServices` writes nothing and does not throw. `FocusServices.fixture` never sets it, which a reading of `UITestFixtures.swift` shows; that file is not compiled here.
    func testTheDefaultWriterDoesNothing() throws {
        let engine = SessionControl(store: ModelTestStore(), monitoring: ModelTestMonitoring(), shield: ModelTestShield(), breakSelection: ModelTestBreakSelection(), everyday: ModelTestEverydayLayer())
        let services = FocusServices(authorization: ModelTestAuthorization(), selection: ModelTestSelection(), engine: engine, applySelection: { _ in }, matchesSelection: { _ in true }, isFixture: true)
        XCTAssertNoThrow(try services.writeTodaySnapshot(TodaySnapshot(dayStart: today, completedCount: 1, focusSeconds: 1500)))
    }

    // MARK: The Focus on call's write point

    private func handler(writes: Box<[String]>, fail: Box<Bool> = Box(false), denied: Bool = false) -> (FocusFilterHandler, FocusServices, SnapshotTestHistory) {
        let shield = ModelTestShield(), authorization = RecordingAuthorization()
        if denied { authorization.status = .denied }
        let engine = SessionControl(store: ModelTestStore(), monitoring: ModelTestMonitoring(), shield: shield, breakSelection: ModelTestBreakSelection(), everyday: ModelTestEverydayLayer())
        var services = FocusServices(authorization: authorization, selection: ModelTestSelection(), engine: engine,
                                     applySelection: { _ in shield.applied = true }, matchesSelection: { _ in shield.applied }, isFixture: true)
        services.settings = FocusSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        services.writeTodaySnapshot = { snapshot in
            if fail.value { throw ModelTestError.storage }
            writes.value.append("write \(snapshot.completedCount)")
        }
        let history = SnapshotTestHistory(acknowledge: engine.acknowledgeTerminal)
        // No `FocusModel`: the refresh closure is what a background launch has, which refreshes no screen.
        let handler = FocusFilterHandler(services: services, history: history, refresh: { writes.value.append("refresh") }, pause: { _ in })
        return (handler, services, history)
    }
    func testOnCallWritesInItsLastStepAfterAStart() async throws {
        let log = Box<[String]>([])
        let (handler, services, history) = handler(writes: log)
        let earlier = Date().addingTimeInterval(-1501)
        try XCTSkipIf(Calendar.current.startOfDay(for: earlier) != today, "the session would start yesterday")
        _ = try services.engine.start(now: earlier, authorized: { .approved }, apply: {}, matches: { true })
        await handler.focusDidChange(startsSession: true)
        XCTAssertEqual(history.stored.count, 1, "the waiting terminal session was imported")
        XCTAssertEqual(try services.engine.snapshot().session?.origin, .focusFilter)
        XCTAssertEqual(log.value, ["refresh", "write 1"])
    }
    func testOnCallWritesAfterARefusal() async throws {
        let log = Box<[String]>([])
        let (handler, services, _) = handler(writes: log, denied: true)
        await handler.focusDidChange(startsSession: true)
        XCTAssertNil(try services.engine.snapshot().session)
        XCTAssertEqual(services.settings.lastFilterRefusal?.reason, .access)
        XCTAssertEqual(log.value, ["refresh", "write 0"])
    }
    func testAThrownWriteChangesNeitherTheResultNorTheStoredRefusal() async throws {
        for denied in [false, true] {
            let log = Box<[String]>([]), fail = Box(true)
            let (handler, services, _) = handler(writes: log, fail: fail, denied: denied)
            await handler.focusDidChange(startsSession: true)
            let session = try services.engine.snapshot().session
            if denied {
                XCTAssertNil(session); XCTAssertEqual(services.settings.lastFilterRefusal?.reason, .access)
            } else {
                XCTAssertEqual(session?.phase, .active); XCTAssertNil(services.settings.lastFilterRefusal)
            }
            XCTAssertEqual(log.value, ["refresh"], "\(denied)")
        }
    }
    func testOffCallWritesNothing() async {
        let log = Box<[String]>([])
        let (handler, _, _) = handler(writes: log)
        await handler.focusDidChange(startsSession: false)
        XCTAssertEqual(log.value, ["refresh"])
    }
}
