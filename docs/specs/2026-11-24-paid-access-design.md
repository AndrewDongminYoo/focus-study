# Paid access design

Date: 2026-11-24.
Status: implemented under [issue #245](https://github.com/AndrewDongminYoo/focus-study/issues/245), gate off in Release until issue #255.
Authority: the [paid unlock decision](2026-11-24-paid-unlock-decision.md) (#219), decisions 2, 5, 6, 8 and 9, "Behavior at the edges" and "Left to the builder".
This document does not change that decision. It owns the rules of access to the paid features at session start.
The paywall design (#246, #247), the 순공 calendar, the weekly review and the share image are out of scope.

## Sources read

- Apple, "Supporting business model changes by using the app transaction" (read 2026-11-24).
  The app compares `AppTransaction.originalAppVersion` with a constant for the version in which the business model changed, and it also reads `Transaction.currentEntitlements`.
  On iOS the sample compares the two values as strings: `appTransaction.originalAppVersion < newBusinessModelVersion`.
  The article does not say whether the app transaction is available without a network connection.
- Apple, `AppTransaction.shared` (read 2026-11-24): the property "throws an error if the AppTransaction isn't available or if the user isn't authenticated with the App Store", and getting it "may require network connectivity".
- Apple, `Transaction.currentEntitlements` (read 2026-11-24): "Products that the App Store has refunded or revoked don't appear in the current entitlements."
- Apple, `Transaction.latest(for:)` (read 2026-11-24): the latest transaction for a product, or `nil` if the customer has not purchased it.

Consequence for this design: the first launch without a network connection can have no app transaction, and an absence in the current entitlements looks the same as "never bought".

## Products

| Product ID                        | Type           | Price | Name          |
| --------------------------------- | -------------- | ----- | ------------- |
| `kr.donminzzi.focusStudy.trial3d` | Non-consumable | 0     | "3-day Trial" |
| `kr.donminzzi.focusStudy.unlock`  | Non-consumable | Store | Full unlock   |

Issue #254 creates both items in App Store Connect with these IDs, with Family Sharing off (decision 9).
`Configuration/FocusStudy.storekit` holds the same two products for local StoreKit testing; the scheme's Run action uses it.

## Flag and threshold

Two build settings in `project.yml`, at project level, so that the app and the App Intents extension read one source:

- `PAID_UNLOCK_ENABLED`: `YES` in Debug builds for the simulator, `NO` in Debug builds for a device and `NO` in Release.
  A signed Debug build on a device uses the sandbox, where `originalAppVersion` is always `"1.0"`, so the gate would lock every focus start and every Focus filter start until the App Store Connect items of #254 exist; the device checks of other features need those starts.
  Issue #255 turns it on for the paid build.
- `PAID_UNLOCK_FIRST_BUILD`: the build number of the first paid build.
  The value `3` is a placeholder above build `2` of version 1.0.0; issue #255 sets the shipped value, and the decision document records it.

`Configuration/App-Info.plist` and `Configuration/Intents-Info.plist` pass them as `FocusPaidUnlockEnabled` and `FocusPaidUnlockFirstBuild`.
Each process reads its own Info.plist (`PaidAccessConfiguration(info:)`).
A missing value, a value other than `YES`, `TRUE` or `1`, or a threshold that is not an integer turns the gate off.
While the gate is off, every person has access, as in 1.0.0, and the app reads no StoreKit value.

## The rule

`Shared/PaidAccess.swift` holds the rule with no StoreKit or Screen Time import; `swift test` covers it (`CoreTests/PaidAccessTests.swift`).

Inputs: the configuration, the last confirmed facts (`PaidAccessFacts`: `originalAppVersion` or none, the unlock purchase or none, the trial purchase or none, each purchase with its `purchaseDate` and `revocationDate`, and `trialStartedAt`, the earliest trial `purchaseDate` that a read found), and the time now.
A purchase's `purchaseDate` is the transaction's `originalPurchaseDate`, because a restored transaction on a new device can carry a later `purchaseDate`.

Output, in this order:

1. Gate off: `granted`.
2. No confirmed facts: `unknown`.
3. An unlock with no `revocationDate`: `granted`.
4. A trial with no `revocationDate`, and now earlier than 72 hours after `trialStartedAt`: `granted`.
5. No `originalAppVersion`: `locked` when an unlock or a trial is recorded, else `unknown`.
   A recorded purchase that reaches this step is refunded or ended. Only a `locked` person sees the paywall, and both products are not family-shareable, so the person is not an earlier user, and the trial end or the refund takes effect also while `AppTransaction.shared` fails.
6. An earlier user: `granted`.
7. Else: `locked`.

A transaction with a `revocationDate` grants nothing.

### Earlier user: an integer compare

`originalAppVersion` is the original `CFBundleVersion` on iOS.
The rule parses it as a non-negative integer of ASCII digits and compares it with `PAID_UNLOCK_FIRST_BUILD` as integers.
It does not compare strings as Apple's sample does, because `"10" < "2"` is true for strings: build 10 would then read as an earlier user.

A value that does not parse as an integer is not an earlier user.
The sandbox and TestFlight return `"1.0"`, so App Review and TestFlight testers see the paywall and the trial, which is what App Review has to see.
A real download always has an integer build number, because every build of this app has one (`CURRENT_PROJECT_VERSION`).

## Facts, cache and confirmed reads

The cache stores the inputs, never the verdict: `PaidAccess/access.json` in the App Group container holds `PaidAccessFacts` as JSON.
Every reader applies the rule with its own clock and its own configuration, so a trial ends by time alone in every process, also when no refresh runs.
The app is the only writer. The App Intents extension reads the file at each Focus filter call. The Monitor never reads it.

A refresh reads three values: `AppTransaction.shared`, and for each product the verified entitlement in `Transaction.currentEntitlements`, else `Transaction.latest(for:)`.
`latest(for:)` is the read that carries a `revocationDate` after a refund, because the current entitlements drop a refunded product.
For the trial, a refresh also reads the earliest `originalPurchaseDate` of every verified trial transaction in `Transaction.all`, refunded ones included.
With no cache, such as after a reinstall or on a new device, the read of one transaction can be a second trial purchase after a refunded first one; the earliest date keeps the first start.
That `Transaction.all` keeps a refunded non-consumable transaction is `[UNCERTAIN]`; no device check covers it.

The merge (`PaidAccess.merge`):

- A verified app transaction replaces `originalAppVersion`. A throw or an unverified result changes nothing.
- A verified transaction of a product replaces that purchase, revoked or not. No transaction, an unverified result or a failed read changes nothing.
- `trialStartedAt` keeps the earliest trial `purchaseDate` of the cache, the read's trial transaction and the read's earliest trial purchase, so a second purchase of the trial product cannot restart the trial.
  It is a separate value: the trial purchase keeps its own `purchaseDate`, and a later trial purchase replaces it without moving the start.
- The merge compares no dates. A later merge replaces the recorded purchase in both directions: a refund locks, a reversed refund that a later read sees grants again, and a new purchase after a refund grants.
  This is correct only because the store merges one update at a time, in the order the updates started (see "Order of updates").
- A purchase that `product.purchase()` returns as verified is merged at once, so a refresh after it that reads nothing cannot leave the sheet locked.
- A read that confirms none of these values writes nothing; with no earlier facts the state stays `unknown`.

So a failed read never removes access, and a refund does: a refund is a verified transaction with a `revocationDate`, which is a signal and not a failed read.
A cache write that fails keeps the facts in memory for the app process; the extension then reads the older file.

## Order of updates

Every update of the facts takes one turn in a queue of the app's `PaidAccessStore`: a refresh, a transaction from `Transaction.updates`, the verified transaction of a purchase, and the refresh after a restore.
A turn runs its StoreKit reads, the merge and the cache write, and the next turn starts only after it ends.
So a merge never applies a read that started before an earlier merge, and the later merge always describes the later App Store state.
A refresh whose read started before a refund arrived merges first, and the refund, queued after it, stays.
`product.purchase()` and `AppStore.sync()` run outside the queue, so the purchase sheet never waits for a refresh; only their results take a turn.

This replaces date comparisons (`purchaseDate`, `signedDate`) between a cached and a read transaction, which each needed another exception for a new order of a refund, a reversal and a repurchase.
The queue rests on one assumption: after `Transaction.updates` delivers a transaction, `Transaction.currentEntitlements` and `Transaction.latest(for:)` already reflect it. `[UNCERTAIN]`: no device check or StoreKit configuration run covers it.

## StoreKit adapter

`App/PaidAccessStore.swift`, compiled into the app and `FocusSDKTests`, not into the App Intents extension.

- `PaidAccessStoreKit` is the protocol of the StoreKit calls; `SystemPaidAccessStoreKit` is the real one, and tests and UI fixtures replace it.
- At launch, `start()` starts the `Transaction.updates` listener, a refresh and the price load. The app also refreshes at each foreground.
  A gate that is off reads nothing.
- The listener finishes every verified transaction and queues it as an update (a refund or an approved Ask to Buy). It waits for that update's turn to end before it takes the next transaction, so the updates queue in the order StoreKit delivers them.
- `state` is synchronous: the rule on the facts in memory and `Date()`.
- Purchase and trial start buy the product with `Product.purchase()`.
  `.success` with a verified transaction finishes it and refreshes; an unverified one is a failure and grants nothing.
  `.pending` (Ask to Buy) grants nothing and shows "승인을 기다리고 있어요."; the approval arrives through `Transaction.updates`.
  `.userCancelled` shows nothing.
- Restore calls `AppStore.sync()` and refreshes; a restore with no access after it shows "복원할 구매가 없어요."
  The app has no account, so restore is the only way back to the unlock on a new device.
- The price is the store's `displayPrice`, never a constant in code.

## App gate

The gate applies only at session start, in `FocusModel`; `FocusServices.paidAccess` is a synchronous closure whose default is `granted`.

- `requestStart()`, after `canStart`: `locked` sets `paywallRequest` and returns no request, so no start is reserved.
  The access recovery tap also starts through `requestStart()`.
- `performStart()` reads it again after its refresh and its existing guard, because access can end between the tap and the section, such as a trial that ends.
  It never awaits StoreKit.
- `granted` and `unknown` start a session. `unknown` never opens the paywall, because decision 6 says that earlier users never see the purchase screen, and a first read can fail.
  Precedent: [access state](2026-11-11-access-state-design.md), where only a confirmed `denied` ends a session.
- `canStart`, `StartBlocker`, the launch route and every accessibility identifier stay the same. The start button stays enabled and shows no blocker; its tap opens the sheet.
- A running session continues when access ends by a trial end or a refund. No refresh or reconcile reads access.

## Temporary paywall sheet

`App/PaidAccessSheet.swift` is an unstyled system sheet that issue #247 replaces. `FocusView` opens it as the `.paywall` sheet when `paywallRequest` changes.

- Before the trial starts it states the trial length, what stops at its end (focus sessions, breaks and the Focus filter start; the everyday layer stays free) and the price of the full unlock (Guideline 3.1.1).
- Buttons: "3일 무료 체험 시작" (hidden after a trial was used, and disabled until the store price is on the sheet), "구매하기" with the store price, "구매 복원", and "닫기".
  While the price is not loaded, the price row shows "확인 중" and a "가격 다시 확인" button loads it again.
- The sheet closes when the state becomes `granted`; the person then taps the start action again. No session starts by itself after a purchase.

## Focus filter gate

- `FocusFilterRefusal.locked` is the refusal for paid access. `.access` keeps its meaning: Screen Time access.
- The handler passes `services.paidAccess() == .locked ? .locked : <length refusal>` as the engine's `inputRefusal`, an autoclosure that the engine evaluates inside the lock, after the stale, repeated and denied-access checks.
  So a trial that ends or a refund that the app records during the import, a lock-retry pause or the wait for the lock refuses the start.
  So the engine's order of a stale call, the activation marker and the denied-access refusal still applies.
  `.locked` comes before the missing-length `.error` of the same step.
- `unknown` does not refuse.
- In the App Intents extension, `Intents/FocusFilterEntry.swift` sets the closure to read the App Group cache at each call. Whether StoreKit runs in that extension is `[UNCERTAIN]`, and nothing depends on it.
  An unreadable App Group gives `unknown` while the gate is on.
- In the app process, the filter handler uses the same store as the screens.
- `FocusGuideView` shows "앱에서 체험을 시작하거나 구매하면 다음부터 시작할 수 있어요." for `.locked`.
- The Monitor never reads access, and its target does not change: `project.yml` excludes `Shared/PaidAccess.swift` from the Monitor's sources.

## Tests

- Host (`swift test`): `CoreTests/PaidAccessTests.swift` covers the rule, the integer compare with the `"10" < "5"` string trap, the values that are not integers, the 72-hour boundary, revocation, a reversed refund, the merge, the configuration keys and the cache file.
- SDK (`FocusSDKTests`):
  - `PaidAccessStoreTests` with a scripted StoreKit: purchase, pending, cancel, failures, restore, a refund from `Transaction.updates`, a stale refresh after that refund, trial expiry and no restart, a failed read that keeps the unlock, the earlier user, the unknown version and the gate off.
  - `PaidAccessStoreKitTests` with `SKTestSession` and `Configuration/FocusStudy.storekit`: price, purchase, restore, trial start and expiry, refund. They skip when the configuration's products do not load; see [Verification](#verification).
  - `PaidAccessGateTests`: the locked tap, access that ends before the start section, `unknown` and `granted` starts, a running session that continues.
  - `FocusFilterHandlerTests`: `.locked` refusal, `unknown` starts, a retry that reads `.locked` after a lock timeout, a running filter session continues.
  - Every existing fixture and test double keeps the default `granted`, so the earlier tests run unchanged.
- UI: `--paid-access locked` ([launch arguments](../notes/development-launch-arguments.md)); the start tap opens the sheet, the trial closes it, and the next tap starts a session. `--focus-filter-refusal locked` shows the refusal in the guide.

## Verification

The acceptance items stay separate, as the decision requires; the [paid access acceptance](../notes/paid-access-acceptance.md) note records each one.

1. Rule, store logic and gate in host, SDK and UI tests: see the note for the run.
2. A pass with the StoreKit test configuration: `[TOOL_FAILED]` on 2026-11-24, see the note.
3. A real purchase and a real restore: unverified, because they need the App Store Connect products of #254.

## Amendment of 2026-11-26

The [paywall design](2026-11-26-paywall-design.md) (issue #246) changes two rules of this document; the sections above keep their original text as the record of what was approved on 2026-11-24.

- [App gate](#app-gate): with access `locked`, `requestStart()` still reserves no start in the engine, but the screen model keeps the start request for the paywall that the start action opens.
- [Temporary paywall sheet](#temporary-paywall-sheet): "No session starts by itself after a purchase" no longer holds. A trial or a purchase confirmed inside a paywall opened by the start action continues that start once; a restore, a pending purchase approved later, a closed or cancelled sheet and any access from outside the sheet start nothing. The paywall design owns the full rule.
