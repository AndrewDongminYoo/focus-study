# M2: Break pass and deadline rule

Date: 2026-11-01.
Status: design for approval. Milestone `M2` in the GitHub project "Focus Study".
Source: operator decisions from the 2026-10-31 brainstorm, confirmed on 2026-11-01.
This document changes [the 2026-10-26 design](2026-10-26-focus-study-design.md) and [the M1 design](2026-10-31-m1-launch-flow-design.md) only where it says so.
Where they differ, this document is the newer decision.
This PR does not edit those documents.
The implementation PR adds dated reconciliation sections to them (see [Superseded lines](#superseded-lines)).

## Intent

A student sometimes needs a blocked app during a focus session, for example to answer a message or to look up a word.
Today the only way out is to end the session.
M2 adds a short, limited break pass: the person can lift the restrictions for a few minutes, and the focus timer stops during that time.
The break must be a small, deliberate step, not a free exit, so each break starts after a waiting screen and the number of breaks is limited.

## Roadmap context

The operator set this order: M1 launch flow and focus length (shipped in PR #46), M2 break pass and deadline, M3 everyday schedule blocking layer, M4 stricter notification handling.
M3 and M4 get their own design documents.
M2 must not block them, but M2 does not build them.

## Goals

- A person can take up to 3 breaks in one focus session.
- Each break lifts the restrictions for exactly 3 minutes and pauses the focus timer.
- A cancellable waiting screen comes before each break, and it gets longer with each break.
- After a break, the restrictions come back without the app, and the timer continues only when the person taps "다시 집중하기".
- A session that is not complete by its deadline counts as unfocused.
- The "중도 종료" button becomes "집중 종료".

## Non-goals in M2 (deliberately excluded)

- A break that is longer than 3 minutes, a break that the person ends early, or a break that the person extends.
- More than 3 breaks, or a break count that depends on the focus length.
- A pause without lifting the restrictions (the timer stops only for a break).
- A local notification when a break ends. The person sees the system shield when they open a blocked app, and returns to the app by themselves. The operator can add a notification later, but it needs notification permission and M4 owns notification decisions.
- A custom shield screen or a shield action that starts a break (issue #40 stays a separate decision).
- Partial credit for a session that misses its deadline.
- The everyday schedule blocking layer (M3) and notification silencing (M4).

## Anti-goals (never, by operator decision)

- Rankings, leaderboards, or any comparison with other people.
- Friend presence or any feature that sends focus or break state off the device.
- Anything that makes the first-screen line "데이터는 기기에만 저장돼요" false.

## Decisions by the operator

### Break pass

1. A session has at most 3 breaks, for every focus length from 25 to 50 minutes.
2. A break lifts all restriction layers for exactly 3 minutes. In M2 the only layer is the focus-session selection. When M3 adds the everyday layer, a break lifts that layer too.
3. The focus timer is paused during a break. One break can never be longer than 5 minutes (positioning principle, 2026-10-31).
4. Before each break, a waiting screen shows a button that fills like a loading indicator. The person can cancel it.
5. The waiting time is 15 seconds for the first break, and doubles for each further break in the same session: 15 s, 30 s, 60 s. The sequence starts again in the next session.
6. When the 3 minutes end, the apps are blocked again at once.
7. The timer continues only after the person taps "다시 집중하기".
8. After the third break, the session has no break button. The only way to leave before completion is "집중 종료".
9. "집중 종료" is the new name of "중도 종료". A session that ends with "집중 종료" gives no focus time.

### Deadline

Deadline = start + focus length + actual break time + 10 minutes of slack.
Actual break time is the waiting time plus 3 minutes, for each break.
If the session is not complete at its deadline:

- The restrictions are lifted.
- The whole session counts as unfocused.
- No focus time accrues, including the minutes that the person already focused.

### Re-block mechanism

At break start, the app registers a separate DeviceActivity interval of at least 15 minutes.
The interval has a `warningTime`, so that the Monitor extension gets a callback at the 3-minute point and applies the shield again.
The device check records whether this works (see [Physical-device verification](#physical-device-verification)).

## Decisions by Claude (the operator can change them)

### Timer and waiting screen

- The focus timer stops when the waiting screen opens, not when the break starts. This follows the deadline formula, which counts the waiting time as break time.
- The restrictions stay on during the waiting screen.
- A cancelled wait does not use a break. It does not move the 15/30/60-second sequence.
- A cancelled wait still adds its waiting time to the deadline, because the timer was stopped during that time.
- If the app goes to the background or closes during the waiting screen, the wait is cancelled. The waiting screen is a step that the person must watch.
- A wait that nobody finishes (the app was closed) counts as cancelled at `waitEndsAt` + grace. The timer runs again from that time, because the restrictions stayed on. Only the time up to that point is added to the deadline.
- The deadline is not checked during a wait. A wait is at most the waiting time plus the grace, and all of it is added to the deadline. The check starts again when the wait is cancelled or the break starts.
- The break button and the waiting screen show how many breaks are left (for example "쉬는 시간 2번 남았어요"). The builder writes the exact copy with the `user-facing-copy` skill, in 해요체.

### Break and return

- The break cannot end early. The operator decided "exactly 3 minutes".
- "집중 종료" is available in every phase: focusing, waiting, on a break, and after the re-block.
- After the re-block, the timer screen shows "다시 집중하기", "집중 종료", and the time that is left to resume and still complete before the deadline (the deadline minus the remaining focus time). When that time is over, the screen says that the session can no longer count as focus.
- The gaps between each re-block and the tap on "다시 집중하기" are not in the deadline formula. Added together, they use up the 10-minute slack. A late re-block callback also uses the slack.
  For example, after the first break, a person who taps "다시 집중하기" more than 10 minutes after the re-block can no longer complete before the deadline. Two gaps of 6 and 5 minutes after two breaks have the same result.
- A session that can no longer complete stays in its phase, with the restrictions on, until the deadline. At the deadline it ends as `.deadlineMissed` in every phase except `waiting`, also in `active` after a resume. This follows the operator's rule word for word: the restrictions lift at the deadline. The rule is in [Timed end](#timed-end).

### Focus time in history and today's total

- Only a session that ends as `.expired` gives focus time. This was already the M1 rule for "오늘 집중 N분 · N회".
- A history row shows a duration only for `.expired`. Other rows show their reason without a duration. Before M2, a "중도 종료" row showed the elapsed time. With breaks, the elapsed time includes break time and is not focus time.
- The history label of `.earlyExit` becomes "집중 종료" for new and old records. The stored raw value `earlyExit` does not change.
- A missed deadline uses the new end reason `.deadlineMissed`. Its history label says that the session was not counted as focus (exact copy by the builder).
- The SwiftData schema of `SessionRecord` does not change. An `.expired` record already gives `expiresAt - startedAt`, because `recordedEnd` is capped at `expiresAt` (see [Session fields](#session-fields)).

### Selection copy in the App Group (privacy boundary change)

This decision changes the 2026-10-26 data boundary, so the operator must approve it before implementation.

- The Monitor extension must apply the shield again at the 3-minute point, while the app is usually not running. The Monitor does not have the selection tokens today. The 2026-10-26 design says: "Monitor ... 선택 토큰이나 SwiftData에 접근하지 않는다" and "토큰, 사용량, 사이트 이름은 공유하지 않는다".
- Proposal: at break start, the app writes a copy of the session's frozen selection (application tokens and web domain tokens only) to the App Group directory `SessionControl/`, as `break-selection.<UUID>.json`. The file uses the same file protection as `control.json`.
- The copy exists only during a break. The re-block deletes it after the shield matches. The end of the session deletes it. A control-state read failure deletes every `break-selection.*` file.
- Tokens are opaque values that the system issues for this device. The file stays on the device, so "데이터는 기기에만 저장돼요" stays true. The Report extension still has no App Group access.
- The re-block always uses this frozen copy, from the app and from the Monitor. The selection editor stays locked during the whole session, including breaks.
- If the operator rejects this proposal: this design found no other way for the Monitor to restore the selection, because a `ManagedSettingsStore` shield cannot be suspended and restored without the tokens. Only the app could re-block, and only while it runs, so "blocked again at once" would not be true.

### Schema and earlier builds

- `ControlEnvelope.schemaVersion` becomes `2`. The M2 build reads version 1 and version 2.
- `FileControl.save` always writes version 2, whatever version it read. Every transition saves the envelope that it decoded, so a default value alone would keep a version 1 file at version 1 after a break starts.
- A version 1 envelope (M1 or earlier build) decodes with no break fields. Its session has 0 breaks and no pause, and it counts down and completes as in M1. The break-shape checks in [Session fields](#session-fields) apply to both versions.
- A build before M2 cannot read a version 2 envelope. It fails with a decoding error (an unknown phase or reason) or with `unsupportedSchema`, because `FileControl.load()` decodes before it checks the version. Both are a control-state read failure, which clears this app's store and stops the focus activities that the old build can parse. A downgrade is not supported, and the old build leaves two things behind:
  - Its `sessionID(_:)` returns `nil` for `focus.<UUID>.break.<n>`, so it does not stop a break activity. Its `handleCallback` ignores that name, and the activity ends by itself at break start + 15 minutes.
  - It does not know `break-selection.*` files. A copy stays in the App Group until an M2 build starts a session or runs its read-failure cleanup. Both delete every copy (see [Process lock and recovery contract](#process-lock-and-recovery-contract)).

## Constraints

- iOS 17 or later, SwiftUI, Observation, SwiftData, iPhone only, portrait only.
- Keep the architecture in `AGENTS.md`. `Shared/` must not import Screen Time SDK modules. The break selection copy is encoded and decoded in `Integration/`.
- Keep the process-lock contract of the 2026-10-26 design: every state change reads the metadata again inside the `flock` section, checks the session identity, makes the system changes, and writes the JSON with an atomic replace. No `await` and no UI wait inside the lock.
- Keep the accessibility identifiers that `UITests/FocusFlowTests.swift` uses. `end` stays on the "집중 종료" button.
- Simulator results do not prove real Screen Time behavior.

## Apple documentation (checked 2026-11-01)

The JSON endpoint `https://developer.apple.com/tutorials/data/documentation/<path>.json` was read for each page.
The iOS 27.1 SDK `DeviceActivity.swiftinterface` was also checked.

| Fact                                                                                                                                                                                | Source                                                                                                                                                                                                                          |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "The minimum interval length for monitoring device activity is fifteen minutes."                                                                                                    | [`MonitoringError.intervalTooShort`](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/intervaltooshort)                                                                            |
| `warningTime` gives `intervalWillEndWarning(for:)` that much time before the interval end (example: a 10:00-11:00 interval with a 5-minute warning gives the end warning at 10:55). | [`DeviceActivitySchedule.warningTime`](https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule/warningtime)                                                                                             |
| The schedule initializer takes `warningTime` (`DateComponents?`, default `nil`).                                                                                                    | [`init(intervalStart:intervalEnd:repeats:warningTime:)`](<https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule/init(intervalstart:intervalend:repeats:warningtime:)>), SDK `.swiftinterface` line 42 |
| If the current date is inside the interval, `intervalDidStart(for:)` is called immediately when monitoring starts.                                                                  | Same initializer page                                                                                                                                                                                                           |
| `startMonitoring` with an activity that is already monitored overwrites the previous schedule and events.                                                                           | [`startMonitoring(_:during:events:)`](<https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/startmonitoring(_:during:events:)>)                                                                        |
| Too many activities, or activities that are too tightly scheduled, can make `startMonitoring` throw. The SDK has `excessiveActivities`, `intervalTooLong` and `intervalTooShort`.   | Same page, SDK `.swiftinterface` lines 167-171                                                                                                                                                                                  |

Not documented, so these stay `[UNCERTAIN]` until a device check:

- How late the system delivers `intervalWillEndWarning(for:)`, with the device unlocked, locked, or after the app was force-quit.
- Whether the 15-minute minimum is measured from `intervalStart` or from the moment of registration, when `intervalStart` is in the past.
- Whether an activity whose non-repeating interval has ended stays in `DeviceActivityCenter.activities` until `stopMonitoring`.

## Design

### Phases

M2 adds three phases to `SessionPhase`: `waiting`, `onBreak` and `breakOver`.

| Phase       | Restrictions | Focus timer | Meaning                                                         |
| ----------- | ------------ | ----------- | --------------------------------------------------------------- |
| `preparing` | being set    | not started | unchanged from the 2026-10-26 design                            |
| `active`    | on           | running     | focusing                                                        |
| `waiting`   | on           | paused      | the waiting screen is open                                      |
| `onBreak`   | off          | paused      | the 3-minute break                                              |
| `breakOver` | on           | paused      | the break ended, and the app waits for "다시 집중하기"          |
| `ending`    | being lifted | stopped     | unchanged; the end reason and the observed time are already set |
| `terminal`  | off          | stopped     | unchanged; waits for the history import                         |

### Session fields

`ControlSession` keeps its current fields, and `expiresAt` keeps its meaning: `startedAt` + the focus length, without breaks.
`length` (`expiresAt - startedAt`) and the storage validation with `FocusLength.isAllowed(seconds:)` therefore do not change.
M2 adds these fields.
All of them are optional in JSON, so a version 1 session decodes without them.

| Field            | Type            | Meaning                                                                        |
| ---------------- | --------------- | ------------------------------------------------------------------------------ |
| `breaksTaken`    | `Int?`          | Breaks that started in this session, 0 to 3 (missing = 0).                     |
| `pausedSeconds`  | `TimeInterval?` | Total of the closed pauses, from wait start to resume or cancel (missing = 0). |
| `pausedAt`       | `Date?`         | Start of the open pause. Set in `waiting`, `onBreak` and `breakOver`.          |
| `deadlineCredit` | `TimeInterval?` | Waiting time (also cancelled waits) plus 180 seconds per break (missing = 0).  |
| `waitEndsAt`     | `Date?`         | When the current wait ends. Set only in `waiting`.                             |
| `breakEndsAt`    | `Date?`         | When the current break ends (break start + 180 s). Set in `onBreak` and later. |

Derived values (in `Shared/`, without the Screen Time SDK):

- Open pause = `now - pausedAt` when `pausedAt` is set, else 0.
- Focused time = `min(length, max(0, now - startedAt - pausedSeconds - open pause))`.
- Remaining time = `length - focused time`, rounded up to whole seconds, as in M1.
- Focus end (only while `active`) = `expiresAt + pausedSeconds`.
- Deadline = `expiresAt + deadlineCredit + 600`. For a session without cancelled waits, this is the operator's formula: start + length + (waiting time + 180 s for each break) + 10 minutes. `deadlineCredit` also holds the waiting time of cancelled waits, and that addition is a decision by Claude (see [Timer and waiting screen](#timer-and-waiting-screen)).
- `recordedEnd` stays capped at `expiresAt`. An `.expired` record therefore gives exactly the focus length. Other reasons show no duration (see [Focus time in history and today's total](#focus-time-in-history-and-todays-total)).

The waiting time and the break length are timing values in `Shared/`: waits `[15, 30, 60]` seconds, break `180` seconds, slack `600` seconds, and a stale-wait grace of `10` seconds.
The engine receives them as one injected value, so that DEBUG fixtures and tests can use short times.
Stored dates (`waitEndsAt`, `breakEndsAt`) carry the times that applied, so a stored session does not depend on the timing value of a later process.

#### Timed end

One rule in `Shared/` decides the end that time alone causes. It compares timestamps, so the order of the checks and the delay of a callback cannot change the result:

- `active`: when `now >= min(focus end, deadline)`, the session ends as `.expired` if `focus end <= deadline`, else as `.deadlineMissed`.
- `onBreak` and `breakOver`: when `now >= deadline`, the session ends as `.deadlineMissed`. A paused session has not completed.
- `waiting`: no timed end. A stale wait is cancelled first (reconcile step 6), and the rule then applies to the `active` result.

A late reconcile after both times therefore gives `.expired` for a session whose focus end was at or before its deadline, and `.deadlineMissed` for a session whose focus end was after it.

#### Storage checks

The store accepts a session of either schema version only if these conditions are true, in addition to the M1 checks:

- `breaksTaken` is 0 to 3, and `pausedSeconds` and `deadlineCredit` are not negative.
- `pausedAt` is set in `waiting`, `onBreak` and `breakOver`, and it is not set in `preparing` and `active`.
- `waitEndsAt` is set in `waiting`. `breakEndsAt` is set in `onBreak` and `breakOver`.
- `breaksTaken` is at least 1 in `onBreak` and `breakOver`, and it is less than 3 in `waiting`.

Any other shape is `ControlIssue.invalidState`, as in M1.

### Monitoring activities

| Activity       | Name                       | Interval                                                       | Purpose                                     |
| -------------- | -------------------------- | -------------------------------------------------------------- | ------------------------------------------- |
| Focus activity | `focus.<UUID>` (unchanged) | `startedAt` to the next time the session must change by itself | Completion or deadline without the app      |
| Break activity | `focus.<UUID>.break.<n>`   | Break start to break start + 15 min, `warningTime` 12 min      | Re-block at break start + 3 min; `n` is 1-3 |

- The focus activity end is always the next time that the session must change without the app:
  - In `active`: `min(focus end, deadline)`.
  - In `waiting`: the `active` end after a stale-wait cancel, `min(focus end, deadline) + (waitEndsAt + grace - pausedAt)`. The cancel adds the same time to `pausedSeconds` and to `deadlineCredit`.
  - In `onBreak` and `breakOver`: the deadline.
- Each change of that end calls `startMonitoring` again with the same name, which overwrites the schedule. The interval start stays `startedAt`, so the interval is always at least 25 minutes long even when little focus time is left. `[UNCERTAIN]`: the 15-minute minimum with a past `intervalStart` (see above).
- A re-registration of the focus activity calls `intervalDidStart(for:)` at once. That callback only reconciles, as in M1. It never applies the shield.
- A session has at most one break activity at a time. The re-block stops it. This keeps the activity count low (`excessiveActivities`).
- Today `ScreenTimeMonitoring.sessionID(_:)` parses everything after `focus.` as one UUID, so it returns `nil` for a break name. M2 changes it to read the 36 characters after `focus.`, so that it finds the session of both names, and adds a parser for the break index. `registeredSessionIDs`, the read-failure cleanup and `stop(id:)` then stop both the focus activity and every break activity of that session.

### Transitions

Each transition is one `withExclusiveAccess` section on `SessionControl`.
Each one reads the envelope again, checks the session ID and the expected phase, and does nothing if they do not match.

1. **Request a break** (`active` → `waiting`). Allowed only if `breaksTaken < 3`. Set `pausedAt = now` and `waitEndsAt = now + wait[breaksTaken]`. Overwrite the focus activity end with the `waiting` end from [Monitoring activities](#monitoring-activities), then save.
2. **Cancel the wait** (`waiting` → `active`). Let `end` be `now`, or `waitEndsAt + grace` if that is earlier. Add `end - pausedAt` to `pausedSeconds` and to `deadlineCredit`. Clear `pausedAt` and `waitEndsAt`. Overwrite the focus activity end with `min(focus end, deadline)`, then save.
3. **Start the break** (`waiting` → `onBreak`). Allowed only if `now >= waitEndsAt` and `now < waitEndsAt + grace`. In this order:
   1. Write the break selection copy.
   2. Register the break activity `focus.<UUID>.break.<breaksTaken + 1>`.
   3. Increase `breaksTaken`. Add the waiting time (`now - pausedAt`) and 180 seconds to `deadlineCredit`. Set `breakEndsAt = now + 180`. Clear `waitEndsAt`.
   4. Overwrite the focus activity end with the deadline.
   5. Save `onBreak`.
   6. Clear this app's named store.
   - If any step up to and including the save fails: stop the break activity, delete the copy, go back to `active` as in "Cancel the wait", and show a retryable error. The shield was not cleared, so no restriction gap opens. If the save of `active` also fails, the stored session stays `waiting`, and reconcile step 6 cancels the wait after the grace ([Reconcile order](#reconcile-order)).
4. **Re-block** (`onBreak` → `breakOver`). Triggers:
   - The Monitor gets `intervalWillEndWarning(for:)` for the current break activity. This re-blocks without a check against `breakEndsAt`, because an early re-block is the safe direction for the 5-minute limit.
   - Any reconcile (app foreground, timer tick, any Monitor callback of this session) when `now >= breakEndsAt`.
   - The break activity's `intervalDidEnd(for:)` at +15 min, as a last backstop.

   In this order:
   1. Under the same lock, evaluate [Timed end](#timed-end) with `timedEnd(at:timing:)`. If it gives a reason, end the session with that reason (transition 6), and do not re-block or save `breakOver`. A late warning can arrive at or after the deadline, for example after a late resume that left only seconds before the deadline. Continue with the next step only when it gives `nil`.
   2. Apply the shield from the break selection copy.
   3. Check that the named store matches the copy.
   4. Save `breakOver`.
   5. Stop the break activity.
   6. Delete the copy.

   If the copy is missing or the store does not match, end the session as `.recoveryInterrupted` (restrictions stay off, and the session is not counted). A break without an end must not happen.

5. **Resume** (`breakOver` → `active`). The person taps "다시 집중하기". If `now >= deadline`, end as `.deadlineMissed` instead. Otherwise add `now - pausedAt` to `pausedSeconds`, clear `pausedAt`, overwrite the focus activity end with `min(new focus end, deadline)`, and save. If the new focus end is after the deadline, the session cannot complete. It stays `active` until the deadline and then ends as `.deadlineMissed` ([Timed end](#timed-end)).
6. **End** (any non-terminal phase → `ending` → `terminal`). Unchanged order from the 2026-10-26 design: save `ending`, clear the store, stop the monitoring, save `terminal`. M2 adds two steps: stop the break activity, and delete the break selection copy.

### Reconcile order

`reconcile` checks the conditions in this order.
The first match decides.

1. `ending`: finish the cleanup (unchanged).
2. Access not approved: end as `.authorizationRevoked` (unchanged, also during a break).
3. `preparing`: end as `.recoveryInterrupted` (unchanged).
4. Observed clock change: end as `.clockChanged` (unchanged).
5. Focus activity not registered: end as `.recoveryInterrupted` (unchanged).
6. `waiting` and `now >= waitEndsAt + grace`: cancel the wait (transition 2), then continue with step 7 on the result. The app was not there to start the break.
7. `active`, `onBreak` or `breakOver`, and [Timed end](#timed-end) gives a reason: end with that reason (`.expired` or `.deadlineMissed`).
8. `onBreak` and `now >= breakEndsAt`: re-block (transition 4).

`StartupRecovery.endCurrent` uses the same Timed end rule instead of `now >= expiresAt`. When the rule gives no reason, it ends as `.earlyExit`, as in M1.

### Callback identity

- `handleCallback` takes the activity name and the callback kind (`intervalDidStart`, `intervalDidEnd`, `intervalWillEndWarning`).
- A name that is not the current session's focus activity or its current break activity (`n == breaksTaken`) changes nothing. A late callback from an earlier break or an earlier session therefore cannot re-block, clear or end a newer session.
- `FocusMonitor` adds `intervalWillEndWarning(for:)`. It passes the callback to the engine with a restore action that reads the break selection copy through `Integration/`.

### Process lock and recovery contract

- The lock, its 0.25-second timeout and the atomic JSON replace do not change.
- The waiting countdown runs in the app, outside the lock. Only the transitions take the lock.
- A failed control-state read (corrupt JSON, unsupported schema, file protection) still clears this app's store and stops every `focus.<UUID>` registration. M2 adds the break activities to that cleanup, and it deletes every `break-selection.*` file. It never applies the shield to recover.
- **Start** (unchanged otherwise) deletes every `break-selection.*` file inside the lock before it saves the new session. No copy can belong to a session that does not exist yet, so this removes a copy that a downgrade or a crash left behind.
- A session that is stored in `waiting`, `onBreak` or `breakOver` when the app or the Monitor starts goes through the reconcile order above. Nothing assumes that the process that started the break is still alive.

## Superseded lines

The implementation PR adds dated reconciliation sections (it does not rewrite the original lines) for these:

- 2026-10-26 design, scope: "일시정지는 제공하지 않는다".
- 2026-10-26 design, data boundary: the Monitor and the App Group have no selection tokens (only if the operator approves the [selection copy](#selection-copy-in-the-app-group-privacy-boundary-change)).
- 2026-10-26 design, "세션 상태와 원자성": `now >= expiresAt` as the expiry rule, and the history duration for every reason.
- M1 design: "the existing "중도 종료" button with its confirmation".
- `AGENTS.md` project scope: "no pause".

## Physical-device verification

Blocked until issues #8, #9 and #10 are resolved (development team, identifiers and entitlements, signed install on an approved device).
Record every result in the [device matrix](../notes/screen-time-device-matrix.md), with device, OS version, scheduled time and observed time.
Do not apply real restrictions without the operator's explicit approval for that run.

Steps:

1. Start a 25-minute session with one app and one website. Take a break. Record the time of the break start and the time when the shield disappears.
2. Leave the app in the background and the device unlocked. Record the time when the shield comes back. Pass: between 3 and 5 minutes after break start.
3. Repeat step 2 with the device locked for the whole break.
4. Repeat step 2 after a force-quit of the app during the break.
5. After the first re-block of a new session, do not tap "다시 집중하기". Pass: the restrictions lift at the deadline (start + length + waiting time + 3 minutes + 10 minutes), without the app, and the history row shows the missed deadline.
6. In a new session, take a break and tap "다시 집중하기" 11 minutes after the re-block. Leave the app in the background. Pass: the restrictions lift at the deadline, before the focus end, without the app, and the history row shows the missed deadline.
7. Take three breaks. Record the waiting times (15 s, 30 s, 60 s), and that no fourth break is offered.
8. Resume with less than 15 minutes of focus left. Record whether the focus activity registration succeeds, and when the session completes.
9. Revoke Screen Time access during a break. Record the end reason and the store state.

Unverified until those steps run:

- The delivery time of `intervalWillEndWarning(for:)`, and therefore the 5-minute limit `[UNCERTAIN]`.
- The re-registration of the focus activity with a past `intervalStart` when less than 15 minutes are left `[UNCERTAIN]`.
- Whether the Monitor can read the break selection copy and apply the shield while the device is locked (file protection `completeUntilFirstUserAuthentication`) `[UNCERTAIN]`.
- Whether an ended break activity stays in `DeviceActivityCenter.activities` `[UNCERTAIN]`.
- The iOS 17 runtime.

If step 2 or 3 fails the 5-minute limit, a fallback to check on the device is a second activity whose `intervalDidStart(for:)` is at break start + 3 minutes.
That fallback is not part of this design until a device result supports it.

## Verification

Follow `AGENTS.md` and [README verification](../../README.md#실행과-검증).

- `Shared/` changes: run `swift test` and the separate-process race check. Extend the race helper with a stale break callback that must not re-block or clear a newer break.
- `Integration/` and `Monitor/` changes: run the SDK tests for the break schedule (15-minute interval, 12-minute `warningTime`) and the activity-name parsing, and compile the Monitor target.
- `App/` changes: run the SDK and UI tests with DEBUG fixture timing (short waits and breaks).
- Target or fixture wiring: run the unsigned device Release build.

## Left to the builder

- The look of the waiting button fill, with motion that respects Reduce Motion.
- The layout of the break, re-block and deadline states on the timer screen.
- Exact copy, written with the `user-facing-copy` skill in 해요체.
