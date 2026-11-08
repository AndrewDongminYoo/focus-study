# M3: Everyday schedule blocking layer

Date: 2026-11-01.
Status: design for approval. Milestone `M3` in the GitHub project "Focus Study".
Source: decisions from the 2026-10-31 brainstorm, confirmed on 2026-11-01.
This document changes [the 2026-10-26 design](2026-10-26-focus-study-design.md), [the M1 design](2026-10-31-m1-launch-flow-design.md) and [the M2 design](2026-11-01-m2-break-pass-design.md) only where it says so.
Where they differ, this document is the newer decision.
This PR does not edit those documents.
The implementation PR adds dated reconciliation sections to them (see [Superseded lines](#superseded-lines)).

## Intent

A focus session protects 25 to 50 minutes.
Outside a session, a student can still open the apps that distract them during the school day.
M3 adds an everyday blocking layer: one daily range in which a separate app and website selection is blocked, with a few short unblocked windows such as lunch.
The layer runs every day without the app.
It is a background rule, not a new main screen, so the app still opens on the focus-start screen.

## Roadmap context

I set this order: M1 launch flow and focus length (PR #46), M2 break pass and deadline (PRs #47 and #48), M3 everyday schedule blocking layer, M4 stricter notification handling.
M4 gets its own design document.
M3 must not block M4, but M3 does not build it.

## Goals

- A person can turn on an everyday layer with its own app and website selection, separate from the focus-session selection.
- The person sets one daily blocking range, for example 08:00-18:00. The same range applies every day of the week.
- Inside the range, the person registers at most 3 unblocked windows. Each window is 15 to 120 minutes long, entirely inside the range, and does not overlap another window.
- Window templates: lunch (점심), going to school (등교) and leaving school (하교).
- Outside the daily range, the layer blocks nothing. Nights and early mornings stay free.
- The everyday layer and the focus layer block the union of their selections.
- An M2 break lifts both layers for its 3 minutes. After the break, each layer comes back as it applies at that time.
- The layer turns on and off every day without the app.
- Inside today's range, the person cannot loosen the layer through the settings.
  - Reconciliation (2026-11-08, #87): one loosening is now allowed inside the range: after a 30-second wait, the person can turn the layer off for the rest of today, once a day, as the [everyday off-for-today](2026-11-08-everyday-off-today.md) spec says; every other edit inside the range stays strict-only.

## Non-goals in M3 (deliberately excluded)

- Rules per weekday, or a different range on some days.
- More than 3 windows, a window shorter than 15 minutes or longer than 120 minutes.
- A blocked-window mode (the person registers blocked times instead of unblocked times).
- A range that crosses midnight.
- Exceptions per app, or a different selection per window.
- A manual "pause the layer" button, and any break that belongs only to the everyday layer.
  - Reconciliation (2026-11-08, #87): the everyday settings screen now has one "off for today" action inside the range, behind a 30-second wait, as the [everyday off-for-today](2026-11-08-everyday-off-today.md) spec says; it ends at local midnight, and there is still no pause with a chosen length, no "turn back on for today" and no break of the everyday layer alone.
- A copy action from the focus-session selection to the everyday selection.
- History, statistics or a report for the everyday layer.
- A notification at the start or end of the range or a window (M4 owns notification decisions).
- A new element on the timer screen. The settings show the layer state.
  - Reconciliation (2026-11-08, #70): the idle timer screen and the completion card now show a one-line everyday status, as the [everyday status on the timer screen](2026-11-08-everyday-status-on-timer.md) spec says; the in-progress and break screens still show none, and the settings row does not change.
- Protection against a manual clock change, a revoked Screen Time access or a deleted app. The 2026-10-26 design already excludes anti-cheating guarantees ("부정행위 방지를 증명하지 않는다").

## Anti-goals (never, by decision)

- Rankings, leaderboards, or any comparison with other people.
- Friend presence, or any feature that sends the layer state or the schedule off the device.
- Anything that makes the first-screen line "데이터는 기기에만 저장돼요" false.

## Decisions by me

1. Blocking applies only inside a daily range that the person sets. Outside it, the layer blocks nothing.
2. The same rules apply every day.
3. The person registers unblocked windows, not blocked ones. Templates: lunch, going to school, leaving school. The intent is one or two short windows a day, plus a move to an academy when needed, not a class timetable.
4. At most 3 unblocked windows, each 15 to 120 minutes long.
5. The layer has its own app selection.
6. Blocking is the union of the everyday layer and the focus layer.
7. A break lifts both layers.

## Decisions by Claude (I can change them)

### Times

- All times are local wall-clock times on a 5-minute grid, stored as minutes after midnight.
- The range starts at 00:00 or later and ends at 23:55 or earlier. The start is before the end, so the range never crosses midnight. The range is at least 60 minutes long.
- Each window starts at or after the range start and ends at or before the range end. Two windows can touch (one ends when the next starts), but they cannot overlap.
- The windows cannot cover the whole range.
- Every interval is half-open: a time belongs to `[start, end)`. At the exact end time of a window, the layer blocks again. At the exact end time of the range, the layer blocks nothing.
- Default range for a new layer: 08:00-18:00.
- A template gives the window a label and a suggested time: lunch 12:00-13:00, going to school 08:00-08:30, leaving school 16:00-16:30. The person can change the times. A fourth kind, a window that the person names by time only (for example a move to an academy), has no suggested time.

### Selection

- The everyday selection uses the same rules as the focus selection: individual app and web domain tokens, no category tokens, at most 50 apps and 50 websites, and at least one app or website when the layer is on.
- Both selections together: at most 50 distinct apps and 50 distinct websites. The app checks this when the person saves either selection. The reason is in [Apple documentation](#apple-documentation-checked-2026-11-01): the limit says "Your app", not each store. A device check can relax this rule later.

### Editing rules

- The everyday settings are part of the settings sheet. The sheet itself is not locked: the timer screen hides its button during a focus session (`FocusModel.isInSession`), but in DEBUG diagnostics mode the button stays during a session on purpose (README device procedure 2). Only the everyday edit is locked: `EverydaySettingsModel.canEdit` is `false` during a session, and under the process lock the save refuses when a stored session is in a phase other than `terminal`. So no edit combines with a focus phase, and the diagnostics path does not change.
- Outside today's stored range (before its start or at or after its end), every edit is accepted, also turning the layer off.
- Inside today's stored range, also during a window, an edit is accepted only if it makes the layer stricter for the rest of today:
  - The layer stays on.
  - The new selection contains every app and website of the stored selection.
  - At every time from now to the stored range end, the new schedule blocks wherever the stored schedule blocks.
  - The new range contains now.
  - The new range ends at or after the stored range end.
- Reconciliation (2026-11-01, hosted review of the M3 PR): the last two conditions were added after the review found that two accepted saves could open editing before the stored range end.
  At 12:30 during lunch, a range moved to 13:00-18:00 kept every blocked time, so it passed the first three conditions, and the next save was outside the new range and could turn the layer off.
  The same gap opened when the range end was pulled back to the start of a window that ended at the range end.
  With the two conditions, the lock end never moves earlier, so after any sequence of accepted edits, editing opens no earlier than the stored range end that the screen showed.
  They also refuse an edit that keeps or adds blocked times but moves the range start past now during a window (for example, a range of 12:45-18:00 at 12:30 during lunch); the person can get the same blocking by shortening the window instead.
  `SessionControl.saveEveryday` in `Shared/SessionControl.swift` is the authority, and `testAcceptedEditsKeepTheLockUntilTheStoredRangeEnd` and `testSaveRefusesARangeEndPulledBackToATrailingWindow` in `CoreTests/EverydayControlTests.swift` cover it.
- Every other edit inside the range is refused, and the screen says when editing opens again (the stored range end). The person can still close the sheet without a change. The builder writes the copy with the `user-facing-copy` skill, in 해요체.
- Reconciliation (2026-11-08, #87): the five conditions and their gate do not change, also while the layer is off for today, and the lock still ends no earlier than the stored range end after any sequence of accepted edits.
  The refusal now names the first failed condition, in the order that the [everyday off-for-today](2026-11-08-everyday-off-today.md#refused-save-conditions-and-their-order) spec gives, and points to the off-for-today action.
  That action is a separate section, not an edit; an accepted save keeps today's off day and removes an off day of an earlier date.
- An accepted edit applies at once.
- A refused edit is not saved for later. A "pending" setting would add a second stored schedule and its own transitions.
- If the stored layer is off, or no layer is stored, every edit is accepted.

### Break interaction

- The everyday layer is lifted for a break only while the stored focus phase is `onBreak` and `now < breakEndsAt`.
- At or after `breakEndsAt`, the everyday layer blocks again by its schedule, even if the focus re-block has not run yet. This keeps a break at 3 minutes for the everyday layer also when the focus re-block is late. The M2 limit of 5 minutes then depends only on the focus re-block.
- I decided that a break lifts both layers. A consequence: a person inside the everyday range can start a focus session, take up to 3 breaks of 3 minutes, end the session with "집중 종료", and start again. M3 accepts this. A limit on breaks across sessions is excluded from M3. I can decide it later.

### Placement

- The settings sheet (`SettingsView`) gets a section for the everyday layer, with one row that opens the everyday settings screen.
- The row shows the state in one line, for example whether the layer blocks now and until when. The timer screen does not change.
  - Reconciliation (2026-11-08, #70): the idle timer screen and the completion card now show a one-line everyday status, as the [everyday status on the timer screen](2026-11-08-everyday-status-on-timer.md) spec says; the in-progress and break screens still show none, and this settings row does not change.
- The layer is off by default. Onboarding does not change.

### Everyday selection in the App Group (privacy boundary change)

This decision changes the 2026-10-26 data boundary again, after the M2 change, so I must approve it before implementation.

- The Monitor extension must apply the everyday shield at the start of the range and at the end of each window, while the app is usually not running. The Monitor needs the tokens to do that.
- Proposal: the everyday selection (application tokens and web domain tokens only) and the schedule are stored together in one file in the App Group directory `SessionControl/`, as `everyday-layer.json`. It is the only stored copy of the everyday selection. The app reads and writes it there, and the Monitor only reads it. It uses the same file protection as `control.json`.
- Difference from M2: the M2 break copy exists only while a break runs. This file exists as long as the layer is set up, also when the layer is off.
- Tokens are opaque values that the system issues for this device. The file stays on the device, so "데이터는 기기에만 저장돼요" stays true. The Report extension still has no App Group access. Usage data and site names are still not shared.
- The focus-session selection does not move. It stays in app private storage (`PrivateSelection/selection.json`), and M2 still copies it to the App Group only for a break.
- If I reject this proposal:
  - On iOS 26.5 and later, `ManagedSettingsStore.isActive` could replace the file. The app would keep the tokens in private storage and apply them to the everyday store once. The Monitor would set `isActive` at each edge and would not need the tokens. Whether a value of `isActive` that the Monitor sets stays in effect is `[UNCERTAIN]`.
  - On iOS 17 to 26.4, this design found no way for the Monitor to restore the everyday shield without the tokens. The layer would be unavailable there, or would work only while the app runs.

## Constraints

- iOS 17 or later, SwiftUI, Observation, SwiftData, iPhone only, portrait only.
- Keep the architecture in `AGENTS.md`. `Shared/` must not import Screen Time SDK modules. The everyday file is encoded and decoded in `Integration/`. `Shared/` sees only the schedule part.
- Keep the process-lock contract of the 2026-10-26 design: every state change reads the stored state again inside the `flock` section, makes the system changes, and writes JSON with an atomic replace. No `await` and no UI wait inside the lock.
- Keep the M2 rules for the focus layer. This document adds steps to M2 transitions 4 and 6 and to the control-state read failure, makes the words "this app's named store" in transition 3 step 6 mean `focusSession` only, lets an everyday name past the M2 callback identity check in one case (see [Callback routing in `handleCallback`](#callback-routing-in-handlecallback)), and changes nothing else in them.
- Keep the accessibility identifiers that `UITests/FocusFlowTests.swift` uses.
- Simulator results do not prove real Screen Time behavior.

## Apple documentation (checked 2026-11-01)

The JSON endpoint `https://developer.apple.com/tutorials/data/documentation/<path>.json` was read for each page.
The iOS 27.1 SDK `ManagedSettings.swiftinterface` was also checked.

| Fact                                                                                                                                                                                                                                                                                                 | Source                                                                                                                                                                                                                                                                   |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `repeats`: "If `false`, the extension stops receiving callbacks when the interval ends for the first time."                                                                                                                                                                                          | [`init(intervalStart:intervalEnd:repeats:warningTime:)`](<https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule/init(intervalstart:intervalend:repeats:warningtime:)>)                                                                         |
| "Use `repeats` to create an activity schedule that repeats until the activity-monitoring stops."                                                                                                                                                                                                     | [`DeviceActivitySchedule.repeats`](https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule/repeats)                                                                                                                                              |
| If the current date is inside the interval, `intervalDidStart(for:)` is called immediately when monitoring starts. Otherwise it is called at the next date that matches `intervalStart`.                                                                                                             | Same initializer page                                                                                                                                                                                                                                                    |
| "The maximum number of activities that can be monitored at one time by an app and its extensions is twenty."                                                                                                                                                                                         | [`MonitoringError.excessiveActivities`](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/excessiveactivities)                                                                                                               |
| "The minimum interval length for monitoring device activity is fifteen minutes." The maximum is one week.                                                                                                                                                                                            | [`intervalTooShort`](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/intervaltooshort), [`intervalTooLong`](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/intervaltoolong) |
| `startMonitoring` with an activity that is already monitored overwrites its schedule. The monitor "may begin receiving callbacks as soon as the system calls this method if the activity's scheduled interval is ongoing."                                                                           | [`startMonitoring(_:during:events:)`](<https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/startmonitoring(_:during:events:)>)                                                                                                                 |
| "Attempting to monitor too many activities or activities that are too tightly scheduled can cause this method to throw an error." and "To avoid errors, reduce the number of unique, tightly-scheduled activities." No threshold for "tightly" is given.                                             | `startMonitoring(_:during:events:)` page                                                                                                                                                                                                                                 |
| `stopMonitoring` "ignores names that don't correspond to monitored activities." With an empty array, it stops every activity.                                                                                                                                                                        | [`stopMonitoring(_:)`](<https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/stopmonitoring(_:)>)                                                                                                                                               |
| The interval start and end "indicate the earliest point when" the callbacks are invoked. "The system actually invokes these methods when someone uses the device during the interval." It "additionally calls `intervalDidEnd(for:)` when you stop monitoring an activity with an ongoing interval." | [`DeviceActivitySchedule.nextInterval`](https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule/nextinterval)                                                                                                                                    |
| Without a calendar in the components, the system uses `Calendar.current`. "The system bases the interval's end date on wall-clock time, regardless of any time zone changes that occur during the interval."                                                                                         | Same page                                                                                                                                                                                                                                                                |
| For events, "the system uses the time zone of the device at `nextInterval.start`" for the whole interval.                                                                                                                                                                                            | `startMonitoring(_:during:events:)` page                                                                                                                                                                                                                                 |
| `intervalDidStart(for:)` and `intervalDidEnd(for:)`: "the system only invokes this method when the device is in use."                                                                                                                                                                                | [`DeviceActivityMonitor`](https://developer.apple.com/documentation/deviceactivity/deviceactivitymonitor) callback pages                                                                                                                                                 |
| `ManagedSettingsStore.Name`: "Initializing multiple stores with the same name will share settings." Use names "to create distinct stores with their own settings."                                                                                                                                   | [`ManagedSettingsStore.Name`](https://developer.apple.com/documentation/managedsettings/managedsettingsstore/name)                                                                                                                                                       |
| "The system is responsible for determining its effective state based on all the settings it receives."                                                                                                                                                                                               | [`ManagedSettingsStore`](https://developer.apple.com/documentation/managedsettings/managedsettingsstore)                                                                                                                                                                 |
| `isActive`: "An inactive store is not included in the effective settings calculation. Defaults to true." Available from iOS 26.5, as are `stores` and `deleteStore()`.                                                                                                                               | [`isActive`](https://developer.apple.com/documentation/managedsettings/managedsettingsstore/isactive), JSON `metadata.platforms`                                                                                                                                         |
| "Your app can shield up to 50 application tokens at once." The same sentence exists for web domain tokens.                                                                                                                                                                                           | [`ShieldSettings.applications`](https://developer.apple.com/documentation/managedsettings/shieldsettings/applications-swift.property), [`webDomains`](https://developer.apple.com/documentation/managedsettings/shieldsettings/webdomains-swift.property)                |

Not documented, so these stay `[UNCERTAIN]` until a device check:

- Whether the shields of two named stores combine as a union. The documentation says only that the system decides the effective state from all settings.
- Whether the limit of 50 tokens applies to each store or to the app. This design assumes the app, which is the stricter reading.
- How many named stores an app can use. This design uses two.
- Which schedules Apple calls "too tightly scheduled". The everyday activities can have edges in the same minute: the default range 08:00-18:00 and the 등교 template 08:00-08:30 start together, and two windows can touch. Whether `startMonitoring` then throws, and whether both callbacks of a shared minute arrive, is not documented.
- How late the system delivers the start and end callbacks of a repeating activity, with the device unlocked, locked, or after the app was force-quit. A callback that is less than one second early, measured by the Monitor's `Date()`, is also `[UNCERTAIN]`.
- Whether a repeating activity stays in `DeviceActivityCenter.activities` between its daily intervals. The `repeats` page implies it, but does not say it.
- What a repeating schedule does on the day of a time zone change or a manual clock change.
- Whether a Monitor callback can run before the first unlock after a restart, when the App Group files are not readable.
- Whether deleting the app removes the settings of its named stores.

## Design

### Two named stores

| Store                      | Owner                       | Cleared by                                                           |
| -------------------------- | --------------------------- | -------------------------------------------------------------------- |
| `focusSession` (unchanged) | The focus layer (M1 and M2) | Session end, break start, start rollback, control-state read failure |
| `everydayLayer` (new)      | The everyday layer          | The everyday convergence, control-state read failure                 |

- The focus layer never writes or clears `everydayLayer`. The everyday layer never writes or clears `focusSession`. So the end of a session never lifts the everyday layer, and the start of a window never lifts a focus session.
- The union of the two layers comes from the system, which combines the settings of both stores (`[UNCERTAIN]`, see above).
- `ShieldClient.clear()` keeps its meaning: it clears `focusSession` only.

### Stored schedule

`everyday-layer.json` in `SessionControl/`, written only by the app, inside a lock section, with an atomic replace:

| Field           | Type               | Meaning                                                                                                            |
| --------------- | ------------------ | ------------------------------------------------------------------------------------------------------------------ |
| `schemaVersion` | `Int`              | `1`. Any other value is a read failure.                                                                            |
| `revision`      | `UUID`             | A new value for each save. The activity names contain it.                                                          |
| `enabled`       | `Bool`             | The layer is on.                                                                                                   |
| `rangeStart`    | `Int`              | Minutes after midnight.                                                                                            |
| `rangeEnd`      | `Int`              | Minutes after midnight.                                                                                            |
| `windows`       | `[EverydayWindow]` | 0 to 3 windows, sorted by start. Each has `kind` (`lunch`, `toSchool`, `fromSchool`, `custom`), `start` and `end`. |
| `applications`  | application tokens | Encoded in `Integration/` only.                                                                                    |
| `webDomains`    | web domain tokens  | Encoded in `Integration/` only.                                                                                    |

- `Shared/` gets `EverydaySchedule` (all fields except the tokens) and its rules. The load checks every rule in [Times](#times) and [Selection](#selection). A file that breaks one is a read failure, as `ControlIssue.invalidState` is for `control.json`.
- No file means that no layer is set up. That is not an error.
- The layer is off after "turn off", but the file keeps the schedule and the selection, so that the person can turn it on again.
- Reconciliation (2026-11-08, #87): the file gets the optional field `offDay`, the local day that the layer is off for, and `schemaVersion` stays `1`, as the [everyday off-for-today](2026-11-08-everyday-off-today.md#stored-off-day) spec says; the off-for-today section also writes the file, with the same revision.

#### The blocking rule

One rule in `Shared/` decides whether the everyday store must block.
It compares the stored state with the time, so a late check and a timely check get the same result:

```plaintext
everyday store blocks = the file is readable
                    and enabled
                    and access is approved (when the section knows it)
                    and rangeStart <= minute(now) < rangeEnd
                    and no window has start <= minute(now) < end
                    and not (stored focus phase == onBreak and now < breakEndsAt)
```

`minute(now)` is the local wall-clock time of `now` in `Calendar.current`, in minutes and seconds after midnight.
The rule depends on the focus layer only through the last line.

- Reconciliation (2026-11-08, #87): the schedule part gets the line `and offDay != dayKey(now)`, as the [everyday off-for-today](2026-11-08-everyday-off-today.md#the-blocking-rule) spec says; it is not part of the break line, so the transition 4 re-block and the transition 6 everyday step read it too.

### Monitoring activities

| Activity        | Name                             | Schedule                                             | Callbacks used                                                   |
| --------------- | -------------------------------- | ---------------------------------------------------- | ---------------------------------------------------------------- |
| Range activity  | `everyday.<revision>.range`      | `rangeStart` to `rangeEnd`, `repeats: true`          | `intervalDidStart` (range start), `intervalDidEnd` (range end)   |
| Window activity | `everyday.<revision>.window.<n>` | Window `n` start to end, `repeats: true`, `n` is 1-3 | `intervalDidStart` (window start), `intervalDidEnd` (window end) |

- A layer that is on uses 1 range activity and 1 activity for each window: at most 4. A layer that is off uses none.
- The schedule components are `hour`, `minute` and `second` (0), without a date, a calendar or a time zone. So the system uses `Calendar.current` and wall-clock time every day.
- Each activity is at least 15 minutes long (range at least 60, window at least 15), so `intervalTooShort` cannot occur.
  The blocked segments between the windows are not used as activities. Two windows 10 minutes apart would make a blocked segment shorter than 15 minutes.
- Apple also says that "too tightly scheduled" activities can make `startMonitoring` throw, and gives no threshold. Edges in the same minute are allowed (a window at the range start, two touching windows), so this is `[UNCERTAIN]` until device step 14.
  The design needs no change for it: a throw in save step 2 rolls the save back with a retryable error, and a throw in convergence step 2 is recorded and retried by later sections.
  The order of callbacks in the same minute does not matter, because each section evaluates [The blocking rule](#the-blocking-rule) by the time and not by the callback. At 08:00 with the range and a window starting together, both sections give "not block".
- Count: the focus activity, at most one break activity, at most 4 everyday activities of the stored revision, and during an edit at most 4 of the earlier revision. That is at most 10 of the 20 allowed.
- No callback is an edge action. Each callback only starts a lock section, and the section makes the store match [The blocking rule](#the-blocking-rule). A lost, late, repeated or stale callback therefore cannot leave a wrong state after the next lock section.
- The revision in the name tells the cleanup which activities belong to the stored file. A schedule comparison through `DeviceActivityCenter.schedule(for:)` is not used.
- `ScreenTimeMonitoring.sessionID(_:)` and the M2 break parser accept only `focus.` names, so the M1 and M2 cleanups never stop an everyday activity. A new parser reads the revision and the part of an `everyday.` name.

### Everyday convergence

The convergence is one step that every lock section runs once at its end, except the read-only `snapshot()` and the new read-only `everydayStatus(now:authorized:)`.
It also runs when the focus part of the same section threw, with one exception: when the section's read of `control.json` threw, the section has no envelope, so no convergence step runs and only the [control-state read failure](#control-state-read-failure) path clears the everyday store.
It runs for every callback name, because it depends only on the stored files and the time, never on the caller.
In order:

1. **Read** `everyday-layer.json`. On a read failure, clear the everyday store, skip step 2, and record the issue for `everydayStatus(now:authorized:)`.
2. **Registrations.**
   - If the section knows that access is not approved: stop every everyday activity.
   - Otherwise, if the stored layer is on, and the section is an app section or a Monitor section that `intervalDidEnd(for:)` or `intervalWillEndWarning(for:)` started: register every activity of the stored revision that `DeviceActivityCenter.activities` does not list. A section that `intervalDidStart(for:)` started never registers, as in the M2 rule [Callback with nothing due](2026-11-01-m2-break-pass-design.md#callback-with-nothing-due).
   - Then, if every activity of the stored revision is registered (or the stored layer is off, or no file exists): stop every everyday activity of another revision.
   - A registration that throws is recorded for `everydayStatus(now:authorized:)`. The activities of the earlier revision then stay, because they are the only source of callbacks until the stored revision is complete.
3. **Store.** Evaluate [The blocking rule](#the-blocking-rule) against the envelope that the section stored last.
   - If it gives "block" and the store does not match the stored selection: apply the stored selection. If the store still does not match, keep what was applied and record the issue.
   - If it gives "not block" and the store has a shield setting: clear the everyday store.

Rules for the convergence:

- A failure in the convergence never throws out of the section and never delays the focus part. A focus end still clears `focusSession` when the everyday file is unreadable, a registration throws, or the store does not match.
- Each step is idempotent.
- The convergence cannot loop, and this does not depend on how `DeviceActivityCenter.activities` lists an activity (`[UNCERTAIN]`, see above):
  - A registration of an activity with an ongoing interval sends `intervalDidStart(for:)` at once. That section never registers.
  - A stop of an activity with an ongoing interval sends `intervalDidEnd(for:)`. That section can register only activities of the stored revision that are missing, and their `intervalDidStart(for:)` sections register nothing. So one stop leads to at most one more round of registrations.
- No repair in [Gaps between steps](#gaps-between-steps) needs a registration from an `intervalDidStart(for:)` section. The save registers before its write, and an app section registers again after access comes back or after a registration failure. A Monitor `intervalDidEnd(for:)` section also retries a failed registration.
- Every stop names its activities. The convergence never calls `stopMonitoring` with an empty array, because an empty array stops every activity, also the focus and break activities.
- Sections without an authorization value (the M2 break transitions, `finish`, `acknowledgeTerminal`) skip the access condition. The next section with a value applies it. The two new app sections, `saveEveryday` and `everydayStatus(now:authorized:)`, take a value, as `start` and `reconcile` do.
- The lock sections in the app run on launch, on foreground, on a day, time zone or clock change, on every session action, and while a session runs. Outside a session, the app does not tick, so the Monitor callbacks keep the layer current.

### Callback routing in `handleCallback`

M2's `handleCallback` returns after its break cleanup for any name that is not the current focus activity or break activity.
M3 adds a route for `everyday.` names, before that check:

1. Read the envelope and run the M2 break cleanup (unchanged).
2. For an `everyday.` name, the focus part runs in one case only: the stored session is `onBreak` and `now >= breakEndsAt`. Then run the M2 reconcile order with the access value of the extension, as an app reconcile does. Without this step, an everyday callback during a late break would leave the focus layer lifted. In every other phase (`preparing`, `active`, `waiting`, `onBreak` before `breakEndsAt`, `breakOver`, `ending`, `terminal`) and with no session, an everyday name does not reach the focus part, and after step 1 only step 4 runs.
   The M2 reconcile is not safe for any caller: it reads the access value and `DeviceActivityCenter` state, and it ends the session when either fails. M2 lets only callbacks of the current session reach those checks: "A name that is not the current session's focus activity or its current break activity (`n == breaksTaken`) changes nothing." ([Callback identity](2026-11-01-m2-break-pass-design.md#callback-identity)). The gate keeps that rule for the up to 8 everyday edges a day and for the `intervalDidEnd(for:)` that each stop of an earlier revision sends. In the one case that passes the gate, the focus shield is already off for the break, so an end on those checks adds no looser state.
   It does not use the early re-block of the break warning, and it does not run the M2 rule [Callback with nothing due](2026-11-01-m2-break-pass-design.md#callback-with-nothing-due). The gate is the same for a stale revision and the stored one.
3. For a focus or break name, the M2 identity check and the M2 steps apply (unchanged).
4. Run the everyday convergence.

`FocusMonitor` passes every name to `handleCallbackRetryingLock`, so a lock timeout is retried up to 4 times, as in M2.

### Transitions of the everyday layer

#### Save (turn on, edit, turn off)

`saveEveryday` is one `withExclusiveAccess` section on `SessionControl`. The app builds the new settings, and the section makes them durable in this order:

1. **Check.** Read the envelope and run the M2 cleanup. Read the access value inside the lock, as `start` does, and refuse with `ControlIssue.unauthorized` if access is not approved. Refuse with `ControlIssue.busy` if a stored session is in a phase other than `terminal`. Read the stored everyday file. Check the new settings against [Times](#times) and [Selection](#selection). Apply [Editing rules](#editing-rules) against the stored file. If the stored file is unreadable, treat it as no stored layer, so the person can set the layer up again.
2. **Register** every activity of the new revision (none if the new layer is off).
3. **Write** the new file. This is the commit point.
4. **Stop** every everyday activity of another revision.
5. **Converge** the store (convergence step 3, against the new file).

A save when access is not approved is refused, also a turn-off. It registers nothing, writes nothing and does not change the store. The section then knows that access is not approved, so its convergence stops every everyday activity and clears the store, as the "Access not approved" columns of [Stored states and side artifacts](#stored-states-and-side-artifacts) give. The stored file stays, and the next app section with access applies it again. The person approves access first, then saves.

If step 2 or 3 throws: stop the activities of the new revision that step 2 registered, keep the stored file, and throw a retryable error.
The store does not change in that case.
Step 4 cannot throw.
A store that does not match after step 5 is recorded as in the convergence, and the save itself succeeds.

Why this order is safe:

- Inside the range, an accepted edit only makes the layer stricter. So between steps 3 and 5, the store holds the earlier, looser state, and the restrictions of the earlier settings are never lifted.
- Outside the range, the earlier settings block nothing now.
- When the new settings block now, the new range interval is ongoing. So step 2 sends `intervalDidStart(for:)` for the new range activity, and that callback repairs every later gap as soon as the app releases the lock. The callback is lost only if the Monitor cannot take the lock within its retries.

#### Range start and end, window start and end

Each one is a callback of an everyday activity.
The section follows [Callback routing in `handleCallback`](#callback-routing-in-handlecallback), and the convergence sets the store.

| Callback                           | Store result                       | Effect of a lost or late callback          | Direction |
| ---------------------------------- | ---------------------------------- | ------------------------------------------ | --------- |
| Range activity `intervalDidStart`  | block (unless a window starts too) | The layer starts late                      | looser    |
| Range activity `intervalDidEnd`    | not block                          | The layer stays on after the range end     | stricter  |
| Window activity `intervalDidStart` | not block                          | The window starts late                     | stricter  |
| Window activity `intervalDidEnd`   | block                              | The layer comes back late after the window | looser    |

- Every callback is one-shot for its edge on that day. No other callback of the layer repeats it.
- The system delivers each callback when the device is first used at or after the edge. A device that is not in use needs no shield, so this delay matters only for the first use.
- A lost or late callback is corrected by the next lock section: the next everyday edge, any focus callback, an app launch or foreground, or any app action. On a day without later edges and without the app, a lost range-start or window-end callback leaves the layer off until the next day's range start. That is the worst case in the looser direction.
- A callback that arrives before its edge, by the Monitor's clock, sets the store to the state before the edge. The documentation says that the edge is the earliest point, so this is `[UNCERTAIN]` and expected not to happen.

### Changes to M2 transitions

#### Transition 3: start the break

No new step.
M2 step 6 says "Clear this app's named store". With two stores, that means `focusSession` only, and it clears `focusSession` as before. The implementation PR records this wording (see [Superseded lines](#superseded-lines)).
The convergence at the end of the section evaluates the stored `onBreak` with `now < breakEndsAt`, and clears the everyday store.
If the break start rolls back, the stored phase is not `onBreak`, and the convergence leaves the everyday store on.

#### Transition 4: re-block

M2 step 2 becomes: apply the focus shield from the break selection copy, then apply the everyday shield if [The blocking rule](#the-blocking-rule) without its last line gives "block".
Both layers therefore come back together, before the save of `breakOver`.
A failure of the everyday part does not change the M2 steps.
Step 3 still checks only the focus store.

#### Transition 6: end

A new step runs after M2 step 4 (delete the break selection copy) and before step 5 (save `terminal`): convergence steps 1 and 3 only (read the everyday file, then set the store).
So the focus part comes first: M2 steps 2 to 4 clear `focusSession` and stop the focus and break activities before any everyday step, and the rule "never delays the focus part" in [Everyday convergence](#everyday-convergence) holds.
Convergence step 2 (the registrations, which can call `startMonitoring` up to 4 times) waits for the convergence at the end of the section.
The stored phase is then `ending`, so the everyday layer blocks again by its schedule, also when the session ends during a break.
The new step adds no looser gap: from `active`, `waiting` or `breakOver`, the everyday store already blocks by the schedule, and from `onBreak`, both layers were already off.
The convergence at the end of the section then finds nothing to change in the store.
A failed save of `ending` leaves the earlier phase stored. The new step then uses that phase, and the end-of-section convergence uses `terminal` (or the earlier phase, if the save of `terminal` fails too).

#### Control-state read failure

M2 clears `focusSession`, stops the focus and break activities, and deletes every break copy.
M3 also clears the everyday store.
The section has no envelope, so no step of the [everyday convergence](#everyday-convergence) runs: it reads no everyday file, registers nothing, stops no everyday activity and applies nothing. A default empty envelope must not stand in for the missing one, because the blocking rule would then give "block" and apply the everyday shield again right after this path cleared it.
The everyday activities stay, so that a later callback can apply the layer again when `control.json` is readable.
It never applies a shield to recover, as in the 2026-10-26 design.
This path is the shared `read()` of every lock section, so it also runs in `snapshot()` and `everydayStatus(now:authorized:)` when they cannot read `control.json`, as the M2 path does for `snapshot()`.

#### Start

M1 start is unchanged. Its rollback clears `focusSession` only.
The everyday store keeps its state during the whole start.

### Stored states and side artifacts

The everyday artifacts are the everyday store contents, the everyday activities and the file.
The two tables give what must hold after the convergence of every lock section.
Every lock section removes what they do not allow: convergence step 3 clears or applies the store, convergence step 2 stops the activities of other revisions, and the [control-state read failure](#control-state-read-failure) path clears the store.

Everyday store contents, for each stored focus phase and each stored everyday state.
"S" is the stored everyday selection, and "empty" is a store without a shield setting.

| Stored focus phase                     | No file, or off | On, schedule does not block now | On, schedule blocks now | File unreadable | Access not approved (the section knows it) |
| -------------------------------------- | --------------- | ------------------------------- | ----------------------- | --------------- | ------------------------------------------ |
| No session                             | empty           | empty                           | S                       | empty           | empty                                      |
| `preparing`                            | empty           | empty                           | S                       | empty           | empty                                      |
| `active`                               | empty           | empty                           | S                       | empty           | empty                                      |
| `waiting`                              | empty           | empty                           | S                       | empty           | empty                                      |
| `onBreak`, `now < breakEndsAt`         | empty           | empty                           | empty                   | empty           | empty                                      |
| `onBreak`, `now >= breakEndsAt`        | empty           | empty                           | S                       | empty           | empty                                      |
| `breakOver`                            | empty           | empty                           | S                       | empty           | empty                                      |
| `ending`                               | empty           | empty                           | S                       | empty           | empty                                      |
| `terminal`                             | empty           | empty                           | S                       | empty           | empty                                      |
| None known (`control.json` unreadable) | empty           | empty                           | empty                   | empty           | empty                                      |

The only focus phase that changes the store is `onBreak` before `breakEndsAt`, because [The blocking rule](#the-blocking-rule) depends on the focus phase only through its last line.
The save refuses in every phase other than `terminal` and no session, so the file and its stored revision change only in those two rows. Convergence step 2 still registers missing activities of the stored revision, stops other revisions and stops every everyday activity without access in every phase.
A stored `preparing` exists only after a process exit inside a start or a failed rollback save, and the next reconcile ends it.

Everyday activities and the file, for each stored everyday state.
They do not depend on the focus phase, with the one exception in the last row:

| Stored everyday state                      | Everyday activities                                           | Everyday file                  |
| ------------------------------------------ | ------------------------------------------------------------- | ------------------------------ |
| No file                                    | none                                                          | none                           |
| A layer that is off                        | none                                                          | kept; only a save replaces it  |
| On (blocking now or not)                   | the stored revision, and others only while it is not complete | kept; only a save replaces it  |
| File unreadable                            | unchanged                                                     | kept, until a save replaces it |
| Access not approved (the section knows it) | none                                                          | kept                           |
| Any, with `control.json` unreadable        | unchanged                                                     | kept, and not read             |

The M2 [break artifacts](2026-11-01-m2-break-pass-design.md#break-artifacts) table does not change.
The everyday file is not a break artifact, and no M2 cleanup deletes it.

- Reconciliation (2026-11-08, #87): both tables get the state "On, off for today": the store is empty in every focus phase, and the activities of the stored revision stay registered, as the [everyday off-for-today](2026-11-08-everyday-off-today.md#stored-states-and-side-artifacts) spec says. In the row "On (blocking now or not)", the file is replaced by a save or, inside the stored range, by the off-for-today section, which writes the same revision and schedule with `offDay` set.

### Gaps between steps

For each gap: a thrown error at a step gives the state of a process exit after the step before it, or the rollback that the transition states.
"Next section" means the next lock section in any process: an everyday or focus callback, an app launch or foreground, or an app action.
The focus restrictions follow the M2 [break artifacts](2026-11-01-m2-break-pass-design.md#break-artifacts) gap table in every row.

| Gap                                                                                                      | Everyday file | Everyday activities                      | Everyday store                         | Repair and direction                                                                                                                                            |
| -------------------------------------------------------------------------------------------------------- | ------------- | ---------------------------------------- | -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Save, step 1 refuses or throws                                                                           | earlier       | earlier                                  | earlier state                          | Nothing changed by the save. After a refusal for access, the convergence of the section gives the row "Access revoked".                                         |
| Save, exit after step 2, or step 2 or 3 throws                                                           | earlier       | earlier, and new ones after an exit      | earlier state                          | The next section registers what the stored revision is missing, then stops the new ones. A thrown error stops them at once. No change in blocking.              |
| Save, exit after step 3 or 4                                                                             | new           | new, and earlier ones after step 3       | earlier state, looser than the new one | The `intervalDidStart(for:)` that step 2 sent repairs it after the lock. Otherwise the next section. Looser until then, never looser than the earlier settings. |
| Save, store does not match after step 5                                                                  | new           | new                                      | partly applied                         | Each later section applies again, and the settings show the issue.                                                                                              |
| Turn off (outside the range), exit after step 3                                                          | off           | earlier                                  | empty (outside the range)              | The next callback of an earlier activity stops all of them. No change in blocking.                                                                              |
| Range start or window end: callback lost, late, or exit before convergence step 3                        | stored        | stored                                   | not blocking                           | Next section. Looser until then (see [the callback table](#range-start-and-end-window-start-and-end)).                                                          |
| Range end or window start: callback lost, late, or exit before convergence step 3                        | stored        | stored                                   | blocking                               | Next section. Stricter until then.                                                                                                                              |
| Convergence step 2 throws                                                                                | stored        | stored revision incomplete, earlier kept | converged by step 3                    | Each later section registers again. The earlier activities still call back at their edges.                                                                      |
| Convergence step 1: file corrupt or of an unknown schema                                                 | unreadable    | unchanged                                | empty                                  | Looser until the person saves the layer again. The settings show the issue.                                                                                     |
| Convergence step 1: file protection before the first unlock                                              | unreadable    | unchanged                                | empty                                  | Looser until the next section after the first unlock (`[UNCERTAIN]` whether such a callback runs).                                                              |
| Break start (transition 3), exit after the save of `onBreak` and before the convergence                  | stored        | stored                                   | blocking                               | Next section clears it while `now < breakEndsAt`. Stricter until then.                                                                                          |
| Break start rolls back                                                                                   | stored        | stored                                   | blocking                               | No change, because no break started.                                                                                                                            |
| Re-block (transition 4), exit after step 2 or a failed save of `breakOver`                               | stored        | stored                                   | blocking                               | The next reconcile at or after `breakEndsAt` re-blocks again. A section before `breakEndsAt` clears the everyday store until then.                              |
| Re-block, exit after the save of `breakOver`                                                             | stored        | stored                                   | blocking (applied in step 2)           | Nothing to repair.                                                                                                                                              |
| `onBreak` after `breakEndsAt`, focus re-block not yet run                                                | stored        | stored                                   | blocking                               | The convergence blocks the everyday layer at once. The focus re-block follows M2.                                                                               |
| Session end (transition 6) from `active`, `waiting` or `breakOver`, exit after step 1, 2, 3 or 4         | stored        | stored                                   | blocking (as before the end)           | Nothing to repair in the store. Reconcile step 1 finishes the end.                                                                                              |
| Session end from `onBreak`, exit after step 1, 2, 3 or 4 (before the everyday step)                      | stored        | stored                                   | not blocking (lifted for the break)    | Next section: reconcile step 1 finishes the end, and its convergence evaluates `ending`. Looser until then, as the focus layer is after step 2.                 |
| Session end, exit after the everyday step, before the save of `terminal`                                 | stored        | stored                                   | blocking                               | Reconcile step 1 finishes the end. Nothing to repair in the store.                                                                                              |
| Session end, everyday step finds the file unreadable or the store does not match                         | stored        | stored                                   | empty, or partly applied               | Steps 5 and later run unchanged. Each later section applies again, and the settings show the issue.                                                             |
| Session end, exit after the save of `terminal`, before the end-of-section convergence                    | stored        | stored                                   | blocking (set by the everyday step)    | Nothing to repair. A registration that the end-of-section convergence would have made comes from the next section.                                              |
| Session end, failed saves of both `ending` and `terminal`                                                | stored        | stored                                   | by the stored earlier phase            | M2 reconcile step 5 ends the session later, and that section converges.                                                                                         |
| Session start, exit after the save of `preparing` (and after the register, verify, apply or verify step) | stored        | stored                                   | as before the start                    | The next reconcile ends `preparing` as `.recoveryInterrupted`, and its convergence evaluates `ending`, then `terminal`. No change in blocking.                  |
| Session start, exit after the save of `active`, before the end-of-section convergence                    | stored        | stored                                   | as before the start                    | `active` does not change the blocking rule, so the store already matches. Nothing to repair.                                                                    |
| Session start, a step throws, then the rollback (clear `focusSession`, stop, save `terminal`)            | stored        | stored                                   | as before the start                    | The end-of-section convergence evaluates `terminal`, or `preparing` if the rollback save fails. Neither changes the result. No change in blocking.              |
| Session start, exit inside the rollback                                                                  | stored        | stored                                   | as before the start                    | The next reconcile ends the stored `preparing`. No change in blocking.                                                                                          |
| Time zone change                                                                                         | stored        | stored                                   | by the earlier local time              | The app converges on `NSSystemTimeZoneDidChange`. Without the app, the next callback. Either direction until then.                                              |
| Manual clock change                                                                                      | stored        | stored                                   | by the earlier clock                   | As for a time zone change. A clock change can move the layer, and M3 does not prevent it (see [Non-goals](#non-goals-in-m3-deliberately-excluded)).             |
| `control.json` unreadable                                                                                | stored        | unchanged                                | empty                                  | Looser while `control.json` stays unreadable, as the focus layer is.                                                                                            |
| Access revoked                                                                                           | stored        | none after a section that knows it       | empty                                  | When access is approved again, the next app section registers the activities and applies the layer.                                                             |

- Reconciliation (2026-11-08, #87): the off-for-today section adds its own rows, and a save while the layer is off for today changes no store in any save row, as the [everyday off-for-today](2026-11-08-everyday-off-today.md#gaps-between-steps) spec says.

### Process lock and recovery contract

- The lock, its 0.25-second timeout and the atomic JSON replace do not change. The everyday file uses the same `control.lock`, so the blocking rule always reads a focus phase and a schedule that belong together.
- The convergence adds one file read and one store comparison to each lock section. It adds no `await` and no wait.
- The M2 session engine changes only in the steps that [Changes to M2 transitions](#changes-to-m2-transitions) and [Callback routing in `handleCallback`](#callback-routing-in-handlecallback) name. Its reconcile order, timing values and break artifacts do not change.
- `StartupRecovery` is unchanged. Its reconcile runs the convergence as every section does. The everyday layer does not depend on the selection or history storage of the app.

### Earlier builds

- `ControlEnvelope.schemaVersion` stays `2`. M3 adds no field to `control.json`.
- An M2 or earlier build's data loads unchanged in M3: no everyday file exists, so the layer is off.
- The everyday file starts at its own `schemaVersion` `1`.
- A downgrade to M2 is not supported. An M2 build ignores `everyday.` names, `everyday-layer.json` and the `everydayLayer` store. The everyday activities keep calling an M2 Monitor, which changes nothing. The everyday store keeps its last state. If that state blocks, it stays on, also at night, until the person revokes Screen Time access or deletes the app (`[UNCERTAIN]` whether deleting the app clears it). M3 accepts this, as M2 accepted its downgrade leftovers.

### Status for the app

`everydayStatus(now:authorized:)` is a read-only lock section, as `snapshot()` is. It returns:

- The stored schedule, or none.
- Whether the layer blocks now ([The blocking rule](#the-blocking-rule), with the access value that the app passes), and the next time that the result changes. When access is not approved, the layer does not block, and there is no next change.
- An issue, if any: the file is unreadable, a registration failed, or the store does not match.

The settings row and the everyday settings screen use it. The timer screen does not.

- Reconciliation (2026-11-08, #70): the idle timer screen and the completion card now also read it for their one-line everyday status, as the [everyday status on the timer screen](2026-11-08-everyday-status-on-timer.md) spec says; the in-progress and break screens still do not.
- Reconciliation (2026-11-08, #87): the status also says whether the layer is off for today, and then its next change is the next day's first blocked time, as the [everyday off-for-today](2026-11-08-everyday-off-today.md#status-for-the-app) spec says; the timer-screen row shows nothing for that state.

## Superseded lines

The implementation PR adds dated reconciliation sections (it does not rewrite the original lines) for these:

- 2026-10-26 design, data boundary: "App과 Monitor는 하나의 `ManagedSettingsStore(named: ManagedSettingsStore.Name("focusSession"))`만 사용한다." and "이 store의 `clearAllSettings()`만 호출하며".
- 2026-10-26 design, data boundary: "선택 토큰은 앱 내부 파일에만 저장한다" and the Monitor row, as M2 already amended it (only if I approve the [everyday selection in the App Group](#everyday-selection-in-the-app-group-privacy-boundary-change)).
- 2026-10-26 design, "구현 후 복구 계약 보완": "이 앱의 명명된 store와 `focus.<UUID>` namespace의 등록만 정리한다" and "다른 namespace의 monitoring을 중지하지 않으며".
- M2 design: transition 3 step 6 (the words "this app's named store"), transition 4 step 2, transition 6, the control-state read failure in [Process lock and recovery contract](2026-11-01-m2-break-pass-design.md#process-lock-and-recovery-contract), and the [Callback identity](2026-11-01-m2-break-pass-design.md#callback-identity) line "A name that is not the current session's focus activity or its current break activity (`n == breaksTaken`) changes nothing." (an everyday name now re-blocks a late break, see [Callback routing in `handleCallback`](#callback-routing-in-handlecallback)).
- `AGENTS.md` project scope, ownership table and data boundary.

## Physical-device verification

Blocked until issues #8, #9 and #10 are resolved (development team, identifiers and entitlements, signed install on an approved device).
Record every result in the [device matrix](../notes/screen-time-device-matrix.md), with device, OS version, scheduled time and observed time.
Do not apply real restrictions without my explicit approval for that run.

Steps:

1. Set a range that started 5 minutes ago and ends in 90 minutes, with one window that starts in 20 minutes and lasts 15 minutes, and one app and one website that are not in the focus selection. Turn the layer on. Record when the shield appears.
2. Leave the app in the background with the device unlocked. Record when the shield disappears at the window start, and when it comes back at the window end.
3. Repeat step 2 with the device locked across each edge, and again after a force-quit of the app.
4. Record when the shield disappears at the range end. Check on the next day that the layer starts again at the range start without the app.
5. Start a focus session with a different app while the layer blocks. Check that both apps are shielded. End the session, and check that the everyday app is still shielded.
6. Start a focus session before a window starts. Check that the focus app stays shielded during the window, while the everyday app is free.
7. Take a break while both layers block. Check that both apps are free, and that both come back at the re-block. Repeat with a break that crosses a window end.
8. While the layer blocks, try to turn it off, remove an app, and lengthen a window. Check that each is refused. Add an app, and check that it is shielded at once.
9. With the DEBUG diagnostic that applies a selection to the everyday store without the union check (plan Task 5), shield 50 apps in each store. Record which apps are shielded.
10. Restart the device during the range. Record the layer state before and after the first unlock.
11. Change the time zone during the range. Record the layer state and the next edge.
12. Revoke Screen Time access while the layer blocks. Record the store state and `DeviceActivityCenter.activities`.
13. After the range end, read `DeviceActivityCenter.activities` and check that the everyday activities are still listed.
14. Save a layer with edges in the same minute: the range 08:00-18:00 with the 등교 window 08:00-08:30, and two touching windows (12:00-13:00 and 13:00-13:30), with the start times shifted to a few minutes from now. Record whether `startMonitoring` throws, which callbacks arrive at each shared minute, and the shield state after each edge.

- Reconciliation (2026-11-08, #87): step 8's refused turn-off stays refused as an edit; steps 15 to 19 for the off-for-today action are in the [everyday off-for-today](2026-11-08-everyday-off-today.md#physical-device-verification) spec.

Unverified until those steps run:

- The union of two named stores `[UNCERTAIN]`.
- Whether the 50-token limit applies to each store or to the app `[UNCERTAIN]`.
- The delivery time of the start and end callbacks of repeating activities, unlocked, locked and after a force-quit `[UNCERTAIN]`.
- Whether repeating activities stay in `DeviceActivityCenter.activities` between intervals `[UNCERTAIN]`.
- The behavior of a repeating schedule at a time zone change or a manual clock change `[UNCERTAIN]`.
- Whether the Monitor can read `everyday-layer.json` after a restart before the first unlock `[UNCERTAIN]`.
- Whether `startMonitoring` and `stopMonitoring` work inside a callback of the same or another everyday activity `[UNCERTAIN]`.
- Whether everyday activities with edges in the same minute count as "too tightly scheduled", and whether every callback of a shared minute arrives `[UNCERTAIN]`.
- The iOS 17 runtime.

## Verification

Follow `AGENTS.md` and [README verification](../../README.md#실행과-검증).

- `Shared/` changes: run `swift test` and the separate-process race check. Extend the race helper with a stale everyday callback that must not undo a newer save.
- `Integration/` and `Monitor/` changes: run the SDK tests for the repeating schedules, the activity-name parsing and the everyday file, and compile the Monitor target.
- `App/` changes: run the SDK and UI tests with a DEBUG fixture that never touches real restrictions.
- Target or fixture wiring: run the unsigned device Release build.

## Left to the builder

- The layout of the everyday settings screen and of the time pickers.
- Exact copy, written with the `user-facing-copy` skill in 해요체, including the refused-edit message and the settings row.
- The order of the templates on the screen.
