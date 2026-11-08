# Turning the everyday layer off for today

Date: 2026-11-08.
Status: design for approval.
Source: [issue #87](https://github.com/AndrewDongminYoo/focus-study/issues/87), decided on 2026-11-08 after a physical-device check; parent issue #39.
This document amends the [M3 design](2026-11-01-m3-schedule-layer-design.md) only where it says so, and the M3 design carries dated reconciliation lines that point here.
It also reads the [everyday status on the timer screen](2026-11-08-everyday-status-on-timer.md) spec, which it does not change.
This document changes no code; a separate implementation issue under #39 follows it.

## Contract

On 2026-11-08 the everyday layer could not be lifted from the app inside today's range.
The only way out was to turn off the app's Screen Time access in iOS Settings, which M3 does not prevent (M3 [Non-goals](2026-11-01-m3-schedule-layer-design.md#non-goals-in-m3-deliberately-excluded)).
`FamilyActivityPicker` has no public API to lock or mark chosen tokens (Apple documentation JSON, 2026-11-08: only `init(selection:)`, `init(headerText:footerText:selection:)` and the `familyActivityPicker(title:headerText:footerText:isPresented:selection:)` modifier), so the picker cannot show which apps an edit may not remove.

Decisions made on 2026-11-08:

1. Inside today's stored range, also during a window, the everyday settings screen offers one action that turns the everyday layer off for the rest of today. It is the only loosening allowed inside the range.
2. The action first shows a 30-second waiting screen. It works once a day: after it succeeds, the layer blocks nothing until today ends. Leaving the app (`.background`) cancels the wait, as the M2 break wait does; an `.inactive` overlay does not.
3. "Off for today" is not "off". The stored layer stays on, and the next day's range blocks again by the stored schedule with no action from the person.
4. Every other edit inside the range keeps the existing strict rule (M3 [Editing rules](2026-11-01-m3-schedule-layer-design.md#editing-rules), five conditions). App or website removal, a shorter range and new unblocked windows stay refused inside the range.
5. A refused save says which of the five conditions failed, in 해요체, with the time that editing opens again and a pointer to the off-for-today action.
6. Focus sessions, breaks, the Focus filter, the Live Activity and the M2 rules do not change. Like every everyday edit, the action is refused while a stored focus session is in a phase other than `terminal`.

Out of scope: picker header or footer copy, a "turn back on for today" action, limits on breaks across sessions, and protection against a revoked Screen Time access or a clock change.

## Today

"Today" is the local calendar day of `now` in the engine calendar (`SessionControl.calendar`, `Calendar.autoupdatingCurrent` in the app and the Monitor), the same calendar that gives `minute(now)` in the M3 [blocking rule](2026-11-01-m3-schedule-layer-design.md#the-blocking-rule).
The day key of a time is the year, month and day of that time in the engine calendar, written as `yyyy-MM-dd`.
The section that turns the layer off stores the day key of its own `now`, not the day when the wait started.
A commit cannot cross midnight in normal clock flow: section step 1 refuses when `now` is outside the stored range, the range end is exclusive (`rangeStart <= minute(now) < rangeEnd`), and no range ends after 23:55, so every commit is before 23:55:00 of the day of its `now`.
The 10-second grace after the wait end (see [The app-side wait](#the-app-side-wait)) only stops a wait from running the section long after it ended; it never moves a commit past the range end.
So, without a clock or time zone change during the wait, the stored day is the day the person saw.

- A time zone change recomputes the day key in the new zone, as `minute(now)` is recomputed. If the local date changes, the stored key no longer matches, and the layer blocks by its schedule (stricter). If travel to the west reaches the stored date again later, the layer is off again for that local date. The total time off can then be longer than one day.
- A manual clock change can move `now` into or out of the stored date, in either direction. M3 does not protect against a clock change, and this document keeps that.
- A change of the calendar system makes the stored key not match, so the layer blocks by its schedule (stricter).

## Design

### Stored off day

`everyday-layer.json` gets one optional field:

| Field    | Type      | Meaning                                                                             |
| -------- | --------- | ----------------------------------------------------------------------------------- |
| `offDay` | `String?` | The day key of the day that the layer is off for. Missing means that no day is off. |

- `schemaVersion` stays `1`. See [Earlier builds and schema](#earlier-builds-and-schema) for the reason.
- `EverydaySchedule` in `Shared/` carries `offDay`, because `Shared/` sees every field except the tokens.
- The load does not validate `offDay`. The rule compares it with today's key as a string, so a malformed value matches no day, and the layer blocks by its schedule (stricter). A malformed `offDay` is not a read failure, because a read failure clears the store (looser).
- `Integration/` gets a write path that replaces the whole file with the same revision, schedule and tokens and a new `offDay`, with the same atomic replace and file protection as a save.
- The revision and the everyday activities do not change. "Off for today" is not "off": the stored layer stays `enabled`, and the activities of the stored revision stay registered, because tomorrow's range start must arrive without the app.
- The wait is not stored. It lives in app memory only, because it is not a security boundary while Screen Time access can be revoked in iOS Settings.

### The blocking rule

The rule gets one line in its schedule part:

```plaintext
everyday store blocks = the file is readable
                    and enabled
                    and offDay != dayKey(now)
                    and access is approved (when the section knows it)
                    and rangeStart <= minute(now) < rangeEnd
                    and no window has start <= minute(now) < end
                    and not (stored focus phase == onBreak and now < breakEndsAt)
```

- The new line belongs to the schedule part, not to the break line. M3 transition 4 (re-block) applies the everyday shield when the rule without its last line gives "block", and the M3 step in transition 6 evaluates the rule with the stored `ending` phase. Both therefore read the off day, and neither applies the everyday shield on a day that is off.
- `EverydayRules.blocks` and `EverydayRules.nextChange` read the line through the schedule part, so every caller of the rule gets it.
- The editing rules do not read the line. They compare the new schedule with the stored schedule part without the off day (see [Editing after the layer is off for today](#editing-after-the-layer-is-off-for-today)).

### The off-for-today section

`turnEverydayOffForToday` is one `withExclusiveAccess` section on `SessionControl`. The app passes the stored revision that the waiting screen was shown for, `now`, the access check and the write.

1. **Check.** Read the envelope and run the M2 cleanup. Read the access value inside the lock and refuse with `ControlIssue.unauthorized` if access is not approved. Refuse with `ControlIssue.busy` if a stored session is in a phase other than `terminal`; a Focus filter can start a session during the wait. Read the stored everyday file. Refuse, with a reason that the screen shows, when the file is unreadable, when no layer is stored or the stored layer is off, when the stored revision is not the one passed, when `now` is outside the stored range, or when the stored `offDay` is already today's key.
2. **Write** the stored file again with `offDay` set to the day key of `now`. This is the commit point.
3. **Converge**: the convergence at the end of the section, as in every lock section. Step 2 finds the stored revision registered and changes nothing. Step 3 evaluates the rule, gets "not block", and clears the everyday store.

Steps 1 and 2 register and stop no activity.
The convergence at the end of the section works as in every app section, also after a refusal or a thrown error: it may register missing activities of the stored revision, and after a refusal for access it stops every everyday activity and clears the store (M3 row "Access revoked").
When the read of `control.json` throws, the read clears the everyday store and no convergence runs (M3 row "`control.json` unreadable").
If step 2 throws, the file stays as it was, the convergence evaluates the earlier file, and the section throws a retryable error.
A store that keeps a shield after step 3 is recorded as `notCleared`, as in the M3 convergence, and the section itself succeeds.
The section adds no `await` and no wait inside the lock.

### The app-side wait

- The everyday settings screen shows the action only when the status says that the stored layer is on, `now` is inside the stored range, the layer is not off for today, `EverydaySettingsModel.canEdit` is `true`, and access is approved.
- The action opens a waiting screen with a 30-second progress indicator and a cancel button, in the manner of the M2 break wait. The restrictions stay on during the wait.
- The waiting time is a timing value next to the M2 timing values, not a stored value.
- At the end of the wait, the app runs the section once, without a further tap. The section runs only while the scene is `.active`; if the wait ends during an `.inactive` overlay, the section runs when the scene becomes `.active` again.
- The section runs only before the wait end plus a grace of 10 seconds, the M2 stale-wait grace. After that, the wait counts as cancelled and changes nothing, so an `.inactive` overlay held open cannot carry a wait into another day or far past the range end.
- `.background` cancels the wait, as `FocusModel.sceneDidLeaveForeground` cancels the M2 wait. Closing the everyday settings screen or the settings sheet also cancels it. An `.inactive` overlay such as Control Center does not.
- A cancelled wait changes nothing and does not use the day's action.
- The action does not save the draft. After the section returns, the screen reads the status again and keeps the draft.
- A refusal or a thrown error ends the wait. The screen shows the reason and reads the status again. To try again, the person starts a new 30-second wait. A refusal because `now` is outside the range says that editing is open now.
- A process exit during the wait leaves nothing stored, so nothing changes.

### Editing after the layer is off for today

This document keeps decision 4 strictly. An earlier proposal was to accept every edit as if it were outside the range once the layer is off for today, because the stored layer then blocks nothing for the rest of today. This design does not take that proposal, for these reasons:

- Inside the range, only turning off is allowed (끄기만).
- With the earlier proposal, the sequence "off for today at 10:00, remove every app at 10:05" makes tomorrow looser than the schedule that the screen showed at 10:00, without a wait until the stored range end. M3 promises that "after any sequence of accepted edits, editing opens no earlier than the stored range end that the screen showed".

So:

- The gate of the M3 editing rules is unchanged: inside today's stored range, with the stored layer on, the five conditions apply, also when the layer is off for today. The gate reads `enabled` and the range, not `offDay`.
- The conditions compare the new schedule with the stored schedule part without the off day, so "the new schedule blocks wherever the stored schedule blocks" means the schedule as it would block on a day that is not off.
- Outside the stored range, every edit is accepted, as in M3.
- An accepted save writes `offDay` itself: the stored `offDay` when it equals the day key of `now`, otherwise none. It ignores any `offDay` that the app passes. So an accepted edit never turns the layer back on for today, and an off day from an earlier date is removed at the next save.
- This changes the write path of the save. Today the app builds the `write` closure of `saveEveryday`, and the closure captures the app's draft schedule, which still has the `offDay` from before the section (none). The save section therefore sets `offDay` on the schedule inside the lock and passes that schedule to the write (for example `write: (EverydaySchedule) throws -> Void`), and the app writes the schedule that the section passes, never its draft. `EverydaySettingsModel.sameEditableSchedule` keeps comparing only `enabled`, the range and the windows, so `offDay` never counts as an unsaved edit. A host test saves a draft without `offDay` while the layer is off for today and checks that the written file keeps today's `offDay`.
- A save after an unreadable file treats the file as no stored layer, as in M3, so it writes no `offDay`. The layer then blocks again today by the new schedule, and the action is offered again. The person could already set any schedule in that case, so this adds no looser state.

#### Refused save: conditions and their order

The save checks the five M3 conditions in this order and refuses with the first one that fails:

1. The layer stays on.
2. The new range contains `now`.
3. The new range ends at or after the stored range end.
4. At every time from `now` to the stored range end, the new schedule blocks wherever the stored schedule blocks.
5. The new selection contains every app and website of the stored selection.

The range conditions come before condition 4, so a shorter range is named as a range change, not as a loss of blocked time.
Condition 4 then names the windows: a new window, a longer window or a window moved into blocked time.
The selection condition comes last because it reads the tokens through `containsStoredSelection` in `Integration/`, and a refusal for the schedule needs no token read.
Today `EverydaySchedule.isAtLeastAsStrict` merges conditions 1 and 4, and the save throws one `ControlIssue.everydayLocked`. The implementation splits them, and the refusal carries the failed condition (for example `everydayLocked(EverydayLockReason)`, or a separate error type if an associated value would break the `ControlIssue` comparisons in `App/`).

The message names the failed condition in 해요체, keeps the existing time that editing opens again (the stored range end), and points to the off-for-today action.
When the layer is already off for today, the pointer is left out, because the action is not offered.
The builder writes the strings with the `user-facing-copy` skill.

### Stored states and side artifacts

The M3 [stored states and side artifacts](2026-11-01-m3-schedule-layer-design.md#stored-states-and-side-artifacts) tables get one more stored everyday state: "On, off for today", which means `enabled` and `offDay == dayKey(now)`.

Everyday store contents for the new state:

| Stored focus phase                     | On, off for today |
| -------------------------------------- | ----------------- |
| No session                             | empty             |
| `preparing`                            | empty             |
| `active`                               | empty             |
| `waiting`                              | empty             |
| `onBreak`, `now < breakEndsAt`         | empty             |
| `onBreak`, `now >= breakEndsAt`        | empty             |
| `breakOver`                            | empty             |
| `ending`                               | empty             |
| `terminal`                             | empty             |
| None known (`control.json` unreadable) | empty             |

A layer that is on with an `offDay` of another day is the M3 state "On, schedule does not block now" or "On, schedule blocks now", by the schedule.
The off-for-today section, like the save, writes only in the rows "No session" and `terminal`.

Everyday activities and the file for the new state:

| Stored everyday state | Everyday activities                                           | Everyday file                                              |
| --------------------- | ------------------------------------------------------------- | ---------------------------------------------------------- |
| On, off for today     | the stored revision, and others only while it is not complete | kept; only a save or the off-for-today section replaces it |

The activities stay registered: they are the only source of tomorrow's callbacks without the app.

### Gaps between steps

The M3 [gap table](2026-11-01-m3-schedule-layer-design.md#gaps-between-steps) applies unchanged, and the section adds these rows.
A thrown error at a step gives the state of a process exit after the step before it, or the result that the section states.

| Gap                                                                                                              | Everyday file                      | Everyday activities | Everyday store                 | Repair and direction                                                                                                                         |
| ---------------------------------------------------------------------------------------------------------------- | ---------------------------------- | ------------------- | ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Process exit or cancel during the wait                                                                           | stored                             | stored              | by the schedule                | Nothing was stored. No change in blocking.                                                                                                   |
| Wait end passes during an `.inactive` overlay, and the grace passes too                                          | stored                             | stored              | by the schedule                | The wait counts as cancelled. The section does not run. No change in blocking.                                                               |
| The lock times out                                                                                               | stored                             | stored              | by the schedule                | The section did not run. The screen shows the error, and a new wait is needed.                                                               |
| Section step 1: the read of `control.json` throws                                                                | stored                             | unchanged           | empty                          | As the M3 row "`control.json` unreadable": the read clears the store, and no convergence runs. Looser while `control.json` stays unreadable. |
| Section step 1 refuses for access                                                                                | stored                             | none                | empty                          | As the M3 row "Access revoked": the convergence stops every everyday activity and clears the store. The screen shows the reason.             |
| Section step 1 refuses for another reason (busy, file unreadable, no layer or off, revision, range, already off) | stored                             | by the convergence  | by the M3 tables               | The section writes nothing; its convergence runs as in every app section. The screen shows the reason, and a new wait is needed.             |
| Section step 2 (the write) throws                                                                                | stored, not off                    | stored              | by the schedule                | Atomic replace, so the earlier file stays. Retryable error. No change in blocking.                                                           |
| Exit after step 2, before convergence step 3                                                                     | off for today                      | stored              | blocking, if it blocked before | The next section clears it: an everyday or focus callback, an app launch or foreground, or any app action. Stricter until then.              |
| Convergence step 3 cannot clear the store                                                                        | off for today                      | stored              | partly cleared                 | Status `notCleared`. Each later section clears again. Stricter until then.                                                                   |
| Convergence step 1: file unreadable after the write                                                              | unreadable                         | unchanged           | empty                          | As the M3 row: looser until the person saves the layer again. The off day is lost with the file.                                             |
| A window or range-end callback later today                                                                       | off for today                      | stored              | empty                          | The rule gives "not block". Nothing to repair.                                                                                               |
| Next day's first blocked time: callback lost, late, or exit before step 3                                        | stored, `offDay` stale             | stored              | not blocking                   | As the M3 row for a lost range start or window end: the next section. Looser until then.                                                     |
| Save while off for today, any M3 save gap                                                                        | earlier or new, both off for today | as the M3 row       | empty                          | Both files are off for today, so the store stays empty in every row of the M3 save gaps. No change in blocking.                              |
| Time zone or manual clock change after the action                                                                | off for today                      | stored              | by the earlier local day       | As the M3 rows: the app converges on the change, otherwise the next callback. Either direction until then (see [Today](#today)).             |

### Callbacks

The section expects no new activity and no new callback.

- The off day ends at local midnight. No range crosses midnight, so the first time on the next day that the rule can give "block" is an existing edge: the range start, or, when a window starts at the range start, the end of the last window in the chain of touching windows that starts there (for 08:00-08:30 and 08:30-09:00, 09:00). The windows cannot cover the whole range, so the chain ends before the range end.
- For a range that starts at 00:00, the range activity's `intervalDidStart(for:)` arrives at 00:00 and evaluates the rule with a day key that no longer matches.
- The callbacks of later edges today (window start or end, range end) start a lock section as before. Each evaluates the rule, gets "not block", and leaves the store empty.
- A lost or late callback at the next day's first blocked time leaves the layer off until the next section, as M3 already accepts for a lost range start. A callback that arrives before midnight by the Monitor's clock evaluates the earlier day and gives "not block"; that early callback is `[UNCERTAIN]` in M3 as well.
- `handleCallback` routing does not change. The off-for-today section is an app section, so its convergence may register missing activities of the stored revision.

### Guards across sequences of accepted actions

Each guard that compares an action with the stored state, checked after sequences of accepted actions:

| Sequence                                                                                          | Result                                                                                                                                                                                     |
| ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Off for today at 10:00, then a looser edit at 10:05 (remove an app, shorten the range)            | Refused by the five conditions, because the gate reads the range and `enabled`, not `offDay`. The lock still ends at the stored range end.                                                 |
| Off for today at 10:00, then a stricter edit at 10:05 (add an app)                                | Accepted. The save keeps today's `offDay`, so the layer blocks nothing until today ends, and the new schedule and selection block from the next day's range.                               |
| Off for today, then a looser edit after the stored range end, then the next day                   | Accepted, as every edit outside the range in M3. The save keeps today's `offDay`; the next day blocks by the new schedule. The same edit was possible at the range end without the action. |
| Off for today, then turn the layer off and on again outside the range on the same day             | Both saves keep today's `offDay`, so the layer stays off for today. There is no way to turn it back on for today.                                                                          |
| Off for today, then the action again on the same day                                              | Not offered; the section refuses because `offDay` is already today's key.                                                                                                                  |
| Off for today on day D, then the next day                                                         | The key no longer matches. The range blocks by the stored schedule, the five conditions apply inside it, and the action is offered once again.                                             |
| Off for today, then a save after the file became unreadable                                       | Treated as no stored layer, as in M3: no `offDay` is written, and the action can be used again today. The person could already save any schedule in that state.                            |
| A stricter edit, then off for today                                                               | Accepted. The section writes the stored schedule as it is, with the new revision that the save registered.                                                                                 |
| A save between the wait start and the section (the stored revision changed)                       | Refused, because the revision passed is not the stored one. The screen reads the status again.                                                                                             |
| The range end passes during the wait                                                              | Refused, because `now` is outside the range. The screen shows that editing is open.                                                                                                        |
| A wait started at 23:54:45 in a range of 00:00-23:55, then Control Center held open past midnight | The grace passes at 23:55:25, so the wait counts as cancelled, and the section never runs with a `now` of the next day.                                                                    |
| A Focus filter session starts during the wait                                                     | Refused with `busy`. A session started after the action keeps the layer off: a break, its re-block and the session end all read the off day through the schedule part of the rule.         |
| Off for today on day D, then a clock set back to day D on a later day                             | Off again for that local date. M3 does not protect against a clock change. A later save removes the stale `offDay`.                                                                        |

### Status for the app

- `everydayStatus(now:authorized:)` returns one more value: whether the stored layer is on and off for today (`offForToday`).
- `blocksNow` is `false` while the layer is off for today.
- `nextChange` is the first time at or after the start of the next local day at which the rule gives "block": the next day's range start, or the end of the last window in the chain of touching windows that starts at the range start. It skips today's edges. `EverydaySchedule.nextChange` already walks every edge in order, so it finds the end of such a chain.
- The issue checks do not change. A layer that is off for today is still `enabled`, so a missing activity of the stored revision is still `registrationFailed`, and a store that keeps a shield is `notCleared`.
- The settings row (`EverydaySettingsModel.statusLine`) says that the layer is off for today and when it blocks again, with the time of `nextChange`, so the time does not read as later today. The builder writes the copy with the `user-facing-copy` skill.
- The everyday settings screen keeps its strict-only message inside the range, also when the layer is off for today, because the five conditions still apply. It shows the off-for-today action only under the conditions in [The app-side wait](#the-app-side-wait).
- The timer-screen row of the [everyday status on the timer screen](2026-11-08-everyday-status-on-timer.md) spec does not change. With `issue == nil` and `blocksNow == false`, it shows no row, and the idle screen gets no "off for today" line. Any `issue` still shows `매일 제한을 확인해 주세요 ›`.
- `EverydaySettingsModel.followStatus` reads the status again at `nextChange` as before, and the everyday settings screen also reads it at today's stored range start and range end when either is still ahead. The action depends on whether `now` is inside the range, and `nextChange` can skip the range start: with a window at the range start, a screen opened before the range would otherwise show the action only at the window end.

### Earlier builds and schema

- `schemaVersion` stays `1`, and `offDay` is an optional key.
- A build from before this change decodes the file with `JSONDecoder`, which ignores the unknown key. That build then blocks by the schedule, which is the stricter direction. A bump to `2` would make that build fail the read and clear the store, which is the looser direction.
- A save by such a build writes no `offDay`, so the layer blocks again today (stricter).
- A file without `offDay` loads in this build as a layer with no off day.
- `ControlEnvelope.schemaVersion` stays `2`. `control.json` gets no field.

## Physical-device verification

The M3 device steps stay. These steps continue the M3 list. Record each result in the [device matrix](../notes/screen-time-device-matrix.md).
Do not apply real restrictions without explicit approval for that run.

15. While the layer blocks, start the off-for-today wait and send the app to the background before 30 seconds. Check that the wait is cancelled and the shield stays. Start it again, open Control Center during the wait, and check that the wait continues.
16. Complete the wait. Record when the shield disappears. Check that the settings row says that the layer is off for today, that the window and range-end edges of today leave the shield off, and that on the next day the shield comes back at the range start without the app.
17. While the layer is off for today and inside the range, try to remove an app, shorten the range and add a window. Check that each save is refused with the matching condition. Add an app and check that the save is accepted and that nothing is shielded until the next day.
18. While the layer is off for today, start a focus session with a different app and take a break. Check that the focus app is shielded, the everyday app stays free, and the re-block applies only the focus shield.
19. Start the wait during a window, and once more about 20 seconds before the range end. Record the result of each.

Unverified until those steps run: the timing of the store clear after the section, and the next day's first blocked edge after a day that was off (`[UNCERTAIN]`, as the M3 callback timing).

## Verification for the implementation

Follow `AGENTS.md` and [README verification](../../README.md#실행과-검증).

- `Shared/` changes: host tests for the day key, the blocking rule with an off day (also across a re-block and a session end), `nextChange` that skips today's edges, the save that keeps or drops `offDay`, the five refusal reasons in their order, and every refusal of the off-for-today section. Run the separate-process race check.
- `Integration/` changes: SDK tests for the file with and without `offDay`, and for a file that an earlier build wrote.
- `App/` changes: SDK tests for the wait (`.background` cancels, `.inactive` keeps, the section runs once at the end) and the copy, and UI tests with a DEBUG fixture that never touches real restrictions. Keep every existing accessibility identifier.
- Simulator results do not prove real Screen Time behavior.
