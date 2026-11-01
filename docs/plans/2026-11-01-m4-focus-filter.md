# M4 Focus Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a person turn on one iOS Focus that has the FocusStudy Focus filter with its session option on, so that iOS filters notifications by the Focus's own settings and a normal focus session starts without opening the app; turning that Focus off ends the session that it started, and the settings sheet explains the setup.

**Architecture:** `Shared/` gets `SessionOrigin`, the optional `ControlSession.origin`, the envelope marker `ControlEnvelope.filterActivation`, and three lock sections on `SessionControl`: `startFromFocusFilter`, `endFromFocusFilter` and `clearFilterActivation(matching:now:)`. `App/` gets the `SetFocusFilterIntent` type (the only file that imports `AppIntents`), a `FocusFilterHandler` that runs the history import, the lock sections with a bounded lock-timeout retry, the stored last refusal and the foreground refresh, one runtime per process, the activation check on launch and foreground, and a guide screen in the settings sheet. `Integration/`, `Monitor/` and `Report/` do not change. The new DEBUG diagnostics are in `App/Debug/` only.

**Tech Stack:** Swift 5 mode, SwiftUI, Observation, SwiftData, AppIntents, FamilyControls, DeviceActivity, ManagedSettings, XCTest (unit and UI tests), XcodeGen.

**Spec:** [`docs/specs/2026-11-01-m4-focus-filter-design.md`](../specs/2026-11-01-m4-focus-filter-design.md)

**Start condition:** The operator approves the spec. Create the implementation worktree from the updated `main`. If the SDK probe in Task 3 shows that the filter needs an entitlement, an `Info.plist` key or a permission, stop and raise it with the operator before Task 4 (spec [Permissions and entitlements](../specs/2026-11-01-m4-focus-filter-design.md#permissions-and-entitlements)).

## Global Constraints

- iOS 17 or later, iPhone only, portrait only.
- `ControlEnvelope.schemaVersion` stays `2`. `origin` and `filterActivation` are optional; a missing `origin` means `manual`.
- `Shared/` must not import Screen Time SDK modules or `AppIntents`. Only `App/FocusStudyFilter.swift` imports `AppIntents`.
- Every filter transition is one `withExclusiveAccess` section on the existing `control.lock`. No `await`, no SwiftData call and no UI wait inside the lock. The history import and the read of `current` run outside the lock.
- Every new lock section ends with the M3 everyday convergence, as every section does. Do not add a read-only exception.
- The filter never requests a permission and never reads `INFocusStatusCenter`. Do not add an entitlement, an `Info.plist` key or a product target.
- Do not declare `allowedExecutionTargets`, `IntentExecutionTargets` or `supportedModes` unless the Task 3 probe shows the need and the CI-pinned Xcode compiles it (spec decision 15).
- The end by Focus off uses `.earlyExit` after the M2 reconcile order. Do not add an `EndReason`.
- `project.yml` is the Xcode project source. Run `xcodegen generate` after each file is added.
- `Package.swift` excludes each `App/` file by name from `FocusHistory`: add every new `App/` file to that list.
- `project.yml` lists by name only the `App/` files that `FocusSDKTests` compiles. Add a new `App/` file there only when an SDK test needs it: `App/FocusFilterHandler.swift` and the runtime holder file (Task 4). Never add `App/FocusStudyFilter.swift` (the only `AppIntents` file, spec decision 15), a view file or a file under `App/Debug/`.
- `Integration/` compiles into the app, `FocusMonitor` and `FocusSDKTests`. Code that uses an app-only type (`FocusFilterHandler`, `FocusStudyFilter`) goes in `App/`, never in `Integration/`.
- All user-facing copy is Korean 해요체, written with the `user-facing-copy` skill, with labels of two or three words and the explanation in footers. Check the spec list of [forbidden promises](../specs/2026-11-01-m4-focus-filter-design.md#settings-guide-content).
- Keep every accessibility identifier that `UITests/FocusFlowTests.swift` uses (AGENTS.md). That file is the list. Read it before a UI change.
- The focus-start screen and onboarding do not change.
- Do not name other repositories in code comments, commits or documents.
- Simulator results do not prove real Screen Time or Focus behavior.

## Review Focus

1. A replayed on call in the same activation never starts a second session: after the session ended, after the history import removed it, and after a refusal. Test: Task 2 Step 1.
2. The Focus-off rule never ends a `manual` session: an off call ends one only through the M2 reconcile order, for the same reasons as any app reconcile. It ends a `focusFilter` session in every phase that is not `terminal`, also `waiting`, `onBreak` and `breakOver`. A session whose time is up ends with its timed reason, not `.earlyExit`. Test: Task 2 Step 1.
3. A `terminal` session that waits for the history import does not refuse the next activation: the handler imports it before the start section. Only a failed import refuses, with `history`. Test: Task 4 Step 1.
4. A refusal records nothing in history and sets the marker. A start failure after the save of `preparing` follows the M1 rollback and keeps the marker. Test: Task 2 Step 1.
5. A process exit or a thrown error at each step of the start and end sections. After the next section, the state must match the spec table [Gaps between steps](../specs/2026-11-01-m4-focus-filter-design.md#gaps-between-steps). Test: Task 2 Step 1.
6. The activation check clears the marker only when the stored marker is still the one it read, and never starts or ends a session. Test: Task 2 Step 1 and Task 4 Step 1.
7. Both new fields survive every transition of every process, also Monitor callbacks, the M3 everyday save and `acknowledgeTerminal`. An M3 envelope loads with every session `manual` and no marker. Test: Task 1 Step 1 and Task 2 Step 1.
8. The filter type compiles with the Xcode that CI pins, and the built app contains the App Intents metadata. Test: Task 3 Step 1.
9. A lock timeout in a filter call is retried up to 4 times with a fresh time, and the pause is outside the lock. Test: Task 4 Step 1.
10. The handler and the app's screens share one engine, one selection repository and one `ModelContainer` in a process. Test: Task 4 Step 1.
11. A filter-started session never sits under a completion card that is still shown, and the card of an `.expired` session that the filter path imports is not lost (spec [Foreground refresh](../specs/2026-11-01-m4-focus-filter-design.md#foreground-refresh)). Test: Task 4 Step 1.

---

### Task 1: Stored fields in `Shared/`

**Files:**

- Modify: `Shared/ControlTypes.swift`
- Test: `CoreTests/SharedControlStoreTests.swift`, `CoreTests/SessionControlTests.swift`

**Interfaces:**

- Produces:
  - `public enum SessionOrigin: String, Codable { case manual, focusFilter }`.
  - `ControlSession.origin: SessionOrigin?` (missing = `manual`), and `public var isFilterStarted: Bool { origin == .focusFilter }`. The public initializer keeps its signature and leaves `origin` unset; the engine sets it before the save of `preparing`.
  - `ControlEnvelope.filterActivation: UUID?`.
  - `enum FocusFilterRefusal: String, Codable { case access, selection, busy, history, error }`.
  - `enum FocusFilterStart: Equatable { case started(ControlSession), repeated, refused(FocusFilterRefusal) }`.

- [ ] **Step 1: Write the failing tests:**
  - `testM3EnvelopeLoadsAsManualWithoutMarker` (write the JSON literal of an M3 version 2 envelope with an `active` session: it loads, `origin` is `nil`, `isFilterStarted` is `false`, and `filterActivation` is `nil`.)
  - `testOriginAndMarkerRoundTripThroughTheStore` (save and load an envelope with `origin = .focusFilter` and a marker.)
  - `testStorageChecksAcceptEitherOriginInEveryPhase` (every phase shape that the M2 checks accept, with each origin and with and without a marker.)
- [ ] **Step 2: Run `swift test --filter SharedControlStoreTests`. Expected: FAIL (members missing).**
- [ ] **Step 3: Implement the interfaces above.** Do not change `FileControl.load` checks.
- [ ] **Step 4: Run `swift test`. Expected: PASS.**
- [ ] **Step 5: Commit** `feat(core): store the session origin and the Focus activation marker`.

### Task 2: Filter transitions in `SessionControl`

**Files:**

- Modify: `Shared/SessionControl.swift`, `Tests/Fixtures/ControlRaceHelper.swift`
- Modify: `README.md`: add the line `PASS: focus off cannot end a manual session` to the 경합 helper row of the 검증 table, in Korean as the row is now. If a new `Shared/` file is added, also add it to the race-check `xcrun swiftc` command in `README.md` and `.github/workflows/verify.yml`. The workflow checks only the exit code, so it needs no PASS change.
- Test: `CoreTests/FocusFilterControlTests.swift` (new)

**Interfaces:**

- Consumes: Task 1.
- Produces:
  - `func startFromFocusFilter(now: Date, length: TimeInterval, authorized: () -> Bool, selectionReady: Bool, apply: () -> Void, matches: () -> Bool) throws -> FocusFilterStart` (the spec section [Filter start](../specs/2026-11-01-m4-focus-filter-design.md#filter-start-focus-on), step 3). It calls `authorized()` inside the lock, as `start` does, and sets `locked.access`, so the end-of-section convergence gets the access value.
  - The M1 start steps move into one private function that both `start` and `startFromFocusFilter` call, with the origin as a parameter. `start` stores `.manual`. The behavior of `start` does not change.
  - `func endFromFocusFilter(now: Date, authorized: Bool) throws` (the spec section [Filter end](../specs/2026-11-01-m4-focus-filter-design.md#filter-end-focus-off)). It runs the private M2 reconcile order with `authorized`, then transition 6 with `.earlyExit` for a `focusFilter` session that is not `terminal`, then a marker-only save if the stored envelope still has a marker.
  - `func clearFilterActivation(matching id: UUID, now: Date) throws` (the spec section [Activation check](../specs/2026-11-01-m4-focus-filter-design.md#activation-check-app-launch-and-foreground), step 3).

- [ ] **Step 1: Write the failing tests** with the shared fakes in `CoreTests/SessionControlTests.swift` (`MemoryControlStore`, `FakeMonitoring`, `FakeShield`, `FakeBreakSelection` and `FakeEverydayStore`). The interruption test needs a fake world that records a snapshot after each effect; `EverydayWorld` in `CoreTests/EverydayControlTests.swift` has that shape but is `private`, so copy its pattern rather than widen its access. Add a record of each save to the fake store where a test checks the save order. The tests:
  - `testOnCallStartsAFilterSessionAndWritesTheMarkerWithPreparing` (the first save is `preparing` with `origin == .focusFilter` and the marker; then `active`.)
  - `testRepeatedOnCallChangesNothing` (a stored marker with no session and with a session in each phase that the M2 cleanup leaves unchanged: `.repeated`, no save, and no `register`, `stop` or `apply` of a focus or break artifact. The everyday convergence runs as in every section, so the test does not assert on everyday activities or the everyday store. A stored marker with a stale `waiting` session that has a break copy: `.repeated`, and the saves and registrations are exactly those that `reconcile` makes for the same state, with the marker and the origin kept.)
  - `testRefusalsSetTheMarkerAndStartNothing` (access not approved: `access`; `selectionReady == false`: `selection`; each phase other than `terminal`: `busy`; `terminal`: `history`. Each saves the envelope with the marker and records no `register` or `apply` of a focus or break artifact; the everyday convergence runs as in every section.)
  - `testStartFailureRollsBackAndKeepsTheMarker` (registration throws, verification fails, `matches` fails: the stored session is `terminal` `.startFailed` with `origin == .focusFilter`, and the marker stays.)
  - `testManualStartStoresManualAndKeepsItsBehavior` (`start` stores `.manual`; every existing `SessionControlTests` case still passes.)
  - `testOffCallEndsOnlyAFilterSession` (access approved, the focus activity registered and no timed end due; parameterized over the phases `active`, `waiting`, `onBreak` and `breakOver`, each origin, and with and without a marker: a `focusFilter` session ends as `.earlyExit`; a `manual` session does not change.)
  - `testOffCallLetsTheTimedEndWin` (a `focusFilter` session past its focus end: `.expired`; past its deadline: `.deadlineMissed`; access not approved: `.authorizationRevoked`. A `manual` session in the same states ends with the same reasons, as an app reconcile ends it.)
  - `testOffCallClearsTheMarkerInTheSaveOfEnding` (the save of `ending` has no marker.)
  - `testOffCallWithoutAFilterSessionSavesOnlyAStoredMarker` (no session and a marker: one save without the marker; no session and no marker: no save.)
  - `testOffCallDuringABreakRemovesBreakArtifactsAndBlocksTheEverydayLayer` (an `onBreak` session inside an everyday range: the break copy and the break activity are removed, `focusSession` is cleared, and the everyday store is applied before the save of `terminal`.)
  - `testClearFilterActivationComparesTheStoredMarker` (the same marker: cleared and saved; a different marker or none: no save; never a session change.)
  - `testOneSessionPerActivationAcrossSequences` and `testFocusOffNeverEndsAManualSessionAcrossSequences` (each row of the spec table [Guards across sequences of calls](../specs/2026-11-01-m4-focus-filter-design.md#guards-across-sequences-of-calls) that the engine can run without the system: the sequence of on, off, check, `start`, `finish`, `acknowledgeTerminal` and time changes, then the stated result.)
  - `testFilterFieldsSurviveEveryTransition` (with a marker and a `focusFilter` session: `requestBreak`, `cancelWait`, `startBreak`, the re-block through `reconcile`, `resume`, `handleCallback` for each callback kind, `saveEveryday` with no session, and `acknowledgeTerminal`. The marker stays after each, and `origin` stays while the session exists.)
  - `testControlReadFailureInAFilterSectionThrows` (a corrupt `control.json`: each of the three sections throws, and the M2 read failure path runs.)
  - `testInterruptionAtEveryStepKeepsTheGapTable` (parameterized, as `testInterruptionAtEveryStepKeepsTheEverydayTable` in M3. The fakes record a snapshot of the fake world after each effect of the start and end sections. Exit pass: for each snapshot, a new `SessionControl` over a copy of it runs `reconcile`, then a repeated on call. Throw pass: each effect that can throw throws once, then `reconcile` runs. After that: the stored phase, the marker and the focus artifacts match the spec table [Gaps between steps](../specs/2026-11-01-m4-focus-filter-design.md#gaps-between-steps).)
- [ ] **Step 2: Run `swift test --filter FocusCoreTests`. Expected: FAIL (members missing).**
- [ ] **Step 3: Implement the interfaces above.** Extend the race helper with a `filter-end` mode: process A calls `endFromFocusFilter` while process B holds the lock and starts a manual session. After both, B's session is `active` and `manual`.
- [ ] **Step 4: Run `swift test`, then `xcodebuild build -project FocusStudy.xcodeproj -scheme FocusStudy -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`. Expected: PASS, and every target compiles.**
- [ ] **Step 5: Run `xcrun swiftc Shared/ControlTypes.swift Shared/SharedControlStore.swift Shared/SessionControl.swift Shared/FocusLength.swift Shared/BreakTiming.swift Shared/EverydaySchedule.swift Tests/Fixtures/ControlRaceHelper.swift -o /tmp/focus-control-race`, then `/tmp/focus-control-race --verify`.** Add any new `Shared/` file before `Tests/Fixtures/ControlRaceHelper.swift`, as in the README and workflow change above. Expected: the three existing PASS lines and `PASS: focus off cannot end a manual session`.
- [ ] **Step 6: Commit** `feat(core): start and end a focus session from the Focus filter`.

### Task 3: The Focus filter type and the SDK probe

**Files:**

- Create: `App/FocusStudyFilter.swift`
- Modify: `Package.swift` (exclude the new `App/` file from `FocusHistory`)
- Test: none. The type compiles into the app target only (spec decision 15), so it is not added to the `FocusSDKTests` sources. Its checks are the probe builds below and device step 1; Task 4 tests the handler contract that `perform()` calls.

**Interfaces:**

- Consumes: nothing from Task 2 yet.
- Produces:
  - `struct FocusStudyFilter: SetFocusFilterIntent` with `@Parameter(title: ..., default: false) var startsSession: Bool`, a title, a description and a display representation.
  - `perform()` passes `startsSession` to the handler (Task 4; until then a no-op closure) and returns `.result()`. It has no other logic.
  - `static func reading() async -> FocusFilterReading` maps `current` for the activation check: `startsSession == true` → `.on`, `false` → `.off`, `SetFocusFilterIntentError.notFound` → `.off`, any other error → `.unknown`. `enum FocusFilterReading { case on, off, unknown }` is declared in `App/FocusFilterHandler.swift` (Task 4; until then in this file), so the handler and its tests do not import `AppIntents`.

- [ ] **Step 1: SDK probe.** Before the final syntax:
  - Write the minimal type: one `Bool` parameter with `default: false`, an empty `perform()`, no `allowedExecutionTargets`, no `supportedModes` and no `openAppWhenRun`.
  - Run `xcodegen generate`, then the simulator build `xcodebuild build -project FocusStudy.xcodeproj -scheme FocusStudy -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO` and the unsigned device Release build `xcodebuild build -project FocusStudy.xcodeproj -scheme FocusStudy -configuration Release -destination 'generic/platform=iOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`. Expected: `BUILD SUCCEEDED`, 0 warnings.
  - Check that the built app has the App Intents metadata: `ls -d DerivedData/Build/Products/Release-iphoneos/FocusStudy.app/Metadata.appintents`. Expected: the path exists. If it does not, find the build setting that XcodeGen must set, and record it in the ledger.
  - For every App Intents member that the type uses, read its `@available` attribute in the local SDK's `AppIntents.swiftinterface`. The local Xcode can be newer than the CI pin in `.github/workflows/verify.yml`, so a local build does not prove the CI build. If the pinned Xcode is installed, also build with `DEVELOPER_DIR` set to it. Otherwise the CI run of the implementation PR is the check, and no member newer than iOS 17 is used without an availability check.
  - Check that the build added no entitlement and no `Info.plist` key. If the filter needs one, stop (see the start condition).
- [ ] **Step 2: Implement the interfaces above.** Write the filter's title, description and parameter title with the `user-facing-copy` skill. Read the declaration again and check that the parameter default is `false` (spec decision 4).
- [ ] **Step 3: Run the two `xcodebuild build` commands and the `ls -d` metadata check of Step 1 again. Expected: `BUILD SUCCEEDED`, 0 warnings, and the metadata path exists.**
- [ ] **Step 4: Commit** `feat(app): declare the FocusStudy Focus filter`.

### Task 4: Filter handler, one runtime per process and foreground refresh

**Files:**

- Create: `App/FocusFilterHandler.swift`
- Modify: `App/FocusRuntime.swift` (the process-wide runtime), `App/FocusStudyApp.swift` (get the runtime from it; run the activation check on launch and on `didBecomeActive`), `App/FocusModel.swift` (refresh when the handler asks; the completion card rules), `App/FocusSettings.swift` (the last refusal, the pending card; in DEBUG the call log), `App/FocusStudyFilter.swift` (connect `perform()` to the handler), `App/Debug/UITestFixtures.swift` (fixture argument `--focus-filter-refusal <reason>`), `App/Debug/DeviceDiagnosticsSection.swift` (the DEBUG actions below), `Package.swift` (exclude the new `App/` files), `project.yml` (add `App/FocusFilterHandler.swift` and the runtime holder file to the `FocusSDKTests` sources)
- Do not modify: `Integration/DeviceDiagnostics.swift`. `Integration/` also compiles into `FocusMonitor` and `FocusSDKTests`, which do not compile `FocusStudyFilter`, so a call to the filter type there breaks those builds.
- Test: `SDKTests/FocusFilterHandlerTests.swift` (new), `SDKTests/FocusModelTests.swift`, `SDKTests/FocusSettingsTests.swift`

**Interfaces:**

- Consumes: Tasks 2 and 3.
- Produces:
  - `@MainActor final class FocusFilterHandler` with `init(services: FocusServices, history: any SessionHistoryProviding, refresh: @escaping () -> Void, now: @escaping () -> Date = Date.init, pause: @escaping (TimeInterval) async -> Void)`.
  - `func focusDidChange(startsSession: Bool) async`: for `true`, the spec steps 1 to 5 of [Filter start](../specs/2026-11-01-m4-focus-filter-design.md#filter-start-focus-on); for `false`, [Filter end](../specs/2026-11-01-m4-focus-filter-design.md#filter-end-focus-off) and the refresh. Each lock section and the history import retry `ControlIssue.lockTimeout` up to 4 times, 0.25 s apart, with a fresh `now()`, and `pause` runs between attempts outside the lock.
  - `func checkActivation(reading: () async -> FocusFilterReading) async`: the spec section [Activation check](../specs/2026-11-01-m4-focus-filter-design.md#activation-check-app-launch-and-foreground). It clears on `.off` only (`notFound` is `.off` after Task 3's mapping).
  - `FocusSettings.lastFilterRefusal: (reason: FocusFilterRefusal, at: Date)?`, with `recordFilterRefusal(_:at:)` and `clearFilterRefusal()`, in the app's `UserDefaults`.
  - `FocusSettings.pendingCompletion: (id: UUID, length: TimeInterval)?`, with `recordPendingCompletion(id:length:)` and `takePendingCompletion()`, in the app's `UserDefaults`. The handler records it after its import of an `.expired` session (spec [Filter start](../specs/2026-11-01-m4-focus-filter-design.md#filter-start-focus-on), step 2).
  - `FocusModel.refresh()`: before its own import, it takes the pending card and sets the card from it only when no session that is not `terminal` is stored. Its own import of an `.expired` session then sets the card as today, so the newer session wins. After its import, it clears `completedSessionID` and `completedLength` when a session is stored and its phase is not `terminal`; no stored session keeps the card (spec [Foreground refresh](../specs/2026-11-01-m4-focus-filter-design.md#foreground-refresh)). `start()` and `dismissCompletion()` do not change.
  - One runtime per process: `FocusBootstrap` and `FocusStudyFilter` get the same `FocusServices` and `ModelContainer`. With `--ui-testing`, that is the fixture runtime. The mechanism is the builder's choice (spec [Left to the builder](../specs/2026-11-01-m4-focus-filter-design.md#left-to-the-builder)).
  - DEBUG diagnostics (only with `--screen-time-diagnostics`), in `App/Debug/DeviceDiagnosticsSection.swift`, which only the app target compiles. The section gets the handler and the `FocusStudyFilter.reading()` closure from the app; `DeviceDiagnostics` does not change. "Focus 켜짐 전달" and "Focus 꺼짐 전달" call `focusDidChange` without a Focus, "current 읽기" shows the result of `FocusStudyFilter.reading()`, and the section shows the call log. In DEBUG builds the handler appends each call (time, value, result) to a short list in the app's `UserDefaults`, also in background launches, which have no launch arguments. It stores no tokens. None of this is in Release builds.
  - DEBUG fixture: `--focus-filter-refusal <reason>` stores that refusal at launch, for the UI test in Task 5. Fixture runtimes never touch real restrictions or a real Focus.

- [ ] **Step 1: Write the failing tests:**
  - `testOnCallImportsAPendingTerminalThenStarts` (a stored `terminal` session: the record is saved, the session is acknowledged, and the new session is `focusFilter`. For an `.expired` session, the pending card is that session's id and length; for any other reason, no pending card.)
  - `testFailedImportRefusesWithHistory` (the history save throws: the refusal is `history`, and no session starts.)
  - `testOnCallUsesTheFocusLengthAndTheFrozenSelection` (`FocusSettings.lengthMinutes == 40`: `expiresAt - startedAt == 2400`, and `apply` gets the stored selection.)
  - `testEmptyOrInvalidSelectionRefusesWithSelection`.
  - `testRefusalIsStoredAndAStartClearsIt`.
  - `testThrownErrorIsStoredAsError` (a `control.json` that cannot be read.)
  - `testLockTimeoutIsRetriedFourTimesWithAFreshTime` (an engine store that throws `lockTimeout` 4 times, then succeeds: the call succeeds and `pause` ran 4 times; 5 timeouts: the refusal is `error`.)
  - `testOffCallEndsTheFilterSessionAndRefreshes`.
  - `testActivationCheckClearsOnlyOnOff` (`.on` and `.unknown`: the marker stays; `.off`: cleared; a marker that changed during the reading: it stays.)
  - `testHandlerNeverRequestsAuthorization` (a fake `AuthorizationProviding` records no `requestIndividual()` call in any test of this file.)
  - `testHandlerAndScreensShareOneRuntime` (the runtime holder gives the same engine, selection repository and `ModelContainer` to both, and builds the runtime once. Put the holder in a file that `FocusSDKTests` compiles, with an injected factory, because `App/FocusRuntime.swift` is not in that target.)
  - In `FocusModelTests`: `testFilterChangeRefreshesTheModel` (the model still shows the completion card of an earlier `.expired` session, then a filter start: after the handler's refresh, `current` is the new session and `completedSessionID == nil`.)
  - In `FocusModelTests`: `testFilterImportOfAnExpiredSessionKeepsTheCard` (a `manual` session ended as `.expired`, then an on call that the handler imports it for and refuses with `selection`: after the next refresh, `completedSessionID` is that session's id and the pending card is cleared. The same with an on call that starts a session: `completedSessionID == nil`, and the pending card is cleared.)
  - In `FocusModelTests`: `testExpiredCardSurvivesRefreshesWithoutASession` (a `manual` session ends as `.expired`, then `refresh()` runs twice with no session stored: the card stays.)
  - In `FocusModelTests`: `testNewerExpiredSessionOverridesThePendingCard` (manual S1 ends as `.expired`; an on call imports S1, stores the pending card and starts S2; S2 ends as `.expired`; an off call; then `refresh()`: the card is S2 with S2's length, and the pending card is cleared.)
  - In `FocusSettingsTests`: `testLastFilterRefusalRoundTrips` and `testPendingCompletionIsTakenOnce`.
- [ ] **Step 2: Run** the iOS tests. Set `SIMULATOR_ID` to an available iPhone UUID from `xcrun simctl list devices available`, then run `xcodebuild test -project FocusStudy.xcodeproj -scheme FocusStudy -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:FocusSDKTests/FocusFilterHandlerTests -only-testing:FocusSDKTests/FocusModelTests -only-testing:FocusSDKTests/FocusSettingsTests`. Expected: FAIL.
- [ ] **Step 3: Implement the interfaces above.**
- [ ] **Step 4: Run the same command, then `swift test`. Expected: PASS.**
- [ ] **Step 5: Commit** `feat(app): run the Focus filter in the app process`.

### Task 5: Settings guide screen

**Files:**

- Create: `App/FocusGuideView.swift`
- Modify: `App/SettingsView.swift`, `UITests/FocusFlowTests.swift`, `Package.swift` (exclude the new `App/` file)
- Do not modify: `project.yml`. The app target compiles all of `App/`, and `FocusSDKTests` compiles no view file. Run `xcodegen generate` after the file is added.

**Interfaces:**

- Consumes: Task 4.
- Produces: identifiers `focusGuideRow` (the row in the settings sheet), `focusGuide` (the guide screen) and `focusFilterRefusal` (the stored refusal line).

Behavior: the settings sheet has a new section with `focusGuideRow` and a one-line footer. The row opens the guide with the content of the spec section [Settings guide content](../specs/2026-11-01-m4-focus-filter-design.md#settings-guide-content). The guide shows `focusFilterRefusal` only when a refusal is stored. The guide has no button that opens Settings. The focus-start screen does not change.

- [ ] **Step 1: Write the failing UI tests** (fixture mode `--selected`):
  - `testFocusGuideOpensFromSettings`: `settingsButton` → `focusGuideRow` → `focusGuide` exists, and `focusFilterRefusal` does not.
  - `testStoredRefusalShowsInTheGuide` (`--focus-filter-refusal busy`: `focusFilterRefusal` exists.)
  - `testTimerScreenIsUnchangedWithTheGuide` (the existing timer identifiers exist, and no guide identifier is on the timer screen.)
- [ ] **Step 2: Run** `xcodebuild test -project FocusStudy.xcodeproj -scheme FocusStudy -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:FocusUITests`, with `SIMULATOR_ID` set as in Task 4 Step 2. Expected: the new tests fail.
- [ ] **Step 3: Implement the screen.** Write the copy with the `user-facing-copy` skill. Check every sentence against the spec list of forbidden promises.
- [ ] **Step 4: Run `xcodebuild test -project FocusStudy.xcodeproj -scheme FocusStudy -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO`, then `xcodebuild build -project FocusStudy.xcodeproj -scheme FocusStudy -configuration Release -destination 'generic/platform=iOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`. Expected: both pass, 0 warnings.**
- [ ] **Step 5: Commit** `feat(settings): add the Focus setup guide`.

### Task 6: Documentation

**Files:**

- Modify: `AGENTS.md`, `README.md` (fixture argument `--focus-filter-refusal`), `docs/implementation-ledger.md`, `docs/specs/2026-10-26-focus-study-design.md`, `docs/specs/2026-11-01-m2-break-pass-design.md`, `docs/notes/screen-time-device-matrix.md`

This task has no code test. Its failing check is a search for the text that it adds.

- [ ] **Step 1: Run the failing check:** `grep -n 'FocusStudyFilter\|FocusFilterHandler\|FocusGuideView' AGENTS.md` and `grep -n -- '--focus-filter-refusal' README.md`. Expected now: both print nothing.
- [ ] **Step 2: Update `AGENTS.md`.** In the project scope, remove the words "designed for M4 and not built yet" from the Focus filter sentence. Update the ownership table with rows or entries for `App/FocusStudyFilter.swift`, `App/FocusFilterHandler.swift` and `App/FocusGuideView.swift`, and the `Shared/` row for the session origin and the activation marker.
- [ ] **Step 3: Add dated reconciliation sections** to the 2026-10-26 and M2 specs for each line in the M4 spec section [Superseded lines](../specs/2026-11-01-m4-focus-filter-design.md#superseded-lines). Do not rewrite the original lines.
- [ ] **Step 4: Add the device-matrix rows** for the M4 steps in the spec section [Physical-device verification](../specs/2026-11-01-m4-focus-filter-design.md#physical-device-verification), all marked unverified. Add the README fixture argument and a ledger entry (what M4 changed, the SDK probe result, and what stays unverified on a device).
- [ ] **Step 5: Run** the two searches from Step 1 again, then `trunk check --no-fix AGENTS.md README.md docs/implementation-ledger.md docs/specs/2026-10-26-focus-study-design.md docs/specs/2026-11-01-m2-break-pass-design.md docs/notes/screen-time-device-matrix.md`. Open each relative link and anchor that this task adds and check that its target exists; the repository has no link-check command. Expected: the first search prints the new ownership lines, the second prints the fixture argument, Trunk reports no issues, and every link resolves.
- [ ] **Step 6: Commit** `docs: record the M4 Focus filter`.
