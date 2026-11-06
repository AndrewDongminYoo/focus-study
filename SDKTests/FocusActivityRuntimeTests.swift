import XCTest

@MainActor private final class ActivityRuntimeClient: FocusActivityClient {
    var isEnabled = true
    var activities: [FocusActivityHandle] = []
    var requestCount = 0, updateCount = 0, endCount = 0
    var failsRequest = false
    func request(_ projection: FocusActivityProjection) throws {
        requestCount += 1
        if failsRequest { throw ControlIssue.io }
        activities.append(.init(id: "activity", sessionID: projection.sessionID))
    }
    func update(_ activity: FocusActivityHandle, content: FocusActivityContent) async { updateCount += 1 }
    func end(_ activity: FocusActivityHandle) async {
        endCount += 1; activities.removeAll { $0.id == activity.id && $0.sessionID == activity.sessionID }
    }
}
@MainActor final class FocusActivityRuntimeTests: XCTestCase {
    private func engine() throws -> (SessionControl, ModelTestStore) {
        let store = ModelTestStore()
        let engine = SessionControl(store: store, monitoring: ModelTestMonitoring(), shield: ModelTestShield(),
                                    breakSelection: ModelTestBreakSelection(), everyday: ModelTestEverydayLayer())
        _ = try engine.start(now: Date(), authorized: { true }, apply: {}, matches: { true })
        return (engine, store)
    }
    func testAppPrivateMarkerSurvivesCoordinatorAndDefaultsReconstruction() async throws {
        let (engine, _) = try engine(), client = ActivityRuntimeClient(), suite = UUID().uuidString
        let first = FocusActivityRuntime.coordinator(engine: engine, defaults: UserDefaults(suiteName: suite)!, client: client, canStart: { true })
        await first.synchronize()
        XCTAssertEqual(client.requestCount, 1)
        client.activities = []
        let second = FocusActivityRuntime.coordinator(engine: engine, defaults: UserDefaults(suiteName: suite)!, client: client, canStart: { true })
        await second.synchronize()
        XCTAssertEqual(client.requestCount, 1)
    }
    func testAmbiguousRequestFailurePersistsFallbackForTheSameSession() async throws {
        let (engine, _) = try engine(), client = ActivityRuntimeClient(), suite = UUID().uuidString
        client.failsRequest = true
        await FocusActivityRuntime.coordinator(engine: engine, defaults: UserDefaults(suiteName: suite)!, client: client, canStart: { true }).synchronize()
        client.failsRequest = false
        await FocusActivityRuntime.coordinator(engine: engine, defaults: UserDefaults(suiteName: suite)!, client: client, canStart: { true }).synchronize()
        XCTAssertEqual(client.requestCount, 1)
        XCTAssertEqual(try engine.snapshot().session?.phase, .active)
    }
    func testUnavailableControlStateEndsOnlyOptionalDisplay() async throws {
        let store = ModelTestStore(), client = ActivityRuntimeClient()
        let monitor = ModelTestMonitoring(), shield = ModelTestShield()
        let selection = ModelTestBreakSelection(), everyday = ModelTestEverydayLayer()
        let engine = SessionControl(store: store, monitoring: monitor, shield: shield, breakSelection: selection, everyday: everyday)
        let session = try engine.start(now: Date(), authorized: { true }, apply: { shield.applied = true }, matches: { shield.applied })
        selection.copies.insert(session.id); everyday.shieldOn = true
        let coordinator = FocusActivityRuntime.coordinator(engine: engine, defaults: UserDefaults(suiteName: UUID().uuidString)!, client: client, canStart: { true })
        await coordinator.synchronize(); store.failRead = true
        await coordinator.synchronize()
        XCTAssertEqual(client.endCount, 1); XCTAssertTrue(client.activities.isEmpty)
        XCTAssertTrue(shield.applied)
        XCTAssertTrue(everyday.shieldOn)
        XCTAssertTrue(monitor.ids.contains(session.id))
        XCTAssertTrue(selection.copies.contains(session.id))
        store.failRead = false
        XCTAssertEqual(try engine.snapshot().session?.phase, .active)
    }
}
