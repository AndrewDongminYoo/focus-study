# Amendment: one focus interval per open session, and a rollover that only changes the stored session

Date: 2026-11-18.
Status: design for approval. Issue #152, after the rollover device run of 2026-11-18.
This document amends the [Focus filter extension design](2026-11-16-focus-filter-extension-design.md) (the "extension design"), the [M2 design](2026-11-01-m2-break-pass-design.md), the [lock-order amendment](2026-11-17-extension-lock-order-amendment.md) and the [Live Activity decision](2026-11-06-live-activity-decision.md), only where it says so; where they differ, this document is the newer decision.

## Problem

The extension design rolls an open session over by registering its focus activity `focus.<UUID>` again with a later end, inside the Monitor's `intervalDidEnd(for:)` of that same activity.
On the iPhone 16 Pro (iOS 27.0.1) on 2026-11-18 at 10:50:17, `UsageTrackingAgent` logged `Deleting budget for one-shot activity: focus.<UUID>` right after the Monitor's re-registration returned, so the interval that the rollover had just registered was removed.
At Focus off, the next section found the focus activity not registered and ended the session as `.recoveryInterrupted` ("중단된 세션 정리"), not counted.
A local probe then moved the rollover into `intervalWillEndWarning(for:)` with a 1-minute warning: the first re-registration kept the interval, but the agent delivered no second warning for the re-registered schedule (an alarm with `isWarning:1` at 12:21:25 and no "will end"), so the second rollover fell back to `intervalDidEnd(for:)` and was deleted again.
A second probe the same day (12:28:21) called `startMonitoring` for intervals of 1, 6, 24, 48, 168 and 192 hours that started 60 s later; every call was accepted, and all six were stopped afterwards with none left.

So a registration of a focus activity inside that activity's own `intervalDidEnd(for:)` does not survive the callback.
This answers the M2 `[UNCERTAIN]` "whether `startMonitoring` for an activity succeeds when it is called inside that activity's own `intervalDidEnd(for:)`" ([Callback with nothing due](2026-11-01-m2-break-pass-design.md#callback-with-nothing-due)): the call does not throw, and the registration is deleted after the callback.
Three paths besides the rollover rely on such a registration: the M2 rule "Callback with nothing due", the cleanup of an interrupted break start (`registerStoredEnd` in a `waiting` session that still has its break copy), and the stale-wait cancel inside a focus callback (`closeWait`).

## Decisions by me (2026-11-18)

1. An open session registers its focus activity once, with an end at the one-week bound of extension design decision 8. A rollover never registers the focus activity again.
2. A rollover changes only the stored session: it advances `expiresAt` by whole base lengths, in any section, from timestamps.
3. The other paths that register a focus activity inside its own `intervalDidEnd(for:)` are decided in this document too.
4. While no callback runs at the base length, the Live Activity of an open session shows the count-up of the extension design decision 25 when it becomes stale, instead of the state that asks for a confirmation.

## Decisions by Claude (I can change them)

### Terms

- The **bound length** of an open session is the largest whole multiple of `baseLength` that is at most `ControlSession.maxLength` (one week): `floor(maxLength / baseLength) × baseLength`.
  For the selectable lengths it is 604,500 s for 25 minutes, 603,000 s for 50 minutes, and 604,800 s for 30 to 45 minutes.
- The **bound end** is `startedAt + bound length + pausedSeconds`: the focus end that the rollover catch-up reaches at the bound, as the last iteration of the rollover loop in `SessionControl.rollOver` reaches it today.
- The **catch-up** is the stored-only rollover of decision 2: while the session is open, in `active`, `now >= focusEnd`, `focusEnd <= deadline`, and `length + baseLength <= maxLength`, add `baseLength` to `expiresAt`. It is the loop of extension design [Rollover](2026-11-16-focus-filter-extension-design.md#rollover) step 2, without steps 3 to 5.
- **Inside its own end** means a section that runs in the Monitor's `intervalDidEnd(for:)` of the focus activity of the stored session.

### The focus activity end of an open session

5. [Monitoring activities](2026-11-01-m2-break-pass-design.md#monitoring-activities) keeps every row for a session that is not open. For an open session:
   - In `active`: the bound end when `focusEnd <= deadline`, else the deadline.
     The difference `focusEnd - deadline` is `pausedSeconds - deadlineCredit - slack`, which a catch-up does not change, so the deadline either comes first at every chunk or at none.
   - In `waiting`: the `active` end above after a stale-wait cancel, that is the `active` end + `(waitEndsAt + grace - pausedAt)`, as M2 adds the same time to `pausedSeconds` and to `deadlineCredit`.
   - In `onBreak` and `breakOver`: the deadline, as today.
   - A session that stops being open keeps the end that was registered while it was open until a section ends it. Every path that clears the marker of an open session also ends that session (extension design [Filter end](2026-11-16-focus-filter-extension-design.md#filter-end-focus-off) and [Activation check](2026-11-16-focus-filter-extension-design.md#activation-check)), and the thrown end of the gap row "Filter end: marker cleared, session end throws" is closed by the #53 rule, so no running session is left with that end.
6. So each focus `didEnd` at its registered end has something due: at the bound end the catch-up stops at the bound and the timed end ends the session as `.expired` (extension design decision 8); at a deadline it ends as `.deadlineMissed`; at a `waiting` end the stale-wait cancel runs and the `active` end it gives is the same time.
7. Transitions that the person starts in the app (request a break, cancel the wait, start the break, resume, the early return) register the end of the phase that they save, by the rule of decision 5, as today. A resume after a break therefore registers the bound end again (or the deadline), from the app's section.
8. The first registration of a session started in the extension still begins 5 s after the section time (lock-order amendment decision 1); its end is now the bound end. The interval is then about one week, inside the 192-hour interval that the probe accepted.
   A session that the app starts from the filter registers from `startedAt`, as today.
   Lock-order amendment decision 3 (later registrations of an extension session start at `startedAt`) stays, but no rollover makes such a registration any more, so its `[UNCERTAIN]` about an immediate callback no longer applies to a rollover.

### The catch-up

9. The catch-up is a pure function in `Shared/` of the envelope and the time.
   Every lock section applies it as the last step of the M2 cleanup, so every section sees a session whose `focusEnd` is after `now` or that sits at the bound. The cleanup saves the result when it changed `expiresAt`; a failed save throws as any cleanup save does, and the next section computes the same catch-up from the same timestamps.
10. The reconcile step "Rollover" of the extension design keeps only its condition and step 2, now in the cleanup: at the bound with `focusEnd <= now`, the timed end of the reconcile ends the session as `.expired`. Steps 3 to 5 (register, save, end on a failed registration) are removed.
11. A rollover is never a callback, so nothing runs at the base length or at a chunk end without the app. The readers of the stored time that ran after a rollover callback before this change read the catch-up instead:

| Reader                                                            | Before                                                                                      | After                                                                                                                                                                                   |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `SessionControl.reconcile` and every section                      | Rolled over in the reconcile, before the timed end                                          | The cleanup catches up, before every section's own step (decision 9)                                                                                                                    |
| `requestBreak` guard (`timedEnd == nil`)                          | A callback kept `focusEnd` after `now`                                                      | Reads the caught-up session, so a break past a chunk end is available                                                                                                                   |
| `activitySnapshot` (the Live Activity read, app and Monitor)      | Read the stored session; the Monitor synchronized after each rollover callback              | Returns the caught-up session, and whether it is open by the envelope rule; the `activation != nil` proxy of `FocusActivityProjection.countsUp` is replaced by that value (decision 13) |
| `StartupRecovery.endCurrent`                                      | Computed the reason from the snapshot's `timedEnd`, which gave `.expired` for a stale chunk | Computes the reason from the caught-up session; an open session then reaches `finish`'s open rule with `.earlyExit`, which records the open focused time                                |
| The filter end's caught-error reason (`timedEnd ?? .earlyExit`)   | Read the stored session after its reconcile                                                 | Reads the caught-up session                                                                                                                                                             |
| The app's timer refresh (`FocusModel`, `timedEnd != nil`)         | Refreshed at the focus end; the reconcile rolled over                                       | Unchanged: the refresh's section catches up, and the next read has no timed end                                                                                                         |
| `FileControl.load` and the Live Activity guard (`hasValidLength`) | A rollover kept `length` a whole multiple of `baseLength`                                   | Unchanged: the catch-up adds whole base lengths and stops at the bound                                                                                                                  |
| History, today summary, widget snapshot, streak                   | Read `expiresAt` of the ended session                                                       | Unchanged: an open session's end sets `expiresAt` from the open focused time (extension design decision 5), not from the chunk                                                          |

### Registration inside its own end

12. Inside its own end, a section never registers the focus activity of the stored session:
    - A registration whose end is not after `now` is skipped and counts as made. Its phase has a timed end that is already due, and the same section's reconcile ends the session at that end. This is the stale-wait cancel of a `waiting` session at its registered end (M2: "the overwrite on the stale-wait path writes the same end again"), which therefore still ends as `.expired` or `.deadlineMissed`, not as `.recoveryInterrupted`.
    - Any other registration counts as failed, and the existing failure rule of that path applies: [Save failure after an overwrite](2026-11-01-m2-break-pass-design.md#save-failure-after-an-overwrite) for `overwriteAndSave`, its step 2 for `registerStoredEnd` in the cleanup. That step ends the session with the reason of the next bullet instead of always `.recoveryInterrupted`.
    - The M2 rule [Callback with nothing due](2026-11-01-m2-break-pass-design.md#callback-with-nothing-due) is replaced: a focus `didEnd` that leaves the stored session in `active`, `waiting`, `onBreak` or `breakOver` ends it. An open session whose open focused time has reached its base length ends as `.expired` with the `expiresAt` of extension design decision 5, as the removed rollover step 5 did; every other session ends as `.recoveryInterrupted`. Every end that this decision causes uses this reason.
      The reason: the registered interval has ended, the system deletes it after the callback, and a session without a callback at its next change must not keep its restrictions (M2).
    - A focus `didEnd` that an overwrite causes (the `didEnd` of the replaced schedule) is not the end of the interval. It reaches the engine only when the overwriting section wrote no fresh registration marker: an app or Monitor section writes one, and its `startMonitoring` returns only after the callbacks that it causes have returned, so those callbacks find the lock busy and skip on the marker ([registration marker](2026-11-10-registration-marker-design.md); on 2026-11-15 all 31 Monitor callbacks of a run with three break requests, starts and resumes skipped this way, [device matrix](../notes/screen-time-device-matrix.md#focus-overwrite-wait-after-the-early-check-2026-11-15)). An extension section writes no marker, so its overwrite's callback waits for the lock and is lost after the bounded retry (lock-order amendment decision 3). So the `didEnd` that the rule above sees is the end of the registered interval; a marker write that failed is the accepted exception (see [Gaps](#gaps-between-steps)).

### Live Activity

13. The projection uses the caught-up session and the envelope's open value (decision 11).
    - `.focus` of an open session (before the base length): the target stays `min(focusEnd, deadline)`, the base end, so the card becomes stale at the base length. The content also carries `focusStart`, the start of the count-up (`now - open focused time`), for an open session.
    - `.openFocus` (after the base length): the target is the focus activity end of decision 5, the next time that a callback can change the session; a chunk end is never a target (extension design decision 25).
14. The card and the compact view of an open session in `.focus` show the `.openFocus` count-up, with its title and its label, once the card is stale or its target has passed, instead of the state that asks for a confirmation. Every other phase keeps the confirmation state.
    The look is the existing `.openFocus` look, so the implementation PR shows it in the visual approval captures (light, dark, largest text) of a stale open card, as a check rather than a new design.
    `[UNCERTAIN]` Whether the system renders the card again at `staleDate` while the app and the Monitor do not run. The current confirmation state already depends on it; device step 4 records it.

### Earlier builds

15. No migration. A session that an earlier build started and that is open at the update has a focus activity registered to its chunk end. At that end the Monitor's `didEnd` catches up and finds nothing due, so decision 12 ends it as `.expired` with the open focused time when the base length was reached. The only device with such a session is the development iPhone, and the device steps start with no session.

## Gaps between steps

The rows of the extension design's [gap table](2026-11-16-focus-filter-extension-design.md#gaps-between-steps) for "Rollover: after step 3" and "Rollover: step 3 throws" no longer exist. The other rows stay.

| Gap                                                                         | Thrown error                                                                                          | Process exit                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| --------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Start: bound end registered, before the save of `active`                    | The M1 rollback stops the activity and records `.startFailed`; `intervalTooLong` takes this path.     | `preparing` stays with an interval of about one week. The `didStart` section (immediate in the app, 5 s later in the extension) or any later section ends it as `.recoveryInterrupted`; the Focus off call does too.                                                                                                                                                                                                                                                         |
| Catch-up computed, before the cleanup's save                                | The cleanup throws; nothing was registered, and the next section catches up from the same timestamps. | Same as a thrown error.                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Transition 1 (request a break), after the overwrite, before the save        | Unchanged (M2).                                                                                       | `active` stays with the `waiting` end registered, which is later by the wait + grace. Manual: unchanged. Open: no callback at the bound end; the callback at the registered end ends the session as `.expired` (decision 6).                                                                                                                                                                                                                                                 |
| Transition 2 (cancel by the person), after the overwrite, before the save   | Unchanged (M2).                                                                                       | `waiting` stays with the `active` end registered. Its `didEnd` comes after `waitEndsAt` + grace, cancels the wait, and the new `active` end is after `now`: decision 12 ends the session with its reason (M2: it registered the `waiting` end again).                                                                                                                                                                                                                        |
| Transition 3 rollback, after the overwrite, before the save                 | Unchanged (M2).                                                                                       | The break copy exists, so the next section's cleanup registers the `waiting` end; in a section outside its own end that registration is made as today; inside its own end it fails, and decision 12 ends the session with its reason.                                                                                                                                                                                                                                        |
| Transition 5 (resume), after the overwrite, before the save                 | Unchanged (M2).                                                                                       | Manual: `breakOver` stays with an earlier end; its `didEnd` has nothing due, and decision 12 ends the session as `.recoveryInterrupted` (M2: it registered the deadline again and ended as `.deadlineMissed`). Open: the registered bound end is later than the deadline, so the restrictions stay past the deadline until the Focus off call, the app's next section or the bound end, each of which ends the session as `.deadlineMissed`. This is the stricter direction. |
| A focus `didEnd` of an overwrite reaches the engine (a marker write failed) | -                                                                                                     | Decision 12 ends a session that still has its interval, as `.recoveryInterrupted` or, for an open session past its base length, `.expired`. The restrictions lift; this is the direction of every other registration failure.                                                                                                                                                                                                                                                |

## One-shot callbacks and their recovery

This replaces the row "Focus activity `didEnd`" of the extension design's [table](2026-11-16-focus-filter-extension-design.md#one-shot-calls-and-their-recovery):

| Callback                                  | Lost when                                       | Recovery                                                                                                                                                                 |
| ----------------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Focus activity `didEnd` at the bound end  | A lock timeout after the retries, late delivery | Any later section: the catch-up stops at the bound, and the timed end gives `.expired`. Until then the restrictions stay, which the Focus off call or the app also ends. |
| Focus activity `didEnd` at a deadline     | Same                                            | As in M2: any later section ends the session as `.deadlineMissed`.                                                                                                       |
| None at the base length or at a chunk end | -                                               | Nothing is due there. The app's timer refresh catches up while the app runs, and the Live Activity follows decision 14.                                                  |

## Bounds

- The interval of an open session is at most the bound length plus the pauses, a little over one week; the M2 pauses (3 breaks with their waits) add minutes.
  The probe accepted 168 and 192 hours from a start 60 s later. Registrations from `startedAt` (every registration after the first) start in the past; the 25-minute registrations of M2 have done that since 2026-11-01.
  `DeviceActivityCenter.MonitoringError` has a case `intervalTooLong` ("The activity's schedule has an interval that is too long.") and states no maximum ([MonitoringError](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror), read through the JSON endpoint on 2026-11-18). `[UNCERTAIN]` above 192 hours; this design never asks for it.
- The bound of extension design decision 8 does not change; the bound end is that bound expressed as a time.
- The registration marker's `validUntil` becomes the bound end for a registration of an open session, about one week later. A marker skips a callback only while it is fresh by `systemUptime` and the lock is busy, so the later `validUntil` widens no skip window.

## Call order across processes

No new call runs in two processes.
The catch-up is a step of every section and saves under `control.lock`, so two processes compute it from the same stored timestamps; whichever section saves first, the other reads the advanced value and finds nothing to add.
After this change an extension section registers a focus activity only in a start (decision 8) and on the stale-wait path of its reconcile, which the lock-order amendment already covers.

## Superseded lines

The implementation PR adds dated reconciliation sections, without rewriting earlier text:

- Extension design decision 3 ("One long interval for the whole Focus was rejected"): decisions 1 and 5 of this document.
- Extension design decision 1 ("a rollover adds one base length to `expiresAt` and registers the new end") and [Rollover](2026-11-16-focus-filter-extension-design.md#rollover) steps 3 to 5, the sentence "The Monitor's `didEnd` of the focus activity runs this", and the [Side artifacts](2026-11-16-focus-filter-extension-design.md#side-artifacts) sentence "A rollover overwrites the focus activity `focus.<UUID>` of the session with a later end": decisions 2, 9 and 10.
- The gap-table rows and the one-shot row named in [Gaps between steps](#gaps-between-steps) and [One-shot callbacks](#one-shot-callbacks-and-their-recovery).
- M2 [Monitoring activities](2026-11-01-m2-break-pass-design.md#monitoring-activities): the open-session rows of decision 5. M2 [Callback with nothing due](2026-11-01-m2-break-pass-design.md#callback-with-nothing-due) and its table: decision 12.
- Lock-order amendment decision 3: the rollover example (decision 8).
- Live Activity decision, open-session row (as amended by extension design decision 25): decisions 13 and 14.
- `AGENTS.md`: the document list.

## Physical-device verification

On the iPhone 16 Pro with a signed Debug build of main after the implementation, with no session at install time (decision 15) and the real base length (25 minutes):

1. App closed, Focus on: the session starts, and the Monitor shields it, as after #172.
2. Focus on past the base length, then past a second chunk: no `Deleting budget for one-shot activity: focus.<UUID>` line from `UsageTrackingAgent` until Focus off; the restrictions stay.
3. Focus off after 2 chunks: `.expired`, with history showing the focused time.
4. Live Activity: start with the app in front, close it, and watch the card at the base length: it shows the count-up (decision 14); record whether it changes without the app.
5. A break started after the base length (the break is available, decision 11), then "다시 집중하기": the session continues; then Focus off: `.expired`.
6. The app opened after a chunk end: the timer screen counts up, and the stored session is caught up (store copy).

The bound end itself (one week) is not run on a device; host tests cover it.

## Verification

- Host tests (`Shared/`): the bound end per base length and per phase (decision 5), with a deadline that comes first; the catch-up in the cleanup of every section, including a save failure; no focus registration in a rollover; the in-own-end rule (decision 12) for a skipped past-end registration (a manual stale-wait cancel still ends as `.expired`), for a failed registration in the cleanup and in `closeWait`, and for nothing due (open past base: `.expired` with the open focused time; otherwise `.recoveryInterrupted`); `StartupRecovery.endCurrent` of an open session past a chunk end; `requestBreak` past a chunk end; the projection and `activitySnapshot` of an open session past a chunk end, and the `focusStart` of an open `.focus`; the M2 transitions 1, 2, 3 and 5 gaps of [Gaps between steps](#gaps-between-steps).
- Each test that asserts a registration end of the old rollover changes to the bound end; the test that asserted the M2 nothing-due re-registration changes to the end of decision 12.
- The separate-process race check, because the cleanup now saves in more sections.
- SDK tests that call the real monitoring adapter with an interval of about one week.
- UI fixtures for the stale open card (decision 14) and the visual approval captures.
- An unsigned device Release build.
- Simulator results do not prove DeviceActivity deletion behavior, interval limits or Live Activity re-rendering on a device.

## Left to the builder

- Where the catch-up lives (`ControlSession` or `SessionControl`) and how `activitySnapshot` returns the open value.
- How a section knows that it runs inside its own end (the callback's activity name and kind are already passed to `handleCallback`).
