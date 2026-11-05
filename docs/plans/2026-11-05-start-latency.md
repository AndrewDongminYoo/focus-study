# Start latency measurement plan

Contract: [start latency measurement](../specs/2026-11-05-start-latency-design.md).

## Steps and owned paths

1. Measure the unchanged start path in `SDKTests/StartLatencyTests.swift`.
   Exercise actual temporary control files and in-memory history; assert the successful active state and the failed idle state before interpreting timing output.
   Run 30 starts without contention and 5 lock timeouts, with raw samples attached to the test result.
2. Regenerate `FocusStudy.xcodeproj` with XcodeGen for the new test file.
   Existing directory source rules in `project.yml` already include `SDKTests/`; no target or build-setting change is intended.
3. Record toolchain, sample values and boundaries in `docs/notes/2026-11-05-start-latency.md`.
   Inspect `App/FocusModel.swift`, `Shared/SharedControlStore.swift`, and the existing design contract as the primary implementation sources.
4. Test a DEBUG-only timing callback in `SDKTests/FocusModelTests.swift` before wiring it around `App/FocusModel.swift`'s full accepted call.
   In `App/FocusRuntime.swift`, enable console output only for the existing opt-in diagnostics runtime.
   Verify successful refresh, early refresh failure and rejected taps; keep logging out of Release and default runs.
5. Obtain successful device timing evidence before choosing the UI change.
   Without that evidence, retain the existing app behavior and save a precise resumable blocker.
6. Within the measured direction, write a behavioral regression before changing production code, verify its intended failure, implement the smallest fix, and run affected SDK/UI checks.
   Review applicable documentation in the same candidate, then continue the authorized PR lifecycle.

## Verification

- Run the SDK measurement suite on the installed iPhone simulator with signing disabled and parallel testing disabled.
  A destination or compilation error is a blocked measurement, not a sample or a behavioral regression.
- Run the affected SDK suite and compile App, Monitor and Report after any model change; add the unsigned device Release build for any DEBUG wiring change.
- Run host tests and the separate-process race helper if shared control behavior changes.
- Check the explicit changed document paths with Trunk, inspect internal links, and review the generated project diff.
- Separate passing synthetic checks from unexecuted physical-device acceptance and any pending visual approval.
