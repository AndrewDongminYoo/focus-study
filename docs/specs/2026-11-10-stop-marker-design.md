# Registration marker for stops

Date: 2026-11-10.
Status: design for approval.
Source: [issue #107](https://github.com/AndrewDongminYoo/focus-study/issues/107) and its [device measurement of 2026-11-10](https://github.com/AndrewDongminYoo/focus-study/issues/107#issuecomment-6766205555).
This document extends the [registration marker design](2026-11-10-registration-marker-design.md) (below, "the marker design") to the `stopMonitoring` calls inside lock sections, as its [Stops](2026-11-10-registration-marker-design.md#stops) section foresaw.
It amends the marker design only where it says so; the implementation PR adds dated reconciliation lines to it (see [Superseded lines](#superseded-lines)).
It keeps the process-lock rule: lock sections stay synchronous, with no `await`, UI wait or actor hop inside the lock, and no lock released around `startMonitoring` or `stopMonitoring`.
This document changes no code.

## Contract

On 2026-11-10, a signed Debug build (`b89cd74`) on an iPhone 16 Pro timed every `stopMonitoring` call that a lock section made.
A stop of an activity whose interval was ongoing took about 2.28 to 2.29 seconds, while the app held the process lock and the main actor.

Decided in this document:

1. The marker file of the marker design also covers stops. Right before each `stopMonitoring` call inside a lock section, the lock holder writes the marker with every activity name that the call passes, and it deletes the marker right after the call, still inside the lock.
2. A Monitor `intervalDidEnd(for:)` callback for one of those names that finds the lock busy returns at once instead of retrying, because the lock holder's section decides the stored phase after the stop.
3. A stop marker never lets an `intervalDidStart(for:)` or an `intervalWillEndWarning(for:)` callback skip.
4. Every lock holder writes the marker for its stops, also the read-failure path of `snapshot()` and `everydayStatus(now:authorized:)`, which do not run through `section`.
5. A DEBUG `END_LATENCY` line times the main-actor part of a session end, so that a session end has a total as a start and a break transition have.
6. Session transitions, rollbacks, the order of steps in every section, privacy limits, activity names and the bounded retry for callbacks that do not match stay as they are.

Out of scope: the first slow call of a run outside any lock (an open point of the marker design), and any change to the app's own lock wait.

## Evidence

All values are from the [issue #107 comment](https://github.com/AndrewDongminYoo/focus-study/issues/107#issuecomment-6766205555), with the `SCREEN_TIME_TIMING` and `BREAK_LATENCY` lines of `--screen-time-diagnostics`.
This document does not measure again.

| Stop inside a lock section                               | Measured time (ms)      |
| -------------------------------------------------------- | ----------------------- |
| `stop` in a session end from `active`                    | 2,289.171 and 2,288.312 |
| `stop_break` in a resume with an early return (re-block) | 2,279.939               |

In the same resume, the two focus registrations took 27.389 and 52.423 ms, and the whole resume took 2,419.169 ms, so the stop is 94% of it.
In the same run, every registration inside a lock section took 25.434 to 134.548 ms (134.548 ms is the first registration of the run), so the marker design works for registrations.

`FocusMonitor` calls `SessionControl.handleCallbackRetryingLock`, which makes attempt 0 and then waits for the lock 5 times for 0.25 s with 4 pauses of 0.25 s, about 2.25 s, and then gives up.
The measured stops are that budget plus about 30 to 40 ms.

`[UNCERTAIN, strong]` Working explanation, as for registrations in the marker design: a stop of an activity with an ongoing interval sends `intervalDidEnd(for:)` (M3 states that it sends it), and iOS waits for that callback before the call returns, while the app still holds the lock.
The callback spends its retry budget and gives up, and only then does the call return.
No Apple documentation states this, and no Monitor-side line timed that callback.
So today the callback that a stop causes is already lost while the holder is alive: a skip removes the wait and loses nothing that today's code keeps.
The marker depends on this explanation for its benefit, not for its safety: every skip in [Which callbacks skip](#which-callbacks-skip) is safe also if iOS does not wait.

Not measured: a stop of two ongoing intervals in one call (a session end during `onBreak`, which stops the focus and the current break activity), `stop_everyday`, the start rollback, the M2 cleanup and the read-failure path.
`[UNCERTAIN]` A stop of two ongoing intervals would take about 4.6 s today, as an overwrite of a running focus interval did before the marker design (two callbacks).
This value is derived, not measured.

## Design

### Marker file, version 2

The file stays `registration-marker.json` in the App Group directory `SessionControl/`, the name that the marker design fixed.
The schema changes to version 2, because one `stopMonitoring` call can pass several names.

| Field           | Type       | Meaning                                                                                                                              |
| --------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `schemaVersion` | `Int`      | `2`.                                                                                                                                 |
| `call`          | `String`   | `register` or `stop`.                                                                                                                |
| `activityNames` | `[String]` | The exact `DeviceActivityName` raw values that the call passes. A registration passes one name; a stop passes one or more names.     |
| `uptime`        | `Double`   | `ProcessInfo.processInfo.systemUptime` right before the call, as in version 1.                                                       |
| `validUntil`    | `Date?`    | For `register`, the value of the marker design. For `stop`, absent: a stop marker has no time bound (see [Time bound](#time-bound)). |

- The encoding, the atomic replace, the file protection and freshness (`0 <= age <= 10` s) do not change.
- A reader treats a version 1 file, a missing or unreadable file, a file that does not decode, a `register` marker without `validUntil`, an unknown `call` and an empty `activityNames` as "no marker". No marker never skips a callback.
- One file is still enough: a lock section makes its registration and stop calls one after another.
- Privacy: the file holds activity names and times only, as in version 1.

### Writing and deleting

The three steps of the marker design apply to stops without change: delete on lock take, write right before the call, delete right after the call.

- **Write.** Right before each `stopMonitoring` call that goes through `MonitoringClient` (`stop(id:)`, `stopBreak(id:index:)` and `stopEveryday(revision:part:)`), the lock holder writes a `stop` marker with every name that the call passes.
- **Delete after the call.** Right after the call returns, still inside the lock. A stop does not throw.
- A marker write that throws does not stop the stop call, and a delete that throws leaves a leftover for the next lock holder, as for registrations.
- The wrapper that writes registration markers also writes stop markers, so host tests check both with a fake client.

The names of `stop(id:)` must be the set that `ScreenTimeMonitoring.stop(id:)` passes: the focus name `focus.<UUID>`, the name of every break of that session that `registeredBreaks` lists, and `focus.<UUID>.break.<n>` for `n` in `1...BreakTiming.maxBreaks`.
The wrapper forms them from `base.registeredBreaks` and the name functions of the marker design, and an SDK test checks that the set is equal to the one that the adapter passes.
`stopBreak(id:index:)` passes `focus.<UUID>.break.<n>`, and `stopEveryday(revision:part:)` passes the everyday name of that part.

### Lock holders that do not run through `section`

`snapshot()` and `everydayStatus(now:authorized:)` call `read(_:)` inside `store.withExclusiveAccess`, so their read-failure stops use the base client today and write no marker.
They must write the marker as every other lock holder does.
`activitySnapshot()` and the DEBUG fixture read make no Screen Time call, so they do not change.
How the wrapper reaches them is left to the builder; a stop marker needs no section time, so the wrapper for these stops does not need the `now` and calendar that registration markers use.

### Which callbacks skip

A Monitor callback returns without running its section only when all of these hold:

1. Its lock attempt did not get the lock (attempt 0 and every retry, as in the marker design).
2. The marker is readable and fresh.
3. The callback's activity name is in `activityNames`.
4. For a `register` marker: the conditions 4 and 5 of the marker design (the kind is `didStart` or `didEnd`, and `now < validUntil`).
5. For a `stop` marker: the kind is `didEnd`.

A `stop` marker never lets a `didStart` or a warning skip: a stop causes neither of them, and the break warning is the one-shot re-block that keeps a break within 5 minutes.

#### Time bound

A `stop` marker has no `validUntil`.
A live holder decides every `didEnd` of a name that it stops, also a genuine one that time causes during the call, because the stopped activity sends no later callback and the holder's section saves the phase that follows the stop ([Stops inside lock sections](#stops-inside-lock-sections)).
The only skip that a time bound could prevent is a leftover whose names were not stopped, and it needs two failures in a row; [Gaps between steps](#gaps-between-steps) gives that row and its repair.
A bound such as the section's `now` plus a few seconds would add a clock read to a call that has none, and it would not remove that row: the freshness of 10 s already bounds it.

### Stops inside lock sections

Each row says what the `didEnd` that the stop causes would do if it ran after the holder, which is the change that a skip leaves out.
A callback after the holder runs the cleanup, the M2 [callback identity](2026-11-01-m2-break-pass-design.md#callback-identity) check or the M3 [callback routing](2026-11-01-m3-schedule-layer-design.md#callback-routing-in-handlecallback), the reconcile order, [Callback with nothing due](2026-11-01-m2-break-pass-design.md#callback-with-nothing-due) for a focus `didEnd`, and the everyday convergence at its end.

| Section and stop                                                                                                                                                 | Names                                                    | State after the holder                                                                                  | The `didEnd` after the holder                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `end()` (transition 6): `stop(id:)` after the save of `ending` and the shield clear                                                                              | the focus name and every break name of the session       | `terminal`, both activities stopped, focus shield cleared, everyday store converged                     | Finds `terminal`: the reconcile returns, and Callback with nothing due excludes `terminal`. Nothing changes.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `end()` whose terminal save throws                                                                                                                               | as above                                                 | `ending` stored (or the earlier phase, when both saves threw), activities stopped, focus shield cleared | Would run the reconcile: `ending` ends again (one more stop of names already stopped), and an earlier phase without a registered focus activity ends as `.recoveryInterrupted`. With the skip, the next section does the same, but `FocusModel.end()` does not reconcile after a thrown `finish` (it clears `current` and shows its error), so the next section is an app launch, a foreground, or a Monitor callback that reaches the reconcile: an everyday edge does so only in `onBreak` after `breakEndsAt`, and the focus and break activities are stopped. When both saves threw during `onBreak`, the stored `onBreak` keeps the everyday layer lifted until then. The focus restrictions are already off, which is what the end asked for. Under the working explanation the callback that the stop causes gives up today before the holder releases the lock, so this state and its recovery are the same today; issue #112 tracks the missing reconcile after a thrown `finish`. |
| Reconciliation (2026-11-13, #112) of the row above                                                                                                               | as above                                                 | as above                                                                                                | The row above says that `FocusModel.end()` does not reconcile after a thrown `finish`; it now does. The app reconciles right after the thrown `finish`, and when that reconcile throws too, on every timer tick of the timer screen in the foreground until one succeeds, so a stored `onBreak` no longer keeps the everyday layer lifted until a launch, a foreground or a Monitor callback. The end message stays until that reconcile succeeds, and also when the reconcile finds the same session still running (a lock timeout threw before the end's section, so nothing was stopped). `SessionControl.end` and its order are unchanged, and `FocusModel.end()` in `App/FocusModel.swift` with `testEndWhoseSavesFailReconcilesOnTicksUntilTheStoreIsWritable` and `testEndLockTimeoutKeepsTheSessionAndReportsTheFailedEnd` is the authority.                                                                                                                                        |
| Start rollback in `begin`: `stop(id:)` after the shield clear                                                                                                    | the new focus name and its break names (none registered) | `terminal` with `.startFailed`, or the stored `preparing` when that save throws                         | Finds `terminal` and changes nothing, or ends `preparing` as `.recoveryInterrupted`, which every next reconcile also does (M1 rollback).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `reBlock` (transition 4): `stopBreak` after the save of `breakOver`, in `resume`, in the app's reconcile and in the Monitor warning section                      | `focus.<UUID>.break.<n>`                                 | `breakOver` committed, the shield back on, the break activity stopped; `resume` then saves `active`     | Passes the identity check as the current break. The reconcile finds `breakOver` or `active` with nothing due for the break. Nothing changes. `reBlock` reaches the stop only after its save succeeded, so a skip never leaves `onBreak` without a break activity.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `startBreak` rollback: `stopBreak` of the new index                                                                                                              | `focus.<UUID>.break.<n>`                                 | `waiting` closed to `active`, or `waiting` with the copy removed                                        | The stored `breaksTaken` was not raised, so the name is not the current break, and the identity check returns. Nothing changes.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| M2 cleanup: `stopBreak` of every break activity that the stored phase does not allow                                                                             | `focus.<UUID>.break.<n>` of an earlier break or session  | the orphan stopped                                                                                      | Not the current break, so the identity check returns; its own cleanup finds nothing left to stop.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `read(_:)` failure (in sections, `snapshot()` and `everydayStatus(now:authorized:)`): `stop(id:)` for every registered session, `stopBreak` for every break      | every focus and break name                               | `control.json` unreadable, both shields cleared, focus and break activities stopped, copies removed     | Reads `control.json`, fails the same way, and runs the same stops of names that are already stopped. Nothing changes.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `saveEveryday` rollback: `stopEveryday` for every part of the new revision                                                                                       | `everyday.<new revision>.<part>`                         | the stored file and the store as before the save                                                        | Takes the everyday route: the M3 late-break reconcile only in `onBreak` after `breakEndsAt`, then the convergence against the stored file, which the holder's own convergence at the end of its section already ran.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `saveEveryday` after the write: `stopEveryday` of every other revision                                                                                           | `everyday.<earlier revision>.<part>`                     | the new file, the new revision registered, the earlier one stopped                                      | As in the row above. The new revision's parts carry every everyday edge from now on, and their names are not in the marker.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Everyday convergence: `stopEveryday` without access, of an earlier revision once the stored one is complete, and of parts that the stored schedule no longer has | `everyday.<revision>.<part>`                             | the stored layer's parts only, or none without access, and the store set by convergence step 3          | Runs the same convergence against the same stored file and access, so it finds nothing to change at the holder's `now`. Work that became due during the stop has its own callback that does not skip ([Work that becomes due during a stop](#work-that-becomes-due-during-a-stop)). The parts that remain registered are not in the marker.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |

A stop of a name whose interval is not ongoing causes no callback, so the names in `stop(id:)` that are not registered cost nothing.

#### Work that becomes due during a stop

A callback section evaluates its own fresh `now`, so a `didEnd` that runs after the holder can find a change that became due during the holder's section, after the holder's `now`: a break end (the M3 late-break reconcile on the everyday route, or the reconcile of a focus or break name), a timed focus end, or an everyday edge.
A skipped `didEnd` that a stop caused is never the trigger of such a change, because each of them has its own genuine callback that a `stop` marker does not list:

- **Break end.** The break warning at `breakEndsAt` re-blocks, and it never skips (M2). The break activity's `didEnd` at +15 min is the backstop, and it is listed only while the holder stops that break activity, which happens only after the holder committed `breakOver` or while it ends the session.
- **Timed focus end.** The focus activity's `didEnd` at the registered end is listed only while the holder stops that focus activity, which happens only while it ends the session or rolls back a start.
- **Everyday edge.** The parts of the stored layer stay registered, are not listed, and carry the edges.

So these callbacks take the bounded retry while the holder runs, as today.
With the marker, the holder's stops no longer wait for their own callbacks, so a holder section is expected to take far less than the 2.25 s budget, and such a callback gets the lock after the holder.
`[UNCERTAIN]` That bound holds only if the working explanation holds; the [physical-device verification](#physical-device-verification) measures it.

If the warning still gives up, because the holder's section holds the lock for longer than its budget, the M2 re-block triggers for a lost warning apply unchanged ([Transitions](2026-11-01-m2-break-pass-design.md#transitions), transition 4): any reconcile when `now >= breakEndsAt` (the app's foreground and timer tick, any later Monitor callback of this session, and an everyday edge in `onBreak` after `breakEndsAt`), and the break activity's `intervalDidEnd(for:)` at +15 min as the last backstop.
With the app in the background and no other callback, that backstop is the bound, which M2 already accepts for a lost warning.
The stop marker does not add this case: before it, the holder's stop alone took about 2.28 s, which is longer than the warning's budget, so a warning that arrived during such a stop gave up already.

#### The extension as the holder

Monitor sections stop too: the warning section re-blocks (`stopBreak`), every callback section can run the M2 cleanup and the convergence, and a callback section can end the session (`stop(id:)`).
As in [The extension as the holder](2026-11-10-registration-marker-design.md#the-extension-as-the-holder) of the marker design, a second callback in the same process finds the lock busy and reads the marker in the same way.
`[UNCERTAIN]` Whether iOS delivers that `didEnd` to the extension while the extension's warning section still runs.

#### A genuine `didEnd` during a stop

A genuine `didEnd` is one that time causes, not the stop.
It can arrive for a name that the holder is stopping, and it skips:

- **Focus end at `expiresAt` or the deadline, during `end()`.** The holder ends the session with its own reason. After the holder the callback would find `terminal`.
- **Break activity end at +15 min (the M2 backstop), during `reBlock` or `end()`.** The holder has committed `breakOver` or is ending the session.
- **Everyday edge of a part that the holder stops.** The part leaves the stored layer (an earlier revision, a removed part, or no access), and the parts that stay registered carry the edges of the stored layer.

A genuine `didEnd` of a name that the marker does not list keeps the bounded retry.

### Stored states and side artifacts

The marker adds no stored phase and no field to `control.json` or `everyday-layer.json`.
The table [Stored states and side artifacts](2026-11-10-registration-marker-design.md#stored-states-and-side-artifacts) of the marker design applies, with "registration call" read as "registration or stop call".

### Gaps between steps

Each stop gets the three sub-steps of the marker design: W (write the marker), C (the `stopMonitoring` call) and D (delete the marker).
They sit inside the step that stops, so the stored phase, the registered schedule and the restrictions in each gap are those of the enclosing step in the M2 [break artifacts](2026-11-01-m2-break-pass-design.md#break-artifacts) table, the M3 [gap table](2026-11-01-m3-schedule-layer-design.md#gaps-between-steps) and the [off-for-today](2026-11-08-everyday-off-today.md#gaps-between-steps) table.

| Gap                                                                           | Marker                                 | Registered activities   | Callbacks of those names                                                                         | Repair                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| ----------------------------------------------------------------------------- | -------------------------------------- | ----------------------- | ------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| W throws                                                                      | none                                   | C runs as today         | The bounded retry of today                                                                       | Nothing to repair.                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Exit after W, before C                                                        | leftover                               | not stopped             | The lock is free after the exit, so every callback runs its section                              | The enclosing step's "exit before the stop" row. The next lock holder deletes the leftover when it takes the lock.                                                                                                                                                                                                                                                                                                                             |
| Exit after W, before C, and then the next holder's delete on lock take throws | leftover, fresh for up to 10 s after W | not stopped             | While that next holder runs, a genuine `didEnd` of a listed name can skip                        | The skipped change is recovered as a lost callback: a focus end by the app's reconcile (after every action, on launch, on foreground, on a timer tick when an end is due) or by the next Monitor callback of any name; the session stays restricted until then, which is the stricter direction. A break end by the M2 cleanup and the warning, an everyday edge by the M3 lost-callback rows. The holder after that one deletes the leftover. |
| Exit during C or after it, before D                                           | leftover                               | stopped, if C completed | Callbacks that arrived while the holder was alive skipped; later ones find the lock free and run | The enclosing step's "exit after the stop" row. A stopped activity sends no later callback, so the leftover can only match a name that is no longer registered. The next lock holder deletes the leftover.                                                                                                                                                                                                                                     |
| D throws                                                                      | leftover until the next lock holder    | stopped                 | As in the row above, for the rest of this section and until the next lock take                   | As in the row above.                                                                                                                                                                                                                                                                                                                                                                                                                           |
| After D                                                                       | none                                   | as the enclosing step   | Normal                                                                                           | As the enclosing step.                                                                                                                                                                                                                                                                                                                                                                                                                         |

The row "Delete on lock take throws" of the marker design applies to a `stop` leftover in the same way.

### One-shot callbacks and their recovery

- A `didEnd` that a stop causes is not one-shot for any change: the holder's section decides the stopped activity ([Stops inside lock sections](#stops-inside-lock-sections)).
- The genuine one-shot callbacks that a stop marker can make skip are the `didEnd` callbacks of names that the holder is stopping ([A genuine `didEnd` during a stop](#a-genuine-didend-during-a-stop)); the holder's section decides them as well.
- The break warning never skips, and every callback of a name that the marker does not list keeps the bounded retry and, after it gives up, is lost as today.
- A process exit after C and before the save that follows the stop leaves the same state as in M2 and M3, and the callbacks that C caused while the holder was alive are lost. Under the working explanation they are lost today too. The enclosing transitions already repair that state without them: `end()` saved `ending` before the stop, so the next reconcile ends the session; `reBlock` saved `breakOver` before the stop; the rollbacks and the convergence leave the state that the next section repairs (M1, M2, M3).
- A leftover that a failed delete leaves can make a callback skip only when its name is listed, the lock is busy, the marker is fresh and the kind is `didEnd` ([Gaps between steps](#gaps-between-steps)).

### Guards across sequences of transitions

| Sequence                                                                                          | Result                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Resume with an early return: overwrite, stop, overwrite in one section                            | The re-block overwrite writes a `register` marker for `focus.<UUID>` and deletes it; `stopBreak` writes a `stop` marker for `focus.<UUID>.break.<n>` and deletes it; the overwrite to `active` writes a `register` marker again. A `didEnd` of the break activity that arrives during the last overwrite does not match (`focus.<UUID>`), takes the bounded retry, and after the section finds `active` with nothing due. |
| Resume, then an immediate end                                                                     | `finish` writes a `stop` marker for its `stop(id:)`. A `didStart` or `didEnd` of the resume's overwrite that arrives during `finish` matches only if its name is listed and it is a `didEnd`; a focus `didEnd` then skips, and after `finish` it would have found `terminal`. A `didStart` takes the bounded retry and finds `terminal`.                                                                                  |
| A session end during `onBreak`                                                                    | One `stop(id:)` call stops the focus and the current break activity. Both `didEnd` callbacks match the one marker and skip.                                                                                                                                                                                                                                                                                               |
| The warning section re-blocks, then the person ends the session                                   | The warning section's `stopBreak` writes its marker in the extension. The app's `finish` waits for the lock as today, then writes its own marker for `stop(id:)`.                                                                                                                                                                                                                                                         |
| An everyday save whose earlier revision has an ongoing range                                      | The new revision's registrations write `register` markers, the stop of the earlier revision writes a `stop` marker. The earlier range's `didEnd` skips; the new range's `didStart` matched its own `register` marker before.                                                                                                                                                                                              |
| A break ends while a section stops an earlier everyday revision                                   | The earlier revision's `didEnd` matches the `stop` marker and skips. The break warning at `breakEndsAt` does not match, takes the bounded retry, gets the lock after the section, and re-blocks. Without access, convergence stopped every everyday part, and the warning still re-blocks the focus layer.                                                                                                                |
| A holder exits after W of a stop; another section takes the lock; a `didEnd` of that name arrives | The second section deleted the leftover when it took the lock, so the callback takes the bounded retry and runs after that section.                                                                                                                                                                                                                                                                                       |

The M2 callback identity check, the M3 callback routing gate and the M3 editing rules are not affected: a skip runs no step.

### Session end timing

A DEBUG `END_LATENCY total_ms=...` line, logged only under `--screen-time-diagnostics` like `START_LATENCY` and `BREAK_LATENCY`, times `FocusModel.end()` on the main actor from the tap to the return of the engine call, with no frame wait or UI animation in it.
It needs no new accessibility identifier, and default runs, synthetic UI fixtures and Release builds emit nothing new.
`docs/notes/development-launch-arguments.md` and `docs/notes/2026-11-05-start-latency.md` list it next to the other latency lines.

### What does not change

- Every lock section stays synchronous, and no lock is released around `startMonitoring` or `stopMonitoring`.
- The marker design for registrations: the `validUntil` rules, attempt 0, the retries, freshness and the delete on lock take.
- The M1 start steps and rollback, the M2 transitions, reconcile order, cleanup and break artifacts, the M3 convergence and callback routing, the M4 filter calls and the off-for-today section.
- The privacy limits, the Release and DEBUG split (the marker is not DEBUG-only; the timing lines are), activity names, accessibility identifiers and `ControlEnvelope.schemaVersion` `2`.

### Earlier builds

- The App, the Monitor and the other extensions ship in one bundle, so they update together.
- A build of the marker design reads a version 2 file as "no marker" and never skips because of it. A version 1 leftover after an upgrade counts as no marker, and the first lock holder deletes it.

## Alternatives considered

**A name prefix instead of a name list.** A `stop(id:)` marker could hold `focus.<UUID>` and match every name that starts with it.
It keeps schema version 1, but it adds a second meaning to `activityName` that depends on the call, and the everyday stops would still need one name each.
It is rejected because a list states exactly what the call passes, and an SDK test can compare it with the adapter.

**A time bound for stop markers.** See [Time bound](#time-bound).

**Stops outside the lock.** Moving the stops after the save and out of the lock section would remove the wait, but it splits every transition that stops, as option B of the marker design would, and it is rejected for the same reason.

## Superseded lines

The implementation PR adds dated reconciliation lines (it does not rewrite the original lines) to the marker design for these:

- Contract, "Out of scope: `stopMonitoring` calls (see Stops)": stops are covered by this document.
- [Marker file](2026-11-10-registration-marker-design.md#marker-file): the fields `schemaVersion` `1` and `activityName` become version 2 with `call`, `activityNames` and an optional `validUntil`.
- [Stops](2026-11-10-registration-marker-design.md#stops), "`stopMonitoring` calls write no marker": they write a `stop` marker.
- [Which callbacks skip](2026-11-10-registration-marker-design.md#which-callbacks-skip), condition 3 ("The marker's `activityName` is equal to the activity name of the callback"): the name is in `activityNames`, and a `stop` marker adds its own kind rule.
- [Lock sections that register](2026-11-10-registration-marker-design.md#lock-sections-that-register), the row "`end()`, the start rollback, the read-failure path: stops only, no", and the row of `snapshot()` and `everydayStatus(now:authorized:)`: they write `stop` markers for their stops.
- [Guards across sequences of transitions](2026-11-10-registration-marker-design.md#guards-across-sequences-of-transitions), the row "Resume, then an immediate end" ("`finish` stops but does not register, so it writes no marker"): see the same row in this document.

## Physical-device verification

Record each result in the [device matrix](../notes/screen-time-device-matrix.md) and in issue #107.
Each install and each run that applies real restrictions needs its own explicit approval.
Simulator results and synthetic monitoring cannot establish any of these results.

1. Build a signed Debug build of the implementation commit, and run it with `--screen-time-diagnostics` on the iPhone 16 Pro of the 2026-11-10 measurement, or record the device and iOS version used.
2. Start a session and end it from `active`. Record `stop` and `END_LATENCY`.
3. Start a session, request a break, let the break start, and resume with an early return. Record `stop_break`, `register` and `BREAK_LATENCY action=resume`.
4. Start a session, let a break start, and end the session during the break. Record `stop` and `END_LATENCY`.
5. With the everyday layer on and its range containing now, save an edit. Record `register_everyday` and `stop_everyday`.
6. Repeat steps 2 to 4 at least 3 times in one run, and once as the first action after a new launch.

Acceptance:

- No `stop`, `stop_break` or `stop_everyday` line inside a lock section is at or above 2,000 ms.
- `END_LATENCY` and `BREAK_LATENCY action=resume` are below 1,000 ms, except a sample that contains the first registration of a run.
- Registrations stay inside the acceptance of the marker design.
- `END_LATENCY` and `BREAK_LATENCY` bound the lock-hold time of the app sections that they time; record them as that bound. Monitor sections have no timing line, so their lock-hold time stays unverified.
- Regression checks without the app in the foreground: a session end lifts the focus restrictions, the break re-blocks about 3 minutes after it starts, a session ends at its focus end, and an everyday window end applies the everyday shield again.
- If the samples still show the unit of about 2.3 s, the working explanation is wrong for stops. Record that, keep #107 open, and decide in a new spec whether to keep the stop marker.

## Verification for the implementation

Follow `AGENTS.md` and [README verification](../../README.md#실행과-검증).

- `Shared/` changes, host tests in `CoreTests/` with fakes:
  - Version 2 encodes and decodes; a version 1 file, a `register` marker without `validUntil`, an unknown `call` and an empty `activityNames` count as no marker.
  - The skip rule for a `stop` marker: a listed name with `didEnd` skips; a listed name with `didStart` or a warning does not; a name that is not listed does not; a `stop` marker has no time condition.
  - The registration rules of the marker design still hold with version 2 (the existing tests, changed only for the new fields).
  - The write and delete around every stop: a fake monitoring client reads a `stop` marker during `stop(id:)`, `stopBreak` and `stopEveryday`, with the names that the call passes; the marker is gone after the call; a write that throws does not stop the stop; the read-failure path of `snapshot()` and `everydayStatus(now:authorized:)` writes the marker.
  - The resume with an early return writes a `register`, a `stop` and a `register` marker in that order.
  - A break end that passes during a `stopEveryday` of an earlier revision: the everyday `didEnd` skips, and the warning callback for the break that comes after the section re-blocks.
  - The same sequence with a warning that exhausts its retries: the break activity's `didEnd` at +15 min re-blocks (or ends the session by its timed end), with the app's reconcile absent.
- The separate-process race check: new cases where a process holds the lock with a `stop` marker for name N, a second process's `didEnd` for N returns at once with `control.json` unchanged, and a `didStart` or a warning for N waits for the full bounded retry. The README lists the new `PASS` lines.
- `Integration/` changes, SDK tests: the names of a `stop(id:)` marker equal the set that `ScreenTimeMonitoring.stop(id:)` passes, with and without a registered break; `DiagnosticMonitoring` still reports one `stop` timing for each stop.
- `App/` changes: an SDK test that `END_LATENCY` is reported once for each `end()` when the measuring closure is set, and not at all when it is not.
- Compile the App and the Monitor, and build an unsigned device Release build.
- The [physical-device verification](#physical-device-verification) above. Without it, the latency result stays unverified.

## Left to the builder

- How the read-failure stops of `snapshot()` and `everydayStatus(now:authorized:)` reach the marked client.
- The Swift shape of version 2 (one type with an optional `validUntil`, or an enum for the call).
- The name of the `END_LATENCY` closure on `FocusServices`.
