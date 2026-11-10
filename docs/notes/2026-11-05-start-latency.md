# Start latency measurements

Issue: [#33](https://github.com/AndrewDongminYoo/focus-study/issues/33).
Contract: [measurement and UI decision](../specs/2026-11-05-start-latency-design.md).

## Baseline measured on 2026-11-05

The production start path was unchanged from `20ad34ec3712b82d49cb55d16de1cb53f9941955`.
`SDKTests/StartLatencyTests.swift` measured the full synchronous `FocusModel.start()` call, including initial refresh, engine start and final refresh or error handling.
Each sample used fresh temporary control files and a fresh in-memory SwiftData container; setup was outside the timed interval.
Authorization, selection, monitoring, shields and the everyday layer were synthetic.
The lock-timeout samples held the actual `control.lock` inode throughout the call, so they failed in the initial refresh before monitoring registration.

| Scenario                             | Samples | p50 (ms) | p95 (ms) | Maximum (ms) |
| ------------------------------------ | ------- | -------- | -------- | ------------ |
| Successful start, no lock contention | 30      | 2.009    | 6.142    | 12.215       |
| Initial-refresh lock timeout         | 5       | 251.917  | 252.298  | 252.298      |

Percentiles use nearest rank; all raw samples are printed as `START_LATENCY` and retained as XCTest text attachments.
The successful samples reached an active session with the synthetic shield applied and no model error.
Timeout samples retained no session, applied no shield, and exposed the retryable model error.

Environment: Xcode 26.6 (`17F113`), SDK product version 26.5.1 (`23F81a`), iPhone 17 simulator on iOS 26.5 (`23F73`), Swift 5 language mode, Debug, signing disabled and parallel testing disabled.
The 10-core host's one-minute load was 6.65 at launch and briefly reached 47.54 around the end of compilation/testing.
These are diagnostic samples from this run, not stable hardware performance guarantees.

## Runtime selection prerequisite

The first test attempt exited 70 before compilation because Xcode reported iOS 26.5 as unavailable, although `simctl` showed the booted runtime and `-showsdks` listed the SDK.
`simctl runtime match list` selected build `23F81a`, while the installed runtime was `23F73`.
A temporary supported `simctl runtime match set iphoneos26.5 23F73 --sdkBuild 23F81a` override made the destinations available.
The SDK test run used that override, then restored the original default mapping in a `finally` block and verified the complete mapping matched its saved value.
No SDK, runtime image or physical device was installed or changed.
Future local runs must resolve this machine prerequisite again; this workaround does not change CI's pinned environment or prove runtime compatibility beyond the executed checks.

## Physical-device sample on 2026-11-05

The first accepted start call in a diagnostic launch on the iPhone 16 Pro took **2,522.737 ms**.
The timer started normally, and the subsequent break was confirmed on the phone.
This is one successful sample; repeated successful starts and the registration interval have not yet been measured.
It does not establish a typical duration or percentile.

Environment: iPhone 16 Pro (`iPhone17,1`), iOS 27.0.1 (`24A446`), signed Debug version 0.1, build 1, launched with `--screen-time-diagnostics` and console forwarding.
The installed build came from `157920edecd1d67ae4da89a755043d3d489d477e`; executable source and project configuration match the merged measurement implementation at `b90c36834010295fc84b73d94c86c40c6d52418a`.
The duration-only console line was `START_LATENCY total_ms=2522.737`, logged at 19:51:03 +09:00.
This was the first measured start in this launch, not a verified first-ever Screen Time registration or a cold-device benchmark.

The total establishes a synchronous main-actor occupation of about 2.52 seconds in a successful real start.
It does not identify which operation caused the delay, measure the subsequent SwiftUI render, or establish when the system shield became visible.
The successful synthetic baseline cannot be used to dismiss this device observation.

## Decision and remaining evidence

The synthetic successful path is short in this run; a real lock timeout can occupy the main actor for about a quarter second.
Neither number measures successful `DeviceActivityCenter.startMonitoring`, real managed-settings effects, or persistent device history.
The real successful sample is long enough to require investigating visible start feedback; removing `isStarting` based on the fast synthetic path is not supported.
Repeated device measurements and investigation of the registration interval remain pending.
The [interface polish design](../specs/2026-11-05-interface-polish-design.md) separates a pending UI request from the unchanged synchronous start body so feedback can be displayed before that body runs.
This does not remove main-actor occupation or establish current physical-device feedback; local rendered verification is recorded with that change.
The current measurements do not close #33.

DEBUG builds provide a timing callback around the accepted synchronous start body, including UI requests, refresh failures, and error handling.
The display-frame opportunity before that body is excluded.
Only the existing real `--screen-time-diagnostics` runtime connects this callback to the `START_LATENCY total_ms=...` console log.
Default runs and synthetic UI fixtures do not emit that log; Release excludes the callback and wiring.
The interval excludes setup before the tap, rejected taps, the timing log itself, and the subsequent SwiftUI render.
The value measures how long the synchronous call occupies the main actor, rather than tap-to-visible-response latency.
Capture first and repeated successful starts with device/OS/build details and their outcomes; use Instruments to isolate registration if a total is slow.

The existing [session design](../specs/2026-10-26-focus-study-design.md) still requires every process-lock section to remain synchronous.
The code readers for this investigation are `App/FocusModel.swift` and `Shared/SharedControlStore.swift`; no session, lock or UI behavior changed during baseline measurement.

Oracle searched the personal `focus-study` index for `start latency`, `progress indicator`, `FocusModel.start`, and `isStarting` at source revision `9670d54de3076c5239713f54900c7a855bd18478`.
The result was no matching precedent, rather than evidence for either UI direction.

## Per-operation timing lines added on 2026-11-10

To split a slow total into Screen Time operations, the `--screen-time-diagnostics` runtime now also logs one line per operation: `SCREEN_TIME_TIMING op=<register|register_break|register_everyday|apply_shield> ms=...`.
Each value is measured with `ProcessInfo.processInfo.systemUptime` around one real `DeviceActivityCenter` registration through `DiagnosticMonitoring`, or around one focus shield apply through `FocusServices.applySelection`.
The `START_LATENCY` and `BREAK_LATENCY` lines did not change.
A start or break transition now emits these lines inside its measured interval, so the earlier statement that the interval excludes the timing log no longer covers them: the total includes the cost of the per-operation lines.
Only `apply_shield` is limited to a start.
Registration lines also appear outside a start: a break transition emits `register_break` and re-registers the focus activity as `register`, callback handling, reconcile and cleanup can re-register the focus activity as `register`, and the everyday convergence at the end of a lock section can emit `register_everyday`.
A `SCREEN_TIME_TIMING` line therefore does not name the operation that caused it; attribute it to a start only when no other operation ran between that start and its `START_LATENCY` line.
Default runs, synthetic UI fixtures and Release builds emit nothing new; the timing code exists only in DEBUG.
SDK tests prove the callback shape with a fake monitoring client; they do not measure real Screen Time.
No device measurement with these lines exists yet, so the slow operation in the 2,522.737 ms sample is still unidentified and #33 stays open.

## Physical-device phases measured on 2026-11-10

Six accepted starts in one diagnostic launch split the device total into Screen Time operations.
Each start was followed by ending the session before the next one; no break, callback or other start ran between a start and its `START_LATENCY` line, so each `register` and `apply_shield` line belongs to that start.

| Start | `register` (ms) | `apply_shield` (ms) | `START_LATENCY` total (ms) | Rest (ms) |
| ----- | --------------- | ------------------- | -------------------------- | --------- |
| 1     | 2,313.355       | 41.537              | 2,389.948                  | 35.056    |
| 2     | 2,319.803       | 42.445              | 2,398.127                  | 35.879    |
| 3     | 2,323.773       | 42.049              | 2,403.707                  | 37.885    |
| 4     | 2,313.959       | 41.885              | 2,391.926                  | 36.082    |
| 5     | 2,318.188       | 41.932              | 2,396.890                  | 36.770    |
| 6     | 2,321.938       | 42.411              | 2,399.960                  | 35.611    |

Nearest-rank p50 of the total is 2,396.890 ms and the maximum is 2,403.707 ms.
"Rest" is the total minus the two timed operations: the lock sections, refreshes, history and logging, about 36 ms.
The focus activity registration (`DeviceActivityCenter.startMonitoring` through `ScreenTimeMonitoring.register`) takes about 2.32 s, 96.7% of the median start, in the first start and in every repeated start alike.
The focus shield write takes about 42 ms.
The 2,522.737 ms sample of 2026-11-05 is consistent with this split.

At launch, before any tap, the everyday convergence registered four everyday activities: the first took 2,375.712 ms and the next three 4.981, 2.612 and 2.666 ms.
So the cost is not a one-time cost per process; why one everyday registration was slow and the others were fast was not established, because the active state of each everyday part at launch was not recorded.

Environment: iPhone 16 Pro (`iPhone17,1`), iOS 27.0.1 (`24A446`), signed Debug version 0.1, build 1, built from `fdf5b57` and installed over the existing app, launched with `--screen-time-diagnostics` and console forwarding; samples logged between 08:53:22 and 08:55:30 +09:00.
The values measure main-actor occupation by the synchronous start body, not tap-to-visible feedback, the SwiftUI render, or when the system shield became visible.

### Outcome for #33

The visible start feedback from the [interface polish design](../specs/2026-11-05-interface-polish-design.md) is the response to this delay: the timer screen shows the pending start before the synchronous body runs.
With repeated device totals and the registration interval now recorded, the measurement work of #33 is complete.
Shortening the registration itself would change where `startMonitoring` runs relative to the process lock, which the session design keeps synchronous; that is a separate decision, not part of #33.

## Registration probe added on 2026-11-10

For #101, the diagnostics button `등록 시간 비교` times throwaway registrations of an interval that contains now and one that starts in 2 minutes, logged as `SCREEN_TIME_PROBE interval=<current|future> n=<1..3> ms=...`; no device results exist yet.
