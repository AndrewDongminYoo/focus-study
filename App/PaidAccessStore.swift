import Foundation
import Observation
import StoreKit

/// The result of a purchase or a trial start. `purchased` carries the verified transaction, which the store merges before its refresh.
/// `pending` (Ask to Buy) grants nothing: an approval arrives later through `Transaction.updates`.
enum PaidPurchaseOutcome: Equatable { case purchased(PaidPurchase), pending, cancelled }
/// What one trial start or purchase from the paywall ended in. Only `confirmed` can continue the start that opened the paywall
/// (docs/specs/2026-11-26-paywall-design.md, contract item 5); `notGranted` is a verified transaction that opens no access by itself,
/// such as a trial that already ended; `busy` is a tap while another action runs.
enum PaidActionResult: Equatable { case confirmed, notGranted, pending, cancelled, failed, busy }

/// The paywall's two decisions, outside the view (`PaidAccessSheet`) so that the SDK tests run the same code as the sheet.
enum PaywallOutcome: Equatable {
    case continueStart, dropStart, none

    /// The result of the sheet's own trial or purchase. Only a confirmed result with access `granted` continues the start;
    /// a pending purchase, a cancel or a failure drops it (contract item 5); a busy store changes nothing.
    init(_ result: PaidActionResult, access: PaidAccessState) {
        self = result == .confirmed && access == .granted ? .continueStart : result == .busy ? .none : .dropStart
    }
    /// Access that opens while none of the sheet's own actions runs, such as an approved purchase from `Transaction.updates`
    /// or a restore, closes the sheet without a confirmation, so its close starts nothing.
    static func closesByItself(access: PaidAccessState, acting: Bool) -> Bool { access == .granted && !acting }
}

/// The StoreKit calls of the store, so that tests and UI fixtures can replace them.
@MainActor protocol PaidAccessStoreKit {
    /// `AppTransaction.originalAppVersion` of a verified app transaction; `nil` when the read throws or is unverified.
    func originalAppVersion() async -> String?
    func read(_ productID: String) async -> PaidAccess.ProductRead
    /// The earliest purchase date of every verified transaction of the product, refunded ones included; `nil` when there is none.
    func firstPurchaseDate(_ productID: String) async -> Date?
    /// The display price that the store returns; `nil` when the product cannot load.
    func displayPrice(_ productID: String) async -> String?
    func purchase(_ productID: String) async throws -> PaidPurchaseOutcome
    func sync() async throws
    /// Calls `handle` with every verified transaction of `Transaction.updates`, after `finish()`, until the task is cancelled.
    /// It awaits `handle` before it takes the next transaction.
    func listen(_ handle: @escaping @MainActor (String, PaidPurchase) async -> Void) -> Task<Void, Never>
}

/// The app's StoreKit 2 calls (docs/specs/2026-11-24-paid-access-design.md, "StoreKit reads").
struct SystemPaidAccessStoreKit: PaidAccessStoreKit {
    func originalAppVersion() async -> String? {
        guard let result = try? await AppTransaction.shared, case .verified(let transaction) = result else { return nil }
        return transaction.originalAppVersion
    }
    /// A verified entitlement first; then the latest verified transaction, which carries a `revocationDate` after a refund,
    /// because `Transaction.currentEntitlements` drops refunded products.
    func read(_ productID: String) async -> PaidAccess.ProductRead {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == productID { return .transaction(Self.purchase(transaction)) }
        }
        guard let latest = await Transaction.latest(for: productID), case .verified(let transaction) = latest else { return .noSignal }
        return .transaction(Self.purchase(transaction))
    }
    /// `Transaction.all` keeps refunded non-consumable transactions, so a refunded first trial still sets the trial start.
    func firstPurchaseDate(_ productID: String) async -> Date? {
        var earliest: Date?
        for await result in Transaction.all {
            guard case .verified(let transaction) = result, transaction.productID == productID else { continue }
            earliest = min(earliest ?? transaction.originalPurchaseDate, transaction.originalPurchaseDate)
        }
        return earliest
    }
    func displayPrice(_ productID: String) async -> String? {
        try? await Product.products(for: [productID]).first?.displayPrice
    }
    func purchase(_ productID: String) async throws -> PaidPurchaseOutcome {
        guard let product = try await Product.products(for: [productID]).first else { throw StoreKitError.notAvailableInStorefront }
        switch try await product.purchase() {
        case .success(let verification):
            // An unverified transaction grants nothing, so it is not finished as a purchase.
            guard case .verified(let transaction) = verification else { throw StoreKitError.unknown }
            await transaction.finish()
            return .purchased(Self.purchase(transaction))
        case .pending: return .pending
        case .userCancelled: return .cancelled
        @unknown default: return .cancelled
        }
    }
    func sync() async throws { try await AppStore.sync() }
    func listen(_ handle: @escaping @MainActor (String, PaidPurchase) async -> Void) -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                let purchase = Self.purchase(transaction)
                await handle(transaction.productID, purchase)
            }
        }
    }
    /// `originalPurchaseDate`, because a restored transaction on a new device can carry a later `purchaseDate`, which would restart the trial.
    nonisolated private static func purchase(_ transaction: Transaction) -> PaidPurchase {
        PaidPurchase(purchaseDate: transaction.originalPurchaseDate, revocationDate: transaction.revocationDate)
    }
}

/// The app's view of paid access: the last confirmed facts in memory and in the App Group cache, and the purchase actions.
/// `state` is synchronous, so the start section never awaits StoreKit.
@MainActor @Observable final class PaidAccessStore {
    let configuration: PaidAccessConfiguration
    @ObservationIgnored private let cache: PaidAccessCache?
    @ObservationIgnored private let kit: any PaidAccessStoreKit
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var updates: Task<Void, Never>?
    private(set) var facts: PaidAccessFacts?
    /// The unlock's price as the store returns it; never a constant in code.
    private(set) var unlockPrice: String?
    private(set) var isWorking = false
    /// The result line of the last action, for the paywall.
    private(set) var message: String?

    init(configuration: PaidAccessConfiguration, cache: PaidAccessCache?, kit: any PaidAccessStoreKit, now: @escaping () -> Date = Date.init) {
        self.configuration = configuration; self.cache = cache; self.kit = kit; self.now = now
        facts = cache?.load()
    }
    var state: PaidAccessState { PaidAccess.state(configuration: configuration, facts: facts, now: now()) }

    /// Launch: the `Transaction.updates` listener, a refresh and the price. A gate that is off reads nothing.
    func start() {
        guard configuration.enabled, updates == nil else { return }
        // The listener awaits each update's turn before it takes the next transaction, so the updates queue in the order StoreKit delivers them.
        updates = kit.listen { [weak self] productID, purchase in
            await self?.apply(productID: productID, purchase: purchase)
        }
        Task { await refresh(); await loadPrice() }
    }
    func loadPrice() async {
        if let price = await kit.displayPrice(PaidAccess.unlockProductID) { unlockPrice = price }
    }
    /// The last queued update. Each update reads and merges inside its own turn, and a turn waits for the one before it,
    /// so a merge never applies a read that started before an earlier merge: the later read always describes the later App Store state.
    @ObservationIgnored private var lastUpdate: Task<Void, Never>?
    private func serially(_ work: @escaping @MainActor () async -> Void) async {
        let previous = lastUpdate
        let turn = Task { @MainActor in
            await previous?.value
            await work()
        }
        lastUpdate = turn
        await turn.value
    }
    func refresh() async {
        guard configuration.enabled else { return }
        await serially {
            let version = await self.kit.originalAppVersion()
            let unlock = await self.kit.read(PaidAccess.unlockProductID), trial = await self.kit.read(PaidAccess.trialProductID)
            let trialFirstPurchase = await self.kit.firstPurchaseDate(PaidAccess.trialProductID)
            self.merge(PaidAccess.Read(originalAppVersion: version, unlock: unlock, trial: trial, trialFirstPurchase: trialFirstPurchase))
        }
    }
    @discardableResult func purchaseUnlock() async -> PaidActionResult { await buy(PaidAccess.unlockProductID, failure: "구매하지 못했어요. 다시 시도해 주세요.") }
    @discardableResult func startTrial() async -> PaidActionResult { await buy(PaidAccess.trialProductID, failure: "체험을 시작하지 못했어요. 다시 시도해 주세요.") }
    /// "구매 복원": the only way back to the unlock on a new device, because the app has no account.
    func restore() async {
        guard !isWorking else { return }
        isWorking = true; message = nil
        defer { isWorking = false }
        do { try await kit.sync() } catch { message = "구매를 복원하지 못했어요. 다시 시도해 주세요."; return }
        await refresh()
        if state != .granted { message = "복원할 구매가 없어요." }
    }
    private func buy(_ productID: String, failure: String) async -> PaidActionResult {
        guard !isWorking else { return .busy }
        isWorking = true; message = nil
        defer { isWorking = false }
        do {
            switch try await kit.purchase(productID) {
            case .purchased(let purchase):
                // The verified transaction applies even when the refresh after it reads nothing.
                await apply(productID: productID, purchase: purchase)
                await refresh()
                // Access that another transaction opened meanwhile, such as an approval from `Transaction.updates`, is not this action's confirmation.
                guard grants(productID: productID, purchase: purchase) else {
                    message = productID == PaidAccess.trialProductID ? "3일 체험이 이미 끝났어요." : failure
                    return .notGranted
                }
                return .confirmed
            case .pending: message = "승인을 기다리고 있어요."; return .pending
            case .cancelled: return .cancelled
            }
        } catch { message = failure; return .failed }
    }
    /// Whether the action's own transaction opens access: an unlock that is not revoked, or a trial that is not revoked and has not ended.
    /// The trial end uses the merged facts, so a second purchase of the trial product does not count from its own date.
    private func grants(productID: String, purchase: PaidPurchase) -> Bool {
        guard !purchase.isRevoked else { return false }
        switch productID {
        case PaidAccess.unlockProductID: return true
        case PaidAccess.trialProductID: return now() < PaidAccess.trialEnd(facts ?? PaidAccessFacts(), trial: purchase)
        default: return false
        }
    }
    /// A verified transaction from `Transaction.updates`, such as a refund or an approved Ask to Buy, or the result of a purchase.
    /// It takes its turn in the queue, so a refresh that read before it cannot overwrite it afterwards.
    func apply(productID: String, purchase: PaidPurchase) async {
        let read: PaidAccess.ProductRead = .transaction(purchase)
        await serially {
            switch productID {
            case PaidAccess.unlockProductID: self.merge(PaidAccess.Read(originalAppVersion: nil, unlock: read, trial: .noSignal))
            case PaidAccess.trialProductID: self.merge(PaidAccess.Read(originalAppVersion: nil, unlock: .noSignal, trial: read))
            default: break
            }
        }
    }
    /// A read that confirms nothing keeps the last confirmed value; a failed cache write keeps the value in memory for this process.
    private func merge(_ read: PaidAccess.Read) {
        guard let merged = PaidAccess.merge(cached: facts, read: read, now: now()), merged != facts else { return }
        facts = merged
        try? cache?.save(merged)
    }
}
