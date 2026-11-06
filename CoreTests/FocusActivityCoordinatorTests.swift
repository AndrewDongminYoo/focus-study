import XCTest
@testable import FocusCore

@MainActor private final class ActivityTestClient: FocusActivityClient {
    var isEnabled = true
    var activities: [FocusActivityHandle] = []
    var requests: [FocusActivityProjection] = []
    var updates: [FocusActivityHandle] = []
    var ends: [FocusActivityHandle] = []
    var failsRequest = false
    var beforeUpdate: (() async -> Void)?
    var beforeRequest: ((FocusActivityProjection) -> Void)?
    var inFlight = 0, maximumInFlight = 0
    func request(_ projection: FocusActivityProjection) throws {
        beforeRequest?(projection)
        requests.append(projection)
        if failsRequest { throw ControlIssue.io }
        activities.append(FocusActivityHandle(id: "created-\(requests.count)", sessionID: projection.sessionID))
    }
    func update(_ activity: FocusActivityHandle, content: FocusActivityContent) async {
        inFlight += 1; maximumInFlight = max(maximumInFlight, inFlight)
        await beforeUpdate?()
        updates.append(activity); inFlight -= 1
    }
    func end(_ activity: FocusActivityHandle) async {
        ends.append(activity)
        activities.removeAll { $0.id == activity.id && $0.sessionID == activity.sessionID }
    }
}
@MainActor private final class ActivityHarness {
    let client = ActivityTestClient()
    var session: ControlSession?
    var unreadable = false, foreground = true
    var attempted: Set<UUID> = []
    init() {
        var value = ControlSession(startedAt: Date(timeIntervalSince1970: 1000))
        value.phase = .active; session = value
    }
    func coordinator() -> FocusActivityCoordinator {
        FocusActivityCoordinator(client: client, snapshot: { [unowned self] in
            if unreadable { throw ControlIssue.io }; return session
        }, timing: .standard, now: { Date(timeIntervalSince1970: 1100) }, canStart: { [unowned self] in foreground },
        hasAttempted: { [unowned self] in attempted.contains($0) }, markAttempted: { [unowned self] in attempted.insert($0) })
    }
}

@MainActor final class FocusActivityCoordinatorTests: XCTestCase {
    func testForegroundStartsOnceAndPersistsBeforeRequest() async throws {
        let h = ActivityHarness(), coordinator: FocusActivityCoordinator
        coordinator = h.coordinator()
        h.client.beforeRequest = { XCTAssertTrue(h.attempted.contains($0.sessionID)) }
        await coordinator.synchronize(); await coordinator.synchronize()
        XCTAssertEqual(h.client.requests.count, 1)
        XCTAssertTrue(h.attempted.contains(try XCTUnwrap(h.session?.id)))
        XCTAssertEqual(h.client.requests.first?.sessionID, h.session?.id)
    }
    func testBackgroundFilterCanUpdateAndEndButCannotStart() async throws {
        let h = ActivityHarness(), coordinator = h.coordinator()
        h.foreground = false
        await coordinator.synchronize(); XCTAssertTrue(h.client.requests.isEmpty)
        let id = try XCTUnwrap(h.session?.id)
        h.client.activities = [.init(id: "existing", sessionID: id)]
        await coordinator.synchronize(); XCTAssertEqual(h.client.updates.count, 1)
        h.session = nil
        await coordinator.synchronize(); XCTAssertEqual(h.client.ends.map(\.id), ["existing"])
    }
    func testDisabledDoesNotConsumeStartMarker() async {
        let h = ActivityHarness(), coordinator = h.coordinator()
        h.client.isEnabled = false
        await coordinator.synchronize()
        XCTAssertTrue(h.client.requests.isEmpty); XCTAssertTrue(h.attempted.isEmpty)
        h.client.isEnabled = true
        await coordinator.synchronize(); XCTAssertEqual(h.client.requests.count, 1)
    }
    func testRequestFailureKeepsSessionAndDoesNotRepeatAnAmbiguousRequest() async {
        let h = ActivityHarness(), coordinator = h.coordinator(), original = h.session
        h.client.failsRequest = true
        await coordinator.synchronize(); await coordinator.synchronize()
        XCTAssertEqual(h.session, original); XCTAssertEqual(h.client.requests.count, 1)
        XCTAssertTrue(h.client.activities.isEmpty)
    }
    func testDismissedSessionIsNotRecreatedAfterCoordinatorReconstruction() async {
        let h = ActivityHarness()
        await h.coordinator().synchronize()
        h.client.activities = []
        await h.coordinator().synchronize()
        XCTAssertEqual(h.client.requests.count, 1)
    }
    func testUnreadableSnapshotRetiresDisplayWithoutStarting() async {
        let h = ActivityHarness(), original = h.session
        h.client.activities = [.init(id: "old", sessionID: UUID())]; h.unreadable = true
        await h.coordinator().synchronize()
        XCTAssertEqual(h.client.ends.map(\.id), ["old"])
        XCTAssertTrue(h.client.requests.isEmpty); XCTAssertEqual(h.session, original)
    }
    func testOrphansAndDuplicatesRetireOnlyExactHandles() async throws {
        let h = ActivityHarness(), id = try XCTUnwrap(h.session?.id)
        h.client.activities = [.init(id: "old", sessionID: UUID()), .init(id: "one", sessionID: id), .init(id: "two", sessionID: id)]
        await h.coordinator().synchronize()
        XCTAssertEqual(h.client.activities.map(\.id), ["one"])
        XCTAssertEqual(Set(h.client.ends.map(\.id)), ["old", "two"])
        XCTAssertTrue(h.client.requests.isEmpty)
    }
    func testLateOldUpdateCannotEndNewSessionAndConvergesToLatestState() async throws {
        let h = ActivityHarness(), old = try XCTUnwrap(h.session)
        var newer = ControlSession(startedAt: Date(timeIntervalSince1970: 1050)); newer.phase = .active
        h.client.activities = [.init(id: "old", sessionID: old.id)]
        var changed = false
        h.client.beforeUpdate = {
            if !changed {
                changed = true; h.session = newer
                h.client.activities.append(.init(id: "new", sessionID: newer.id))
                await Task.yield()
            }
        }
        await h.coordinator().synchronize()
        XCTAssertEqual(h.client.activities.map(\.id), ["new"])
        XCTAssertEqual(h.client.ends.map(\.id), ["old"])
        XCTAssertTrue(h.client.updates.contains { $0.id == "new" })
        XCTAssertEqual(h.session?.id, newer.id)
    }
    func testWaitingNeverStartsExternalWaitCountdown() async {
        let h = ActivityHarness()
        h.session?.phase = .waiting; h.session?.pausedAt = Date(timeIntervalSince1970: 1050)
        await h.coordinator().synchronize()
        XCTAssertTrue(h.client.requests.isEmpty)
    }
    func testConcurrentSynchronizationsDoNotOverlapTransportWork() async throws {
        let h = ActivityHarness(), coordinator = h.coordinator()
        h.client.activities = [.init(id: "existing", sessionID: try XCTUnwrap(h.session?.id))]
        let started = expectation(description: "first update suspended")
        var release: CheckedContinuation<Void, Never>?
        var first = true
        h.client.beforeUpdate = {
            if first {
                first = false
                await withCheckedContinuation { release = $0; started.fulfill() }
            }
        }
        let one = Task { await coordinator.synchronize() }
        await fulfillment(of: [started], timeout: 2)
        let two = Task { await coordinator.synchronize() }
        await Task.yield()
        XCTAssertEqual(h.client.maximumInFlight, 1)
        release?.resume()
        await one.value; await two.value
        XCTAssertEqual(h.client.maximumInFlight, 1)
    }
}
