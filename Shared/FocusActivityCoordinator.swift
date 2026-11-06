import Foundation

struct FocusActivityHandle: Equatable {
    var id: String
    var sessionID: UUID
    var isLive = true
}
@MainActor protocol FocusActivityClient: AnyObject {
    var isEnabled: Bool { get }
    var activities: [FocusActivityHandle] { get }
    func request(_ projection: FocusActivityProjection) throws
    func update(_ activity: FocusActivityHandle, content: FocusActivityContent) async
    func end(_ activity: FocusActivityHandle) async
}

/// Display work never participates in a restriction transaction or its process lock.
@MainActor final class FocusActivityCoordinator {
    private let client: any FocusActivityClient
    private let snapshot: () throws -> ControlSession?
    private let timing: BreakTiming
    private let now: () -> Date
    private let canStart: () -> Bool
    private let hasAttempted: (UUID) -> Bool
    private let markAttempted: (UUID) -> Void
    private var pending: Task<Void, Never>?
    private var pendingID: UUID?
    init(client: any FocusActivityClient, snapshot: @escaping () throws -> ControlSession?, timing: BreakTiming,
         now: @escaping () -> Date = Date.init, canStart: @escaping () -> Bool,
         hasAttempted: @escaping (UUID) -> Bool, markAttempted: @escaping (UUID) -> Void) {
        self.client = client; self.snapshot = snapshot; self.timing = timing; self.now = now
        self.canStart = canStart; self.hasAttempted = hasAttempted; self.markAttempted = markAttempted
    }
    func synchronize() async {
        let previous = pending, id = UUID()
        let work = Task { @MainActor [weak self] in
            await previous?.value
            await self?.perform()
        }
        pending = work; pendingID = id
        await work.value
        if pendingID == id { pending = nil; pendingID = nil }
    }
    private func read() -> ControlSession? { try? snapshot() }
    private func project(_ session: ControlSession?) -> FocusActivityProjection? {
        FocusActivityProjection.make(session: session, now: now(), timing: timing)
    }
    private func remember(_ id: UUID) { if !hasAttempted(id) { markAttempted(id) } }
    private func perform() async {
        // A different process can commit during an await. Re-read after effects and converge,
        // with a bound so continuous transitions cannot keep an extension alive indefinitely.
        for _ in 0..<3 {
            let before = read()
            var kept: FocusActivityHandle?
            for activity in client.activities.sorted(by: { $0.id < $1.id }) {
                guard let latest = project(read()), activity.sessionID == latest.sessionID else {
                    await client.end(activity); continue
                }
                remember(latest.sessionID)
                guard client.isEnabled, activity.isLive, kept?.sessionID != latest.sessionID else {
                    await client.end(activity); continue
                }
                kept = activity
                await client.update(activity, content: latest.content)
            }
            if let latest = project(read()), latest.content.phase != .waiting,
               client.isEnabled, canStart(), !hasAttempted(latest.sessionID),
               !client.activities.contains(where: { $0.sessionID == latest.sessionID }) {
                // Persist before the synchronous request. An ambiguous failure uses the app
                // fallback for this session instead of risking recreation after dismissal.
                remember(latest.sessionID)
                if let verified = project(read()), verified.sessionID == latest.sessionID, canStart() {
                    try? client.request(verified)
                }
            }
            if read() == before { return }
        }
    }
}
