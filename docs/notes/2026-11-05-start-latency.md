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

## Decision and remaining evidence

The synthetic successful path is short in this run; a real lock timeout can occupy the main actor for about a quarter second.
Neither number measures successful `DeviceActivityCenter.startMonitoring`, real managed-settings effects, or persistent device history.
Therefore the progress UI decision and removal of `isStarting` remain pending successful device measurements.
The current measurements do not close #33.

DEBUG builds provide a timing callback around accepted `FocusModel.start()` calls, including refresh failures and error handling.
Only the existing real `--screen-time-diagnostics` runtime connects this callback to the `START_LATENCY total_ms=...` console log.
Default runs and synthetic UI fixtures do not emit that log; Release excludes the callback and wiring.
The interval excludes setup before the tap, rejected taps, the timing log itself, and the subsequent SwiftUI render.
The value measures how long the synchronous call occupies the main actor, rather than tap-to-visible-response latency.
Capture first and repeated successful starts with device/OS/build details and their outcomes; use Instruments to isolate registration if a total is slow.

The existing [session design](../specs/2026-10-26-focus-study-design.md) still requires every process-lock section to remain synchronous.
The code readers for this investigation are `App/FocusModel.swift` and `Shared/SharedControlStore.swift`; no session, lock or UI behavior changed during baseline measurement.

Oracle searched the personal `focus-study` index for `start latency`, `progress indicator`, `FocusModel.start`, and `isStarting` at source revision `9670d54de3076c5239713f54900c7a855bd18478`.
The result was no matching precedent, rather than evidence for either UI direction.
