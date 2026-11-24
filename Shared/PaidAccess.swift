import Foundation

/// Access to the paid features at session start (docs/specs/2026-11-24-paid-access-design.md).
/// `unknown` never opens the paywall and never refuses a start: only a confirmed `locked` does.
/// A recorded purchase that no longer grants, a trial that ended or a refunded unlock, is `locked` also while the version is unknown.
enum PaidAccessState: String, Codable, Equatable { case granted, locked, unknown }

/// One in-app purchase as the last confirmed read saw it. A purchase with a `revocationDate` grants nothing.
struct PaidPurchase: Codable, Equatable {
    /// The transaction's `originalPurchaseDate`, which a restore on a new device keeps.
    var purchaseDate: Date
    var revocationDate: Date?
    var isRevoked: Bool { revocationDate != nil }
}

/// The inputs of the rule, as the app's last confirmed reads left them. The cache stores these, never the verdict, so the trial ends by time alone in every process.
struct PaidAccessFacts: Codable, Equatable {
    /// `AppTransaction.originalAppVersion`; `nil` until one verified read.
    var originalAppVersion: String?
    var unlock: PaidPurchase?
    var trial: PaidPurchase?
    /// The earliest trial `purchaseDate` that any read found. The trial ends 72 hours after it, so a second trial purchase cannot restart it.
    /// It is separate from `trial`, which keeps the purchase's own date as its identity.
    var trialStartedAt: Date?
    /// The time of the last read that changed or confirmed these values.
    var confirmedAt: Date?
}

/// The build settings `PAID_UNLOCK_ENABLED` and `PAID_UNLOCK_FIRST_BUILD`, which each process reads from its own Info.plist.
struct PaidAccessConfiguration: Equatable {
    var enabled: Bool
    var firstPaidBuild: Int
    static let disabled = PaidAccessConfiguration(enabled: false, firstPaidBuild: Int.max)
    static let enabledKey = "FocusPaidUnlockEnabled", firstBuildKey = "FocusPaidUnlockFirstBuild"
    /// A missing value, or a threshold that is not an integer, turns the gate off, so every person keeps access as before the paid build.
    init(info: [String: Any]?) {
        let flag = (info?[Self.enabledKey] as? String).map { ["YES", "TRUE", "1"].contains($0.uppercased()) } ?? false
        let first = (info?[Self.firstBuildKey] as? String).flatMap(PaidAccess.buildNumber)
        if flag, let first { self.init(enabled: true, firstPaidBuild: first) } else { self = .disabled }
    }
    init(enabled: Bool, firstPaidBuild: Int) { self.enabled = enabled; self.firstPaidBuild = firstPaidBuild }
}

enum PaidAccess {
    /// The non-consumable full unlock.
    static let unlockProductID = "kr.donminzzi.focusStudy.unlock"
    /// The price-0 non-consumable "3-day Trial" (App Review Guideline 3.1.1).
    static let trialProductID = "kr.donminzzi.focusStudy.trial3d"
    static let trialLength: TimeInterval = 72 * 3600

    /// The build number as an integer. Apple's sample compares strings, where `"10" < "2"` is true.
    /// A value that is not an integer, such as the `"1.0"` of the sandbox and TestFlight, gives `nil`.
    static func buildNumber(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isASCII) else { return nil }
        return Int(trimmed).flatMap { $0 >= 0 ? $0 : nil }
    }
    /// A person whose first download is a build before the first paid build (decision 6). A value that is not an integer is not an earlier user.
    static func isEarlierUser(originalAppVersion: String, firstPaidBuild: Int) -> Bool {
        guard let build = buildNumber(originalAppVersion) else { return false }
        return build < firstPaidBuild
    }
    /// The trial grants access from its first purchase until 72 hours after it.
    static func trialEnd(_ facts: PaidAccessFacts, trial: PaidPurchase) -> Date {
        min(facts.trialStartedAt ?? trial.purchaseDate, trial.purchaseDate).addingTimeInterval(trialLength)
    }

    /// The rule. `facts` is `nil` before the first confirmed read.
    static func state(configuration: PaidAccessConfiguration, facts: PaidAccessFacts?, now: Date) -> PaidAccessState {
        guard configuration.enabled else { return .granted }
        guard let facts else { return .unknown }
        if let unlock = facts.unlock, !unlock.isRevoked { return .granted }
        if let trial = facts.trial, !trial.isRevoked, now < trialEnd(facts, trial: trial) { return .granted }
        // Only a person who was `locked` sees the paywall, and both products are not family-shareable, so a recorded purchase
        // that no longer grants is not an earlier user's: the trial end or the refund takes effect without the version.
        guard let version = facts.originalAppVersion else { return facts.unlock != nil || facts.trial != nil ? .locked : .unknown }
        return isEarlierUser(originalAppVersion: version, firstPaidBuild: configuration.firstPaidBuild) ? .granted : .locked
    }

    /// What one read of a product found.
    enum ProductRead: Equatable {
        /// A verified transaction, revoked or not.
        case transaction(PaidPurchase)
        /// No verified transaction: never bought, an unverified result or a failed read. It is not a signal and changes nothing.
        case noSignal
    }
    /// One refresh: `originalAppVersion` is `nil` when `AppTransaction.shared` threw or was unverified.
    struct Read: Equatable {
        var originalAppVersion: String?
        var unlock: ProductRead
        var trial: ProductRead
        /// The earliest `originalPurchaseDate` of every verified trial transaction, refunded ones included; `nil` when none was read.
        /// It keeps the first trial start when no cache holds it, such as after a reinstall or on a new device.
        var trialFirstPurchase: Date? = nil
    }
    /// A failed read never removes access: `noSignal` and a `nil` version change nothing.
    /// A verified transaction replaces the recorded one of its product, revoked or not. The caller runs its reads and merges one at a time,
    /// in the order they started (`PaidAccessStore`), so the later read always describes the later App Store state and no date comparison is needed.
    /// `trialStartedAt` keeps the earliest trial purchase date that any read found, so a second purchase of the trial product cannot restart the trial.
    /// Returns `nil` while nothing has been confirmed yet, so the state stays `unknown`.
    static func merge(cached: PaidAccessFacts?, read: Read, now: Date) -> PaidAccessFacts? {
        var facts = cached ?? PaidAccessFacts()
        var confirmed = false
        if let version = read.originalAppVersion { facts.originalAppVersion = version; confirmed = true }
        if case .transaction(let unlock) = read.unlock { facts.unlock = unlock; confirmed = true }
        if case .transaction(let trial) = read.trial {
            let earliest = min(trial.purchaseDate, read.trialFirstPurchase ?? trial.purchaseDate)
            facts.trialStartedAt = min(facts.trialStartedAt ?? facts.trial?.purchaseDate ?? earliest, earliest)
            facts.trial = trial
            confirmed = true
        }
        guard confirmed else { return cached }
        facts.confirmedAt = now
        return facts
    }
}

/// The last confirmed facts in the App Group container. The app is the only writer; the App Intents extension reads it at each Focus filter call.
/// The Monitor never reads it, because the gate applies only at session start.
struct PaidAccessCache {
    let file: URL
    init(container: URL) { file = container.appendingPathComponent("PaidAccess", isDirectory: true).appendingPathComponent("access.json") }
    /// A missing or unreadable file is no confirmed value.
    func load() -> PaidAccessFacts? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(PaidAccessFacts.self, from: data)
    }
    func save(_ facts: PaidAccessFacts) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(facts).write(to: file, options: .atomic)
    }
    func state(configuration: PaidAccessConfiguration, now: Date) -> PaidAccessState {
        // A gate that is off never reads the file.
        guard configuration.enabled else { return .granted }
        return PaidAccess.state(configuration: configuration, facts: load(), now: now)
    }
}
