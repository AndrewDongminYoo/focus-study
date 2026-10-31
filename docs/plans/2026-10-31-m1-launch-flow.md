# M1 Launch Flow and Focus Length Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open the app on a full-screen timer (or onboarding when setup is incomplete), and make the focus length a 25-50 minute setting.

**Architecture:** `Shared/` gets a length-aware session (`ControlSession` stores its own length through `expiresAt`). A new app-only `FocusSettings` keeps the length and the onboarding flag in `UserDefaults`. `FocusModel` computes a launch route, and SwiftUI shows onboarding, the timer screen, settings and today's history from that route.

**Tech Stack:** Swift 5 mode, SwiftUI, Observation, SwiftData, FamilyControls, DeviceActivity, XCTest (unit and UI tests), XcodeGen.

**Spec:** [`docs/specs/2026-10-31-m1-launch-flow-design.md`](../specs/2026-10-31-m1-launch-flow-design.md)

**Start condition:** Start after PR #45 (iPhone-only portrait) merges. Create the implementation worktree from the updated `main`.

## Global Constraints

- iOS 17 or later, iPhone only, portrait only.
- Allowed focus lengths: 25, 30, 35, 40, 45, 50 minutes. Default: 25 minutes.
- A changed length applies from the next session. A running session keeps its length.
- `Shared/` must not import Screen Time SDK modules.
- `project.yml` is the Xcode project source. Run `xcodegen generate` after each change to it. Keep `Package.swift` exclusions aligned for new files under `App/`.
- All user-facing copy is Korean 해요체, written with the `user-facing-copy` skill. No copy states "25분" when the configured length differs.
- Keep these accessibility identifiers: `start`, `end`, `selection`, `report`, `authorize`, `settings`, `startError`, `retry`, `countdown`, `completion`, `completionDismiss`, `startBlocker`, `chooseSelection`, `pickerSave`, `pickerCancel`, `selectionCounts`, `selectionIssue`, `reportReload`, `reportWaiting`, `startupRetry`, `startupEnd`.
- The permission step requests the system prompt only once. A returning person sees a Settings guide. Do not build a private Screen Time deep link.
- Simulator results do not prove real Screen Time behavior.

## Review Focus

1. A session stored by the current build (1500 seconds) is still active when the M1 build launches. It must load, count down and complete normally. Test: Task 1 Step 1.
2. The person changes the length during an active session. The running session must keep its original length and end time. Test: Task 4 Step 1.
3. The app is killed after the selection is saved in onboarding step 3. The relaunch must resume at the length step, not open the timer. Test: Task 4 Step 1.
4. Access is revoked during a session and approved again later. The session must end as `authorizationRevoked`, the app must show the permission step with the Settings guide, and after approval it must return straight to the timer. Test: Task 4 Step 1 and Task 5 Step 1.
5. A 50-minute session crosses midnight. The remaining time must be capped by 3000 seconds, and the record must belong to the start day. Test: Task 1 Step 1 and Task 2 Step 1.

---

### Task 1: Length-aware session in `Shared/`

**Files:**

- Create: `Shared/FocusLength.swift`
- Modify: `Shared/ControlTypes.swift:13-15`, `Shared/SessionControl.swift:11-18`, `Shared/SharedControlStore.swift:35`, `Shared/TimeRules.swift:3`
- Test: `CoreTests/FocusLengthTests.swift` (new), `CoreTests/SessionControlTests.swift`, `CoreTests/SharedControlStoreTests.swift`, `CoreTests/TimeRulesTests.swift`

**Interfaces:**

- Produces:
  - `public enum FocusLength { public static let allowedMinutes: [Int]; public static let defaultMinutes: Int; public static func isAllowed(seconds: TimeInterval) -> Bool }` (`isAllowed` compares with a 0.01-second tolerance).
  - `ControlSession.init(startedAt: Date, length: TimeInterval = 1500, id: UUID = UUID())` and `public var length: TimeInterval { get }` (`expiresAt - startedAt`).
  - `SessionControl.start(now: Date, length: TimeInterval = 1500, authorized: () -> Bool, apply: () -> Void, matches: () -> Bool) throws -> ControlSession`.
  - `TimeRules.remaining(startedAt: Date, expiresAt: Date, now: Date) -> Int`, which replaces `remaining(expiresAt:now:)` and caps at `expiresAt - startedAt`.

- [ ] **Step 1: Write the failing tests**

```swift
// CoreTests/FocusLengthTests.swift
func testAllowedLengthsAre25To50InFiveMinuteSteps() {
    XCTAssertEqual(FocusLength.allowedMinutes, [25, 30, 35, 40, 45, 50])
    XCTAssertEqual(FocusLength.defaultMinutes, 25)
    XCTAssertTrue(FocusLength.isAllowed(seconds: 3000)); XCTAssertFalse(FocusLength.isAllowed(seconds: 1560))
}
// CoreTests/SessionControlTests.swift
func testStartUsesRequestedLengthForExpiryAndMonitorInterval() throws {
    let (engine, _, monitor, shield) = fixture()
    let s = try engine.start(now: now, length: 2400, authorized: { true }, apply: { shield.apply() }, matches: { shield.applied })
    XCTAssertEqual(s.length, 2400); XCTAssertEqual(monitor.intervals[s.id]?.1, now.addingTimeInterval(2400))
}
// CoreTests/SharedControlStoreTests.swift
func testStoreLoadsEveryAllowedLengthIncludingLegacy1500() throws { /* save 1500 and 3000; both load */ }
func testStoreRejectsSessionWithDisallowedLength() throws { /* save 1560 via JSON; load throws ControlIssue.invalidState */ }
// CoreTests/TimeRulesTests.swift
func testRemainingIsCappedBySessionLength() {
    let start = Date(timeIntervalSince1970: 0), end = start.addingTimeInterval(3000)
    XCTAssertEqual(TimeRules.remaining(startedAt: start, expiresAt: end, now: start.addingTimeInterval(-60)), 3000)
    XCTAssertEqual(TimeRules.remaining(startedAt: start, expiresAt: end, now: start.addingTimeInterval(2999.2)), 1)
}
```

For `testStoreRejectsSessionWithDisallowedLength`, write the envelope JSON with a session whose `expiresAt - startedAt` is 1560, because `ControlSession.init` cannot create that shape.

- [ ] **Step 2: Run `swift test` and confirm the new tests fail to compile or fail.**
- [ ] **Step 3: Implement the interfaces above.** `SessionControl.start` passes `length` to `ControlSession.init`. The store validation uses `FocusLength.isAllowed(seconds:)`. Update the existing `TimeRulesTests` calls to the new signature.
- [ ] **Step 4: Run `swift test`. Expected: all tests pass.**
- [ ] **Step 5: Run the race check from README (`xcrun swiftc ... -o /tmp/focus-control-race` then `/tmp/focus-control-race --verify`). Expected: `PASS: stale A cannot clear B`.**
- [ ] **Step 6: Commit** `feat(core): give each focus session its own length`.

### Task 2: Record duration follows the session length

**Files:**

- Modify: `App/SessionRecord.swift:15`
- Test: `HistoryTests/SessionRecordTests.swift`

**Interfaces:**

- Consumes: `ControlSession.init(startedAt:length:id:)` from Task 1.
- Produces: `SessionRecord.duration` capped at `expiresAt - startedAt`.

- [ ] **Step 1: Write the failing tests** `testFiftyMinuteRecordDurationIsCappedAt3000` (a 3000-second session observed 4000 seconds after start reports `duration == 3000`) and `testRecordCrossingMidnightBelongsToStartDay` (start 23:40 local, 50-minute session, `records(on:)` for the start day returns it, the next day does not).
- [ ] **Step 2: Run `swift test --filter FocusHistoryTests`. Expected: the 3000 test fails with 1500.**
- [ ] **Step 3: Implement** the cap with `expiresAt.timeIntervalSince(startedAt)`. The SwiftData schema does not change.
- [ ] **Step 4: Run `swift test`. Expected: PASS.**
- [ ] **Step 5: Commit** `fix(history): cap record duration by the session's own length`.

### Task 3: `FocusSettings` for length and onboarding

**Files:**

- Create: `App/FocusSettings.swift`
- Modify: `App/FocusModel.swift` (`FocusServices`), `project.yml` (`FocusSDKTests` sources), `Package.swift` (exclude `FocusSettings.swift`)
- Test: `SDKTests/FocusSettingsTests.swift` (new)

**Interfaces:**

- Consumes: `FocusLength` from Task 1.
- Produces:
  - `@MainActor @Observable final class FocusSettings { init(defaults: UserDefaults = .standard); var lengthMinutes: Int; var lengthSeconds: TimeInterval { get }; var hasCompletedOnboarding: Bool; func migrateIfNeeded(accessApproved: Bool, hasSelection: Bool) }`.
  - Keys: `focusLengthMinutes`, `onboardingCompleted`, `onboardingMigrationV1Done`.
  - `lengthMinutes` returns `FocusLength.defaultMinutes` when the stored value is missing or not allowed. Setting a value that is not allowed leaves the stored value unchanged.
  - `migrateIfNeeded` runs once (guarded by `onboardingMigrationV1Done`). It sets `hasCompletedOnboarding = true` only if both arguments are true.
  - Reconciliation (2026-10-31, final review): the shipped interface is `migrateIfNeeded(hasSelection:)`, and it reads only the selection; this supersedes the two-argument signature above and the Step 1 tests that pass access. `App/FocusSettings.swift`, the reconciliation in `docs/specs/2026-10-31-m1-launch-flow-design.md`, and `testExistingSelectionMigratesEvenWhenFirstAccessReadIsNotApproved` are the authority (commit `f9d5c80`).
  - `FocusServices` gets `var settings = FocusSettings()`.

- [ ] **Step 1: Write the failing tests** with `UserDefaults(suiteName: UUID().uuidString)!`: default is 25, `40` persists across a new instance, `27` is rejected, migration sets the flag for an existing user, migration does not set it for a new user, and a second migration call with both `true` after a first call with `false` does not set the flag.
- [ ] **Step 2: Run** `xcodegen generate`, then the iOS test command with `-only-testing:FocusSDKTests/FocusSettingsTests`. Expected: FAIL (type missing).
- [ ] **Step 3: Implement `FocusSettings`.**
- [ ] **Step 4: Run the same command. Expected: PASS.** Run `swift package describe` to confirm `Package.swift` still resolves.
- [ ] **Step 5: Commit** `feat(app): store focus length and onboarding completion`.

### Task 4: Launch route and length in `FocusModel`

**Files:**

- Modify: `App/FocusModel.swift`, `App/FocusStudyApp.swift` (call `migrateIfNeeded` after `prepare()`), `App/Debug/UITestFixtures.swift`
- Test: `SDKTests/FocusModelTests.swift`

**Interfaces:**

- Consumes: `FocusSettings` (Task 3), `SessionControl.start(now:length:...)` and `TimeRules.remaining(startedAt:expiresAt:now:)` (Task 1).
- Produces:
  - `enum OnboardingStep: Int, CaseIterable { case intro, permission, selection, length }`.
  - `enum LaunchRoute: Equatable { case onboarding(OnboardingStep), timer }`.
  - `FocusModel.route: LaunchRoute`:
    - Not completed: `.intro` if access is `.notRequested`, `.permission` if `.denied`, `.selection` if the selection is empty, else `.length`.
    - Completed: `.permission` if access is not approved, `.selection` if the selection is empty, else `.timer`.
  - `FocusModel.completeOnboarding()` sets `settings.hasCompletedOnboarding = true`.
  - `start()` passes `settings.lengthSeconds`. `remaining` with no session returns `Int(settings.lengthSeconds)`.
  - DEBUG fixture: `FocusServices.fixture(arguments:)` uses an in-memory `UserDefaults(suiteName:)`. Mode `onboarding` gives `.notRequested` access, no selection and no flag. Other modes set the flag. Argument `--length <minutes>` sets the length.

- [ ] **Step 1: Write the failing tests:**
  - `testRouteForNewUserFollowsOnboardingOrder`: intro, permission after denial, selection, length, then timer after `completeOnboarding()`.
  - `testRelaunchAfterSelectionResumesAtLengthStep`: a new model on the same defaults with access approved and a selection, but no flag, returns `.onboarding(.length)`.
  - `testRevokedAccessAfterCompletionShowsPermissionThenTimer`.
  - `testStartUsesConfiguredLength` (`lengthMinutes = 40` gives `current?.length == 2400`).
  - `testChangingLengthDuringSessionKeepsRunningSession` (start at 25, set 50, `current?.expiresAt` is unchanged).
  - Make `ModelTestAuthorization.status` and `ModelTestSelection.counts` settable for these tests.
- [ ] **Step 2: Run** the iOS tests with `-only-testing:FocusSDKTests/FocusModelTests`. Expected: FAIL.
- [ ] **Step 3: Implement the interfaces above.**
- [ ] **Step 4: Run the same command. Expected: PASS.**
- [ ] **Step 5: Commit** `feat(app): route launch to onboarding or the timer`.

### Task 5: Onboarding screens

**Files:**

- Create: `App/OnboardingView.swift`
- Modify: `App/FocusStudyApp.swift` (show `OnboardingView` or `FocusView` from `model.route`), `Package.swift` (exclude), `UITests/FocusFlowTests.swift`

**Interfaces:**

- Consumes: `FocusModel.route`, `OnboardingStep`, `completeOnboarding()` (Task 4), `SelectionEditor` and `FixtureSelectionEditor` (existing).
- Produces: identifiers `onboardingNext`, `onboardingBack`, `lengthPicker`, `onboardingFinish`, and reuses `authorize`, `settings`, `chooseSelection`.

Behavior: one screen per step, with a back button except on the intro. The intro states the purpose and "데이터는 기기에만 저장돼요". The permission step shows `authorize` when access is `.notRequested`, and the Settings guide with the `settings` link when it is `.denied`. The `settings` link opens `UIApplication.openSettingsURLString`. The guide text must not state a Settings menu path as fact, because no device check has recorded that path (issues #11 and #38). The permission step has no exit to other screens. The selection step shows the counts and `chooseSelection`, and enables `onboardingNext` only when the selection is not empty. The length step shows `lengthPicker` with the six values, and `onboardingFinish` calls `completeOnboarding()`.

- [ ] **Step 1: Write the failing UI tests:**
  - `testNewUserCompletesOnboardingInOrder` (mode `onboarding`): intro → authorize → choose sample selection → pick 40 → finish → `countdown` reads "남은 시간 40분 0초".
  - `testOnboardingBackReturnsToPreviousStep`.
  - Update `testDeniedPermissionShowsSettingsAndDisablesStartAndReport` → `testDeniedPermissionShowsSettingsGuide`: mode `denied` shows the `settings` link, and `start` does not exist.
- [ ] **Step 2: Run** `-only-testing:FocusUITests`. Expected: the new tests fail.
- [ ] **Step 3: Implement `OnboardingView` and the routing.** Write the copy with the `user-facing-copy` skill.
- [ ] **Step 4: Run the full iOS scheme. Expected: PASS.**
- [ ] **Step 5: Commit** `feat(onboarding): guide new users through access, selection and length`.

### Task 6: Timer screen (layout A), settings and today's history

**Files:**

- Modify: `App/FocusView.swift`
- Create: `App/SettingsView.swift`, `App/TodayHistoryView.swift`
- Modify: `Package.swift` (exclude), `UITests/FocusFlowTests.swift`, `App/Debug/DeviceDiagnosticsSection.swift` (move into `SettingsView` in DEBUG)

**Interfaces:**

- Consumes: `FocusModel` (Task 4), `FocusSettings` (Task 3), `UsageReportHost` and `FixtureUsageReportHost` (existing).
- Produces: identifiers `settingsButton`, `restrictionSummary`, `todaySummary`. `selection` stays on the top-left "제한할 앱" button. `report` moves to a link inside `TodayHistoryView`.

Layout A from the spec: the timer fills the screen, with "제한할 앱" top-left and the settings button top-right. The countdown, "집중 시작하기", `restrictionSummary`, `startBlocker`, and the error with `retry` are in the center. `todaySummary` ("오늘 집중 N분 · N회", completed sessions only) is at the bottom and opens `TodayHistoryView` as a sheet. While a session is active, show only the countdown, a status line, and `end` with its existing confirmation. Keep the completion state. Remove the navigation title. Completion copy, the `.expired` reason label and the countdown context use the session or setting length. The start button text has no number.

- [ ] **Step 1: Update the UI tests to the new paths and add:**
  - `testTodaySummaryCountsOnlyCompletedSessions` (mode `expiring`: wait for `completion`, dismiss, `todaySummary` contains "1회").
  - `testLengthSettingAppliesToNextSession` (open `settingsButton`, pick 45, `countdown` reads "남은 시간 45분 0초").
  - `testCompletionCopyUsesSessionLength` (`expiring --length 40`; the `completion` label contains "40분").
  - Tests that read history (`중도 종료` row) open `todaySummary` first.
- [ ] **Step 2: Run** `-only-testing:FocusUITests`. Expected: the new and moved tests fail.
- [ ] **Step 3: Implement the views.**
- [ ] **Step 4: Run the full iOS scheme, then the unsigned device Release build. Expected: both pass, 0 warnings.**
- [ ] **Step 5: Commit** `feat(focus): open on a full-screen timer with settings and today's history`.

### Task 7: Documentation

**Files:**

- Modify: `AGENTS.md`, `README.md` (fixture modes `onboarding` and `--length`), `docs/implementation-ledger.md`, `docs/specs/2026-10-26-focus-study-design.md` (add a dated reconciliation section, do not rewrite the original lines)

- [ ] **Step 1: Update `AGENTS.md`** so that it no longer says "fixed 25-minute focus sessions". It must say that the length is a 25-50 minute setting, and link the M1 spec.
- [ ] **Step 2: Add the reconciliation section** to the 2026-10-26 spec. It names the M1 spec and the merged code as the authority for session length and launch flow.
- [ ] **Step 3: Add the README fixture modes and a ledger entry** (what M1 changed, what stays unverified on a device).
- [ ] **Step 4: Run** `trunk check` on the changed files and the internal-link check. Expected: no issues.
- [ ] **Step 5: Commit** `docs: record M1 launch flow and focus length`.
