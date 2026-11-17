# Amendment: no immediate DeviceActivity callback while the extension holds the lock

Date: 2026-11-17.
Status: design for approval. Issue #152, after the device run recorded in #170.
This document amends the [shield amendment](2026-11-16-extension-shield-amendment.md) (the "shield amendment") and, through it, the [Focus filter extension design](2026-11-16-focus-filter-extension-design.md), only where it says so; where they differ, this document is the newer decision.

## Problem

The device run of 2026-11-17 ([device matrix](../notes/screen-time-device-matrix.md#focus-filter-extension-after-the-shield-amendment-2026-11-17-stopped-152)) showed that `startMonitoring` of an interval that starts now and `stopMonitoring` of a running interval return only after the Monitor's callback for that interval returns.
The extension makes both calls inside its lock section, and under decision 9 of the shield amendment it writes no registration marker, so the Monitor's callback waits for the lock until its bounded retry runs out (2281 ms), and only then does the extension's call return.
So the Monitor never shields a session that the extension starts, and never lifts the shield of a session that the extension ends.
The app does not have this problem: its sections write the registration and stop markers, and a callback that finds one returns at once (device matrix, 2026-11-14 timings).
A probe showed that a registration whose interval starts 5 s later returns in 32 ms, and that the Monitor then takes the lock and applies the shield; it also showed that the Monitor and the app write the same `focusSession` store.
A second probe the same afternoon, with the delayed start and with every focus stop of the extension made after the lock is released, passed both ways twice with the app closed: the on calls took 113 and 52 ms and the Monitor shielded the selection 5.5 and 6.2 s after the call, and the off calls took 41 and 36 ms, during which the Monitor's `intervalDidEnd` cleared `focusSession` inside the 29 and 24 ms deferred `stop` (device matrix, same section).

## Decisions by Claude (I can change them)

### Start

1. The first focus registration of a session that an extension section starts, in the start steps, begins at the section time plus `extensionStartDelay`, 5 s; its end is `expiresAt`, as today.
   The interval is then at least the focus length minus 5 s, at least 24 min 55 s, above DeviceActivity's 15-minute minimum.
   The session's `startedAt` does not change, so its focused time still starts at the call (shield amendment, decision 6); the shield arrives with the Monitor's `intervalDidStart` about 5 to 7 s later (device: 5.5 to 6.6 s).
2. The registration check of the start steps (`isRegistered`) is unchanged; the probe read the delayed interval as registered right after the call.
3. Every later registration of the same session in an extension section, such as a rollover, keeps the start at `startedAt`, as today, so its length stays what the engine computes and a late catch-up cannot fall below the 15-minute minimum.
   Only the first registration is delayed, because only that call creates an interval whose `intervalDidStart` would be due at once.
   `[UNCERTAIN]` Whether registering a running interval again with a later end delivers an immediate callback. If it does, that call waits up to about 2.3 s and the Monitor's callback is lost; a callback of a running session changes nothing that the next section does not redo, so the cost is the wait.

### Stops

4. An extension section never calls `stop`, `stopBreak` or `stopEveryday` inside the lock. It records each stop and makes it after the lock is released, in the order recorded, before the call returns.
   Inside the section, an activity with a recorded stop counts as not registered, so every rule that reads `isRegistered` sees the state that the section committed.
5. This covers every stop of an extension section: the end of a session (Focus off, the activation check, a refused or failed start and its rollback), the break cleanup, and the read-failure cleanup.
   - Reconciliation (2026-11-17, #172): the extension defers only the stop of a session that its own section ended, whose focus and break names no process registers again. It makes no other stop: an orphaned break activity of a running session and the read-failure cleanup are left to the next section in the app container, which stops inside its own lock with its markers. A deferred stop of a reusable name, such as break `(S, 1)` of a `waiting` session, could remove the registration that the app makes for the same name between the release of the lock and the stop.
6. While the extension waits in its deferred `stopMonitoring`, the Monitor's `intervalDidEnd` takes the lock, finds the session `terminal` or removed, and lifts the focus shield by the repair rule (shield amendment, decisions 8 and 11).

### Everyday layer

7. An extension section neither registers nor stops an everyday activity: its convergence does nothing. This replaces decision 10 of the shield amendment, under which the extension registered and stopped everyday activities.
   A registration of an everyday activity whose range has begun would wait for the Monitor in the same way, and the Monitor's everyday callback would be lost.
   The next section in the app or the Monitor converges the everyday layer, as it does today.

### Unchanged

8. The extension still writes no registration or stop marker (shield amendment, decision 9): with the delayed start and the deferred stops, no callback for the extension's own changes arrives while it holds the lock, and a marker would make the Monitor skip the callback that must apply or lift the shield.
9. The app and the Monitor keep their markers, their in-lock registrations and stops, and the repair of decision 11.

## Gaps between steps

| Gap                                                                                  | Thrown error                                                                              | Process exit or lost callback                                                                                                                                                                                                                                                                                                                                                |
| ------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Extension start: saved `active` with `shieldPending`, the delayed interval not begun | -                                                                                         | The Monitor's `intervalDidStart` applies the shield when the interval begins; if it is lost, the next section in the app container does (shield amendment, decision 11)                                                                                                                                                                                                      |
| Extension start: rollback after the registration                                     | The rollback saves `terminal`, `.startFailed`, and the deferred stop removes the interval | The interval stays registered with a `terminal` session; its `intervalDidStart` finds nothing pending, and its `intervalDidEnd` at the registered end lifts nothing that is on                                                                                                                                                                                               |
| Extension end: saved `terminal`, deferred stops not yet made                         | -                                                                                         | The interval stays registered. The shield stays until the next section in the app container lifts it by the repair, at the latest the interval's own `intervalDidEnd` at its registered end, or the app's next launch or foreground                                                                                                                                          |
| Deferred stop: the Monitor's `intervalDidEnd` finds the lock held by another section | -                                                                                         | Its bounded retry runs; if it runs out, the next section in the app container lifts the shield                                                                                                                                                                                                                                                                               |
| The Focus turns off within the start delay                                           | -                                                                                         | The end saves `terminal` and the deferred stop removes an interval that has not begun; no shield was applied                                                                                                                                                                                                                                                                 |
| Extension end: both saves of `end` fail (reconciliation 2026-11-17, #172)            | The section throws; the stored session stays running, and the deferred stop still runs    | The stop delivers the Monitor's `intervalDidEnd`, whose reconcile ends the running session as `.recoveryInterrupted` because its registration is gone; this keeps the #53 rule that Focus off releases a filter session. If the app registered a break in between, the stop removes it too, and the same reconcile ends the session, so no restriction stays wrongly applied |

The third row is the cost of deferring the stop: a process exit between the commit and the stop leaves a shield that only the app container can lift, bounded by the registered end of the interval, which is at most one base length after the last rollover.

## One-shot callbacks

| Callback                                                           | Recovery                                                |
| ------------------------------------------------------------------ | ------------------------------------------------------- |
| `intervalDidStart` of a delayed interval                           | Decision 11 of the shield amendment, first rule         |
| `intervalDidEnd` during the extension's deferred stop              | Decision 11 of the shield amendment, second rule        |
| An everyday callback that the extension's section no longer causes | None needed: the extension changes no everyday activity |

## Cross-process order

- A deferred stop names only the activities of the session that the section ended; a later section in any process that starts a new session registers a new name, so a late deferred stop cannot stop it.
- The app never registers the activity of a `terminal` session again, so a deferred stop cannot remove a registration that a later section made for the same session.
- The Monitor's callback for the delayed start can arrive while another section holds the lock; it keeps its bounded retry, and the repair of the next section covers a callback that runs out.

## Superseded lines

- Shield amendment, decision 10 (the extension registers and stops everyday activities): replaced by decision 7.
- Shield amendment, gap table, rows 2 and 4: the lost callback is no longer the expected case for the extension; it stays the recovery path.

## Physical-device verification

1. App closed, Focus on: the selection is shielded within about 10 s, and the extension's call returns in well under a second.
2. App closed, Focus off: the shield is lifted within a few seconds, without opening the app, and the extension's call returns in well under a second.
3. The everyday layer keeps its state through both calls, and the next app section converges it.
4. The remaining steps of the shield amendment (3 to 6) and of the extension design (4 to 11).

## Verification

- Host tests: an extension section never calls a stop inside the lock and makes every recorded stop after it, in order, also when the section threw; a recorded stop reads as not registered inside the section; the first registration of an extension start begins at the section time plus 5 s and keeps its end; a rollover in an extension section, also a late catch-up 20 minutes after a missed rollover, keeps the start at `startedAt`, so its interval stays at least 15 minutes and the session keeps running; an extension section changes no everyday activity.
- The separate-process race check: an extension end whose deferred stop runs while a Monitor-like callback waits for the lock, and the callback then lifts the shield.
- An unsigned device Release build, and the device steps above.
