# Amendment: shields only in the app container

Date: 2026-11-16.
Status: design for approval. Issue #152, after the first device run recorded in #167.
This document amends the [Focus filter extension design](2026-11-16-focus-filter-extension-design.md) (the "extension design") only where it says so; where they differ, this document is the newer decision.

## Problem

The first device run showed that the extension's ManagedSettings calls use the container `kr.donminzzi.focusStudy.intents`, while the app uses `kr.donminzzi.focusStudy`.
A store name such as `focusSession` names a different store in each container.
So a shield that the extension applies cannot be cleared by the app or the Monitor, and every end that they run for an extension-started session (`집중 종료`, a break, a timed end, the read-failure cleanup) leaves it on.
A DEBUG probe the same evening showed that a DeviceActivity interval that the extension registers belongs to the app: the app's Monitor received `intervalDidStart` within a second of the registration and `intervalDidEnd` when the extension stopped it.

## Decisions by me (2026-11-16)

1. The extension never applies or clears a shield. Only processes of the app container, the app and the Monitor, write ManagedSettings stores.

## Decisions by Claude (I can change them)

### Roles

1. The extension writes the control state and registers or stops DeviceActivity intervals. It never calls a `ShieldClient`, a `BreakSelectionStore` shield method or an everyday store method.
2. The Monitor applies the focus shield of a session that the extension started, in `intervalDidStart` of its focus activity, and lifts the focus shield of a session that the extension ended, in `intervalDidEnd`.
3. The app keeps its own shield writes, and its reconcile repairs any shield that a lost Monitor callback left wrong (see [Repair in the app container](#repair-in-the-app-container)).

### Start in the extension

4. The extension runs the M1 start steps without the shield steps: save `preparing`, register the focus activity, verify the registration, and save `active` with a new optional session field `shieldPending = true`. The verification of the shield (`matches`) moves to the Monitor.
5. `intervalDidStart` of the focus activity of a stored `active` session with `shieldPending` applies the focus selection from `FocusSelection/selection.json` (the App Group file of the extension design, decision 12), checks it with `matches`, and saves `shieldPending = nil`. If the selection cannot be read or the check fails, the section ends the session with `.startFailed` and lifts what it applied, as the M1 rollback does.
6. A session with `shieldPending` counts as running for every rule of the extension design. Its focused time starts at `startedAt`, as for every session; the device run showed the Monitor callback within one second.

### End in the extension

7. The Focus-off end, the activation check and a refused or failed start in the extension save their end and stop the focus and break activities, as today, but call no shield method.
8. `intervalDidEnd` of a focus or break activity whose stored session is `terminal` or `ending` with the same id, or whose session is no longer stored, lifts the focus shield in the app container. This extends the M2 rule "a late callback of an earlier session cannot clear this one": the identity check still applies, and a callback for another running session changes nothing.

### Locks and markers

9. A section of the extension writes no registration or stop marker. The marker tells a Monitor callback that the lock holder's section decides that activity, and an extension section cannot decide a shield. So the Monitor's callback waits for the lock with its bounded retry, as for any other holder.

### Everyday layer

10. A section of the extension registers and stops the everyday activities as every section does, but its convergence skips the store steps (`applyStored`, `clearShield`). The next section in the app container converges the store.

### Repair in the app container

11. Every section in the app or the Monitor, after its own steps, applies these two rules before the everyday convergence:
    - a stored `active` session with `shieldPending` is shielded and saved without the flag, as in decision 5 (a lost `intervalDidStart`);
    - with no running session stored, the focus shield is lifted (a lost `intervalDidEnd`).
12. The rules hold for a manual session too, which never has `shieldPending`.

### Filter option label

13. The filter's `Bool` option is renamed from "집중 시작" to "자동으로 집중 시작", so that it no longer reads as the app's "집중 시작하기" button (2026-11-16: the two were confused during the device run). The parameter key `startsSession` stays, so an existing filter keeps its value.

## Stored values

| Value           | Where                              | Type    | Meaning                                                                                      |
| --------------- | ---------------------------------- | ------- | -------------------------------------------------------------------------------------------- |
| `shieldPending` | `ControlSession` in `control.json` | `Bool?` | `true` from the extension's save of `active` until a section in the app container shields it |

- Optional, so the schema version stays `2`; a missing value means no pending shield.
- [Length validation](2026-11-16-focus-filter-extension-design.md#length-validation) does not change. A session with `shieldPending` is valid only in `active`; the store rejects it in any other phase.

## Gaps between steps

| Gap                                                                  | Thrown error                                                         | Process exit or lost callback                                                                                                       |
| -------------------------------------------------------------------- | -------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Extension start: after the registration, before the save of `active` | The rollback stops the activity and saves `terminal`, `.startFailed` | `preparing` stays; the next reconcile ends it as `.recoveryInterrupted` and stops the activity (M1)                                 |
| Monitor `intervalDidStart` not delivered or lock retries run out     | -                                                                    | The session runs unshielded until the next section in the app container applies decision 11                                         |
| Monitor apply succeeds, save of the cleared flag throws              | The shield is on and the flag stays; the next section saves again    | Same                                                                                                                                |
| Extension end: `intervalDidEnd` not delivered                        | -                                                                    | The focus shield stays until the next section in the app container (decision 11), at the latest the app's next launch or foreground |
| Monitor `intervalDidEnd` before the extension's save of `ending`     | -                                                                    | The callback waits for the lock (decision 9) and then sees the stored end                                                           |

The second and fourth rows are the cost of a process that cannot shield: a lost Monitor callback leaves the shield wrong until the app container runs again.
The unshielded direction (second row) is looser and bounded by the next Monitor callback, such as the focus end or a rollover, or the app.
The shielded direction (fourth row) is stricter; the person can always open the app, which repairs it.

## One-shot callbacks

| Callback                                           | Recovery                 |
| -------------------------------------------------- | ------------------------ |
| `intervalDidStart` of an extension-started session | Decision 11, first rule  |
| `intervalDidEnd` after an extension end            | Decision 11, second rule |

## Superseded lines of the extension design

- Decision 10 and the transitions "Filter start" and "Filter end": the extension compiles the shield adapters but never calls them; the shield steps move to the Monitor (decisions 4 to 8).
- Decision 20 keeps its access rule; the shield verification that it describes moves to the Monitor.

## Physical-device verification

1. App closed, Focus on: the Monitor applies the shield within a few seconds (log line of the Monitor), and the selection is shielded on screen.
2. App closed, Focus off: the Monitor lifts the shield on `intervalDidEnd`.
3. Focus on, then open the app: the session stays running (no `.recoveryInterrupted`), and `집중 종료` lifts the shield.
4. A break in an extension-started session lifts and restores the shield as for a manual session.
5. The remaining device steps of the extension design, 4 to 11.
6. The renamed option shows "자동으로 집중 시작" in the Focus settings, and a filter added before the rename keeps its value.

## Verification

- Host tests: the extension's sections never call the shield or the everyday store (a fake `ShieldClient` that fails the test when called), the Monitor's `intervalDidStart` applies a pending shield and clears the flag, a failed apply ends as `.startFailed`, `intervalDidEnd` lifts the shield of an ended session and not of another running one, decision 11 in both directions, and the store rejects `shieldPending` outside `active`.
- The separate-process race check: an extension-like section without markers and a Monitor callback that waits for its lock.
- SDK tests for the Monitor's selection read from the App Group.
- An unsigned device Release build, and the device steps above.
