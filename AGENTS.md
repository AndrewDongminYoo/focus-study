# FocusStudy Agent Guide

## Project scope

FocusStudy is a provisional product name for an iOS 17+ app built with SwiftUI, Observation, and SwiftData.
It provides individual Screen Time authorization, app and website selection, fixed 25-minute focus sessions, local session history, and an isolated usage report.
Keep changes within this baseline unless the task explicitly expands it: no pause, parental management, Android client, accounts, backend, AI, or rewards.
Preserve existing Korean UI text; use English for code identifiers and technical documentation.

## Sources and project generation

- `project.yml` is the XcodeGen source for targets, build settings, dependencies, and the shared `FocusStudy` scheme.
- `FocusStudy.xcodeproj` is tracked generated output.
  Change `project.yml` first, run `xcodegen generate`, and review the generated diff rather than editing the project file by hand.
- `Package.swift` defines the macOS-testable modules and their source inclusion/exclusion rules.
  Keep these rules aligned when adding files under `App/` or `Report/`.
- Both build definitions use Swift 5 language mode; the package requires Swift tools 6.0 and macOS 14+ for host tests.
  There are no external package dependencies in the current manifest.
- `.github/workflows/verify.yml` defines CI checks and its explicit Xcode/runtime pins.
  Read it before changing toolchain assumptions; the deployment target does not identify the SDK required to compile current API references.

Use these current documentation paths:

- [Design](docs/specs/2026-10-26-focus-study-design.md)
- [Implementation plan](docs/plans/2026-10-26-focus-study.md)
- [Implementation decisions](docs/implementation-ledger.md)
- [Review regressions](docs/notes/independent-review.md)
- [Physical-device acceptance](docs/notes/screen-time-device-matrix.md)

The plan preserves the initial task breakdown and links to current interfaces.
Use source and manifests for executable behavior, and the implementation ledger for historical decisions.
Historical approvals and verification results in these documents do not authorize new external actions or establish current test success.
Keep new plans, specs, and notes under `docs/plans/`, `docs/specs/`, and `docs/notes/`.

## Architecture and ownership

| Location | Responsibility |
| --- | --- |
| `App/FocusStudyApp.swift`, `App/FocusRuntime.swift` | Bootstrap, recovery before storage loading, real versus DEBUG fixture wiring |
| `App/FocusModel.swift`, `App/FocusView.swift` | Main-actor state, session actions, foreground/lifecycle refresh, selection and history UI |
| `App/AuthorizationService.swift`, `App/SelectionRepository.swift`, `App/SelectionEditor.swift` | Individual authorization, private token persistence, draft selection validation |
| `App/SessionRecord.swift` | SwiftData session records, terminal import and acknowledgement |
| `App/UsageReportHost.swift` | Report context/filter and explicit content recreation on reload |
| `Shared/` | Screen Time SDK-independent control types, state machine, file locking, recovery, validation, and time rules |
| `Integration/ScreenTimeAdapters.swift` | FamilyControls, DeviceActivity, ManagedSettings, and App Group adapters |
| `Monitor/FocusMonitor.swift` | Extension callbacks delegated to the shared session engine |
| `Report/` | Extension-only usage aggregation and token-row rendering |
| `Presentation/UsageSummarySection.swift` | Shared total/unavailable rendering; the app uses synthetic values only in DEBUG fixtures |
| `App/Debug/UITestFixtures.swift` | Synthetic authorization, selection, monitoring, storage failures, and report lifecycle/state probes |
| `Integration/DeviceDiagnostics.swift`, `App/Debug/DeviceDiagnosticsSection.swift` | Opt-in DEBUG diagnostics around the real monitoring adapter and shared callback engine |

The app and Monitor compile `Shared/` and `Integration/` directly into their targets.
Report has a separate source boundary and does not depend on those directories.
`Presentation/` contains display-only code compiled into App and Report; it does not transport report data to the host.
SwiftPM exposes `FocusCore`, `FocusHistory`, and `FocusReportLogic` for host tests; keep Screen Time SDK imports out of `Shared/`.
Use the existing protocols and injected closures for failure tests rather than adding another service framework.

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
