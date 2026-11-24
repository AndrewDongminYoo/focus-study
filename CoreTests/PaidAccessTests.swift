import XCTest
@testable import FocusCore

final class PaidAccessTests: XCTestCase {
    private let on = PaidAccessConfiguration(enabled: true, firstPaidBuild: 5)
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func facts(version: String? = nil, unlock: PaidPurchase? = nil, trial: PaidPurchase? = nil) -> PaidAccessFacts {
        PaidAccessFacts(originalAppVersion: version, unlock: unlock, trial: trial, confirmedAt: t0)
    }

    func testGateOffGrantsEverything() {
        for value in [nil, facts(), facts(version: "99")] {
            XCTAssertEqual(PaidAccess.state(configuration: .disabled, facts: value, now: t0), .granted)
        }
    }
    func testNoConfirmedValueIsUnknown() {
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: nil, now: t0), .unknown)
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: facts(), now: t0), .unknown)
    }
    /// Apple's sample compares strings, and `"10" < "5"` is true as strings: build 10 would read as an earlier user.
    func testBuildNumbersCompareAsIntegers() {
        XCTAssertTrue("10" < "5", "the string trap that the rule avoids")
        XCTAssertFalse(PaidAccess.isEarlierUser(originalAppVersion: "10", firstPaidBuild: 5))
        XCTAssertTrue(PaidAccess.isEarlierUser(originalAppVersion: "2", firstPaidBuild: 5))
        XCTAssertTrue(PaidAccess.isEarlierUser(originalAppVersion: "4", firstPaidBuild: 5))
        XCTAssertFalse(PaidAccess.isEarlierUser(originalAppVersion: "5", firstPaidBuild: 5))
        XCTAssertTrue(PaidAccess.isEarlierUser(originalAppVersion: "2", firstPaidBuild: 10))
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: facts(version: "10"), now: t0), .locked)
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: facts(version: "2"), now: t0), .granted)
    }
    /// The sandbox and TestFlight return `"1.0"`, which is not an integer: not an earlier user, so App Review and TestFlight see the paywall.
    func testNonIntegerVersionIsNotAnEarlierUser() {
        for value in ["1.0", "", " ", "abc", "-1", "２"] {
            XCTAssertFalse(PaidAccess.isEarlierUser(originalAppVersion: value, firstPaidBuild: 5), value)
            XCTAssertEqual(PaidAccess.state(configuration: on, facts: facts(version: value), now: t0), .locked, value)
        }
        XCTAssertEqual(PaidAccess.buildNumber(" 3 "), 3)
    }
    func testUnlockGrantsUntilRevoked() {
        let unlock = PaidPurchase(purchaseDate: t0)
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: facts(version: "99", unlock: unlock), now: t0), .granted)
        // An unknown version does not hide a confirmed unlock.
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: facts(unlock: unlock), now: t0), .granted)
        let refunded = PaidPurchase(purchaseDate: t0, revocationDate: t0.addingTimeInterval(60))
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: facts(version: "99", unlock: refunded), now: t0), .locked)
        // A refunded earlier user keeps access through the earlier-user rule.
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: facts(version: "2", unlock: refunded), now: t0), .granted)
        // A refund takes effect also while the version is unknown; with no purchase at all the state stays `unknown`.
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: facts(unlock: refunded), now: t0), .locked)
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: facts(), now: t0), .unknown)
    }
    func testTrialEnds72HoursAfterItsPurchaseDate() {
        let trial = PaidPurchase(purchaseDate: t0)
        let value = facts(version: "99", trial: trial)
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: value, now: t0), .granted)
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: value, now: t0.addingTimeInterval(72 * 3600 - 1)), .granted)
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: value, now: t0.addingTimeInterval(72 * 3600)), .locked)
        // An ended trial takes effect also while the version is unknown: only a `locked` person can have bought the trial.
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: facts(trial: trial), now: t0.addingTimeInterval(72 * 3600)), .locked)
        let revoked = PaidPurchase(purchaseDate: t0, revocationDate: t0.addingTimeInterval(10))
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: facts(version: "99", trial: revoked), now: t0.addingTimeInterval(20)), .locked)
    }
    func testMergeKeepsConfirmedValuesOnAFailedRead() {
        let cached = facts(version: "99", unlock: PaidPurchase(purchaseDate: t0))
        let failed = PaidAccess.Read(originalAppVersion: nil, unlock: .noSignal, trial: .noSignal)
        XCTAssertEqual(PaidAccess.merge(cached: cached, read: failed, now: t0.addingTimeInterval(5)), cached)
        XCTAssertNil(PaidAccess.merge(cached: nil, read: failed, now: t0))
    }
    func testMergeAppliesARefundAndKeepsTheFirstTrialDate() throws {
        let cached = facts(version: "99", unlock: PaidPurchase(purchaseDate: t0), trial: PaidPurchase(purchaseDate: t0))
        let later = t0.addingTimeInterval(3600)
        let read = PaidAccess.Read(originalAppVersion: nil, unlock: .transaction(PaidPurchase(purchaseDate: t0, revocationDate: later)),
                                   trial: .transaction(PaidPurchase(purchaseDate: later)))
        let merged = try XCTUnwrap(PaidAccess.merge(cached: cached, read: read, now: later))
        XCTAssertEqual(merged.originalAppVersion, "99")
        XCTAssertEqual(merged.unlock?.revocationDate, later)
        XCTAssertEqual(merged.trial?.purchaseDate, later)
        XCTAssertEqual(merged.trialStartedAt, t0)
        XCTAssertEqual(merged.confirmedAt, later)
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: merged, now: t0.addingTimeInterval(PaidAccess.trialLength)), .locked)
    }
    /// With no cache, the earliest trial purchase of the read sets the start, also when the read's trial transaction is a later purchase.
    func testMergeWithoutACacheTakesTheFirstTrialPurchase() throws {
        let second = t0.addingTimeInterval(PaidAccess.trialLength + 3600)
        let read = PaidAccess.Read(originalAppVersion: "99", unlock: .noSignal, trial: .transaction(PaidPurchase(purchaseDate: second)), trialFirstPurchase: t0)
        let merged = try XCTUnwrap(PaidAccess.merge(cached: nil, read: read, now: second))
        XCTAssertEqual(merged.trialStartedAt, t0)
        XCTAssertEqual(merged.trial?.purchaseDate, second)
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: merged, now: second.addingTimeInterval(10)), .locked)
    }
    /// The store merges one read at a time in the order the reads started, so the later merge wins in both directions:
    /// a refund locks, a reversed refund grants again, and a new purchase after a refund grants. The trial start never moves later.
    func testLaterMergeReplacesTheRecordedTransaction() throws {
        let refunded = t0.addingTimeInterval(60), reversed = t0.addingTimeInterval(600), repurchased = t0.addingTimeInterval(1200)
        func unlockRead(_ purchase: PaidPurchase) -> PaidAccess.Read { PaidAccess.Read(originalAppVersion: nil, unlock: .transaction(purchase), trial: .noSignal) }
        var value = facts(version: "99", unlock: PaidPurchase(purchaseDate: t0))
        value = try XCTUnwrap(PaidAccess.merge(cached: value, read: unlockRead(PaidPurchase(purchaseDate: t0, revocationDate: refunded)), now: refunded))
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: value, now: refunded), .locked)
        value = try XCTUnwrap(PaidAccess.merge(cached: value, read: unlockRead(PaidPurchase(purchaseDate: t0)), now: reversed))
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: value, now: reversed), .granted)
        value = try XCTUnwrap(PaidAccess.merge(cached: value, read: unlockRead(PaidPurchase(purchaseDate: t0, revocationDate: reversed)), now: reversed))
        value = try XCTUnwrap(PaidAccess.merge(cached: value, read: unlockRead(PaidPurchase(purchaseDate: repurchased)), now: repurchased))
        XCTAssertEqual(value.unlock, PaidPurchase(purchaseDate: repurchased))
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: value, now: repurchased), .granted)
        // A later trial purchase replaces the recorded trial, but the trial still ends 72 hours after the first one.
        var trial = try XCTUnwrap(PaidAccess.merge(cached: nil, read: PaidAccess.Read(originalAppVersion: "99", unlock: .noSignal, trial: .transaction(PaidPurchase(purchaseDate: t0))), now: t0))
        let second = t0.addingTimeInterval(3600)
        trial = try XCTUnwrap(PaidAccess.merge(cached: trial, read: PaidAccess.Read(originalAppVersion: nil, unlock: .noSignal, trial: .transaction(PaidPurchase(purchaseDate: second))), now: second))
        XCTAssertEqual(trial.trial, PaidPurchase(purchaseDate: second))
        XCTAssertEqual(trial.trialStartedAt, t0)
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: trial, now: second.addingTimeInterval(10)), .granted)
        XCTAssertEqual(PaidAccess.state(configuration: on, facts: trial, now: t0.addingTimeInterval(PaidAccess.trialLength)), .locked)
    }
    func testConfigurationReadsTheInfoKeys() {
        XCTAssertEqual(PaidAccessConfiguration(info: ["FocusPaidUnlockEnabled": "YES", "FocusPaidUnlockFirstBuild": "7"]), PaidAccessConfiguration(enabled: true, firstPaidBuild: 7))
        XCTAssertEqual(PaidAccessConfiguration(info: ["FocusPaidUnlockEnabled": "NO", "FocusPaidUnlockFirstBuild": "7"]), .disabled)
        XCTAssertEqual(PaidAccessConfiguration(info: ["FocusPaidUnlockEnabled": "YES"]), .disabled)
        XCTAssertEqual(PaidAccessConfiguration(info: ["FocusPaidUnlockEnabled": "YES", "FocusPaidUnlockFirstBuild": "$(PAID_UNLOCK_FIRST_BUILD)"]), .disabled)
        XCTAssertEqual(PaidAccessConfiguration(info: nil), .disabled)
    }
    func testCacheRoundTripAndUnreadableFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PaidAccessTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PaidAccessCache(container: directory)
        XCTAssertNil(cache.load())
        XCTAssertEqual(cache.state(configuration: on, now: t0), .unknown)
        let value = facts(version: "99", trial: PaidPurchase(purchaseDate: t0))
        try cache.save(value)
        XCTAssertEqual(cache.load(), value)
        XCTAssertEqual(cache.state(configuration: on, now: t0), .granted)
        XCTAssertEqual(cache.state(configuration: on, now: t0.addingTimeInterval(PaidAccess.trialLength)), .locked)
        try Data("not json".utf8).write(to: cache.file)
        XCTAssertNil(cache.load())
        XCTAssertEqual(cache.state(configuration: on, now: t0), .unknown)
    }
}
