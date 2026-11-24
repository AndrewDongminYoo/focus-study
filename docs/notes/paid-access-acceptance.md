# Paid access acceptance

The acceptance record of the [paid access design](../specs/2026-11-24-paid-access-design.md) (#245).
Each item stays separate: a pass of one item is no evidence for another.

## 1. Rule, store logic and gate: tests, 2026-11-24

- `swift test`: `CoreTests/PaidAccessTests.swift` passed with the rest of the host suites.
- `FocusSDKTests`: `PaidAccessStoreTests` (scripted StoreKit), `PaidAccessGateTests` and the new `FocusFilterHandlerTests` cases passed on the iOS 26.5 simulator.
- `FocusUITests`: `testLockedStartOpensThePaywallSheet` and `testLockedRefusalShowsInTheGuide` passed.

In the `FocusSDKTests` run, 281 tests ran: 276 passed and 5 were skipped.
The 5 skipped tests are all of `PaidAccessStoreKitTests`, the only tests that use real StoreKit with `Configuration/FocusStudy.storekit` (item 2).
So purchase, restore, trial expiry and refund through real StoreKit have no passing test; only the scripted fakes passed.

These runs prove the rule and the app's use of it with synthetic StoreKit values. They prove nothing about StoreKit's own behavior.

## 2. StoreKit test configuration: `[TOOL_FAILED]`, 2026-11-24

`PaidAccessStoreKitTests` ran `SKTestSession` with `Configuration/FocusStudy.storekit` and skipped, because `Product.products(for:)` returned no product.
Every write of the session failed with this log line, from the first `SKTestSession` call:

```log
[SKTestSession] Error saving configuration file: Error Domain=SKInternalErrorDomain Code=3 "(null)"
```

Setups tried, each with the same error:

1. `FocusSDKTests`, which has no host app (the line names `com.apple.dt.xctest.tool`).
2. A temporary unit-test target hosted by the app (the line names `kr.donminzzi.focusStudy`), unsigned. The target was removed after the run.
3. The same hosted target, ad-hoc signed for the simulator.
4. The configuration with the `USA` storefront and `en_US` locale, without the app policies.
5. The configuration as version 3 with an 8-character identifier.
6. `FocusSDKTests` built with ad-hoc simulator signing (`CODE_SIGN_IDENTITY=-`) instead of `CODE_SIGNING_ALLOWED=NO`, run with `-only-testing:FocusSDKTests/PaidAccessStoreKitTests`.

Environment: Xcode 26.6 (17F113), iOS Simulator SDK 26.5, runtime iOS 26.5 (23F77), simulator `FFC1A524-3E57-4417-861F-203E0FD46BF2`.
Whether `SKTestSession` needs an app host in this setup is `[UNCERTAIN]`, because it ran in neither.
The configuration file is version 4 with the `KOR` storefront; its format is not checked by a passing run.

Only real StoreKit can show these points, which the design depends on:

- `Transaction.currentEntitlements` drops a refunded product.
- `Transaction.latest(for:)` carries the `revocationDate` of a refunded product.
- A restored trial transaction on a new device carries the first purchase as its `originalPurchaseDate`, which the adapter reads, so `trialStartedAt` stays the first purchase date.
- `Transaction.updates` delivers a refund that happened while the app was not running.

## 3. Real purchase and restore: unverified

A real purchase, a real trial start, a restore on a second device and a refund need the App Store Connect items of #254 and a sandbox or TestFlight account.
None of them has run.
In the sandbox and TestFlight `originalAppVersion` is `"1.0"`, so these runs show the paywall path, not the earlier-user path.
The earlier-user path of a real download stays unverified until a 1.0.0 install updates to the paid build.
