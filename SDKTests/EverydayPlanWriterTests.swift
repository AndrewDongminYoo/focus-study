import XCTest

@MainActor final class EverydayPlanWriterTests: XCTestCase {
    final class Box<T> { var value: T; init(_ value: T) { self.value = value } }
    private var directories: [URL] = []
    override func tearDown() async throws {
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        directories = []
    }
    private func container() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EverydayPlanWriterTests-\(UUID().uuidString)")
        directories.append(url)
        return url
    }
    /// An off schedule: its status has no registration or shield issue, so the write does not depend on the wall clock.
    private let schedule = EverydaySchedule(revision: UUID(), enabled: false, rangeStart: 480, rangeEnd: 1080, windows: [EverydaySchedule.template(.lunch)!])
    private var file: EverydayPlanFile { EverydayPlanFile(plan: EverydayPlan(schedule), needsCheck: false) }

    // MARK: The write check and the reload requests

    func testWritesTheFileOfTheContainerWithTheControlFileOptions() throws {
        let root = container(), options = Box<[Data.WritingOptions]>([]), reloads = Box(0)
        let writer = EverydayPlanWriter(container: root, store: { data, url, option in options.value.append(option); try TodaySnapshotWriter.replace(data, at: url, options: []) },
                                        reload: { reloads.value += 1 })
        XCTAssertEqual(writer.url, root.appendingPathComponent("TodaySnapshot/everyday-plan.json"))
        try writer.write(file)
        XCTAssertEqual(options.value, [SharedControlStore.fileWritingOptions])
        XCTAssertEqual(EverydayPlanFile.decode(try Data(contentsOf: writer.url)), file)
        XCTAssertEqual(reloads.value, 1)
    }
    func testUnchangedContentWritesNothingAndAsksForNoReload() throws {
        let root = container(), writes = Box(0), reloads = Box(0)
        let writer = EverydayPlanWriter(container: root, store: { writes.value += 1; try TodaySnapshotWriter.replace($0, at: $1, options: $2) }, reload: { reloads.value += 1 })
        try writer.write(file); try writer.write(file)
        XCTAssertEqual(writes.value, 1); XCTAssertEqual(reloads.value, 1)
        try writer.write(EverydayPlanFile(plan: EverydayPlan(schedule), needsCheck: true))
        XCTAssertEqual(writes.value, 2); XCTAssertEqual(reloads.value, 2, "a changed write asks again")
    }
    func testTheFirstCheckOfAProcessAsksOnceWhenTheFileIsAlreadyCorrect() throws {
        let root = container()
        try EverydayPlanWriter(container: root, reload: {}).write(file)
        // A new process: the file is already correct, so nothing is written, and the first check still asks once.
        let writes = Box(0), reloads = Box(0)
        let writer = EverydayPlanWriter(container: root, store: { _, _, _ in writes.value += 1 }, reload: { reloads.value += 1 })
        try writer.write(file)
        XCTAssertEqual(writes.value, 0); XCTAssertEqual(reloads.value, 1)
        try writer.write(file)
        XCTAssertEqual(writes.value, 0); XCTAssertEqual(reloads.value, 1, "every later check that writes nothing asks for nothing")
    }
    func testAnUnreadableOrInvalidFileIsWrittenAgain() throws {
        let root = container()
        let writer = EverydayPlanWriter(container: root, reload: {})
        try FileManager.default.createDirectory(at: writer.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("damaged".utf8).write(to: writer.url)
        try writer.write(file)
        XCTAssertEqual(EverydayPlanFile.decode(try Data(contentsOf: writer.url)), file)
        let writes = Box(0)
        let unreadable = EverydayPlanWriter(container: root, read: { _ in throw CocoaError(.fileReadNoPermission) }, store: { _, _, _ in writes.value += 1 }, reload: {})
        try unreadable.write(file)
        XCTAssertEqual(writes.value, 1)
    }
    func testAThrownWriteAsksForNoReloadAndTheNextCheckWritesAndAsks() throws {
        let root = container(), fail = Box(true), reloads = Box(0)
        let writer = EverydayPlanWriter(container: root, store: { data, url, options in
            if fail.value { throw CocoaError(.fileWriteOutOfSpace) }
            try TodaySnapshotWriter.replace(data, at: url, options: options)
        }, reload: { reloads.value += 1 })
        XCTAssertThrowsError(try writer.write(file))
        XCTAssertEqual(reloads.value, 0)
        fail.value = false
        try writer.write(file)
        XCTAssertEqual(reloads.value, 1)
        XCTAssertEqual(EverydayPlanFile.decode(try Data(contentsOf: writer.url)), file)
    }

    // MARK: The write points of the screen models

    private func model(writes: Box<[EverydayPlanFile]>, fail: Box<Bool> = Box(false)) -> (FocusModel, ModelTestEverydayLayer, ModelTestAuthorization) {
        let shield = ModelTestShield(), layer = ModelTestEverydayLayer(), authorization = ModelTestAuthorization()
        let engine = SessionControl(store: ModelTestStore(), monitoring: ModelTestMonitoring(), shield: shield, breakSelection: ModelTestBreakSelection(), everyday: layer)
        var services = FocusServices(authorization: authorization, selection: ModelTestSelection(), engine: engine,
                                     applySelection: { _ in shield.applied = true }, matchesSelection: { _ in shield.applied }, isFixture: true)
        services.settings = FocusSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        services.writeEverydayPlan = { file in
            if fail.value { throw ModelTestError.storage }
            writes.value.append(file)
        }
        return (FocusModel(services: services, history: ModelTestHistory(acknowledge: engine.acknowledgeTerminal)), layer, authorization)
    }
    func testRefreshEverydayWritesThePlanOfASuccessfulRead() {
        let writes = Box<[EverydayPlanFile]>([])
        let (model, layer, _) = model(writes: writes)
        model.refreshEveryday()
        XCTAssertEqual(writes.value, [EverydayPlanFile(plan: nil, needsCheck: false)], "a missing everyday file writes no schedule")
        layer.schedule = schedule
        model.refreshEveryday()
        XCTAssertEqual(writes.value.last, file)
    }
    func testRefreshEverydayWritesNeedsCheckAfterADeniedRead() {
        let writes = Box<[EverydayPlanFile]>([])
        let (model, layer, authorization) = model(writes: writes)
        layer.schedule = schedule; authorization.status = .denied
        model.refreshEveryday()
        XCTAssertEqual(writes.value, [EverydayPlanFile(plan: EverydayPlan(schedule), needsCheck: true)])
    }
    func testAnUnreadableEverydayFileWritesNothing() {
        let writes = Box<[EverydayPlanFile]>([])
        let (model, layer, _) = model(writes: writes)
        layer.schedule = schedule; layer.unreadable = true
        model.refreshEveryday()
        XCTAssertTrue(writes.value.isEmpty)
        let settings = EverydaySettingsModel(focus: model)
        settings.refreshStatus()
        XCTAssertTrue(writes.value.isEmpty)
    }
    func testAThrownPlanWriteKeepsTheStatusAndTheNextReadWritesAgain() {
        let writes = Box<[EverydayPlanFile]>([]), fail = Box(true)
        let (model, layer, _) = model(writes: writes, fail: fail)
        layer.schedule = schedule
        model.refreshEveryday()
        XCTAssertEqual(model.everydayStatus?.schedule, schedule); XCTAssertNil(model.everydayStatus?.issue)
        XCTAssertTrue(writes.value.isEmpty)
        fail.value = false
        model.refreshEveryday()
        XCTAssertEqual(writes.value, [file])
    }
    func testSettingsRefreshStatusWritesThePlanOfASuccessfulRead() {
        let writes = Box<[EverydayPlanFile]>([])
        let (model, layer, _) = model(writes: writes)
        layer.schedule = schedule
        let settings = EverydaySettingsModel(focus: model)
        writes.value = []
        settings.refreshStatus()
        XCTAssertEqual(settings.status?.schedule, schedule)
        XCTAssertEqual(writes.value, [file])
    }
    /// What this establishes: the default closure of `FocusServices` writes nothing and does not throw.
    func testTheDefaultWriterDoesNothing() {
        let engine = SessionControl(store: ModelTestStore(), monitoring: ModelTestMonitoring(), shield: ModelTestShield(), breakSelection: ModelTestBreakSelection(), everyday: ModelTestEverydayLayer())
        let services = FocusServices(authorization: ModelTestAuthorization(), selection: ModelTestSelection(), engine: engine, applySelection: { _ in }, matchesSelection: { _ in true }, isFixture: true)
        XCTAssertNoThrow(try services.writeEverydayPlan(file))
    }
}
