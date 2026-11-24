import XCTest
import StoreKit
import StoreKitTest

/// A scripted StoreKit: each product read, purchase result and sync result is set by the test.
@MainActor private final class ScriptedStoreKit: PaidAccessStoreKit {
    var version: String?
    var reads: [String: PaidAccess.ProductRead] = [:]
    /// `nil` returns `.purchased` with the product's entry in `purchased`.
    var purchaseResult: Result<PaidPurchaseOutcome, Error>?
    /// What a `.purchased` result returns and adds to the reads.
    var purchased: [String: PaidPurchase] = [:]
    /// The refresh after a purchase reads nothing, as when its StoreKit reads fail.
    var purchaseHiddenFromReads = false
    var syncError: Error?
    var syncAdds: [String: PaidPurchase] = [:]
    private(set) var calls: [String] = []
    func originalAppVersion() async -> String? { calls.append("version"); return version }
    /// When set, the next read of the unlock waits until the test resumes `heldRead`, as a slow StoreKit read would.
    var holdUnlockRead = false
    private(set) var heldRead: CheckedContinuation<Void, Never>?
    func resumeHeldRead() { heldRead?.resume(); heldRead = nil }
    func read(_ productID: String) async -> PaidAccess.ProductRead {
        calls.append("read \(productID)")
        if productID == PaidAccess.unlockProductID, holdUnlockRead {
            holdUnlockRead = false
            await withCheckedContinuation { heldRead = $0 }
        }
        return reads[productID] ?? .noSignal
    }
    /// What `Transaction.all` returns as the product's earliest purchase; `nil` unless a test sets it.
    var firstPurchases: [String: Date] = [:]
    func firstPurchaseDate(_ productID: String) async -> Date? { firstPurchases[productID] }
    func displayPrice(_ productID: String) async -> String? { "₩14,000" }
    func purchase(_ productID: String) async throws -> PaidPurchaseOutcome {
        calls.append("purchase \(productID)")
        if let purchaseResult { return try purchaseResult.get() }
        let purchase = purchased[productID] ?? PaidPurchase(purchaseDate: Date())
        if !purchaseHiddenFromReads { reads[productID] = .transaction(purchase) }
        return .purchased(purchase)
    }
    func sync() async throws {
        calls.append("sync")
        if let syncError { throw syncError }
        for (id, purchase) in syncAdds { reads[id] = .transaction(purchase) }
    }
    func listen(_ handle: @escaping @MainActor (String, PaidPurchase) async -> Void) -> Task<Void, Never> { Task {} }
}

/// The store's merge, cache and action rules with a scripted StoreKit (docs/specs/2026-11-24-paid-access-design.md).
@MainActor final class PaidAccessStoreTests: XCTestCase {
    private let enabled = PaidAccessConfiguration(enabled: true, firstPaidBuild: 3)
    private func cache() -> PaidAccessCache {
        PaidAccessCache(container: FileManager.default.temporaryDirectory.appendingPathComponent("PaidAccess-\(UUID().uuidString)"))
    }
    private func store(_ kit: ScriptedStoreKit, cache: PaidAccessCache? = nil, now: @escaping () -> Date = Date.init) -> PaidAccessStore {
        PaidAccessStore(configuration: enabled, cache: cache, kit: kit, now: now)
    }

    func testPurchaseGrantsAndWritesTheCache() async {
        let kit = ScriptedStoreKit(); kit.version = "10"; kit.purchased[PaidAccess.unlockProductID] = PaidPurchase(purchaseDate: Date())
        let file = cache(), store = store(kit, cache: file)
        await store.refresh(); XCTAssertEqual(store.state, .locked)
        await store.purchaseUnlock()
        XCTAssertEqual(store.state, .granted); XCTAssertNil(store.message)
        XCTAssertNotNil(file.load()?.unlock)
        XCTAssertEqual(file.state(configuration: enabled, now: Date()), .granted)
    }
    /// The verified purchase grants even when the refresh after it reads nothing.
    func testPurchaseGrantsWhenTheRefreshAfterItReadsNothing() async {
        let kit = ScriptedStoreKit(); kit.version = "10"; kit.purchaseHiddenFromReads = true
        let file = cache(), store = store(kit, cache: file)
        await store.refresh(); XCTAssertEqual(store.state, .locked)
        await store.purchaseUnlock()
        XCTAssertEqual(store.state, .granted); XCTAssertNil(store.message)
        XCTAssertEqual(file.state(configuration: enabled, now: Date()), .granted)
    }
    /// Ask to Buy: nothing is granted until `Transaction.updates` delivers the approval.
    func testPendingGrantsNothing() async {
        let kit = ScriptedStoreKit(); kit.version = "10"; kit.purchaseResult = .success(.pending)
        let store = store(kit)
        await store.refresh(); await store.purchaseUnlock()
        XCTAssertEqual(store.state, .locked)
        XCTAssertEqual(store.message, "승인을 기다리고 있어요.")
        await store.apply(productID: PaidAccess.unlockProductID, purchase: PaidPurchase(purchaseDate: Date()))
        XCTAssertEqual(store.state, .granted)
    }
    func testCancelShowsNothingAndAFailureShowsItsMessage() async {
        let kit = ScriptedStoreKit(); kit.version = "10"; kit.purchaseResult = .success(.cancelled)
        let store = store(kit)
        await store.refresh(); await store.purchaseUnlock()
        XCTAssertEqual(store.state, .locked); XCTAssertNil(store.message)
        kit.purchaseResult = .failure(StoreKitError.networkError(URLError(.notConnectedToInternet)))
        await store.purchaseUnlock()
        XCTAssertEqual(store.message, "구매하지 못했어요. 다시 시도해 주세요.")
        await store.startTrial()
        XCTAssertEqual(store.message, "체험을 시작하지 못했어요. 다시 시도해 주세요.")
        XCTAssertEqual(store.state, .locked)
    }
    func testRestore() async {
        let kit = ScriptedStoreKit(); kit.version = "10"
        let store = store(kit)
        await store.restore()
        XCTAssertEqual(store.message, "복원할 구매가 없어요."); XCTAssertEqual(store.state, .locked)
        kit.syncError = StoreKitError.userCancelled
        await store.restore()
        XCTAssertEqual(store.message, "구매를 복원하지 못했어요. 다시 시도해 주세요.")
        kit.syncError = nil; kit.syncAdds[PaidAccess.unlockProductID] = PaidPurchase(purchaseDate: Date())
        await store.restore()
        XCTAssertNil(store.message); XCTAssertEqual(store.state, .granted)
        XCTAssertEqual(kit.calls.filter { $0 == "sync" }.count, 3)
    }
    /// A refund from `Transaction.updates` is a signal: it removes access and reaches the cache that the extension reads.
    func testRefundUpdateRevokesAndReachesTheCache() async {
        let kit = ScriptedStoreKit(); kit.version = "10"
        let bought = Date()
        kit.reads[PaidAccess.unlockProductID] = .transaction(PaidPurchase(purchaseDate: bought))
        let file = cache(), store = store(kit, cache: file)
        await store.refresh(); XCTAssertEqual(store.state, .granted)
        await store.apply(productID: PaidAccess.unlockProductID, purchase: PaidPurchase(purchaseDate: bought, revocationDate: Date()))
        XCTAssertEqual(store.state, .locked)
        XCTAssertNotNil(file.load()?.unlock?.revocationDate)
        XCTAssertEqual(file.state(configuration: enabled, now: Date()), .locked)
    }
    /// A refresh whose read started before a refund arrived through `Transaction.updates` merges first, so the refund, merged after it, stays.
    /// A refresh that starts after the refund describes the later App Store state, so a reversed refund grants again.
    func testStaleRefreshAfterARefundStaysLocked() async {
        let kit = ScriptedStoreKit(); kit.version = "10"
        let bought = Date()
        kit.reads[PaidAccess.unlockProductID] = .transaction(PaidPurchase(purchaseDate: bought))
        let file = cache(), store = store(kit, cache: file)
        await store.refresh(); XCTAssertEqual(store.state, .granted)
        kit.holdUnlockRead = true
        let stale = Task { await store.refresh() }
        while kit.heldRead == nil { await Task.yield() }
        let refund = Task { await store.apply(productID: PaidAccess.unlockProductID, purchase: PaidPurchase(purchaseDate: bought, revocationDate: Date())) }
        for _ in 0..<20 { await Task.yield() }
        // The held read returns the pre-refund transaction, as a read that started before the update would.
        kit.resumeHeldRead()
        await stale.value; await refund.value
        XCTAssertEqual(store.state, .locked)
        XCTAssertEqual(file.state(configuration: enabled, now: Date()), .locked)
        // The App Store reversed the refund: the next refresh reads the purchase without a revocation.
        await store.refresh()
        XCTAssertEqual(store.state, .granted)
        XCTAssertEqual(file.state(configuration: enabled, now: Date()), .granted)
    }
    func testTrialEndsByTimeAndCannotRestart() async throws {
        var clock = Date()
        let start = clock
        let kit = ScriptedStoreKit(); kit.version = "10"; kit.purchased[PaidAccess.trialProductID] = PaidPurchase(purchaseDate: start)
        let file = cache(), store = store(kit, cache: file, now: { clock })
        await store.startTrial()
        XCTAssertEqual(store.state, .granted)
        clock = start.addingTimeInterval(PaidAccess.trialLength - 1); XCTAssertEqual(store.state, .granted)
        clock = start.addingTimeInterval(PaidAccess.trialLength); XCTAssertEqual(store.state, .locked)
        XCTAssertEqual(file.state(configuration: enabled, now: clock), .locked)
        // A later trial transaction keeps the first purchase date.
        kit.reads[PaidAccess.trialProductID] = .transaction(PaidPurchase(purchaseDate: clock))
        await store.refresh()
        XCTAssertEqual(store.facts?.trialStartedAt, start)
        XCTAssertEqual(store.state, .locked)
    }
    /// No cache, as after a reinstall: a refunded first trial and a second trial purchase. The trial start comes from the first purchase,
    /// which only `Transaction.all` still holds, so the second purchase does not grant another 72 hours.
    func testTrialStartComesFromTheFirstPurchaseWithoutACache() async {
        let now = Date(), first = now.addingTimeInterval(-PaidAccess.trialLength - 3600)
        let kit = ScriptedStoreKit(); kit.version = "10"
        kit.reads[PaidAccess.trialProductID] = .transaction(PaidPurchase(purchaseDate: now.addingTimeInterval(-60)))
        kit.firstPurchases[PaidAccess.trialProductID] = first
        let file = cache(), store = store(kit, cache: file, now: { now })
        await store.refresh()
        XCTAssertEqual(store.facts?.trialStartedAt, first)
        XCTAssertEqual(store.state, .locked)
        XCTAssertEqual(file.state(configuration: enabled, now: now), .locked)
    }
    /// A failed read never removes access: the cached unlock stays, and the state never becomes `unknown` or `locked`.
    func testFailedReadKeepsTheCachedUnlock() async throws {
        let file = cache()
        try file.save(PaidAccessFacts(originalAppVersion: "10", unlock: PaidPurchase(purchaseDate: Date()), trial: nil, confirmedAt: Date()))
        let store = store(ScriptedStoreKit(), cache: file)
        XCTAssertEqual(store.state, .granted)
        await store.refresh()
        XCTAssertEqual(store.state, .granted)
        XCTAssertNotNil(file.load()?.unlock)
    }
    /// A refresh that confirms nothing does not write the cache again.
    func testReadThatConfirmsNothingDoesNotRewriteTheCache() async throws {
        let file = cache()
        try file.save(PaidAccessFacts(originalAppVersion: "10", unlock: PaidPurchase(purchaseDate: Date()), trial: nil, confirmedAt: Date()))
        let store = store(ScriptedStoreKit(), cache: file)
        try FileManager.default.removeItem(at: file.file)
        await store.refresh()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.file.path))
        XCTAssertEqual(store.state, .granted)
    }
    func testEarlierUserAndUnknownVersion() async {
        let earlier = ScriptedStoreKit(); earlier.version = "2"
        let earlierStore = store(earlier)
        await earlierStore.refresh(); XCTAssertEqual(earlierStore.state, .granted)
        let file = cache(), unread = store(ScriptedStoreKit(), cache: file)
        await unread.refresh()
        XCTAssertEqual(unread.state, .unknown); XCTAssertNil(file.load())
    }
    func testGateOffReadsNothing() async {
        let kit = ScriptedStoreKit(); kit.version = "10"
        let store = PaidAccessStore(configuration: .disabled, cache: nil, kit: kit)
        store.start(); await store.refresh()
        XCTAssertEqual(store.state, .granted)
        XCTAssertTrue(kit.calls.isEmpty); XCTAssertNil(store.facts)
    }
}

/// The StoreKit test configuration `Configuration/FocusStudy.storekit` with the real StoreKit 2 calls; only `originalAppVersion` is injected,
/// because a test has no app transaction of a real download and the sandbox value is `"1.0"`.
/// A pass here does not prove a real purchase or restore (docs/specs/2026-11-24-paid-access-design.md, "Verification").
/// On 2026-11-24 every `SKTestSession` write failed with `SKInternalErrorDomain Code=3` in this project's simulator runs, so these tests skip
/// when no product of the configuration loads, and the skip stays visible in the test report.
/// A product ID that the configuration file does not hold, or a load of only one product, fails instead, because that is not the environment.
@MainActor final class PaidAccessStoreKitTests: XCTestCase {
    private var session: SKTestSession!
    private let enabled = PaidAccessConfiguration(enabled: true, firstPaidBuild: 3)

    override func setUp() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "FocusStudy", withExtension: "storekit"))
        let ids = [PaidAccess.unlockProductID, PaidAccess.trialProductID]
        // The file read does not depend on StoreKit, so a wrong or missing product ID fails here and never skips.
        let configuration = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let configured = Set(((configuration["products"] as? [[String: Any]]) ?? []).compactMap { $0["productID"] as? String })
        XCTAssertEqual(configured, Set(ids), "Configuration/FocusStudy.storekit must hold exactly the product IDs of PaidAccess")
        session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()
        let loaded = Set(try await Product.products(for: ids).map(\.id))
        if loaded.isEmpty {
            throw XCTSkip("SKTestSession loaded no product of the StoreKit configuration (SKInternalErrorDomain Code=3 on 2026-11-24); see the paid-access design, Verification.")
        }
        XCTAssertEqual(loaded, Set(ids), "the StoreKit configuration loaded only some products")
    }
    override func tearDown() async throws { session?.clearTransactions(); session = nil }

    private struct Kit: PaidAccessStoreKit {
        let system = SystemPaidAccessStoreKit()
        func originalAppVersion() async -> String? { "1.0" }
        func read(_ productID: String) async -> PaidAccess.ProductRead { await system.read(productID) }
        func firstPurchaseDate(_ productID: String) async -> Date? { await system.firstPurchaseDate(productID) }
        func displayPrice(_ productID: String) async -> String? { await system.displayPrice(productID) }
        func purchase(_ productID: String) async throws -> PaidPurchaseOutcome { try await system.purchase(productID) }
        func sync() async throws { try await system.sync() }
        func listen(_ handle: @escaping @MainActor (String, PaidPurchase) async -> Void) -> Task<Void, Never> { system.listen(handle) }
    }
    private func makeStore(now: @escaping () -> Date = Date.init) -> (PaidAccessStore, PaidAccessCache) {
        let cache = PaidAccessCache(container: FileManager.default.temporaryDirectory.appendingPathComponent("PaidAccess-\(UUID().uuidString)"))
        return (PaidAccessStore(configuration: enabled, cache: cache, kit: Kit(), now: now), cache)
    }

    func testPriceComesFromTheStore() async throws {
        let (store, _) = makeStore()
        await store.loadPrice()
        let expected = try await Product.products(for: [PaidAccess.unlockProductID]).first?.displayPrice
        XCTAssertEqual(store.unlockPrice, expected)
        XCTAssertNotNil(expected)
    }
    /// The sandbox value `"1.0"` is not an earlier user, so a new person is locked until a purchase.
    func testPurchase() async throws {
        let (store, cache) = makeStore()
        await store.refresh(); XCTAssertEqual(store.state, .locked)
        await store.purchaseUnlock()
        XCTAssertNil(store.message); XCTAssertEqual(store.state, .granted)
        XCTAssertEqual(cache.state(configuration: enabled, now: Date()), .granted)
    }
    func testRestoreAfterAPurchaseOutsideTheApp() async throws {
        _ = try await session.buyProduct(identifier: PaidAccess.unlockProductID)
        let (store, _) = makeStore()
        await store.restore()
        XCTAssertEqual(store.state, .granted); XCTAssertNil(store.message)
    }
    func testTrialStartAndExpiry() async throws {
        var clock = Date()
        let (store, cache) = makeStore(now: { clock })
        await store.startTrial()
        let trial = try XCTUnwrap(store.facts?.trial)
        XCTAssertEqual(store.state, .granted)
        clock = trial.purchaseDate.addingTimeInterval(PaidAccess.trialLength)
        XCTAssertEqual(store.state, .locked)
        XCTAssertEqual(cache.state(configuration: enabled, now: clock), .locked)
        await store.startTrial(); await store.refresh()
        XCTAssertEqual(store.facts?.trialStartedAt, trial.purchaseDate)
        XCTAssertEqual(store.state, .locked)
    }
    func testRefundRevokesTheUnlock() async throws {
        let (store, cache) = makeStore()
        await store.purchaseUnlock(); XCTAssertEqual(store.state, .granted)
        let transaction = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == PaidAccess.unlockProductID })
        try session.refundTransaction(identifier: transaction.identifier)
        await store.refresh()
        XCTAssertNotNil(store.facts?.unlock?.revocationDate)
        XCTAssertEqual(store.state, .locked)
        XCTAssertEqual(cache.state(configuration: enabled, now: Date()), .locked)
    }
}
