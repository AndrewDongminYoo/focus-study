# Start latency measurement

Issue: [#33](https://github.com/AndrewDongminYoo/focus-study/issues/33).

## Problem and scope

`FocusModel.start()` runs synchronously on the main actor, including its initial refresh, session registration, and final refresh or failure handling.
SwiftUI cannot render the temporary `isStarting` value during that call.
Measure the existing path before choosing between an observable progress state and removing conditions that cannot be rendered.

## Measurement contract

- Time the complete `FocusModel.start()` call with the monotonic system uptime clock.
  Construct services, history storage and selections before the interval.
- Record individual samples, sample count, nearest-rank p50 and p95, maximum, toolchain, runtime, and dependency boundaries.
- Measure success without contention and a real `SharedControlStore` lock timeout separately.
  Use temporary control files, in-memory SwiftData, and synthetic authorization, monitoring and shields for simulator tests.
- Keep synthetic measurements distinct from successful real `DeviceActivityCenter.startMonitoring` calls.
  Simulator measurements cannot establish that device latency is negligible.
- Before deciding the UI direction, collect successful device start measurements, including the first start and subsequent starts, under the physical-device authorization rules.
  Record both total start time and the registration interval when investigating a slow sample.
- Provide an opt-in DEBUG timing callback for accepted start calls, including early refresh failures.
  The existing `--screen-time-diagnostics` runtime writes total milliseconds to the console; default runs, synthetic fixtures and Release builds do not emit device timing logs.
  Exclude rejected taps and preserve all existing start and failure behavior.

## Acceptance and constraints

Record measured values and their limits in the PR.
Use relevant measurements to decide whether the start needs visible progress; do not remove `isStarting` based only on a fast synthetic monitor.
If device measurements are unavailable, retain an explicit measurement blocker rather than claim issue completion.

Keep every process-lock section synchronous: no `await`, UI wait, or actor hop inside the lock.
Preserve session transitions, rollback, privacy boundaries, and accessibility identifiers.
Do not change authorization, dependencies, provisioning, or real restrictions as part of measurement setup.
Any eventual rendered change requires operator visual approval before merge.
