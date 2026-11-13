# Registration marker for Monitor callbacks

Date: 2026-11-10.
Status: design for approval.
Source: [issue #101](https://github.com/AndrewDongminYoo/focus-study/issues/101) and its [device measurement of 2026-11-10](https://github.com/AndrewDongminYoo/focus-study/issues/101#issuecomment-6757355284).
This document amends the [2026-10-26 design](2026-10-26-focus-study-design.md), the [M2 design](2026-11-01-m2-break-pass-design.md) and the [M3 design](2026-11-01-m3-schedule-layer-design.md) only where it says so; the implementation PR adds dated reconciliation lines to them (see [Superseded lines](#superseded-lines)).
It keeps the process-lock rule of the [start latency design](2026-11-05-start-latency-design.md): no `await`, UI wait or actor hop inside the lock.
This document changes no code.

## Contract

On 2026-11-10, a signed Debug build on an iPhone 16 Pro with iOS 27.0.1 measured every `DeviceActivityCenter.startMonitoring` call that a lock section makes.
A call for an interval that contains now took about 2.3 seconds for each interval callback that it caused, while the app held the process lock and the main actor.

Decided on 2026-11-10 (option A, "registration marker"):

1. Right before each `startMonitoring` call inside a lock section, the lock holder writes a small App Group file that names the activity that it registers. It deletes the file right after the call, still inside the lock.
2. A Monitor callback for that same activity name that finds the lock busy returns at once instead of retrying, because the lock holder's section already decides the stored phase and the registered schedule for that activity, and it ends with the everyday convergence.
3. Every other callback keeps the bounded retry of today, after one more lock attempt that does not wait ([When the Monitor reads the marker](#when-the-monitor-reads-the-marker)).
4. Lock sections stay synchronous. No lock is released around `startMonitoring`. Session transitions, rollback, privacy limits and identifiers do not change.

Out of scope: `stopMonitoring` calls (see [Stops](#stops)), the first slow call of a run outside any lock ([Evidence](#evidence)), and any change to the app's own lock wait.

Reconciliation (2026-11-10, issue #107): `stopMonitoring` calls inside lock sections are no longer out of scope; the [stop marker design](2026-11-10-stop-marker-design.md) covers them, and its code is the authority.

## Evidence

All values in the two tables are from the [issue #101 comment](https://github.com/AndrewDongminYoo/focus-study/issues/101#issuecomment-6757355284), with the `SCREEN_TIME_TIMING`, `START_LATENCY` and `BREAK_LATENCY` lines of `--screen-time-diagnostics`.
This document does not measure again.

| Registration inside a lock section                                      | Measured time (ms)                 |
| ----------------------------------------------------------------------- | ---------------------------------- |
| New focus activity (start)                                              | 2,309.640                          |
| First everyday part, whose interval contains now                        | 2,280.414 and 2,292.251            |
| Later everyday parts, whose intervals start later (no callback)         | 3.260 to 6.045                     |
| New break activity                                                      | 2,328.948                          |
| Overwrite of the running focus activity (old interval ends, new starts) | 4,607.604, 4,619.592 and 4,618.003 |

| User action                                                                   | Main-actor time (ms) |
| ----------------------------------------------------------------------------- | -------------------- |
| Start, in a section whose everyday convergence also registered its four parts | 4,724.523            |
| Break request                                                                 | 4,643.394            |
| Automatic break start                                                         | 7,011.413            |
| Resume                                                                        | 4,652.340            |

No sample measured a start without an everyday registration in the section.
`[UNCERTAIN]` Such a start would take about 2,419 ms: 4,724.523 ms minus the four everyday registrations of the same sample (2,292.251, 5.741, 3.921 and 3.480 ms, 2,305.393 ms in total).
This value is derived, not measured.

`FocusMonitor` calls `SessionControl.handleCallbackRetryingLock`, which waits for the lock 5 times for 0.25 s with 4 pauses of 0.25 s, about 2.25 s, and then gives up.
The measured unit (about 2.3 s for each callback) matches that budget.

`[UNCERTAIN]` Working explanation: iOS delivers the interval callbacks that a `startMonitoring` call causes to the Monitor extension and waits for them before the call returns, while the app still holds the lock.
The extension waits for the lock until its retry budget ends, and only then does the call return.
No Apple documentation states this.
The marker depends on this explanation for its benefit, not for its safety: every skip in [Which callbacks skip](#which-callbacks-skip) is safe also if iOS does not wait.

`[UNCERTAIN]` Open point: a probe registration outside any lock section took 2,376.897 ms once, as the first call of the run, and then 18.3 to 48.5 ms.
Lock contention does not explain it, and the marker does not address it.
It could be the cost of launching the extension, which no measurement has checked.

## Design

### Marker file

The marker is `registration-marker.json` in the App Group directory `SessionControl/`, next to `control.json` and `control.lock`.

| Field           | Type     | Meaning                                                                                                              |
| --------------- | -------- | -------------------------------------------------------------------------------------------------------------------- |
| `schemaVersion` | `Int`    | `1`.                                                                                                                 |
| `activityName`  | `String` | The exact `DeviceActivityName` raw value that the call passes to `startMonitoring`.                                  |
| `uptime`        | `Double` | `ProcessInfo.processInfo.systemUptime` right before the call.                                                        |
| `validUntil`    | `Date`   | The first time at which something can be due for that activity that the holder did not decide (see the table below). |

- The file is written with an atomic replace and the file protection of `control.json` (`completeUntilFirstUserAuthentication`), and it is encoded with `JSONEncoder` as `control.json` is.
- One file is enough: a lock section registers its activities one after another, so at most one registration call is in progress.
- A reader treats a missing file, a read failure, a file that does not decode and an unknown `schemaVersion` as "no marker". No marker never skips a callback.
- Privacy: an activity name holds a session UUID or an everyday revision UUID and a part. The file holds no tokens, no app or website names, no Focus name and no usage data, and it never leaves the device. It is still a new App Group file, so the 2026-10-26 data boundary sentence gets a reconciliation line ([Superseded lines](#superseded-lines)).

Reconciliation (2026-11-10, issue #107): the file is now schema version 2, with the fields `schemaVersion` `2`, `call` (`register` or `stop`), `activityNames` and an optional `validUntil`, which a `register` marker must have and a `stop` marker does not have ([Marker file, version 2](2026-11-10-stop-marker-design.md#marker-file-version-2)).
A version 1 file now counts as no marker, and so do a `register` marker without `validUntil`, an unknown `call` and an empty `activityNames`.

#### Freshness

A marker is fresh when `0 <= systemUptime(now) - uptime <= 10` seconds.

- `systemUptime` is one clock for the whole system, so a value that the app writes compares correctly with a value that the extension reads. It does not move with a manual clock change or a time zone change, and `SharedControlStore` already uses it for the lock deadline.
- Apple documents it as "The amount of time the system has been awake since the last time it was restarted" (Apple documentation JSON for `ProcessInfo.systemUptime`, read on 2026-11-10). So the age of a marker grows only while the device is awake.
- A restart sets `systemUptime` back near zero. A marker from before the restart with a recorded `uptime` above the current value has a negative age and is not fresh. A recorded value that happens to be 0 to 10 s below the current value looks fresh, but it cannot cause a skip: before the first unlock the file is unreadable (no marker), the skip needs a busy lock, and every lock holder deletes the marker when it takes the lock ([Writing and deleting](#writing-and-deleting)).
- The bound is 10 s because it is longer than the longest single registration that was measured (4.62 s for an overwrite, 2.38 s for the first call of a run). So the marker of a live holder stays fresh during its own call also if the working explanation is wrong and the call stays slow.
- The bound only limits how long a leftover that no lock holder deleted can matter.

### Writing and deleting

1. **Delete on lock take.** Right after any process takes the lock, and before it reads `control.json`, it deletes the marker. No process can be inside a registration call then, so a marker found here is a leftover of a holder that exited. This step is part of `SharedControlStore.withExclusiveAccess`, so every lock holder runs it: every `SessionControl` section, `snapshot()`, `activitySnapshot()`, `everydayStatus(now:authorized:)`, the [control-state read failure](2026-11-01-m3-schedule-layer-design.md#control-state-read-failure) path and the DEBUG fixture read. A failed delete does not fail the section.
2. **Write.** Right before each `startMonitoring` call that goes through `MonitoringClient` (`register`, `registerBreak` and `registerEveryday`), the lock holder writes the marker for that call.
3. **Delete after the call.** Right after the call returns or throws, the holder deletes the marker, still inside the lock. Then the existing steps continue: the save, the rollback, or [Save failure after an overwrite](2026-11-01-m2-break-pass-design.md#save-failure-after-an-overwrite).

- A marker write that throws does not stop the registration. The call runs without a marker, and the callbacks that it causes use the bounded retry of today. The marker is a speed-up, never a condition of a transition.
- A delete that throws leaves a leftover. The next lock holder deletes it in step 1. Until then, the busy-lock condition, the name condition and the freshness bound limit it ([Gaps between steps](#gaps-between-steps)).
- The reader, a Monitor callback, only reads. It never writes or deletes the marker, because it does not hold the lock.
- The write and the delete after the call sit in a `MonitoringClient` wrapper in `Shared/`, so that host tests can check them with a fake client. `SessionControl` makes the wrapper for each lock section with the section's `now` and the engine calendar, and the wrapper never reads the clock. So every `validUntil` comes from the section's `now`, also when an earlier call in the same section ran past a whole minute. The wrapper forms each activity name as `ScreenTimeMonitoring` does, and an SDK test checks that the two are equal. Every caller of `register`, `registerBreak` and `registerEveryday` is a `SessionControl` lock section (a search of the Swift sources on 2026-11-10 found no other caller apart from the forwarding `DiagnosticMonitoring` and the test fakes).

#### Stops

`stopMonitoring` calls write no marker.
M3 states that a stop of an activity with an ongoing interval sends `intervalDidEnd(for:)`.
`[UNCERTAIN]` Whether a stop waits for that callback, as the registrations seem to, was not measured: `DiagnosticMonitoring` times registrations only.
The stops inside lock sections are in `end()` (`stop(id:)`), the start rollback, the re-block (`stopBreak`), the M2 cleanup, the read-failure path, the everyday save and the convergence (`stopEveryday`).
If a later measurement shows the same unit for a session end, a separate spec extends the marker to stops.

Reconciliation (2026-11-10, issue #107): the device measurement showed that unit for stops, and `stopMonitoring` calls inside lock sections now write a `stop` marker with every name that the call passes ([stop marker design](2026-11-10-stop-marker-design.md), [Writing and deleting](2026-11-10-stop-marker-design.md#writing-and-deleting)).

### Which callbacks skip

A Monitor callback returns without running its section only when all of these hold:

1. The lock attempt of the callback did not get the lock (see [When the Monitor reads the marker](#when-the-monitor-reads-the-marker)).
2. The marker is readable and fresh.
3. The marker's `activityName` is equal to the activity name of the callback.
4. The callback kind is `didStart` or `didEnd`. An `intervalWillEndWarning(for:)` never skips.
5. The `now` of the callback attempt is before the marker's `validUntil`.

Reconciliation (2026-11-10, issue #107): condition 3 is now "the callback's activity name is in the marker's `activityNames`", and conditions 4 and 5 apply to a `register` marker. A `stop` marker skips only a `didEnd`, with no time condition ([Which callbacks skip](2026-11-10-stop-marker-design.md#which-callbacks-skip)).

| Registration       | Activity name                                                   | `validUntil`                                                                                                                                                   | Callbacks that the call can cause                                                                         |
| ------------------ | --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `register`         | `focus.<UUID>`                                                  | The end that the call registers                                                                                                                                | A new activity: `didStart`. An overwrite of a running interval: `didEnd` of the old one, then `didStart`. |
| `registerBreak`    | `focus.<UUID>.break.<n>`                                        | The break start plus `breakLength`, the time of its warning                                                                                                    | `didStart`                                                                                                |
| `registerEveryday` | `everyday.<revision>.range` or `everyday.<revision>.window.<n>` | The start of the next whole minute after the section's `now` (not the time of the call), in the engine calendar, both given to the wrapper by `SessionControl` | `didStart`, when the interval contains now                                                                |

A break activity and an everyday activity are never overwritten: a break uses a new index in its session, a save creates a new revision (`EverydaySettingsModel` sets `schedule.revision = UUID()`), and the convergence registers only the parts that `DeviceActivityCenter.activities` does not list.
So only a focus registration can cause a `didEnd`.

#### Why a skip is safe

A skip changes nothing; it only leaves out the section that the callback would run.
So no guard can be bypassed by a skip, and the only question is whether a needed change is lost.

- **`didStart` that the call caused.** It is not a time edge, and nothing is due at it:
  - For the focus activity, the interval starts at `startedAt`, which is in the past at every registration. The callback section would run the M2 cleanup and reconcile order, which the holder's section has decided for the phase it saves. A `didStart` section never runs [Callback with nothing due](2026-11-01-m2-break-pass-design.md#callback-with-nothing-due), and its convergence never registers. Its M2 cleanup step 1 and reconcile step 6 can register the focus activity, but only for a stale wait, and the holder ran the same cleanup at its own start; no registering section leaves a stale wait behind, because `startBreak` requires `now < waitEndsAt + grace`, `cancelWait` closes the wait, and the break-start rollback goes through `closeWait`.
  - For a break activity, the callback, run after the holder, would find `onBreak` with `now < breakEndsAt` and change nothing.
  - For an everyday activity, the callback section has only the everyday convergence to do (or the M3 late-break reconcile, which needs `now >= breakEndsAt`). The holder's section runs the convergence at its end, after this registration.
- **`didEnd` of the replaced focus interval.** The holder replaces the schedule with the end for the phase that it then saves. If that save throws, the holder registers the stored phase's end again under its own marker. The callback, run after the holder, would find nothing due and, as a `didEnd`, would run [Callback with nothing due](2026-11-01-m2-break-pass-design.md#callback-with-nothing-due): one more overwrite of the same end, with two more callbacks.
- **Access.** A callback section evaluates the extension's access value, and a skipped one does not. The next section that knows the access value applies it: every app action calls `FocusModel.refresh()` after it, which reconciles with the app's value, and the app reconciles on launch, on foreground, and on a timer tick when a break end, a timed end or `expiresAt` is due. Under the working explanation, the callback that a call causes already gives up today before the holder releases the lock.

#### A genuine callback while the marker is fresh

A genuine callback is one that time causes, not the registration.
It can arrive for the same name while the holder's call is in progress:

- **Focus `didEnd` at the end of the replaced schedule.** It skips, when `now` is still before the new end. The holder has replaced that schedule with the one for the phase that it saves, and the new end is the next time that the saved phase must change. Whatever the replaced schedule was due for belongs to the phase that the holder replaces.
- **Focus `didEnd` at or after the new end.** It does not skip, because `now >= validUntil`. This covers a new end that passed during the section, because the holder computed it from the section's `now`. The callback takes the bounded retry and, after the holder, ends the session by the M2 [Timed end](2026-11-01-m2-break-pass-design.md#timed-end).
- **Break warning.** It never skips (condition 4). It is also due at `validUntil`.
- **Everyday edge.** Every everyday edge is on a whole minute (second 0, M3 [Monitoring activities](2026-11-01-m3-schedule-layer-design.md#monitoring-activities)). The holder's convergence evaluates the blocking rule at the section's `now`, so it has seen every edge up to that time. An edge after the section's `now` is at or after the next whole minute, so `now >= validUntil` and the callback does not skip.
- **Focus or break `didStart`.** No genuine one exists apart from the callback that the registration causes: a focus interval starts at `startedAt`, and a break interval starts at its registration.

### When the Monitor reads the marker

`handleCallbackRetryingLock` gets one attempt before the retries of today:

1. **Attempt 0.** Try the lock once, without waiting. `SharedControlStore` with a timeout of 0 makes one `flock(LOCK_EX | LOCK_NB)` call and then throws `lockTimeout`. If the lock is busy, read the marker. If the callback matches, return. Attempt 0 goes through the same `ControlStore` value as the retries, with a timeout argument of 0, so a host fake sees it as one more lock attempt. Any error other than `lockTimeout` is thrown at once, as today.
2. **Retries of today.** 5 attempts that wait up to 0.25 s for the lock, with 4 pauses of 0.25 s, each with a fresh `now`. After every `lockTimeout`, read the marker again. If the callback matches, return.

The marker can appear after the callback starts to wait: the holder may register that name later in its section, and then the holder decides that activity as well.
Attempt 0 has no pause after it.
A callback that gets the lock at any attempt runs its section as today.

Worst case for each callback:

| Callback                                                               | Attempt 0, then the retries (this design)                       | Marker read only after the first 0.25 s timeout |
| ---------------------------------------------------------------------- | --------------------------------------------------------------- | ----------------------------------------------- |
| Caused by the holder's call, marker matches                            | One non-blocking lock call and one file read                    | 0.25 s                                          |
| Not matching (another name, a warning, `now >= validUntil`, no marker) | About 2.25 s, as today, plus attempt 0 and up to 6 marker reads | About 2.25 s, as today                          |

With the second variant, a start would still wait about 0.25 s, a break request 0.5 s, an automatic break start 0.75 s, and a resume 0.5 s, or 1.0 s when the early return also overwrites.
This design takes attempt 0.
`[UNCERTAIN]` The time that iOS needs to deliver a callback, including a launch of the extension, is not part of this bound.

The marker is not read before the first lock attempt.
A marker without a busy lock is a leftover of a holder that exited, and the callback must then run, because no other section decides its activity; it can be the repair of [Callback with nothing due](2026-11-01-m2-break-pass-design.md#callback-with-nothing-due).

#### The extension as the holder

Monitor sections register too: the M2 cleanup, reconcile step 6 and Callback with nothing due register the focus activity, and the convergence of a `didEnd` or `intervalWillEndWarning(for:)` section registers missing everyday parts.
The callbacks that such a registration causes go to the Monitor extension.
Each lock attempt opens `control.lock` again, and `flock` locks belong to an open file description, so a second callback in the same process finds the lock busy as a callback in another process does, and the marker works the same way.
`[UNCERTAIN]` Whether iOS delivers a second callback to the extension while its first callback still runs.
The M2 `[UNCERTAIN]` about a `startMonitoring` call inside the activity's own `intervalDidEnd(for:)` does not change.

### Lock sections that register

Every registration through `MonitoringClient` writes the marker, and every such registration runs inside a lock section.

| Section                                                                                                                 | Registrations it can make                                                                                                                                                                     | Writes the marker                                       |
| ----------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| `start` (`begin`)                                                                                                       | `register` of a new focus activity                                                                                                                                                            | yes                                                     |
| `startFromFocusFilter` (`begin`)                                                                                        | `register` of a new focus activity                                                                                                                                                            | yes                                                     |
| `requestBreak`                                                                                                          | `overwriteAndSave`: `register` (overwrite)                                                                                                                                                    | yes                                                     |
| `cancelWait`                                                                                                            | `closeWait`, then `overwriteAndSave`                                                                                                                                                          | yes                                                     |
| `startBreak`                                                                                                            | `registerBreak`, then `register` (overwrite); the rollback through `closeWait` or `registerStoredEnd`                                                                                         | yes, for each call                                      |
| `resume`                                                                                                                | `reBlock` with an early return (`overwriteAndSave` before `breakEndsAt`), then `overwriteAndSave` to `active`                                                                                 | yes, for each call                                      |
| `finish`, `acknowledgeTerminal`, `clearFilterActivation`, `endFromFocusFilter`, `reconcile` (app and `StartupRecovery`) | M2 cleanup step 1 (`registerStoredEnd` or `closeWait`), reconcile step 6 (`closeWait`), [Save failure after an overwrite](2026-11-01-m2-break-pass-design.md#save-failure-after-an-overwrite) | yes                                                     |
| `handleCallback` (Monitor)                                                                                              | The same cleanup and reconcile steps, and Callback with nothing due (`registerStoredEnd`)                                                                                                     | yes, in the extension                                   |
| `saveEveryday`                                                                                                          | `registerEveryday` for every part of the new revision                                                                                                                                         | yes, for each call                                      |
| `turnEverydayOffForToday`                                                                                               | none in its steps                                                                                                                                                                             | no                                                      |
| Everyday convergence at the end of a section that may register (app sections, Monitor `didEnd` and warning sections)    | `registerEveryday` for every missing part of the stored revision                                                                                                                              | yes, for each call, also in the extension               |
| `end()`, the start rollback, the read-failure path                                                                      | stops only                                                                                                                                                                                    | no                                                      |
| `snapshot()`, `activitySnapshot()`, `everydayStatus(now:authorized:)`, DEBUG fixture read                               | none                                                                                                                                                                                          | no; they delete a leftover on lock take                 |
| DEBUG registration probe (`--screen-time-diagnostics`)                                                                  | `probe.<interval>.<n>` outside any lock section                                                                                                                                               | no; its callbacks find the lock free and change nothing |

Reconciliation (2026-11-10, issue #107): the row of `end()`, the start rollback and the read-failure path, and the row of `snapshot()` and `everydayStatus(now:authorized:)`, are superseded for stops: these lock holders now write a `stop` marker for each of their stops ([stop marker design](2026-11-10-stop-marker-design.md), [Stops inside lock sections](2026-11-10-stop-marker-design.md#stops-inside-lock-sections)).

### Stored states and side artifacts

The marker adds no stored phase and no field to `control.json` or `everyday-layer.json`.

| Moment                                                                                                                | `registration-marker.json`                                                 |
| --------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Inside a lock section, from the marker write to the delete after that registration call                               | the marker of that call                                                    |
| Every other moment: every stored phase, no session, a terminal session, `control.json` unreadable, no process running | none; a leftover is deleted by the next lock holder when it takes the lock |

The M2 [break artifacts](2026-11-01-m2-break-pass-design.md#break-artifacts) table and the M3 [stored states and side artifacts](2026-11-01-m3-schedule-layer-design.md#stored-states-and-side-artifacts) tables do not change.
The marker is not a break artifact, and neither cleanup reads it.

### Gaps between steps

Each registration gets three sub-steps: W (write the marker), C (the `startMonitoring` call) and D (delete the marker).
They sit inside the step that registers, so the stored phase, the registered schedule and the restrictions in each gap are those of the enclosing step in the M2 [break artifacts](2026-11-01-m2-break-pass-design.md#break-artifacts) table, the M2 [Callback with nothing due](2026-11-01-m2-break-pass-design.md#callback-with-nothing-due) table, the M3 [gap table](2026-11-01-m3-schedule-layer-design.md#gaps-between-steps) and the [off-for-today](2026-11-08-everyday-off-today.md#gaps-between-steps) table.
A gap before C is the gap before the registration in those tables, and a gap after C is the gap after it.
A thrown error at a sub-step gives the state of a process exit after the sub-step before it, or the rollback that the enclosing transition states.

| Gap                                 | Marker                               | Registered schedule                                                              | Callbacks of that name                                                                                    | Repair                                                                                                                                                                                                                                                                                                                             |
| ----------------------------------- | ------------------------------------ | -------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Delete on lock take throws          | leftover, maybe fresh for up to 10 s | unchanged                                                                        | A callback for the leftover's name that finds this section holding the lock can skip, before `validUntil` | A lost callback, recovered as in [One-shot callbacks](#one-shot-callbacks-and-their-recovery). The next lock holder deletes the leftover.                                                                                                                                                                                          |
| W throws                            | none                                 | C runs as today                                                                  | The bounded retry of today                                                                                | Nothing to repair.                                                                                                                                                                                                                                                                                                                 |
| Exit after W, before C              | leftover                             | earlier (C did not run)                                                          | The lock is free after the exit, so every callback runs its section                                       | The enclosing step's "exit before the registration" row. The next lock holder deletes the leftover.                                                                                                                                                                                                                                |
| C throws                            | deleted in D                         | As the enclosing rollback states; a registration that threw may still exist (M3) | Callbacks that arrived during C while the holder was alive skipped                                        | The existing rollback: the start rollback stops the activity, [Save failure after an overwrite](2026-11-01-m2-break-pass-design.md#save-failure-after-an-overwrite) registers again under a new marker, the break-start rollback stops the break activity, the save stops every new name, and the convergence records the failure. |
| Exit during C or after it, before D | leftover                             | the new schedule, if C completed                                                 | Callbacks that arrived while the holder was alive skipped; later ones find the lock free and run          | The enclosing step's "exit after the registration" row, with the changes in [One-shot callbacks](#one-shot-callbacks-and-their-recovery). The next lock holder deletes the leftover.                                                                                                                                               |
| D throws                            | leftover until the next lock holder  | the new schedule                                                                 | As in the first row, for the rest of this section and until the next lock take                            | As in the first row.                                                                                                                                                                                                                                                                                                               |
| After D                             | none                                 | as the enclosing step                                                            | Normal                                                                                                    | As the enclosing step.                                                                                                                                                                                                                                                                                                             |

### One-shot callbacks and their recovery

- A callback that a registration causes is not one-shot for any change: nothing is due at it ([Why a skip is safe](#why-a-skip-is-safe)).
- The genuine one-shot callbacks never skip: the break warning (the 5-minute limit), every focus end at or after the end that the holder registered, and every everyday edge after the section's `now`.
- A genuine focus `didEnd` of a replaced schedule can skip, and the replacement's end is the next callback of that activity.
- A process exit after C and before the save leaves the same state as in M2 and M3, but the callbacks that C caused and that arrived while the holder was alive are lost. Under the working explanation they are lost today too, because they give up before the holder releases the lock. If the working explanation is wrong, today such a callback could run after the exit; with the marker, these repairs apply instead:
  - **Start**, exit after `register` and before the save of `active`: the stored `preparing` stays, maybe with the focus shield applied, until the next reconcile ends it as `.recoveryInterrupted`: an app launch, or the focus activity's `didEnd` at `expiresAt` at the latest. This is the stricter direction, and it is bounded by the session length.
  - **Overwrite** in transitions 1, 2 and 5: the M2 table [Callback with nothing due](2026-11-01-m2-break-pass-design.md#callback-with-nothing-due) does not use the callbacks of the overwrite; it uses the `didEnd` at the registered end, which is a genuine callback.
  - **Everyday save**, exit after step 3 or 4: M3 expects the `intervalDidStart(for:)` that step 2 sent to repair the store after the lock. With the marker, that callback skips while the app holds the lock, so the next section repairs it. The store stays looser than the new settings until then, and never looser than the earlier settings (M3). This changes the M3 line in [Superseded lines](#superseded-lines).
  - **Convergence**, exit after a registration and before convergence step 3: the M3 rows "exit before convergence step 3" apply: the next section.
- A callback that a leftover makes skip (a failed delete) is recovered by the next section: the app's reconcile after every action, on launch and foreground, and on a timer tick when something is due; the next Monitor callback of any name; for a break, the break activity's `intervalDidEnd(for:)` at +15 min (M2 backstop); for the everyday layer, the M3 lost-callback rows. A leftover can only make a callback skip when that name is in the leftover, the lock is busy, the marker is fresh, and `now < validUntil`.
- A callback that does not match keeps the bounded retry, and after it gives up it is lost as today.

### Guards across sequences of transitions

| Sequence                                                                                  | Result                                                                                                                                                                                                                                                                                            |
| ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Start, then a break request within a second                                               | Each section writes and deletes its own marker. A `didStart` of the start that arrives during the request's overwrite matches the request's marker (`focus.<UUID>`, before the `waiting` end) and skips. One that arrives after the request finds `waiting` with nothing due and changes nothing. |
| Break request, the wait, the automatic break start                                        | The `didStart` of `break.<n>` that arrives during the later focus overwrite of the same section does not match (`focus.<UUID>`), so it takes the bounded retry. After the save it finds `onBreak` before `breakEndsAt` and changes nothing.                                                       |
| Break start, then an early resume                                                         | `resume` overwrites twice (re-block with an early return, then `active`), each under its own marker. The warning of `break.<n>` is never skipped. After the resume it is a current-break callback in `active`, and the reconcile order has nothing due.                                           |
| Resume, then an immediate end                                                             | `finish` stops but does not register, so it writes no marker. Callbacks of the resume that arrive during `finish` take the bounded retry, and after it they find `terminal` and change nothing.                                                                                                   |
| Two registrations of the same name in one section (an early resume, a save failure)       | Each call writes its own marker with its own `validUntil`. A callback of the first call that arrives during the second matches the second, and the holder decides both.                                                                                                                           |
| A callback that started to retry before the holder registered its name                    | It reads the marker after each timeout, and it skips once the holder's marker names it and `now < validUntil`. The holder decides that activity in the same section.                                                                                                                              |
| A holder exits during C; another section takes the lock; a callback for that name arrives | The second section deleted the leftover when it took the lock, so the callback takes the bounded retry and runs after that section.                                                                                                                                                               |
| An everyday save at 09:59:59.9 whose new range starts at 10:00                            | The range part does not contain now, so its call causes no callback. The genuine `didStart` at 10:00 has `now >= validUntil` (10:00), so it takes the bounded retry and converges after the save.                                                                                                 |

Reconciliation (2026-11-10, issue #107): in the row "Resume, then an immediate end", `finish` now writes a `stop` marker for its `stop(id:)`, so a focus `didEnd` of a listed name skips during `finish`, while a `didStart` still takes the bounded retry ([Guards across sequences of transitions](2026-11-10-stop-marker-design.md#guards-across-sequences-of-transitions)).

The M2 [Callback identity](2026-11-01-m2-break-pass-design.md#callback-identity) check, the M3 [callback routing](2026-11-01-m3-schedule-layer-design.md#callback-routing-in-handlecallback) gate and the M3 editing rules are not affected: a skip runs no step, so it cannot make a late callback change a newer session or a newer revision.

### What does not change

- Every lock section stays synchronous: no `await`, no UI wait, no actor hop, and no lock release around `startMonitoring`.
- The lock file, its 0.25-second timeout for app sections, the atomic JSON replace and `FocusFilterHandler`'s own retry.
- The M1 start steps and rollback, the M2 transitions, reconcile order, Save failure after an overwrite, Callback with nothing due and break artifacts, the M3 convergence and callback routing, the M4 filter calls and the off-for-today section.
- The privacy limits: no tokens, usage data or names leave the app's own files, and Report gets no App Group access.
- The Release and DEBUG split. The marker is not DEBUG-only; the timing logs stay DEBUG-only, and the Monitor adds no log.
  - Reconciliation (2026-11-13, #113): the [Monitor timing design](2026-11-13-monitor-timing-design.md) defines the one exception: a DEBUG build of the Monitor writes timing lines to the unified log while the app's diagnostics flag is on. A Release build of the Monitor still adds no log.
- Activity names, accessibility identifiers and `ControlEnvelope.schemaVersion` `2`.
- `FocusMonitor` still synchronizes the Live Activity after each callback, also after a skip. That read takes its own lock attempt and may time out while the holder runs, as today.

### Earlier builds

- The App, the Monitor and the other extensions ship in one bundle, so they update together.
- An earlier build never reads or deletes the marker. A downgrade leaves at most one leftover, which that build ignores. After an upgrade, the first lock holder deletes it.
- A marker with an unknown `schemaVersion` counts as no marker.

## Alternatives considered

**Option B, two-phase start outside the lock.** Save `preparing` in one section, release the lock, call `startMonitoring` with no lock held, then take the lock again to verify, apply and save `active`.
The probe shows that a registration outside the lock takes 18 to 49 ms after the first call of a run, so this would also remove the wait.
It is rejected because it breaks the contract of the 2026-10-26 design and M1 that registration, verification and the save of `active` happen in one lock section, and the same change would be needed for every overwrite in M2 and every registration in M3.
Each split section adds a new interleaving (a Focus filter call, a `finish`, a callback or the everyday convergence between the two halves) that needs its own phase rules and gap tables, which is a redesign of M1 to M3.

**Option C, a smaller retry budget.** Fewer or shorter lock waits in `handleCallbackRetryingLock` make each caused callback cheaper, but every lost unit is still paid, and the budget applies to every callback.
The bounded retry exists because a single lock timeout dropped a one-shot Monitor callback (the M2 implementation review), and the genuine one-shot callbacks include the break warning that keeps a break within 5 minutes, the focus end and the everyday edges.
A smaller budget loses more of them, and it does not remove the wait.
So it is rejected.

## Superseded lines

The implementation PR adds dated reconciliation lines (it does not rewrite the original lines) for these:

- 2026-10-26 design, "타깃과 데이터 경계": "App Group에는 `ControlEnvelope.schemaVersion`과 선택적인 `session`을 저장한다." (as the M4 adjustment extends it): the App Group also holds `registration-marker.json` during a registration call, with an activity name and times only.
- M2 [Process lock and recovery contract](2026-11-01-m2-break-pass-design.md#process-lock-and-recovery-contract): "`FocusMonitor` retries it up to 4 times, 250 ms apart and with a fresh time, only when the lock times out": a callback that matches the marker returns at once, and attempt 0 comes before the retries.
- M3 [Save](2026-11-01-m3-schedule-layer-design.md#save-turn-on-edit-turn-off), "Why this order is safe", third bullet, and the M3 gap row "Save, exit after step 3 or 4": the `intervalDidStart(for:)` that step 2 sends skips while the app holds the lock, so the next section repairs the store.
- M3 [Callback routing in `handleCallback`](2026-11-01-m3-schedule-layer-design.md#callback-routing-in-handlecallback), last line: as for the M2 line above.

## Physical-device verification

Record each result in the [device matrix](../notes/screen-time-device-matrix.md).
Each install and each run that applies real restrictions needs its own explicit approval.
Simulator results and synthetic monitoring cannot establish any of these results.

1. Build a signed Debug build of the implementation commit, and run it with `--screen-time-diagnostics` on the device of the 2026-11-10 measurement (iPhone 16 Pro, iOS 27.0.1), or record the device and iOS version used.
2. With the everyday layer on and its range containing now, launch the app. Record the `SCREEN_TIME_TIMING op=register_everyday` lines.
3. Start a session. Record `START_LATENCY` and the `register` line.
4. Request a break, let the break start, and resume once at the end of the break and once with an early return. Record `BREAK_LATENCY` for `request`, `startBreak` and `resume`, and the `register` and `register_break` lines.
5. Repeat steps 3 and 4 at least 3 times in one run, and once as the first action after a new launch.

Acceptance:

- No `register`, `register_break` or `register_everyday` line inside a lock section is at or above 2,000 ms, except the first registration of a run, which is recorded separately as the open point of [Evidence](#evidence).
- `START_LATENCY` and each `BREAK_LATENCY` (`request`, `startBreak`, `resume`) are below 1,000 ms, except a sample that contains the first registration of a run.
- Regression checks without the app in the foreground: the break re-blocks about 3 minutes after it starts, a session ends at its focus end, and an everyday window end applies the everyday shield again.
- If the samples still show the unit of about 2.3 s, the working explanation is wrong. Record that, keep #101 open, and decide in a new spec whether to keep the marker and whether to reconsider option B or C.

## Verification for the implementation

Follow `AGENTS.md` and [README verification](../../README.md#실행과-검증).

- `Shared/` changes, host tests in `CoreTests/` with fakes:
  - The marker encodes and decodes; a missing, unreadable or undecodable file and an unknown `schemaVersion` count as no marker.
  - Freshness at ages -0.001, 0, 10 and 10.001 s.
  - `validUntil` for each registration: the registered focus end, the break warning time, and the next whole minute in the engine calendar.
  - The skip rule for every condition: a name that differs, a warning, a focus `didEnd` before and at `validUntil`, an everyday `didStart` at the next minute, and no marker.
  - The retry: a match at attempt 0 returns without a pause and without running the section; a callback that does not match keeps 4 pauses; a marker that appears after a later timeout makes the callback return; a callback that gets the lock runs its section.
  - Existing tests that change: attempt 0 takes one more entry of the `World` fake's `lockFailures`, so three tests in `CoreTests/BreakControlTests.swift` fail unchanged. The implementation PR gives each of them one more `lockTimeout`, so that each keeps its purpose: `testWarningCallbackRetriesLockTimeoutAndStillReBlocks` (2 timeouts, pauses `[0.25]`, 3 clock reads), `testFocusEndCallbackRetriesLockTimeoutWithFreshTime` (2 timeouts, pauses `[0.25]`, the session still ends by the fresh time) and `testCallbackRetryStopsAfterFourLockTimeouts` (6 timeouts, 4 pauses, `lockTimeout` thrown, state unchanged). `testCallbackRetryIgnoresOtherErrors` does not change, because attempt 0 throws the first error. A search of the Swift sources on 2026-11-10 found no other caller of `handleCallbackRetryingLock` apart from `FocusMonitor`; the race helper `Tests/Fixtures/ControlRaceHelper.swift` does not call it. The timeout argument also reaches every `ControlStore` conformer: `SharedControlStore` and the fakes in `CoreTests/` (`World`, `EverydayWorld`, `FilterWorld`, `MemoryControlStore`) and `SDKTests/FocusModelTests.swift` (`ModelTestStore`).
  - The write and delete around every registration: a fake monitoring client reads the marker during its call; the marker is deleted after a call that throws; a marker write that throws does not stop the registration; every lock holder, also `snapshot()`, `activitySnapshot()` and `everydayStatus(now:authorized:)`, deletes a leftover.
- The separate-process race check: the marker source joins the `xcrun swiftc` file list in the README. New cases: a process holds the lock with the marker for name N, and a second process's callback for N returns at once with `control.json` unchanged; a callback for another name waits for the full bounded retry; after a holder exits without deleting its marker, the next process takes the lock, runs its section and deletes the leftover. The README lists the new `PASS` lines.
- `Integration/` changes, SDK tests: the marker's `activityName` equals the `DeviceActivityName` raw value that `ScreenTimeMonitoring` passes for the focus, break and everyday names, and the file has the protection of `control.json`.
- Compile the App and the Monitor, and build an unsigned device Release build.
- The [physical-device verification](#physical-device-verification) above. Without it, the latency result stays unverified.

## Left to the builder

- The name and the shape of the timeout argument for attempt 0 on `ControlStore`.
- The names of the marker type and its reader. The file name `registration-marker.json` is fixed by this document.
