# Dedicated break screen implementation plan

Contract: [dedicated break screen and early return](../specs/2026-11-05-break-screen-design.md).
Execution: native changes in the current `perf/33-device-start-latency` workspace, preserving the active device console session.

## 1. Early return and accounting

Owned paths: `Shared/SessionControl.swift`, `CoreTests/BreakControlTests.swift`, `CoreTests/EverydayControlTests.swift`.

Add regressions for early return from `onBreak`: restored restrictions, active focus, actual pause, reduced deadline credit, consumed break, correct registration, repeat safety, stale callback, and subsequent normal break.
Add save, restore, registration, retry, and process-interruption cases using the existing fake world.
Check everyday-layer restoration under the existing schedule rule.
Run focused regressions before changing the engine and record their intended failures.
Extend `resume` and the existing re-block helper with the smallest compatible change, then run `swift test -j 2` and the README race helper.

## 2. Model and dedicated surface

Owned paths: `App/FocusModel.swift`, `App/FocusView.swift`, a new `App/BreakSessionView.swift` if needed, `SDKTests/FocusModelTests.swift`, and `UITests/FocusFlowTests.swift`.

Expose the existing return action during `onBreak` without bypassing engine guards.
First add the SDK/UI expectations that fail on the current behavior.
Keep shared lifecycle refresh and one-second ticking in the existing owner; derive screen choice from the session phase.
Move break-specific content into its own surface and give focus controls a lower action area separate from the centered timer.
Preserve all existing identifiers and session-end/error paths; keep copy short and consistent with the existing 해요체.

If a new App file is added, update `Package.swift` exclusions and regenerate the tracked project with `xcodegen generate`.
Do not edit generated project output directly.
Run affected SDK/UI tests with the installed simulator using the README command and one heavy job at a time.
Compile App, Monitor, and Report through those checks.

## 3. Documentation and review

Owned paths: the affected M2 contract, `AGENTS.md` scope sentence if early-return wording becomes stale, the measurement note, and the relevant verification record.

Reconcile the historical “exactly three minutes” exclusion with this approved early-return rule, keeping history and current behavior distinct.
Keep the first real successful start sample and later samples separate from the synthetic baseline.
Run scoped Trunk checks, internal-link checks, and complete diff review.
Review the core transaction and presentation changes at the repository-required depth and recheck affected regressions after repairs.
Capture the waiting, break, normal-ended, and early-return states for explicit visual approval before the PR merge.

## Review focus

Check interruptions before and after the shortened-credit save, registration failure after re-block, stale callbacks during a newer break, everyday-layer restoration, and large text without obscured return or end actions.
Do not suspend while holding a process lock or infer real Screen Time correctness from fixtures.
