# Focus filter in an App Intents extension, and a session that follows the Focus

Date: 2026-11-16.
Status: design for approval. Issue #152, under #54.
This document changes [the M4 design](2026-11-01-m4-focus-filter-design.md), [the M1 design](2026-10-31-m1-launch-flow-design.md), [the 2026-10-26 design](2026-10-26-focus-study-design.md), [the Live Activity decision](2026-11-06-live-activity-decision.md) and [the home widget design](2026-11-13-home-widget-design.md) only where it says so.
Where they differ, this document is the newer decision.
The implementation PR adds dated reconciliation sections to those documents (see [Superseded lines](#superseded-lines)).

## Problem

On iOS 27.0.1 the Focus filter runs only while the app process is running.
With the app suspended or closed, `donotdisturbd` logs `No extension for action in app; background update unavailable. ... action=FocusStudyFilter`, and `perform()` never runs (device record of 2026-11-15 in #152).
So a Focus with the session option starts no session unless the app is open, which defeats M4: the person turns on one Focus and expects the restrictions without opening the app.

A second gap is about time.
M4 starts one normal session of the focus length (25 to 50 minutes).
When the Focus stays on longer, the session ends and the restrictions lift while the Focus is still on.
The person expects the restrictions to stay for as long as the Focus stays on, as the Focus filter of a shipped Screen Time blocking app does ("Start an endless ... timer when this Focus mode is active. The timer stops when the Focus mode ends.", seen on the same iPhone on 2026-11-15).

## Decisions by me (2026-11-16)

1. The filter runs in an App Intents extension, so a Focus starts a session without the app. The extension target needs its own App ID, profile, App Group and Family Controls entitlement; that signing change gets a separate explicit approval before implementation.
2. A Focus with the option on still starts one normal session (M4 decision 1 stays). The session continues until the Focus turns off, also after the focus length. History records the time that was really focused. Breaks follow the M2 rules unchanged: at most 3 in the whole session.
3. "집중 종료" in the app ends the session and lifts its restrictions at once, also while the Focus is on. No new session starts until the Focus turns off and on again (the M4 activation marker rule).
4. The focus selection and the focus length move from the app's private storage to the App Group, as one source. No private copy remains. This is a privacy boundary change, in the same way as the everyday selection file `everyday-layer.json`.

## Decisions by Claude (I can change them)

### Terms

- An **open session** is a session with `origin == focusFilter` whose stored `activation` equals the stored `filterActivation` of the envelope. That is: the Focus activation that started it has not ended, as far as the stored state knows.
- The **base length** is the focus length at the start of an open session. It is stored as `baseLength`.
- A **rollover** moves the focus end of an open session that reached it to one base length later.

### The session that follows the Focus

1. An open session keeps every M2 rule. Only its end by time changes: when its focus end comes in `active`, it does not end as `.expired`; a rollover adds one base length to `expiresAt` and registers the new end.
2. A rollover runs only in `active`, only when the focus end is not after the deadline. A deadline that comes first still ends the session as `.deadlineMissed`, as today. A rollover moves the deadline as well, because the deadline is computed from `expiresAt`.
3. The rollover chunk is the base length, never shorter, so every registered focus interval is at least 25 minutes, above the 15-minute system minimum of a DeviceActivity interval. One long interval for the whole Focus was rejected: no checked document states a maximum interval length (see [Apple documentation](#apple-documentation-checked-2026-11-16)), and a rollover reuses the registration that the device already proved.
4. When the Focus turns off, an open session ends with this reason, in this order:
   - `.authorizationRevoked` with a `denied` access read (the [access-state design](2026-11-11-access-state-design.md));
   - `.deadlineMissed` when the deadline has passed (`timedEnd`); the timed `.expired` never applies here, because the session is still treated as open in this end (see [Filter end](#filter-end-focus-off));
   - `.expired` when the open focused time (decision 5) is at least the base length: the session counts as completed;
   - else `.earlyExit`, as in M4.
5. The **open focused time** at `end` is `end - startedAt - pausedSeconds - openPause`, not capped at `length`. `focused(at:)` caps at `length`, so it would drop the time after a lost rollover, while the restrictions stayed on. An open session that ends as `.expired` stores `expiresAt = startedAt + open focused time` in its `ending` save, so `length` is the focused time. This applies to every end of a session that was open at the start of the section: the Focus off call, the activation check and "집중 종료". History, the today summary, the widget snapshot and the streak then read the real focused time with no change to `SessionRecord` (`focusDuration = expiresAt - startedAt`). This is the M2 meaning of `expiresAt`: start plus focus time, never moved by breaks.
6. A session that is no longer open (its activation was cleared, see [Activation check](#activation-check)) ends by time at its current focus end as `.expired`, with the same `expiresAt` rule. So it ends at most one chunk later, never at once in the middle of a chunk.
7. A manual session never rolls over, also while a Focus with this filter is on.
8. One bound on the session, not on the Focus: a rollover runs only while the new `length` stays at or below `TodaySnapshot.maxFocusSeconds` (one week), the bound that [Length validation](#length-validation) and the widget snapshot already use. At that bound the session ends by time at its last focus end as `.expired`, as in decision 6, and the open focused time of decision 5 is capped at the same bound. No smaller limit: the person can always end the session with "집중 종료" (decision 3), a lost off call is repaired by the activation check when the app opens, and a shorter limit would lift the restrictions while the Focus is still on, against decision 2.

### Where the filter runs

9. The intent type `FocusStudyFilter`, the filter handler and the lock sections it calls are compiled into the app target and into a new App Intents extension target, `FocusStudyIntents` (bundle identifier `kr.donminzzi.focusStudy.intents`).
   On 2026-11-15 the system used the running app for an off call ("Application is running; will use for action FocusStudyFilter") and asked for an extension when the app was not running ("will use extension if available"), so both processes can receive a call.
   Both run the same handler on the same App Group state under the same `control.lock`, so the process that runs a call does not change the result.
   `[UNCERTAIN]` Whether the system accepts the same `SetFocusFilterIntent` type in the app and in an extension, and which one it picks while the app runs. Device step 1 records it. If the build or the system refuses the duplicate, the type moves to the extension only, and the app reads `current` through a shared file of the type that has no `perform()` side effect; the builder raises that change before making it.
10. The extension compiles `Shared/`, `Integration/` (Screen Time adapters and App Group files), the filter handler, the history store types and the today rules. It compiles no SwiftUI view and nothing of `Report/`.
11. The extension has these entitlements: the App Group `group.kr.donminzzi.focusStudy` and `com.apple.developer.family-controls`. No other capability. The Family Controls distribution entitlement is requested per bundle identifier before an App Store release (see the [privacy and distribution review](../notes/screen-time-device-matrix.md) of #17); a development build does not need it.

### Data that moves to the App Group

12. The focus selection moves from `Application Support/PrivateSelection/selection.json` (app container) to `FocusSelection/selection.json` in the App Group container, with the same encoding and the same atomic replace.
13. The focus length moves from the app's `UserDefaults.standard` to `UserDefaults(suiteName: "group.kr.donminzzi.focusStudy")`, with the same key and the same validation (`FocusLength`).
14. The last filter refusal and the pending completion card move to the same App Group `UserDefaults`, with the same keys, because the extension now writes them. They hold a reason and a time, and a session id and a length; no token.
15. The onboarding flag and every other value stay in the app.
16. Migration runs once in the app, on launch, before the first read of either value, with the focus length first: write the effective focus length to the App Group (the stored value, or `FocusLength.defaultMinutes` when none is stored, as `FocusSettings` reads it today), read it back, then remove the old key; then copy the private selection file to the App Group path with an atomic replace, read it back and compare, then delete the private file. So an App Group selection always has an App Group length next to it. A failure at any point leaves the old value in place and retries on the next launch. The app reads the App Group value when it exists, else the old value, so a person never loses a selection.
17. Until the app has run the migration once, the extension finds no App Group selection and refuses with `selection`. The settings sheet shows that refusal as for any refusal. The first launch after the update repairs it.
18. Data boundary after this change: the App Group holds the focus selection tokens, the everyday selection tokens, the session-scoped break copy (M2), the control state, the marker files, the history store and the today snapshot. The Report extension still has no App Group access. The widget still reads only `TodaySnapshot/today.json`. The Monitor may read the focus selection file, but this design gives it no reason to; the re-block of a break keeps using the break copy.

### Access read in the extension

19. A fresh extension process is expected to read `notDetermined` until it calls `requestAuthorization`: the Monitor process read `notDetermined` with access approved (#115), and a revocation in Settings also read `notDetermined` (#118). So the access value in the extension is usually `unknown`.
20. The filter start treats `unknown` as "not proven denied": it does not refuse with `access`, and the two access reads inside the M1 start steps (after the registration and after the shield, `SessionControl.begin`) accept `unknown` as well. They still fail on `denied`, and the registration check (`isRegistered`) and the shield check (`matches`) stay as they are, so the start proves its restrictions without proving access. If shields or registration fail, the M1 rollback records "시작 실패" (`.startFailed`). Only `denied` refuses with `access`. This changes the access-state rule "an action that needs access refuses on `unknown`" for the filter start only. The reason: a refusal on `unknown` would refuse every background start.
    `[UNCERTAIN]` Whether `requestAuthorization(for: .individual)` in the extension returns at once without UI for an approved app. The builder may call it before the read only if a device check shows no prompt; otherwise the extension does not call it.

### App screens

21. The app's screens refresh on the next `didBecomeActive`, as today. The handler also posts a Darwin notification `kr.donminzzi.focusStudy.control-changed` after a call that changed the stored state, and the app refreshes on it while it runs. Neither carries data.
22. The timer screen of an open session shows a countdown until the base length, as today. After the base length it shows the focused time counting up, with a short line that the session continues while the Focus is on. The break controls and "집중 종료" stay. Copy and layout go through the visual approval gate (light, dark, largest text).
23. The completion card shows the focused time of an `.expired` open session, through the pending card when the filter path imported it.

### Live Activity

24. An extension cannot start a Live Activity: ActivityKit starts one only from the app in the foreground (`[UNCERTAIN]` for an App Intents extension; device step 9). So a session that the extension starts has no Live Activity until the app comes to the foreground, where the existing coordinator starts it from the stored state.
25. For an open session after its base length, the Live Activity shows the focused time counting up from its last confirmed value, with no planned end. A rollover is not a planned end and is never displayed as one. The projection checks the session with the rule of [Length validation](#length-validation), not with `FocusLength.isAllowed` alone. Until the base length, the projection of the [Live Activity decision](2026-11-06-live-activity-decision.md) applies unchanged.

### Home widget

26. The extension does not write `TodaySnapshot/today.json`; the app stays the only writer. A session that the extension ends appears in the widget after the next app refresh, as a session that the Monitor ends does today.

## Stored values

| Value            | Where                              | Type            | Meaning                                                                                                    |
| ---------------- | ---------------------------------- | --------------- | ---------------------------------------------------------------------------------------------------------- |
| `activation`     | `ControlSession` in `control.json` | `UUID?`         | The `filterActivation` that started this session. Set once in the save of `preparing`; `nil` for `manual`. |
| `baseLength`     | `ControlSession` in `control.json` | `TimeInterval?` | The focus length at the start of a `focusFilter` session; `nil` for `manual` and for earlier sessions.     |
| Focus selection  | App Group `FocusSelection/`        | file            | Moved from the app container (decision 12).                                                                |
| Focus length     | App Group `UserDefaults`           | `Int` minutes   | Moved from `UserDefaults.standard` (decision 13).                                                          |
| Refusal and card | App Group `UserDefaults`           | as in M4        | Moved from `UserDefaults.standard` (decision 14).                                                          |

- `ControlEnvelope.schemaVersion` stays `2`. Both new session fields are optional, so a file of an earlier build decodes without them, and an earlier build drops them on its next save. A session without `activation` is never open, so it ends by time as in M4.
- `Shared/` computes "open" from the envelope: `session.isFilterStarted && session.activation != nil && session.activation == envelope.filterActivation`.

### Length validation

Today `FileControl.load()` (`Shared/SharedControlStore.swift`) and `FocusActivityProjection.make` require `FocusLength.isAllowed(seconds: session.length)`, the selectable 25 to 50 minutes.
A rollover (length = a multiple of the base length) and an `.expired` end of an open session (length = the open focused time) break that check, and a failed load clears the shields and stops monitoring.
So one `Shared/` rule replaces the check in both places:

| Stored session                                          | Valid when                                                                                                                                                                    |
| ------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `baseLength == nil` (manual, or an earlier session)     | `FocusLength.isAllowed(seconds: length)`, as today.                                                                                                                           |
| `baseLength != nil`, any phase except the two below     | `FocusLength.isAllowed(seconds: baseLength)`, and `length` is a whole multiple of `baseLength` (1 or more), within 0.01 seconds, and at most `TodaySnapshot.maxFocusSeconds`. |
| `baseLength != nil`, `ending` or `terminal`, `.expired` | `FocusLength.isAllowed(seconds: baseLength)`, and `baseLength <= length <= TodaySnapshot.maxFocusSeconds` (one week).                                                         |

- A finite check on `length` comes first in every row.
- The upper bound in the third row keeps a damaged file from reaching history with an unbounded duration; it is the bound that the widget snapshot already uses.
- `.earlyExit` never follows a rollover, because a rollover needs the base length to be reached and the end then gives `.expired` (decision 4), so its length stays a multiple.
- An earlier build without this rule reads a rolled-over or finalized open session as invalid and clears it, with its shields. That happens only after a downgrade, which this project does not ship; the M4 [Earlier builds](2026-11-01-m4-focus-filter-design.md#earlier-builds) rule is otherwise unchanged.

## Side artifacts

No new monitoring activity and no new named store.
A rollover overwrites the focus activity `focus.<UUID>` of the session with a later end; it is the same activity.
The M2 break artifacts table and the M3 tables apply unchanged to every stored phase of an open session.
The focus selection file is not a side artifact of a session: it exists while a selection is saved, as the private file did.

## Transitions

Every section is one `withExclusiveAccess` section on `control.lock`, reads the envelope again, runs the M2 cleanup and ends with the M3 everyday convergence, as every section does.
A section is the same in the app, in the extension and in the Monitor.

### Filter start (Focus on)

The M4 [filter start](2026-11-01-m4-focus-filter-design.md#filter-start-focus-on) with these changes:

- Step 1 reads the focus length and the focus selection from the App Group (decisions 12 and 13), and the access value as in decision 20. No selection gives the refusal `selection` (decision 17). A selection with no allowed focus length gives the refusal `error`: the migration order of decision 16 makes it a damaged state, and the extension never starts with a default length that the person may not have chosen.
- Step 3.8 saves `preparing` with `activation = filterActivation` (the new marker of step 3.3) and `baseLength = focus length`.
- Step 5 posts the Darwin notification (decision 21) instead of calling the app's model when the process is the extension.
- The today snapshot write of the 2026-11-14 reconciliation runs only in the app process (decision 26).

### Rollover

Part of the M2 reconcile order, before the timed end:

1. If the stored session is open, `active`, and `now >= focusEnd`, and `focusEnd <= deadline`, and `length + baseLength <= TodaySnapshot.maxFocusSeconds` (decision 8):
2. Add `baseLength` to `expiresAt` until `focusEnd > now`, but never past the bound of decision 8. A late callback catches up in one section. If the bound stops the catch-up while `focusEnd <= now`, the section skips steps 3 and 4 and the timed end of the reconcile ends the session as `.expired` (decision 8).
3. Register the focus activity with the new end (`min(focusEnd, deadline)`, as `focusActivityEnd` computes).
4. Save the session.
5. If step 3 throws: end the session with M2 transition 6 and `.expired`, with `expiresAt` set by decision 5 from the session before step 2. The base length was reached, so the session counts; its restrictions lift while the Focus may still be on. This keeps the M2 invariant that a session without a callback at its next change does not keep its restrictions.

The Monitor's `didEnd` of the focus activity runs this through its existing reconcile, and so does every other section that reconciles.

### Filter end (Focus off)

The M4 [filter end](2026-11-01-m4-focus-filter-design.md#filter-end-focus-off), with step 4 changed: a filter-started session that is not `terminal` ends with the reason of decision 4, and with the `expiresAt` of decision 5 for `.expired`.
The section decides whether the stored session is open before step 2 clears the marker, and keeps that decision for the rest of the section. For a session that was open, the reconcile of step 3 neither rolls it over nor ends it with the timed `.expired`; it can still end it as `.deadlineMissed` or `.authorizationRevoked`. Step 4 then ends it with the reason of decision 4 and the open focused time of decision 5, so a lost rollover does not shorten the recorded time.
The #53 guarantee (the off call releases a filter-started session after a caught cleanup or reconcile error) applies unchanged, with the reason order of decision 4.

### Activation check

The M4 [activation check](2026-11-01-m4-focus-filter-design.md#activation-check-app-launch-and-foreground) gets one change: `clearFilterActivation(matching:)` also ends the stored session when it was open for that marker, with the reason of decision 4.
So a lost off call keeps the restrictions only until the app opens.
Without the app, a lost off call keeps an open session rolling over (decision 8); the person ends it with "집중 종료" or by turning the Focus on and off again (the next off call clears the marker and ends the session).

### Manual end

"집중 종료" runs `finish()` as today. For an open session the reason is `.expired` when the open focused time is at least the base length (decision 5 sets `expiresAt`), else `.earlyExit`.
The marker stays, so the same activation starts no new session (M4 decision 11).

## Gaps between steps

| Gap                                                                   | Thrown error                                                                                                                                                                                            | Process exit                                                                                                             |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Rollover: after step 3 (register), before step 4 (save)               | The save throws: the registered end is later than the stored one. The next `didEnd` comes at the new end; its reconcile rolls the stored session over again from the old focus end (step 2 catches up). | Same as a thrown save.                                                                                                   |
| Rollover: step 3 throws                                               | Step 5 ends the session as `.expired`.                                                                                                                                                                  | Exit before step 3: nothing changed; the old activity already ended, so the next section that reconciles rolls over.     |
| Rollover lost (no `didEnd`, Monitor not run)                          | -                                                                                                                                                                                                       | The shield stays and nothing changes until the next section; the session then catches up or ends by the off call.        |
| Filter end: marker cleared, session end throws                        | The #53 rule ends the session.                                                                                                                                                                          | The save of `ending` carries the cleared marker; before it, the stored marker stays and the activation check repairs it. |
| Migration: length written, before its read-back or the selection copy | The old key stays; retry next launch. The extension sees a length and no selection, and refuses with `selection`.                                                                                       | Same as a thrown error.                                                                                                  |
| Migration: selection copy written, before its read-back               | The old file stays; retry next launch.                                                                                                                                                                  | Both copies exist; the next launch compares and deletes the old one.                                                     |

## One-shot calls and their recovery

| Call                    | Lost when                                                                        | Recovery                                                                                    |
| ----------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Focus on                | The system does not call, or the extension cannot read (before the first unlock) | None until the Focus turns off and on again; the refusal is stored when the call ran.       |
| Focus off               | The system does not call, or the lock retries run out                            | Activation check on the next app launch or foreground; "집중 종료"; the next off call.      |
| Focus activity `didEnd` | A lock timeout after the retries, or a late delivery                             | Any later reconcile rolls over or ends the session; `focusEnd` is computed from timestamps. |

## Apple documentation (checked 2026-11-16)

The JSON endpoint `https://developer.apple.com/tutorials/data/documentation/<path>.json` was read for each page.

| Fact                                                                                                                                                                                                                               | Source                                                                                                                                                   |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| The sample configures "the iOS and App Intents extension targets", whose bundle identifiers "need to support the App Groups capability"; turning on the Focus delivers the parameters "in the sample app's App Intents extension". | [Defining your app's Focus filter](https://developer.apple.com/documentation/appintents/defining-your-app-s-focus-filter)                                |
| `startMonitoring`: "Attempting to monitor too many activities or activities that are too tightly scheduled can cause this method to throw an error." It overwrites an earlier schedule of the same activity.                       | [`startMonitoring(_:during:events:)`](<https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/startmonitoring(_:during:events:)>) |
| `DeviceActivitySchedule` states no maximum interval length.                                                                                                                                                                        | [`DeviceActivitySchedule`](https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule)                                              |
| The Family Controls capability adds `com.apple.developer.family-controls`, and an App Store submission needs the distribution entitlement.                                                                                         | [Family Controls](https://developer.apple.com/documentation/familycontrols)                                                                              |

Not documented, so `[UNCERTAIN]` until a device step:

1. Whether `ManagedSettingsStore` writes and `DeviceActivityCenter.startMonitoring` succeed in an App Intents extension process.
2. Whether the extension can read the authorization state without a prompt (decision 20).
3. The decisions of decision 9 (one type in two targets).
4. How long the system lets the extension run, and whether a call that waits for the lock (up to 4 retries 250 ms apart) finishes.

## Superseded lines

The implementation PR adds dated reconciliation sections, without rewriting earlier text:

- M4 decision 14 ("in the main app target, not in a new App Intents extension") and the constraint "No new product target": superseded by decisions 9 to 11.
- M4 decision 1 ("No endless timer"): an open session continues after the focus length (decision 2 of this document).
- M4 [Activation check](2026-11-01-m4-focus-filter-design.md#activation-check-app-launch-and-foreground) step 3 ("never starts or ends a session"): it ends an open session.
- M1 design: the focus length is read by the app and the extension, from the App Group.
- 2026-10-26 design: the focus selection is in the App Group, not in the app container.
- Live Activity decision, "State and time projection": the open-session row of decision 25.
- Home widget design: unchanged in rules; the reconciliation notes decision 26.
- `AGENTS.md` architecture table: the new target and the moved values.

## Physical-device verification

On the iPhone 16 Pro with the signed Debug build, after the signing approval:

1. Build and install with the type in both targets; record which process runs each call (`donotdisturbd` category `AppFocusConfiguration`, and the handler's log), with the app running and with the app closed.
2. App closed, Focus on: a session starts, the focus selection is shielded, the refusal row is clear.
3. App closed, Focus off before the base length: `.earlyExit`, restrictions lifted.
4. Focus on for longer than the base length: a rollover at the base length (store copy shows `expiresAt` moved by one base length), restrictions stay.
5. Focus off after one rollover: `.expired`, history shows the focused time, the streak and the widget count it after the app refresh.
6. A break inside an open session, then Focus off during the break: the reason of decision 4.
7. "집중 종료" during an open session: restrictions lift at once; turning the Focus off and on starts a new session.
8. A Focus on before the first unlock after a restart: what the extension reads, and the stored refusal.
9. Live Activity: none while the app stays closed; it appears when the app opens; after the base length it counts up.
10. Migration: update over the current build with a saved selection and a 40-minute focus length; both values survive, and the private file is gone.

## Verification

- Host tests (`Shared/`): rollover in `active` at the focus end, catch-up after a late callback, no rollover for a manual session or a session whose activation was cleared, deadline before the focus end, rollover registration failure, the reason order of decision 4, `expiresAt` of decision 5 (including a Focus off after a lost rollover, which records the uncapped time), a filter start with `unknown` access that passes both verification reads and one with `denied` that rolls back, a save and reload through `FileControl` after a rollover and after an `.expired` finalization (each row of [Length validation](#length-validation), and a length outside it that throws), the Live Activity projection of a rolled-over session, decoding a version 2 file without the new fields.
- The separate-process race check, because rollover adds a write to an existing callback.
- SDK tests for the migration and for the App Group stores.
- UI tests with fixtures for the count-up timer screen and the completion card of an open session.
- An unsigned device Release build of every target, because the target configuration changes.
- Simulator results do not prove Focus filter delivery, extension Screen Time access or rollover timing on a device.

## Left to the builder

- The file layout of the new target in `project.yml` and `Package.swift`, and how the app and the extension share the handler.
- The Darwin notification mechanism and its name, if the given name collides.
- The copy of the count-up timer line, with short labels (subject to the visual approval gate).
