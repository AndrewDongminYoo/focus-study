# Paid unlock decision

Date: 2026-11-24.
Status: approved on 2026-11-24, not yet implemented.
Source: [issue #219](https://github.com/AndrewDongminYoo/focus-study/issues/219), under the parent issue #214.
This document changes no code.
The implementation is later work under the follow-up issues that [Follow-up work](#follow-up-work) lists, and it starts after this decision is approved.

## Intent

Version 1.0.0 is free and has no in-app purchase.
This decision makes 온:공 a study app that a student pays for once.
The everyday blocking layer stays free for every user.
Focus sessions and the new study-record features become one paid unlock, after a free 3-day trial.

Reason for the payment, in one sentence: the unlock opens the tools that measure, collect and look back on 순공 time (time spent in focused study), not a decoration on top of a free app.

## Contract

Decided on 2026-11-24:

1. **Free for every user**: the everyday layer and everything it needs, which is Screen Time authorization, app and website selection, the everyday settings screen, the shield and the shield action.
2. **Paid unlock**: one non-consumable in-app purchase opens all of these:
   - Focus sessions: the focus timer, breaks, the Focus filter start, and the Live Activity of a session.
   - The 순공 calendar: completed focus time by local day, across months.
   - The weekly review: a look back at one week of completed focus time.
   - The share image: an image of the 순공 calendar that the person sends out through the system share sheet.
3. **No subscription.** The purchase opens the paid features fully and for good.
4. **Price**: KRW 14,000 on the Korea storefront.
   If App Store Connect has no price point of exactly KRW 14,000, use the nearest price point and record it in this document.
5. **Trial**: a free 3-day trial, as App Review Guideline 3.1.1 permits for non-subscription apps.
   - The trial is a separate non-consumable in-app purchase at price 0, named "3-day Trial" by the 3.1.1 naming convention.
   - The person starts the trial with an explicit action.
   - Before the trial starts, the app shows the trial duration, the features that stop at its end, and the price of the full unlock (3.1.1).
   - The trial covers every paid feature.
6. **Earlier users keep everything free.**
   A person whose first download is a build before the first paid build gets every paid feature, including the features that this decision adds, without a trial and without a purchase.
   - The app reads this from `AppTransaction.originalAppVersion`.
     On iOS this value is the original `CFBundleVersion` (the build number), not the marketing version.
   - Version 1.0.0 is build `2` (`CURRENT_PROJECT_VERSION: "2"` in `project.yml`).
   - The paid build number is fixed when the paid build ships, and it is recorded in this document.
     Every later build number must be larger than it.
   - These users never see the trial offer or the purchase screen.
7. **Positioning**: a study app in the words that students use (순공, 공부 시간).
   The baseline exclusions stay: no ranking, no comparison with friends, no friend presence, no social feed, no account and no backend.
   The share image goes out only by the person's own share action, and the app sends no data off the device by itself.
8. **One paid build**: the first paid build ships the purchase, the trial, the paywall, the 순공 calendar, the weekly review and the share image together.
   Updates before it ship none of these.
9. **No Family Sharing**: Family Sharing stays off for both in-app purchase items, and it is not planned.
   Apple's article "Supporting Family Sharing in your app" (read 2026-11-24) says: "After you enable Family Sharing for an Apple In-App Purchase, you can't turn it off."
10. **Terms**: in AGENTS.md, the excluded "rewards" include "unlocks".
    That word means an unlock earned by use, such as a badge or a streak prize.
    The paid unlock of this document is a purchase and is not a reward.

## App Review

Guideline 4.10 forbids charging for Screen Time APIs as such.
The everyday layer uses the same Screen Time APIs and stays free, so the basic blocking is free for every user.
The paid unlock charges for features that the app builds itself: the focus timer and its break rules, the Focus filter start, and the study-record features.

Precedent: Opal keeps app blocking and timers free and sells Hard Mode, more rules and history in Pro, including a one-time Lifetime plan ([Opal pricing](https://opalapp.com/pricing), read 2026-11-24).
That precedent is partial, because Opal does not lock its basic timers.
Whether App Review accepts a paid focus session is `[UNCERTAIN]`.
If App Review rejects it, this decision is made again before any other change.

The current review note in [App Store listing](../notes/app-store-listing.md) says "The Screen Time features are free. The app has no in-app purchase in this version."
The first paid build replaces that note with text that states these items:

- The everyday blocking layer, which uses the Screen Time APIs, stays free for every user.
- The one-time purchase opens the focus timer sessions, the 순공 calendar, the weekly review and the share image, which the app builds itself.
- The 3-day trial is a price-0 non-consumable item named "3-day Trial".
- Users who downloaded a build before the paid build keep every feature free.

## Behavior at the edges

These decisions were proposed while this document was written, and they are approved with it:

- (Writing session's call) A session that runs when the trial ends continues to its normal end.
  The gate applies only when a session starts.
- (Writing session's call) When a Focus filter turns on and the person has no access to the paid features, no session starts, and the app records a refusal in the same way as other Focus filter refusals.
- (Writing session's call) The today summary, the today history sheet, the streak line and the home screen widget stay free.
  They exist in 1.0.0, and they show only what the person already recorded.
- (Writing session's call) After the trial ends, the session history stays on the device.
  The 순공 calendar, the weekly review and the share image show it again after a purchase.
- (Writing session's call) The app still opens on the focus-start screen for a person without access, because the main flow stays the focus-start screen.
  The start action opens the paywall instead of a session.
  The launch route and the accessibility identifiers of that screen stay the same.
- (Writing session's call) A refund removes access.
  The app reads `revocationDate` from the current entitlements and from `Transaction.updates`.
  A refund is a valid signal, not a failed read, so the rule "a failed read never removes access" does not apply to it.
  A session that runs at that time continues to its normal end.

## Follow-up work

Each item is its own issue, with its own design, under the parent issue #214:

1. Access to the paid features: StoreKit 2 purchase, restore, the 3-day trial, the earlier-user check, and the gate at session start, in the app and in the App Intents extension.
2. The paywall and the trial offer screens, with the copy.
3. The 순공 calendar.
4. The weekly review.
5. The share image.
6. Store work: the in-app purchase items in App Store Connect, the review note, the App Store listing text and the [store privacy declarations](../notes/store-privacy-declarations.md).

Item 1 comes first.
Items 3 to 5 can start in any order after it.
All six items ship in the same paid build (decision 8), so no item reaches the App Store alone.

## Left to the builder

- How the App Intents extension and the Monitor read access to the paid features.
  The Monitor never decides access, because the gate applies only at session start.
- Whether `AppTransaction.shared` and `Transaction.currentEntitlements` give a result without a network connection on the first launch `[UNCERTAIN]`.
  Read Apple's article "Supporting business model changes by using the app transaction" before the design of item 1.
- In the sandbox, `originalAppVersion` is always `1.0`.
  Tests need a way to inject the earlier-user result and the purchase state, behind `#if DEBUG` like the other fixtures.
- The layout and copy of every new screen.

Lessons from earlier one-time unlocks, for the design of item 1:

- Show the price that the store returns for the product, never a price constant in code.
- An entitlement read that fails is an error state, not "free".
  It never removes access that the person already has.
- The app has no account, so "Restore Purchases" is the only way to get the unlock back on a new device.
  The paywall shows it.
- A pass in a StoreKit test configuration or the sandbox does not prove a real purchase or a restore.
  Keep those as separate acceptance items.

## Evidence

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), read 2026-11-24:
  - 3.1.1: "Non-subscription apps may offer a free time-based trial period before presenting a full unlock option by setting up a Non-Consumable IAP item at Price Tier 0 that follows the naming convention: “XX-day Trial.”"
  - 4.10: "You may not monetize built-in capabilities provided by the hardware or operating system, such as Push Notifications, the camera, or the gyroscope; or Apple services and technologies, such as Apple Music access, iCloud storage, or Screen Time APIs."
- [`AppTransaction.originalAppVersion`](https://developer.apple.com/documentation/storekit/apptransaction/originalappversion), read 2026-11-24: the value "remains constant and doesn’t change when the customer upgrades the app", holds "the original value of the CFBundleVersion for apps running on all other platforms" than macOS, and is "always 1.0" in the sandbox.
- Opal ([pricing page](https://opalapp.com/pricing) and [help article](https://help.opalapp.com/article/how-much-does-opal-pro-cost-and-what-does-it-give-me)), read 2026-11-24: the pricing page lists App Blocking and "Basic Timers & Soundscapes" in the free tier, and the help article lists "unlimited access to immediate Timers" as free; Pro lists Hard Mode ("No way out. You can't turn Opal off."); the Lifetime plan is "$399/forever" as a "One Time Payment".
- [Device matrix](../notes/screen-time-device-matrix.md), 2026-11-15: after a force-quit during a session, every app of the focus selection stayed shielded.
  Blocking does not need the app process, so a "works when the app is off" mode cannot separate a paid mode from the free one.
- The source of `App/`, `Shared/` and `project.yml` has no StoreKit use today.
