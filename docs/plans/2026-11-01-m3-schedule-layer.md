# M3 Everyday Schedule Blocking Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a person turn on an everyday blocking layer with its own selection, one daily range and at most 3 unblocked windows, which runs every day without the app, blocks together with the focus layer, and is lifted by an M2 break.

**Architecture:** `Shared/` gets `EverydaySchedule` with its time rules and the blocking rule, and `SessionControl` gets the everyday convergence that runs at the end of every lock section, the `saveEveryday` transition and `everydayStatus(now:authorized:)`. `Integration/` gets `everyday-layer.json` in the App Group (schedule and tokens), the named store `everydayLayer`, and repeating DeviceActivity schedules named `everyday.<revision>.range` and `everyday.<revision>.window.<n>`. `Monitor/` passes every callback name to the engine. `App/` gets an everyday settings screen inside the settings sheet.

**Tech Stack:** Swift 5 mode, SwiftUI, Observation, SwiftData, FamilyControls, DeviceActivity, ManagedSettings, XCTest (unit and UI tests), XcodeGen.

**Spec:** [`docs/specs/2026-11-01-m3-schedule-layer-design.md`](../specs/2026-11-01-m3-schedule-layer-design.md)

**Start condition:** The operator approves the spec, including the [everyday selection in the App Group](../specs/2026-11-01-m3-schedule-layer-design.md#everyday-selection-in-the-app-group-privacy-boundary-change). Create the implementation worktree from the updated `main`. If the operator rejects the App Group file, stop and revise the spec before Task 3.

## Global Constraints

- iOS 17 or later, iPhone only, portrait only.
- Times are minutes after midnight on a 5-minute grid. Range: start before end, at least 60 minutes, end at 23:55 or earlier. Windows: at most 3, each 15 to 120 minutes, inside the range, not overlapping, not covering the whole range. Intervals are half-open (`[start, end)`).
- Both selections together: at most 50 distinct apps and 50 distinct websites.
- `ControlEnvelope.schemaVersion` stays `2`. Do not add everyday fields to `control.json`.
- `Shared/` must not import Screen Time SDK modules. The tokens are encoded and decoded in `Integration/`.
- Every transition is one `withExclusiveAccess` section on the existing `control.lock`. No `await` and no UI wait inside the lock.
- The focus layer never writes `everydayLayer`, and the everyday layer never writes `focusSession`. `ShieldClient.clear()` keeps clearing `focusSession` only.
- An everyday failure in the convergence (unreadable file, registration error, store mismatch) never throws out of a lock section and never stops a focus step. Only `saveEveryday` throws for an everyday failure: for a refusal, a registration failure or a write failure. `everydayStatus(now:authorized:)` reports the everyday failures as `issue` and throws only the errors of its lock section (`lockTimeout`, a failed read of `control.json`), which Task 5 catches on their own.
- Never call `stopMonitoring` with an empty array. It stops every activity, also the focus and break activities. Every everyday stop names its activities.
- A Monitor section that `intervalDidStart(for:)` started never registers an activity (spec [Everyday convergence](../specs/2026-11-01-m3-schedule-layer-design.md#everyday-convergence)).
- `project.yml` is the Xcode project source. Run `xcodegen generate` after each file is added. Keep `Package.swift` exclusions aligned for new files under `App/`.
- All user-facing copy is Korean 해요체, written with the `user-facing-copy` skill.
- Keep every accessibility identifier that `UITests/FocusFlowTests.swift` uses (AGENTS.md). That file is the list. Read it before a UI change.
- The timer screen does not change. Do not add a notification, a custom shield, or a shield action.
- Simulator results do not prove real Screen Time behavior.

## Review Focus

1. A late callback of an earlier revision arrives after a save. It must not register, stop or apply anything that the new file does not allow. Test: Task 2 Step 1 and the race check in Task 2 Step 5.
2. An `onBreak` session is past `breakEndsAt`, and an everyday callback arrives before the focus re-block. The everyday layer must block again, and the M2 reconcile order must re-block the focus layer. This is the only case in which an everyday callback reaches the M2 reconcile. Test: Task 2 Step 1.
3. The person edits the layer inside today's range. Every edit that loosens the layer for the rest of today must be refused, also during a window. Test: Task 1 Step 1 and Task 2 Step 1.
4. A session ends during a break, inside the range. The everyday layer must block again right after the save of `ending`. Test: Task 2 Step 1.
5. The everyday file is unreadable, a registration throws, or the store does not match. The focus part of the same section must run unchanged, and a focus end must still clear `focusSession`. Test: Task 2 Step 1.
6. A process exit or a thrown error at each step of the save and of the changed M2 transitions. After the next section, the artifacts must match the spec table [Stored states and side artifacts](../specs/2026-11-01-m3-schedule-layer-design.md#stored-states-and-side-artifacts), and blocking must never be looser than the earlier settings. Test: Task 2 Step 1.
7. A registration of an activity with an ongoing interval sends `intervalDidStart(for:)` at once. That section must register nothing, also when the fake center does not list the new activity, so the convergence cannot loop. A stop of an ongoing activity sends `intervalDidEnd(for:)`, which may register only missing activities of the stored revision. Test: Task 2 Step 1.
8. A version 2 `control.json` from the M2 build, and no everyday file. The M3 build must load it unchanged, with the layer off. Test: Task 2 Step 1.
9. The union of both selections is over 50 apps or 50 websites. Each save must refuse it. Test: Task 4 Step 1.
10. An everyday callback, of the stored or an earlier revision, arrives in any focus phase other than `onBreak` at or after `breakEndsAt`. It must not reach the M2 reconcile, so it cannot end the session on the access value or on `DeviceActivityCenter` state (spec [Callback routing in `handleCallback`](../specs/2026-11-01-m3-schedule-layer-design.md#callback-routing-in-handlecallback)). Test: Task 2 Step 1.
11. An everyday status failure in `FocusModel.refresh()` must not clear `current` or set `errorMessage`. Test: Task 5 Step 1.

---

### Task 1: `EverydaySchedule` and its rules in `Shared/`

**Files:**

- Create: `Shared/EverydaySchedule.swift`
- Test: `CoreTests/EverydayScheduleTests.swift` (new)

**Interfaces:**

- Produces:
  - `public enum EverydayWindowKind: String, Codable { case lunch, toSchool, fromSchool, custom }`.
  - `public struct EverydayWindow: Codable, Equatable { public var kind: EverydayWindowKind; public var start: Int; public var end: Int; public init(kind: EverydayWindowKind, start: Int, end: Int) }`.
  - `public struct EverydaySchedule: Codable, Equatable { public var revision: UUID; public var enabled: Bool; public var rangeStart: Int; public var rangeEnd: Int; public var windows: [EverydayWindow]; public init(revision: UUID, enabled: Bool, rangeStart: Int, rangeEnd: Int, windows: [EverydayWindow]) }`. The explicit public initializers follow the other public structs in `Shared/`, because the initializer that the compiler generates for a struct is internal to `FocusCore`.
  - `public static let standard: EverydaySchedule` (off, 08:00-18:00, no windows) and `public static func template(_ kind: EverydayWindowKind) -> EverydayWindow?` (lunch 12:00-13:00, going to school 08:00-08:30, leaving school 16:00-16:30, `nil` for `custom`).
  - `public var isValid: Bool` (every rule in the spec section [Times](../specs/2026-11-01-m3-schedule-layer-design.md#times)).
  - `public func blocks(at now: Date, calendar: Calendar) -> Bool` (schedule part of the spec [blocking rule](../specs/2026-11-01-m3-schedule-layer-design.md#the-blocking-rule): enabled, inside the range, outside every window).
  - `public func isInsideRange(at now: Date, calendar: Calendar) -> Bool`.
  - `public func nextChange(after now: Date, calendar: Calendar) -> Date?` (the next time that `blocks` changes, for the settings row).
  - `public func isAtLeastAsStrict(as stored: EverydaySchedule, from now: Date, calendar: Calendar) -> Bool` (the schedule conditions of the spec [Editing rules](../specs/2026-11-01-m3-schedule-layer-design.md#editing-rules): still enabled, and blocks at every time from `now` to the stored range end where `stored` blocks).
  - `public enum EverydayRules { public static func blocks(schedule: EverydaySchedule?, session: ControlSession?, authorized: Bool?, now: Date, calendar: Calendar) -> Bool }` (the whole blocking rule, `authorized: nil` when the section does not know it).

- [ ] **Step 1: Write the failing tests** with a fixed `Calendar` in `Asia/Seoul`:
  - `testValidationAcceptsTheSpecLimitsAndRejectsEachBreach` (range 59 minutes, range end 23:56, start after end, 4 windows, a 10-minute and a 125-minute window, a window outside the range, two overlapping windows, windows that cover the range, a time off the 5-minute grid. Two touching windows are valid.)
  - `testBlocksUsesHalfOpenIntervals` (range 08:00-18:00, lunch 12:00-13:00: 07:59:59 no, 08:00:00 yes, 11:59:59 yes, 12:00:00 no, 12:59:59 no, 13:00:00 yes, 17:59:59 yes, 18:00:00 no. A layer that is off: no at every time.)
  - `testWindowThatStartsAtRangeStartAndWindowThatEndsAtRangeEnd`.
  - `testNextChangeGivesTheNextEdgeAndTheNextDayAfterTheRange`.
  - `testBreakLiftsTheLayerOnlyBeforeBreakEndsAt` (`EverydayRules.blocks` with an `onBreak` session: no at `breakEndsAt - 1`, yes at `breakEndsAt`. Every other phase: as the schedule.)
  - `testUnauthorizedNeverBlocksAndUnknownAccessFollowsTheSchedule`.
  - `testStricterEditsAreAcceptedInsideTheRange` (at 10:00: remove the lunch window, shorten it, move the range end later, move the range start earlier, add a window that ends before 10:00.)
  - `testLooserEditsAreRejectedInsideTheRange` (at 10:00: turn off, lengthen lunch, add a window at 15:00, move the range end earlier. At 12:30, inside lunch: lengthen lunch to 13:30.)
  - `testEveryEditIsAcceptedOutsideTheRangeOrWhenNothingIsOn` (at 07:00 and at 18:00: turn off and add a window. A stored layer that is off: every valid edit.)
  - `testDecodingTheStoredShapeRoundTrips`.
- [ ] **Step 2: Run `swift test --filter EverydayScheduleTests`. Expected: FAIL (types missing).**
- [ ] **Step 3: Implement the interfaces above.** Use `calendar.dateComponents([.hour, .minute, .second], from: now)` for the wall-clock time. Compare in seconds after midnight, so that 11:59:59 is not 12:00.
- [ ] **Step 4: Run `swift test`. Expected: PASS.**
- [ ] **Step 5: Commit** `feat(core): add the everyday schedule and its time rules`.

### Task 2: Everyday convergence and save in `SessionControl`

**Files:**

- Modify: `Shared/ControlTypes.swift` (protocols), `Shared/SessionControl.swift`, `Tests/Fixtures/ControlRaceHelper.swift`
- Modify: `README.md` and `.github/workflows/verify.yml` (add `Shared/EverydaySchedule.swift` to the race-check `xcrun swiftc` command, because `SessionControl` now uses it). In `README.md`, also add the new line `PASS: stale everyday revision cannot undo a newer save` to the 경합 helper row of the 검증 table, in Korean as the row is now. The workflow checks only the exit code, so it needs no PASS change.
- Modify so that every target still compiles (each conformer and call site of the changed protocol and initializer):
  - `Integration/ScreenTimeAdapters.swift`: `registerEveryday` throws `ControlIssue.io` until Task 3, `registeredEveryday` returns `[]`, and `stopEveryday` calls `stopMonitoring` for the name.
  - `Integration/DeviceDiagnostics.swift`: the wrapper forwards the new members to its base.
  - `App/Debug/UITestFixtures.swift`: fixture monitoring records everyday registrations in memory, and a fixture `EverydayLayerStore` holds a schedule and a synthetic shield flag in memory.
  - `App/FocusRuntime.swift` and `Monitor/FocusMonitor.swift`: pass an `EverydayLayerStore` whose `load()` returns `nil` until Task 3 (Monitor) and Task 5 (app).
  - `SDKTests/DeviceDiagnosticsTests.swift` and `SDKTests/FocusModelTests.swift`: fakes get the new members.
  - Do not add protocol-extension defaults. They would hide a missing implementation.
- Test: `CoreTests/EverydayControlTests.swift` (new), `CoreTests/SessionControlTests.swift`, `CoreTests/BreakControlTests.swift` and `CoreTests/StartupRecoveryTests.swift` (fakes get the new protocol members)

**Interfaces:**

- Consumes: Task 1.
- Produces:
  - `enum EverydayPart: Hashable { case range, window(Int) }`.
  - `MonitoringClient` adds `registerEveryday(revision: UUID, part: EverydayPart, start: Int, end: Int) throws`, `var registeredEveryday: [(revision: UUID, part: EverydayPart)] { get }` and `stopEveryday(revision: UUID, part: EverydayPart)`.
  - `protocol EverydayLayerStore { func load() throws -> EverydaySchedule?; func storeMatches() -> Bool; func applyStored() -> Bool; var hasShield: Bool { get }; func clearShield() }`. `applyStored` applies the stored selection to `everydayLayer` and returns `true` only when the store matches it.
  - `SessionControl.init(store:monitoring:shield:breakSelection:everyday:timing:calendar:)`, with `calendar` defaulting to `.current`.
  - `func saveEveryday(_ schedule: EverydaySchedule, now: Date, authorized: () -> Bool, containsStoredSelection: () throws -> Bool, write: () throws -> Void) throws` (the five steps of the spec section [Save](../specs/2026-11-01-m3-schedule-layer-design.md#save-turn-on-edit-turn-off)). It calls `authorized()` inside the lock, as `start` does, and throws `ControlIssue.unauthorized` before any registration, write or store change when it returns `false`.
  - `func everydayStatus(now: Date, authorized: Bool) throws -> EverydayStatus` (`authorized` as in `reconcile`; `blocksNow` uses it in the blocking rule), with `struct EverydayStatus: Equatable { var schedule: EverydaySchedule?; var blocksNow: Bool; var nextChange: Date?; var issue: EverydayIssue? }` and `enum EverydayIssue { case unreadable, registrationFailed, notApplied }`.
  - `ControlIssue` adds `everydayLocked` (an edit that loosens the layer inside today's range).
  - The convergence of the spec section [Everyday convergence](../specs/2026-11-01-m3-schedule-layer-design.md#everyday-convergence) runs at the end of every lock section except `snapshot()` and `everydayStatus(now:authorized:)`, also when the focus part threw, but not when the read of `control.json` threw. It evaluates the envelope that the section stored last, not an envelope whose save failed.
  - `handleCallback` follows the spec section [Callback routing in `handleCallback`](../specs/2026-11-01-m3-schedule-layer-design.md#callback-routing-in-handlecallback): an `everyday.` name reaches the M2 reconcile only when the stored session is `onBreak` and `now >= breakEndsAt`.
  - `reBlock` and `end` get the steps of the spec section [Changes to M2 transitions](../specs/2026-11-01-m3-schedule-layer-design.md#changes-to-m2-transitions). In `end`, the everyday step (convergence steps 1 and 3 only) runs after the deletion of the break copy and before the save of `terminal`. A `read` failure also calls `everyday.clearShield()`, and runs no convergence step: no everyday file read, no registration, no stop and no apply.

- [ ] **Step 1: Write the failing tests** with a fake monitor that records every everyday registration and stop, a fake focus shield, a fake break selection store, and a fake `EverydayLayerStore` that records `applyStored` and `clearShield`:
  - `testConvergenceAppliesInsideTheRangeAndClearsInAWindowAndAfterTheRange`.
  - `testConvergenceRegistersTheStoredRevisionAndThenStopsOthers`.
  - `testEarlierRevisionStaysWhileTheStoredRevisionIsIncomplete` (the registration of `window.1` throws: the earlier revision's activities are not stopped, and the status issue is `registrationFailed`.)
  - `testDidStartSectionNeverRegisters` (the fake center does not list the stored revision. `intervalDidStart` of an everyday activity: no registration is recorded. `intervalDidEnd` of the same activity, and an app `reconcile`: the missing activities are registered.)
  - `testStopsAlwaysNameTheirActivities` (no `stopEveryday` call and no `stop` call gets an empty name list, in every test of this file. The fake monitor fails the test on an empty list.)
  - `testLateCallbackOfEarlierRevisionFollowsTheNewFile`.
  - `testUnreadableFileClearsTheStoreAndKeepsActivities`.
  - `testUnauthorizedSectionStopsEveryEverydayActivityAndClearsTheStore`, and `testAccessBackRegistersAndApplies`.
  - `testSaveRefusedDuringASessionWithBusy` (each phase except `terminal`.)
  - `testSaveRefusedWithoutAccessRegistersAndWritesNothing` (no session, a stored layer that blocks now, and `authorized` returning `false`, for a turn-on, an edit and a turn-off: `unauthorized`, no `registerEveryday` and no `write` is recorded, and the stored file does not change. The end-of-section convergence then stops every everyday activity and clears the store, as the spec table [Stored states and side artifacts](../specs/2026-11-01-m3-schedule-layer-design.md#stored-states-and-side-artifacts) gives for access not approved.)
  - `testStatusWithoutAccessDoesNotBlock` (a stored layer that blocks now: `everydayStatus(now:authorized:)` with `authorized: false` gives `blocksNow == false` and `nextChange == nil`.)
  - `testSaveInsideTheRangeRefusesLooserEdits` (the schedule cases of Task 1, plus `containsStoredSelection` returning `false`: `everydayLocked`, and nothing is registered or written.)
  - `testSaveOrderRegistersBeforeWriteAndStopsAfter`.
  - `testSaveRegistrationOrWriteFailureStopsNewActivitiesAndKeepsTheFile`.
  - `testSaveTreatsAnUnreadableStoredFileAsNoLayer`.
  - `testBreakStartLiftsTheEverydayLayerAndRollbackKeepsIt`.
  - `testReBlockAppliesBothLayersBeforeTheSaveOfBreakOver`.
  - `testEverydayCallbackAfterBreakEndsAtBlocksAndReBlocksTheFocusLayer` (an `onBreak` session 10 s after `breakEndsAt`, and a window-end callback: the everyday store is applied, and the session is `breakOver`.)
  - `testEverydayCallbackNeverChangesTheFocusPhaseOutsideALateBreak` (parameterized over a callback of the stored revision and of an earlier revision, each callback kind, and the phases `active`, `waiting`, `breakOver` and `onBreak` before `breakEndsAt`. Case 1: the focus activity is registered and access is approved. Case 2: access is not approved and the fake center does not list the focus activity. In both cases the stored phase does not change, and no focus `register`, `stop` or `clear` is recorded.)
  - `testEndDuringBreakAppliesTheEverydayLayerAfterTheFocusRelease` (the fakes record the order: the save of `ending`, the focus `clear`, the focus `stop`, the deletion of the break copy, then `applyStored`, then the save of `terminal`. No everyday registration is recorded before the save of `terminal`.)
  - `testEverydayFailureNeverStopsAFocusEnd` (unreadable file, throwing registration, and a store that does not match: each `finish` still clears `focusSession` and saves `terminal`.)
  - `testControlReadFailureClearsBothStoresAndKeepsEverydayActivities` (with a stored layer that blocks now and a missing activity of the stored revision: after the failed read, no everyday file read, no `registerEveryday`, no `stopEveryday` and no `applyStored` is recorded. The same holds for `snapshot()` and `everydayStatus(now:authorized:)`.)
  - `testStartAndStartRollbackNeverWriteTheEverydayStore`.
  - `testM2EnvelopeWithoutEverydayFileLoadsWithTheLayerOff` (write the JSON literal of an M2 version 2 envelope in `active`: the session counts down as in M2, `everydayStatus` has no schedule, and no everyday registration is recorded.)
  - `testInterruptionAtEveryStepKeepsTheEverydayTable` (parameterized, as `testInterruptionAtEveryStepOfBreakAndEndTransitionsKeepsTheArtifactTable` in M2. The fakes record a snapshot of the whole fake world after each effect of the save, of the convergence, of the M1 start and its rollback, and of the M2 transitions 3, 4 and 6 with the layer blocking. Exit pass: for each snapshot, a new `SessionControl` over a copy of it runs `reconcile`. Throw pass: each effect that can throw throws once, then `reconcile` runs. After that reconcile: the everyday artifacts match the spec table [Stored states and side artifacts](../specs/2026-11-01-m3-schedule-layer-design.md#stored-states-and-side-artifacts). For the save snapshots before the write, the store is never looser than the earlier file allows.)
- [ ] **Step 2: Run `swift test --filter FocusCoreTests`. Expected: FAIL (members missing).**
- [ ] **Step 3: Implement the interfaces above.** Extend the race helper with a `stale-everyday` mode: process A delivers a callback of an earlier revision while process B holds the lock and saves a new revision. After both, only the new revision's activities are registered, and the synthetic everyday shield matches the new file.
- [ ] **Step 4: Run `swift test`, then the simulator build from README. Expected: PASS, and every target compiles.**
- [ ] **Step 5: Run the race check. Expected: `PASS: stale A cannot clear B`, `PASS: stale break 1 cannot touch break 2` and `PASS: stale everyday revision cannot undo a newer save`.**
- [ ] **Step 6: Commit** `feat(core): converge the everyday layer in every lock section`.

### Task 3: Everyday file, named store, repeating schedules and Monitor routing

**Files:**

- Create: `Integration/EverydayLayerFile.swift`
- Modify: `Integration/ScreenTimeAdapters.swift` (replace the Task 2 stub of `registerEveryday` and `registeredEveryday`, add `ScreenTimeEverydayShield`), `Monitor/FocusMonitor.swift` (replace the Task 2 placeholder with `EverydayLayerFile`)
- Test: `SDKTests/ScreenTimeAdapterTests.swift`, `SDKTests/EverydayLayerFileTests.swift` (new), `SDKTests/DeviceDiagnosticsTests.swift`

**Interfaces:**

- Consumes: Task 2.
- Produces:
  - `ScreenTimeMonitoring.everydaySchedule(start: Int, end: Int) -> DeviceActivitySchedule`, with `hour`, `minute` and `second` components only and `repeats: true`.
  - `ScreenTimeMonitoring.everydayName(_ activity: DeviceActivityName) -> (revision: UUID, part: EverydayPart)?` for `everyday.<UUID>.range` and `everyday.<UUID>.window.<n>` (`n` 1-3), `nil` for every other name. `sessionID(_:)` still returns `nil` for an everyday name.
  - `final class ScreenTimeEverydayShield` over `ManagedSettingsStore(named: ManagedSettingsStore.Name("everydayLayer"))`, with `apply`, `matches`, `hasShield` and `clear`.
  - `final class EverydayLayerFile: EverydayLayerStore { init(directory: URL, shield: ScreenTimeEverydayShield); func selection() throws -> FamilyActivitySelection?; func contains(_ selection: FamilyActivitySelection) throws -> Bool; func write(_ schedule: EverydaySchedule, selection: FamilyActivitySelection) throws }`. It writes `everyday-layer.json` with `.atomic` and `.completeFileProtectionUntilFirstUserAuthentication`, and it stores application and web domain tokens only. `load()` throws for an unknown `schemaVersion` or a schedule that is not valid.
  - `FocusMonitor` passes every activity name to `handleCallbackRetryingLock`.

- [ ] **Step 1: Write the failing tests:**
  - `testEverydayScheduleRepeatsWithTimeComponentsOnly` (no date, calendar or time zone components.)
  - `testEverydayNameParsesRangeAndWindowsAndRejectsOthers` (`everyday.<UUID>.range`, `everyday.<UUID>.window.2`, `everyday.<UUID>.window.4`, `everyday.bad.range`, `focus.<UUID>`.)
  - `testSessionIDIgnoresEverydayNames`.
  - `testEverydayLayerFileLifecycle` (in a temporary directory: `write` then `load` returns the schedule, `contains` is `true` for a superset and `false` for a subset, a file with `schemaVersion` 2 or an invalid schedule throws, no file gives `nil`.)
  - `testDiagnosticMonitoringForwardsEverydayRegistration`.
- [ ] **Step 2: Run** `xcodegen generate`, then the iOS test command with `-only-testing:FocusSDKTests`. Expected: FAIL.
- [ ] **Step 3: Implement the interfaces above.**
- [ ] **Step 4: Run the same command. Expected: PASS.** Compile the Monitor target with the simulator build from README.
- [ ] **Step 5: Commit** `feat(integration): run the everyday layer from repeating schedules`.

### Task 4: Union limit of both selections

**Files:**

- Modify: `Shared/SelectionValidator.swift`, `App/SelectionFeedback.swift`, `App/FocusModel.swift` (`saveSelection`, the only caller of `SelectionStoring.save`, used by `SelectionEditor` in onboarding and in the timer screen), `App/Debug/UITestFixtures.swift` (a fixture everyday selection for the check)
- Test: `CoreTests/SelectionTests.swift`, `SDKTests/SelectionFeedbackTests.swift`, `SDKTests/FocusModelTests.swift`

**Interfaces:**

- Consumes: Task 3 (`EverydayLayerFile.selection()`).
- Produces:
  - `SelectionValidator.validateUnion(apps: Int, websites: Int) throws` for the number of distinct tokens in both selections. It throws the existing limit error over 50.
  - `FocusServices.everydaySelection: () -> FamilyActivitySelection?` reads the stored everyday selection. An unreadable everyday file gives `nil`, because the layer then blocks nothing.
  - `FocusModel.saveSelection` checks the union of the draft and `everydaySelection()` before it calls `SelectionStoring.save`. The `SelectionStoring` protocol does not change.
  - Task 5 runs the same check in the everyday save, against `services.selection.selection`.
  - A feedback message for the union limit, written with the `user-facing-copy` skill.

- [ ] **Step 1: Write the failing tests:** `testUnionOfBothSelectionsIsLimitedTo50AppsAnd50Websites` (49 + 2 distinct apps: refused; 50 + 50 equal apps: accepted), `testFocusSelectionSaveRefusesAUnionOver50` (in `FocusModelTests`: the repository is not written), and `testUnionLimitMessage`.
- [ ] **Step 2: Run `swift test --filter SelectionTests`, and the SDK tests `SelectionFeedbackTests` and `FocusModelTests`. Expected: FAIL.**
- [ ] **Step 3: Implement the interfaces above.**
- [ ] **Step 4: Run the same commands. Expected: PASS.**
- [ ] **Step 5: Commit** `feat(selection): limit both selections together to 50 apps and 50 websites`.

### Task 5: Everyday settings model and runtime wiring

**Files:**

- Create: `App/EverydaySettingsModel.swift`
- Modify: `App/FocusModel.swift` (`FocusServices` gets the everyday members), `App/FocusRuntime.swift` (create `EverydayLayerFile` in the App Group directory and pass it to the engine and the model), `App/Debug/UITestFixtures.swift`, `Integration/DeviceDiagnostics.swift` and `App/Debug/DeviceDiagnosticsSection.swift` (the diagnostic action below), `Package.swift` (exclude the new `App/` file), `project.yml` if the file list is explicit
- Test: `SDKTests/EverydaySettingsModelTests.swift` (new), `SDKTests/FocusModelTests.swift`, `SDKTests/DeviceDiagnosticsTests.swift`

**Interfaces:**

- Consumes: Tasks 2, 3 and 4.
- Produces:
  - `@MainActor @Observable final class EverydaySettingsModel` with `status: EverydayStatus?`, `draft: EverydaySchedule`, `draftSelection: FamilyActivitySelection`, `canEdit: Bool` (`false` during a focus session), `refusalMessage: String?`, `refresh()`, `addWindow(_ kind: EverydayWindowKind)`, `removeWindow(at:)` and `save()`.
  - `save()` first checks the union of `draftSelection` and the focus selection with `SelectionValidator.validateUnion` (Task 4). It then calls `saveEveryday` with `authorized` from `services.authorization.hasAccessNow()` (as `start` gets it), `containsStoredSelection` from `EverydayLayerFile.contains` and `write` from `EverydayLayerFile.write`, and shows a refused edit with the stored range end.
  - DEBUG diagnostics (only with `--screen-time-diagnostics`, as in `DeviceDiagnostics`): an action that applies a chosen selection to `everydayLayer` without the union check, for spec device step 9. It is not in Release builds and not in synthetic fixtures.
  - `FocusModel.refresh()` also refreshes the everyday status after its reconcile. The `everydayStatus(now:authorized:)` call gets the same `access == .approved` value as the reconcile and goes in its own `do`/`catch` after the existing history block, not in the first `do` block with the reconcile and the snapshot. Its failure (for example `lockTimeout` against a Monitor everyday callback) sets only the everyday status issue. It does not change `current` or `errorMessage`.
  - DEBUG fixture: argument `--everyday-fixture blocking` stores a layer whose range started 5 minutes before launch on the 5-minute grid and lasts 2 hours, with one synthetic app. Fixture monitoring and the fixture `EverydayLayerStore` never touch real restrictions.

- [ ] **Step 1: Write the failing tests:**
  - `testNewLayerStartsFromTheStandardRangeAndIsOff`.
  - `testTemplatesAddSuggestedTimesAndCustomHasNone`.
  - `testSaveInsideTheRangeShowsTheRefusalWithTheRangeEnd`.
  - `testEditingIsLockedDuringAFocusSession`.
  - `testStatusShowsBlockingNowAndTheNextChange`.
  - `testUnreadableFileShowsTheIssueAndAllowsSettingUpAgain`.
  - `testEverydayStatusFailureLeavesTheSessionAndErrorUnchanged` (in `FocusModelTests`: an `active` session, and an engine whose `everydayStatus(now:authorized:)` throws `lockTimeout`. After `refresh()`, `current` is the session and `errorMessage` is `nil`.)
  - `testEverydaySaveRefusesAUnionOver50` (nothing is registered or written).
- [ ] **Step 2: Run** the iOS tests with `-only-testing:FocusSDKTests/EverydaySettingsModelTests` and `-only-testing:FocusSDKTests/FocusModelTests`. Expected: FAIL.
- [ ] **Step 3: Implement the interfaces above.**
- [ ] **Step 4: Run the same command, then `swift test`. Expected: PASS.**
- [ ] **Step 5: Commit** `feat(app): edit the everyday layer with the strict-only rule`.

### Task 6: Everyday settings screen

**Files:**

- Create: `App/EverydaySettingsView.swift`
- Modify: `App/SettingsView.swift`, `UITests/FocusFlowTests.swift`, `Package.swift` (exclude the new `App/` file)

**Interfaces:**

- Consumes: Task 5.
- Produces: identifiers `everydayRow` (the row in the settings sheet), `everydayToggle`, `everydayRangeStart`, `everydayRangeEnd`, `everydayAddWindow`, `everydayWindow.<n>`, `everydaySelection`, `everydaySave`, `everydayRefusal`, `everydayStatus`.

Behavior: the settings sheet has a section for the everyday layer with `everydayRow`, which shows the status in one line. The row opens the everyday settings screen with the toggle, the range, the windows with the three templates and a custom window, and the everyday selection (a second `FamilyActivityPicker`, or the fixture editor in DEBUG fixtures). A refused save shows `everydayRefusal` with the stored range end. The timer screen does not change.

- [ ] **Step 1: Write the failing UI tests** (fixture mode `--selected`):
  - `testEverydayLayerTurnsOnFromSettings`: `settingsButton` → `everydayRow` → set the selection → `everydayToggle` → `everydaySave` → `everydayStatus` shows the layer as on.
  - `testLooserEditInsideTheRangeIsRefused` (mode `--everyday-fixture blocking`: turn the layer off, then `everydaySave` shows `everydayRefusal`, and `everydayStatus` still shows blocking.)
  - `testThreeWindowsAreTheLimit` (`everydayAddWindow` is disabled after the third window.)
  - `testTimerScreenIsUnchangedWithTheLayerOn` (the existing timer identifiers exist, and no everyday identifier is on the timer screen.)
- [ ] **Step 2: Run** `-only-testing:FocusUITests`. Expected: the new tests fail.
- [ ] **Step 3: Implement the screen.** Write the copy with the `user-facing-copy` skill.
- [ ] **Step 4: Run the full iOS scheme, then the unsigned device Release build. Expected: both pass, 0 warnings.**
- [ ] **Step 5: Commit** `feat(settings): set up the everyday layer from the settings sheet`.

### Task 7: Documentation

**Files:**

- Modify: `AGENTS.md`, `README.md` (fixture argument `--everyday-fixture blocking`), `docs/implementation-ledger.md`, `docs/specs/2026-10-26-focus-study-design.md`, `docs/specs/2026-11-01-m2-break-pass-design.md`, `docs/notes/screen-time-device-matrix.md`

This task has no code test. Its failing check is a search for the text that it adds.

- [ ] **Step 1: Run the failing check:** `grep -n 'everyday' AGENTS.md` and `grep -n -- '--everyday-fixture' README.md`. Expected now: the first prints only the documentation-path lines, and the second prints nothing.
- [ ] **Step 2: Update `AGENTS.md`** so that the project scope names the everyday layer and links the M3 spec. Update the `Shared/`, `Integration/` and `Monitor/` rows of the ownership table for the everyday convergence, the everyday file and the named store `everydayLayer`.
- [ ] **Step 3: Add dated reconciliation sections** to the 2026-10-26 and M2 specs for each line in the M3 spec section [Superseded lines](../specs/2026-11-01-m3-schedule-layer-design.md#superseded-lines). Do not rewrite the original lines.
- [ ] **Step 4: Add the device-matrix rows** for the M3 steps in the spec section [Physical-device verification](../specs/2026-11-01-m3-schedule-layer-design.md#physical-device-verification), all marked unverified. Add the README fixture argument and a ledger entry (what M3 changed, what stays unverified on a device).
- [ ] **Step 5: Run** the two searches from Step 1 again, then `trunk check` on the changed files and the internal-link check. Expected: the first search prints the new scope and ownership lines, the second prints the fixture argument, and the checks report no issues.
- [ ] **Step 6: Commit** `docs: record the M3 everyday layer`.
