# Live Activity Implementation Plan

> Execute task-by-task with the root as implementer; keep process-lock sections synchronous and use the existing injected-closure/protocol conventions.

**Goal:** Implement issue #74's optional local, read-only focus/break Live Activity without changing session success or shielding behavior.

**Architecture:** Project engine snapshots into SDK-independent display content and serialize display effects outside the engine lock.
One ActivityKit adapter is shared by the app and Monitor; a separate WidgetKit extension receives only the display payload.
Every card identifies scheduled times and the last confirmation so a delayed update does not assert current shielding or completion.

**Tech stack:** Swift 5, Foundation, ActivityKit, WidgetKit and SwiftUI; iOS 17 minimum; no package dependency.

**Spec:** [Approved adoption contract](../specs/2026-11-06-live-activity-decision.md), [implementation #74](https://github.com/AndrewDongminYoo/focus-study/issues/74).

## Constraints and review focus

- Preserve focus/break/latest-return/deadline accounting, wait cancellation, history and everyday-layer independence.
- Add no notifications, push token/server, interactive session actions, widget App Group access or report/selection transport.
- Use the iOS 16.2 content update/end overloads; do not use iOS 17.2 timestamp or newer scheduled-start APIs without availability guards.
- ActivityKit failures never roll back or delay an engine transition; unreadable control state removes the optional display.
- Display every scheduled boundary as a plan, include last confirmation, and show a neutral stale fallback; zero never asserts re-blocking or completion.
- Test session A updates/ends while B starts, state changes during an awaited display operation, and disabled/dismissed/restarted activities.
- Persist the app's per-session start marker before requesting; a missing/dismissed activity for an already-started session is not recreated.
- A background Focus filter may update/end existing activities but creates none; foreground entry can attach a still-relevant session.
- Simulator/typecheck evidence does not establish physical callback timing or iOS 17 runtime behavior; retain those release gates.

## Task 1: Pure projection and display coordination

Owned files: `Shared/FocusActivityContent.swift`, `Shared/FocusActivityProjection.swift`, `Shared/FocusActivityCoordinator.swift`, `CoreTests/FocusActivityTests.swift`, `CoreTests/FocusActivityCoordinatorTests.swift`.

- [x] Add and run failing projection assertions for phase filtering and literal boundary values before implementation.
- [x] Implement `FocusActivityContent` as Codable/Hashable timing, phase and freshness values only.
- [x] Implement projection from `ControlSession`, with separate focus end, break end, latest resume and absolute deadline.
- [x] Add failing coordinator regressions using injected snapshot/client/ledger closures and controllable async operations.
- [x] Implement serialized, bounded reconciliation with snapshot revalidation and exact activity/session identity; test disabled/start-failure/unreadable, orphan, dismissed, duplicate and delayed-operation cases.
- [x] Run `swift test` and the existing separate-process race helper; the core engine itself remains unchanged.

## Task 2: Platform adapter and existing runtime hooks

Owned files: `Activity/FocusActivityAttributes.swift`, `Activity/SystemFocusActivityClient.swift`, `App/FocusActivityRuntime.swift`, `App/FocusModel.swift`, `App/FocusRuntime.swift`, `App/FocusRuntimeHolder.swift`, `App/FocusStudyApp.swift`, `Monitor/FocusMonitor.swift`, affected SDK tests.

- [x] Add failing SDK assertions that a session refresh, read failure and filter/storage-error end notify the display hook without affecting session results.
- [x] Add an ActivityKit adapter that enumerates exact handles, checks enablement, requests without push, updates and ends using iOS 17-compatible APIs.
- [x] Wire one app coordinator before selection/history loading; use app-private UserDefaults for its display-only marker and current foreground state for start permission.
- [x] Notify after existing model, startup, filter and Monitor operations release their process lock; serialize Monitor effects per extension process and never await them inside the engine.
- [x] Keep default synthetic fixtures on a no-op display hook; add one explicit DEBUG ActivityKit probe backed by the synthetic engine for simulator evidence.
- [x] Run affected SDK tests and compile App/Monitor; mark the real Monitor runtime path unverified until a separately approved device run.

## Task 3: Widget, generation and rendered feasibility

Owned files: `Widget/FocusActivityWidget.swift`, `Configuration/Activity-Info.plist`, `Configuration/App-Info.plist`, `project.yml`, generated `FocusStudy.xcodeproj`, `Package.swift`, fixture/UI regression paths, applicable README/AGENTS/spec/device notes.

- [x] Add the Lock Screen and compact/minimal/expanded Island presentations with Korean labels, semantic colors, bounded system timer text and explicit confirmation/planned-time context.
- [x] Add one extension without entitlements/App Group and embed it from the app; edit XcodeGen first, regenerate and review the generated diff.
- [x] Keep SwiftPM source boundaries and SDK test target inclusion aligned.
- [x] Exercise actual ActivityKit start, update, stale/elapsed display and relaunch on the simulator without real Screen Time calls.
      System dismissal gestures were unavailable; retain that physical-device gate and the passing private-ledger reconstruction regressions.
- [x] Capture light/dark, larger text and all presentations; the minimal Island is a shared-view preview, with actual system minimal presentation unverified.
      The real focus-expiry probe showed delayed redraw; do not infer prompt fallback from a static preview.
- [x] If the probe cannot communicate uncertainty clearly, record the failed gate and defer shipment rather than add a server or alter session rules.

## Completion gates

- [x] Run affected host/race/SDK/UI checks, simulator builds and unsigned device Release; run Trunk and documentation/link checks.
- [x] Correct implementation-caused documentation drift and record precisely which feasibility/device gates remain unverified.
- [x] Apply Large-scope parallel read-only review plus adversarial cross-check if the final diff meets repository thresholds; repair sequentially and revalidate affected checks.
- [ ] Commit scoped concerns, push, open the PR and complete current-head hosted review/CI before final body/assignment.
- [ ] Request operator visual approval with surviving artifacts and exact head; merge only after technical and visual gates; keep physical-device release gates and #74 open.
- [ ] Preserve completion evidence and retire owned state after verified merge and settled follow-through.

Minimum commands are `swift test`, the README's separate-process race helper, affected `xcodebuild test` SDK/UI suites, simulator build, unsigned device Release build, and `trunk check --no-fix`.
