# FocusStudy Agent Guide

## Project scope

The app's display name is "온:공", and FocusStudy is the code and project name of this iOS 17+ app built with SwiftUI, Observation, and SwiftData.
It provides individual Screen Time authorization, app and website selection, focus sessions whose length is a personal setting from 25 to 50 minutes in 5-minute steps (see the [M1 design](docs/specs/2026-10-31-m1-launch-flow-design.md)), local session history, and an isolated usage report.
A session has up to 3 breaks of up to 3 minutes, each after a waiting screen; “다시 집중하기” can end a break early, and a deadline determines whether the session counts as unfocused (see the [M2 design](docs/specs/2026-11-01-m2-break-pass-design.md) and its linked early-return amendment).
An everyday blocking layer has its own selection, one daily range and at most 3 unblocked windows; it runs every day without the app, blocks together with the focus layer, and a break lifts it (see the [M3 design](docs/specs/2026-11-01-m3-schedule-layer-design.md)); inside the range, after a 30-second wait, it can be turned off for the rest of today once a day (see the [off-for-today spec](docs/specs/2026-11-08-everyday-off-today.md)).
A Focus filter starts a normal focus session when an iOS Focus with its session option turns on and ends that session when the Focus turns off; iOS filters notifications by the Focus's own settings, which the app neither reads nor changes (see the [M4 design](docs/specs/2026-11-01-m4-focus-filter-design.md)).
A read-only Live Activity projects confirmed timing as planned times, never shielding (see [contract](docs/specs/2026-11-06-live-activity-decision.md)).
Keep changes within this baseline unless the task explicitly expands it: no other pause, parental management, Android client, accounts, backend, AI, or rewards.
Preserve existing Korean UI text; use English for code identifiers and technical documentation.

## Sources and project generation

- `project.yml` owns targets, settings, dependencies and the shared scheme.
  Change it first, regenerate tracked `FocusStudy.xcodeproj` with `xcodegen generate`, and review the diff; never edit generated output directly.
- `Package.swift` owns host modules and source rules; align it when adding App or Report files.
- Both use Swift 5 mode; host tests require Swift tools 6.0 and macOS 14+. There are no external dependencies.
- `.github/workflows/verify.yml` owns SDK/runtime pins; the deployment target alone does not establish API availability.

Use these current documentation paths:

- [Design](docs/specs/2026-10-26-focus-study-design.md)
- [M1 launch flow and focus length design](docs/specs/2026-10-31-m1-launch-flow-design.md), which supersedes the original design on session length and launch flow
- [M2 break pass and deadline design](docs/specs/2026-11-01-m2-break-pass-design.md)
- [M3 everyday schedule blocking layer design](docs/specs/2026-11-01-m3-schedule-layer-design.md)
- [M4 Focus filter design](docs/specs/2026-11-01-m4-focus-filter-design.md)
- [Everyday status on the timer screen](docs/specs/2026-11-08-everyday-status-on-timer.md), which amends the M3 design for the timer screen
- [Turning the everyday layer off for today](docs/specs/2026-11-08-everyday-off-today.md), which amends the M3 design for in-range editing
- [Everyday schedule preview as a day clock](docs/specs/2026-11-09-everyday-day-clock.md), which amends the [schedule preview spec](docs/specs/2026-11-06-everyday-schedule-preview.md) with a 24-hour clock above the text rows
- [Registration marker for Monitor callbacks](docs/specs/2026-11-10-registration-marker-design.md), which amends the 2026-10-26, M2 and M3 designs with an App Group marker file, so that a Monitor callback skips the lock wait while a lock section registers the same activity
- [Registration marker for stops](docs/specs/2026-11-10-stop-marker-design.md), which extends that marker to the `stopMonitoring` calls inside lock sections
- [Access state](docs/specs/2026-11-11-access-state-design.md), which amends the 2026-10-26, M2, M3 and M4 designs so that only a `denied` access read ends a session or stops the everyday layer, and an unknown read does not
- [Monitor timing](docs/specs/2026-11-13-monitor-timing-design.md), a design for approval: DEBUG-only timing lines for Monitor callbacks, turned on by an App Group flag that `--screen-time-diagnostics` writes
- [Implementation plan](docs/plans/2026-10-26-focus-study.md)
- [M1 implementation plan](docs/plans/2026-10-31-m1-launch-flow.md)
- [M2 implementation plan](docs/plans/2026-11-01-m2-break-pass.md)
- [M3 implementation plan](docs/plans/2026-11-01-m3-schedule-layer.md)
- [M4 implementation plan](docs/plans/2026-11-01-m4-focus-filter.md)
- [Implementation decisions](docs/implementation-ledger.md)
- [Review regressions](docs/notes/independent-review.md)
- [Physical-device acceptance](docs/notes/screen-time-device-matrix.md)
- [Development launch arguments](docs/notes/development-launch-arguments.md): UI fixtures, Live Activity probes, device diagnostics

The plan preserves the initial task breakdown and links to current interfaces.
Use source and manifests for executable behavior, and the implementation ledger for historical decisions.
Historical approvals and verification results in these documents do not authorize new external actions or establish current test success.
Keep new plans, specs, and notes under `docs/plans/`, `docs/specs/`, and `docs/notes/`.

## Architecture and ownership

| Location                                                                                                              | Responsibility                                                                                                                                                                                                                                                               |
| --------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `App/FocusStudyApp.swift`, `App/FocusRuntime.swift`                                                                   | Bootstrap, recovery before storage loading, one-time onboarding migration, launch routing, real versus DEBUG fixture wiring                                                                                                                                                  |
| `App/FocusModel.swift`, `App/FocusView.swift`, `App/BreakSessionView.swift`                                           | Main-actor state, launch route, session actions, foreground/lifecycle refresh, timer screen and phase-driven break screen                                                                                                                                                    |
| `App/FocusSettings.swift`, `App/SettingsView.swift`                                                                   | Focus length, onboarding completion flag, last Focus filter refusal, pending completion card, settings sheet with DEBUG diagnostics                                                                                                                                          |
| `App/FocusStudyFilter.swift`                                                                                          | The `SetFocusFilterIntent` type with one `Bool` option, the only file that imports `AppIntents`; app target only                                                                                                                                                             |
| `App/FocusFilterHandler.swift`, `App/FocusRuntimeHolder.swift`                                                        | Focus filter on and off calls, history import, lock-timeout retry and activation check; one engine, selection repository and `ModelContainer` per process                                                                                                                    |
| `App/FocusGuideView.swift`                                                                                            | Focus setup guide in the settings sheet, with the last refusal                                                                                                                                                                                                               |
| `App/EverydaySettingsModel.swift`, `App/EverydaySettingsView.swift`                                                   | Everyday layer screen in the settings sheet: draft schedule and selection, strict-only save, status row                                                                                                                                                                      |
| `App/OnboardingView.swift`, `App/TodayHistoryView.swift`                                                              | Onboarding steps, today's session history sheet                                                                                                                                                                                                                              |
| `App/AuthorizationService.swift`, `App/SelectionRepository.swift`, `App/SelectionEditor.swift`                        | Individual authorization, private token persistence, draft selection validation                                                                                                                                                                                              |
| `App/SessionRecord.swift`                                                                                             | SwiftData session records, terminal import and acknowledgement                                                                                                                                                                                                               |
| `App/UsageReportHost.swift`                                                                                           | Report context/filter and explicit content recreation on reload                                                                                                                                                                                                              |
| `Shared/`                                                                                                             | SDK-independent control types, session origin and Focus activation marker, session, break and Focus filter transitions, deadline rule, file locking, recovery, validation, time rules, everyday schedule rules and the everyday convergence at the end of every lock section |
| `Integration/ScreenTimeAdapters.swift`, `Integration/BreakSelectionFile.swift`, `Integration/EverydayLayerFile.swift` | FamilyControls, DeviceActivity, ManagedSettings, and App Group adapters; the session-scoped break selection copy; the everyday file `everyday-layer.json` (the only stored everyday selection), the named store `everydayLayer` and the repeating everyday schedules         |
| `Monitor/FocusMonitor.swift`                                                                                          | Extension callbacks delegated to the shared session engine for every activity name, including the re-block on a break activity's end warning and the everyday edges                                                                                                          |
| `Report/`                                                                                                             | Extension-only usage aggregation and token-row rendering                                                                                                                                                                                                                     |
| `Presentation/UsageSummarySection.swift`                                                                              | Shared total/unavailable rendering; the app uses synthetic values only in DEBUG fixtures                                                                                                                                                                                     |
| `App/Debug/UITestFixtures.swift`                                                                                      | Synthetic authorization, selection, monitoring, storage failures, and report lifecycle/state probes                                                                                                                                                                          |
| `Integration/DeviceDiagnostics.swift`, `App/Debug/DeviceDiagnosticsSection.swift`                                     | Opt-in DEBUG diagnostics around the real monitoring adapter and shared callback engine                                                                                                                                                                                       |

App and Monitor compile `Shared/` and `Integration/`; Report stays separate.
`Presentation/` shares views between App and Report, never report data.
Widget compiles only `Shared/FocusActivityContent.swift` and Activity attributes/views, with no App Group or control-store access.
SwiftPM exposes `FocusCore`, `FocusHistory`, `FocusReportLogic`; keep Screen Time imports out of `Shared/` and reuse injected protocols/closures.

## Behavioral changes and verification

Read the [design contract](docs/specs/2026-10-26-focus-study-design.md) before changing session transitions, persistence, authorization, selection, or report data handling.
It owns the product limits, process-lock contract, recovery behavior, and privacy boundaries.
Review the [regression record](docs/notes/independent-review.md) when touching recovery, history failures, or report reload.

Use the commands and suite mapping in [README verification](README.md#실행과-검증).
Choose checks by the changed behavior; documentation-only changes require source/path review, internal-link checks, and the [Trunk check](README.md#문서와-설정-품질-검사) rather than a mobile build.
Before a heavy mobile job, check `uptime` and run only one build or simulator test job at a time.
For behavioral fixes, first reproduce the failure in the relevant suite; a build or destination failure is not a behavioral regression test.

- Changes in `Shared/`: run host tests; locking, session transitions, or callback identity also require the separate-process race check.
- Changes in `App/`, `Integration/`, or `Monitor/`: run affected SDK/UI tests and compile the relevant iOS targets.
- Changes in `Report/`: run report aggregation tests and compile the extension.
  Changes to report reload also require the shared-container UI regression.
- Changes to target configuration or DEBUG fixture wiring: verify an unsigned device Release build as well as simulator behavior.

Keep fixture implementations behind `#if DEBUG`, using temporary control storage and in-memory SwiftData without real authorization requests, monitoring registration, or shields.
Preserve accessibility identifiers used by `UITests/FocusFlowTests.swift` when editing UI.
Real-device diagnostics are separate from fixtures: `--screen-time-diagnostics` opts into the real runtime in DEBUG builds only.
Do not enable that path during synthetic tests or infer permission to apply restrictions from build or installation approval.
Report what each executed check establishes; simulator and unsigned build results never prove real Screen Time behavior or iOS 17 runtime support.

## Signing and physical-device boundary

Follow [device preparation](README.md#실제-기기를-연결하기-전) and record evidence in the [device matrix](docs/notes/screen-time-device-matrix.md).
Do not use `-allowProvisioningUpdates`, change accounts/profiles, apply real restrictions, or install on a physical device without the corresponding explicit authorization.
Keep unexecuted physical-device scenarios explicitly unverified.
