# Access state: approved, denied or unknown

Date: 2026-11-11.
Status: design for approval.
Source: [issue #115](https://github.com/AndrewDongminYoo/focus-study/issues/115) and its [device evidence of 2026-11-11](https://github.com/AndrewDongminYoo/focus-study/issues/115#issuecomment-6782241159).
This document amends the [2026-10-26 design](2026-10-26-focus-study-design.md), the [M2 design](2026-11-01-m2-break-pass-design.md), the [M3 design](2026-11-01-m3-schedule-layer-design.md) and the [M4 design](2026-11-01-m4-focus-filter-design.md) only where it says so; the implementation PR adds dated reconciliation lines to them (see [Superseded lines](#superseded-lines)).
It also records one Live Activity copy change ([Live Activity break label](#live-activity-break-label)).
It keeps the process-lock rule: lock sections stay synchronous, with no `await`, UI wait or actor hop inside the lock.
This document changes no code.

## Contract

Decided on 2026-11-11:

1. Every access value that reaches the session engine is one of three states: `approved`, `denied` or `unknown`.
   `AuthorizationStatus.approved` (and `.approvedWithDataAccess` on iOS 26.4 and later) is `approved`, `.denied` is `denied`, and `.notDetermined` and every other value are `unknown`.
2. `unknown` is not an observation of revocation. A section with `unknown` does not end a session as `.authorizationRevoked` and does not stop the everyday layer for access; it runs every other step of its transition as it would with access.
3. Only `denied` runs the access rules of today: the M2 reconcile step 2 ends the session as `.authorizationRevoked`, and the M3 convergence stops every everyday activity and clears the store.
4. Every read of `AuthorizationCenter.shared.authorizationStatus` happens on the main queue, also in the Monitor extension.
5. A person's action that needs access (start, a Focus filter start, an everyday save, turning the everyday layer off for today) still requires `approved`, and refuses with the existing refusal on `denied` and on `unknown`.
6. The compact Live Activity label of a break changes from "휴식 예정" to "휴식 끝".

Out of scope: requesting authorization from the extension, a stored copy of the app's last access value, and the Monitor-side timing of #113.

## Evidence

Apple's documentation for `AuthorizationCenter.authorizationStatus` (documentation JSON, read on 2026-11-11):

> The initial value is always notDetermined. The system sets this property only after a call to requestAuthorization(for:) succeeds. It then updates the property until a call to revokeAuthorization(completionHandler:) succeeds or your app exits.

> Only access the authorizationStatus property on the DispatchQueue.main queue.

The page says nothing about app extensions or `DeviceActivityMonitor`.

Today the value reaches the engine as a `Bool`:

| Reader           | Where                                                     | Value passed                                                                                                                        |
| ---------------- | --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Monitor callback | `Monitor/FocusMonitor.swift`                              | `ScreenTimeAccess.isApproved(AuthorizationCenter.shared.authorizationStatus)`, read on the callback's thread, once per lock attempt |
| Launch recovery  | `App/FocusRuntime.swift`, `App/FocusStudyApp.swift`       | `authorization.hasAccessNow()`, read right after launch                                                                             |
| App sections     | `App/FocusModel.swift`, `App/EverydaySettingsModel.swift` | `access == .approved`, where `AuthorizationService.refresh()` maps `.notDetermined` after an earlier request to `.denied`           |
| Focus filter     | `App/FocusFilterHandler.swift`                            | `authorization.status == .approved`, and `hasAccessNow()` for a start                                                               |

So `false` today means "denied or not yet known".
On the device on 2026-11-11 (my daily iPhone 16 Pro, access on in Settings, focus restrictions working with the app in front), a break with the app in the background never re-blocked four times on two builds, `741ae90` and `b89cd74`: the session ended as `.authorizationRevoked` ("접근 철회로 중단") and every everyday activity was stopped, with no app-side stop logged ([#115 comment](https://github.com/AndrewDongminYoo/focus-study/issues/115#issuecomment-6782241159)).
With no session running, the everyday activities were stopped again by a process without console logs, and at two app launches the first section stopped all four everyday parts before any registration.
`[UNCERTAIN]` Whether the extension's value ever leaves `.notDetermined`, and what it reads after a real revocation. The [physical-device verification](#physical-device-verification) checks both.
`[UNCERTAIN]` The one passing background check on 2026-11-10 (about 15:00, `2aba43c`) is not explained.

## Design

### The access state

`Shared/` gets one value type for the engine, for example `AccessState { approved, denied, unknown }` (the name is left to the builder).
Every engine entry point that takes `authorized: Bool` or `access: Bool?` today takes this state instead; the closures that start and save read it inside the lock as today.
`Shared/` keeps no Screen Time import: `Integration/` maps `AuthorizationStatus` to the state, as `ScreenTimeAccess.isApproved` does today.

| `AuthorizationStatus`                          | State      |
| ---------------------------------------------- | ---------- |
| `.approved`                                    | `approved` |
| `.approvedWithDataAccess` (iOS 26.4 and later) | `approved` |
| `.denied`                                      | `denied`   |
| `.notDetermined`                               | `unknown`  |
| any other or future value                      | `unknown`  |

The existing `nil` access of M3 ("the section does not know the access value") is the same as `unknown`.

### Reading on the main queue

`Integration/` owns one reader that returns the state from the main queue: on the main thread it reads directly, otherwise it reads through `DispatchQueue.main.sync`.
The reader runs before each lock attempt, as the closure does today, never inside a lock section, so no lock is held while it waits for the main queue.
`[UNCERTAIN]` On which thread the extension delivers a callback, and whether its main queue runs while a callback waits; no source read here documents either. If a device run shows that the hop does not return, the reader falls back to `unknown`, which this design treats as safe.

### What each state does

| Rule                                                                                        | `approved`                                   | `denied`                          | `unknown`                                                            |
| ------------------------------------------------------------------------------------------- | -------------------------------------------- | --------------------------------- | -------------------------------------------------------------------- |
| M2 reconcile step 2                                                                         | continue                                     | end as `.authorizationRevoked`    | continue (step 2 skipped)                                            |
| M2 reconcile steps 1 and 3 to 7, the cleanup, transitions 1 to 6, Callback with nothing due | as today                                     | as today                          | as today                                                             |
| M3 convergence step 2                                                                       | register missing parts, stop other revisions | stop every everyday activity      | register missing parts, stop other revisions (as the existing `nil`) |
| M3 blocking rule and convergence step 3                                                     | by schedule                                  | does not block, clear the store   | by schedule (as the existing `nil`)                                  |
| `start`, `startFromFocusFilter`, `saveEveryday`, `turnEverydayOffForToday`                  | proceed                                      | refuse (`access`, `unauthorized`) | refuse, the same refusal                                             |
| `endFromFocusFilter` after a caught error                                                   | M4 order                                     | `.authorizationRevoked`           | the M4 order without the access branch: timed end, else `.earlyExit` |
| `everydayStatus(now:authorized:)`                                                           | as today                                     | "not approved"                    | as approved for the blocking rule; the settings show no access issue |

Why `unknown` continues: every step that `unknown` keeps is the step that the same section runs with access, and none of them loosens a restriction.
The break warning re-blocks, a timed end ends, and an everyday edge converges by schedule.
The only steps that `unknown` skips are the two that lift restrictions because of access, and they still run on the next `denied` read.

### The app's access value

`AuthorizationService.status` gets a fourth UI value, `checking`, for `.notDetermined` after an earlier request; today `refresh()` shows that case as `denied`. `notRequested` (no earlier request), `approved` and `denied` keep their meaning.
The engine calls stop deriving their value from it: `FocusModel`, `EverydaySettingsModel`, `FocusFilterHandler` and launch recovery pass the state from the main-queue reader, so `checking` reaches the engine as `unknown`.
When the published status changes, the existing subscription calls `refresh()`; the app section that follows reads the new state.

The screens follow the session before access, so a running session stays reachable while access is `checking`:

| UI status                | Session current and not `terminal`                                       | No current session                                                                                                                                                        |
| ------------------------ | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `approved`               | timer screen, as today                                                   | timer screen or the next onboarding step, as today                                                                                                                        |
| `checking`               | timer screen with its end and resume controls; no start control is shown | timer screen with the start control enabled and a short status line that access is being checked; a tap runs the recovery below; the line's copy is left to visual review |
| `denied`, `notRequested` | timer screen with its end and resume controls, as `checking`             | the permission step of onboarding, as today                                                                                                                               |

So `FocusModel.route` keeps the timer screen in `checking`, `startBlocker` reports `checking` as its own blocker whose action is the recovery tap, and only `denied` and `notRequested` without a current session route to the permission step.

Leaving `checking` after a cold launch:

- Observed on 2026-11-11, against the documentation's wording: in the app process the published value settled to approved without a new request. At the 07:42:47 launch the section right after the first one registered with access, and a start that requires `approved` passed at 07:43:53. `[UNCERTAIN]` Whether that holds on every launch and in the extension.
- If the value stays `.notDetermined`, the person's tap on the enabled start control is the recovery: the app first runs `requestIndividual()`, which now runs the documented request also in `checking` (today only in `notRequested`), and calls the engine's `start` only after the published value reads approved; the engine's `start` still requires `approved` inside the lock. A request is never made without a person's tap, because it can show system UI. `[UNCERTAIN]` Whether a request after an earlier approval shows any UI.
- A request that throws is not a revocation: the UI shows its error and stays in `checking`, and nothing reaches the engine. A revocation reaches the engine only as a published `.denied` read; until the value settles to `.denied`, revocation cleanup waits, which is the accepted cost in [A real revocation](#a-real-revocation).

### A real revocation

| Moment of revocation                       | Who observes it                                                                 | Result                                                                                                                               |
| ------------------------------------------ | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| App in front                               | the subscription fires; the next app section reads `denied`                     | ends as `.authorizationRevoked`, as today                                                                                            |
| App in background, then a Monitor callback | the Monitor reads `denied` only if the extension's value is set; else `unknown` | `denied`: ends as today. `unknown`: the callback runs its other steps, and the next app section that reads `denied` ends the session |
| App not running                            | launch reads `unknown` until the value is set; the subscription then fires      | the first app section after the value reads `denied` ends the session; a session whose time ended first ends with its timed reason   |

`[UNCERTAIN]` Whether iOS keeps a `ManagedSettingsStore` shield after the person revokes access; the device check records it.
The looser outcome that this design accepts: after a revocation with the app in the background, the session's record can end with its timed reason instead of `.authorizationRevoked` when no app section runs before its end.
The restrictions themselves are not this app's to keep after a revocation; the record's reason is the only difference.

### Stored states and side artifacts

The state is an input to a section, never stored.
`control.json`, `everyday-layer.json`, `registration-marker.json`, the break copies and their tables in M2, M3 and the marker designs do not change.

### Gaps between steps

No transition gets a new step, so the gap tables of M1, M2, M3, the off-for-today design and the marker designs keep their rows.
The only new interleaving is the main-queue read before a lock attempt:

| Gap                                                                               | State used               | Effect                                                                                                 |
| --------------------------------------------------------------------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------ |
| The status changes between the read and the lock                                  | the earlier read         | As today with the `Bool`: the section runs on the value it read; the next section reads the new value. |
| The read returns `unknown` and a later read in the same callback returns `denied` | each attempt reads again | A retry after a lock timeout uses the new value, as the per-attempt closure does today.                |
| The main-queue hop does not return (`[UNCERTAIN]`)                                | none                     | The reader's fallback returns `unknown`; the callback then runs its section.                           |

### One-shot callbacks and their recovery

- The break warning was lost to `.authorizationRevoked` on the device; with `unknown` it reaches the re-block, which is the one-shot change that keeps a break within 5 minutes.
- A timed focus `didEnd` with `unknown` ends the session by its timed reason instead of `.authorizationRevoked`.
- An everyday edge with `unknown` converges by schedule instead of stopping every everyday activity, so the layer keeps its own callbacks.
- A `denied` read in any of them behaves as today.

### Guards across sequences of transitions

| Sequence                                                                               | Result                                                                                                                                 |
| -------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Break start in the app, app in the background, warning in a cold extension (`unknown`) | The warning re-blocks and saves `breakOver`; the everyday layer blocks again by schedule. The app's next section finds `breakOver`.    |
| App launch (`unknown`), then the subscription fires (`approved`)                       | The launch section keeps every everyday part and the stored session; the next section registers nothing new.                           |
| App launch (`unknown`), then the subscription fires (`denied`)                         | The launch section changes nothing for access; the next app section ends the session and stops the everyday layer.                     |
| A start tap while the state is `unknown` right after launch                            | The UI shows `checking` and runs the request; the engine's start still requires `approved`, so it starts only after the value settles. |
| Focus turns off while the app is not running (`unknown`)                               | `endFromFocusFilter` ends a filter-started session as `.earlyExit` (or its timed reason) and never as `.authorizationRevoked`.         |

### Live Activity break label

The compact label above the break countdown names the time at `breakEndsAt`, but "휴식 예정" reads as a break that has not started.
It changes to "휴식 끝"; the long label "쉬는 시간 종료 예정" and every other label stay.
The [Live Activity decision](2026-11-06-live-activity-decision.md#state-and-time-projection) leaves the exact copy to visual review, so the implementation PR shows the change in captures (light, dark, the largest text size) and waits for approval before the merge.
The "확인" that replaces the countdown after `breakEndsAt` without a newer state is the existing stale rule; on the device it stayed because the session ended as `.authorizationRevoked` instead of `breakOver`, which this design addresses.

## Alternatives considered

**The Monitor never decides access.** Simpler, but a `denied` that the extension does observe would then wait for an app section, and the Focus filter and launch paths would still need the three states.

**The app stores its last confirmed access in the App Group, and the Monitor reads it.** It adds a stored file with its own gap and freshness rules, and a stale `approved` would keep a revoked session running; it is rejected for this step.

**A retry of the read in the extension until it leaves `.notDetermined`.** Apple documents that the value is set only after a successful request in that process, so a retry has no documented end.

## Superseded lines

The implementation PR adds dated reconciliation lines (it does not rewrite the original lines) for these:

- 2026-10-26 design, "권한 철회는 즉시 관측 가능한 시점에 중단/미사용으로 전환하고 store와 monitoring을 정리한다.": a revocation is observed only as `denied`; `.notDetermined` is `unknown` and is not an observation.
- 2026-10-26 design, M4 adjustment line "권한이 없으면 `.authorizationRevoked`로 끝난다": only with `denied`.
- M2 [Reconcile order](2026-11-01-m2-break-pass-design.md#reconcile-order), step 2 "Access not approved: end as `.authorizationRevoked`": access `denied`; `unknown` skips the step.
- M3 [Everyday convergence](2026-11-01-m3-schedule-layer-design.md#everyday-convergence), step 2 "If the section knows that access is not approved": the section read `denied`.
- M3 [Callback routing in `handleCallback`](2026-11-01-m3-schedule-layer-design.md#callback-routing-in-handlecallback), "with the access value of the extension": the state from the main-queue reader.
- M4 "Run the M2 reconcile order with the access value of the call" (the Focus filter off): the state of the call, with the `endFromFocusFilter` row of [What each state does](#what-each-state-does).

## Physical-device verification

Record each result in the [device matrix](../notes/screen-time-device-matrix.md) and in issue #115.
Each install and each run that applies real restrictions needs its own explicit approval.
Simulator results and synthetic tests cannot establish any of these results.

1. Build a signed Debug build of the implementation commit and run it with `--screen-time-diagnostics` on the iPhone 16 Pro of the 2026-11-11 runs.
2. Start a session, start a break with the app in front, then put the app in the background with a blocked app open. At `breakEndsAt` plus a few seconds, record whether the shield returns; on return, record the session state and today's history.
3. Repeat step 2 three times, at least once after the app was not running for several minutes.
4. With the everyday range containing now and no session, leave the app in the background past an everyday edge, and record whether the everyday shield follows the schedule; on return, record whether the app had to register the everyday parts again (`register_everyday` with no `stop_everyday` before it).
5. Launch the app cold with access on, and record the first section's lines (no `stop_everyday` before the registrations), how long the screen shows `checking`, and whether a session that ran before the launch stays reachable.
6. Revoke access in Settings with the app not running, then launch it cold: record whether the published value settles to `.denied`, and what a tap on the start control shows if it stays `.notDetermined`.
7. Revoke access for the app in Settings with a session running and the app in the background, wait past one Monitor callback, then open the app. Record the end reason, whether the shields stayed while access was off, and grant access again.

Acceptance:

- Steps 2 and 3: the shield returns at the end of every break, and no session ends as `.authorizationRevoked`.
- Steps 4 and 5: no everyday stop for access appears while access is on, and a running session stays reachable on every screen.
- Step 6: no session starts; the session is never started on a request result alone, and the screen leaves `checking` only on a published value.
- Step 7: the session ends as `.authorizationRevoked` at the latest when the app comes to the front, unless its timed end came first.

## Verification for the implementation

Follow `AGENTS.md` and [README verification](../../README.md#실행과-검증).

- `Shared/` changes, host tests in `CoreTests/`:
  - The mapping table above, through a fake reader.
  - Reconcile with `unknown` in each phase: no `.authorizationRevoked`, every other step as with `approved`; with `denied`: as today.
  - Convergence with `unknown`: registers missing parts and applies the store by schedule; with `denied`: stops every everyday activity.
  - `handleCallback` for the break warning with `unknown`: re-blocks; for a timed focus `didEnd` with `unknown`: ends by the timed reason.
  - `start`, `startFromFocusFilter`, `saveEveryday` and `turnEverydayOffForToday` refuse on `unknown` as on `denied`.
  - `endFromFocusFilter` after a caught error with `unknown`: never `.authorizationRevoked`.
  - The existing tests that pass `authorized: false` keep their meaning as `denied`.
- The separate-process race check keeps its `PASS` lines; the race helper passes the state.
- `Integration/` and `App/` changes, SDK tests: the reader maps each `AuthorizationStatus` value; `FocusModel`, `EverydaySettingsModel` and `FocusFilterHandler` pass `unknown` while `AuthorizationService.status` is `checking`; `route` and `startBlocker` follow each row of the UI status table; `requestIndividual()` runs in `checking`.
- UI tests: the Live Activity test that reads "휴식 예정" reads "휴식 끝"; captures of the compact presentation in light, dark and the largest text size.
- Compile the App, the Monitor and the Widget, and build an unsigned device Release build.
- The [physical-device verification](#physical-device-verification) above. Without it, the fix stays unverified.

## Left to the builder

- The name and the shape of the state type and of the reader.
- How the reader's fallback on a hop that does not return is detected, if a device run shows that case at all.
