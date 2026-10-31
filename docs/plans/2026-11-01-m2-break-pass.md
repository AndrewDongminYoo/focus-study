# M2 Break Pass and Deadline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a person take up to 3 breaks of exactly 3 minutes in a focus session, with a waiting screen before each break, a re-block without the app, and a deadline after which the session counts as unfocused.

**Architecture:** `Shared/` gets three paused phases (`waiting`, `onBreak`, `breakOver`), optional break fields on `ControlSession`, schema version 2, and the break transitions on `SessionControl`. `Integration/` gets a break activity (`focus.<UUID>.break.<n>`, 15-minute interval, 12-minute `warningTime`) and a session-scoped copy of the frozen selection in the App Group. `Monitor/` re-blocks on `intervalWillEndWarning(for:)`. `FocusModel` and `FocusView` drive the waiting screen, the break countdown and "다시 집중하기".

**Tech Stack:** Swift 5 mode, SwiftUI, Observation, SwiftData, FamilyControls, DeviceActivity, ManagedSettings, XCTest (unit and UI tests), XcodeGen.

**Spec:** [`docs/specs/2026-11-01-m2-break-pass-design.md`](../specs/2026-11-01-m2-break-pass-design.md)

**Start condition:** The operator approves the spec, including the [selection copy in the App Group](../specs/2026-11-01-m2-break-pass-design.md#selection-copy-in-the-app-group-privacy-boundary-change). Create the implementation worktree from the updated `main`. If the operator rejects the selection copy, stop and revise the spec before Task 2.

## Global Constraints

- iOS 17 or later, iPhone only, portrait only.
- Production timing: waits 15, 30 and 60 seconds; break 180 seconds; deadline slack 600 seconds; stale-wait grace 10 seconds; at most 3 breaks. Only DEBUG fixtures and tests use other values.
- `expiresAt` keeps its M1 meaning (`startedAt` + focus length). Breaks never move it.
- `Shared/` must not import Screen Time SDK modules. The selection copy is encoded and decoded in `Integration/`.
- Every transition is one `withExclusiveAccess` section. No `await` and no UI wait inside the lock.
- `project.yml` is the Xcode project source. Run `xcodegen generate` after each file is added. Keep `Package.swift` exclusions aligned for new files under `App/`.
- All user-facing copy is Korean 해요체, written with the `user-facing-copy` skill. The button with identifier `end` reads "집중 종료".
- Keep every accessibility identifier that `UITests/FocusFlowTests.swift` uses (AGENTS.md). That file is the list; read it before a UI change.
- Do not add a local notification, a custom shield, or a shield action.
- Simulator results do not prove real Screen Time behavior.

## Review Focus

1. A version 1 session stored by the M1 build is active when the M2 build launches. It must load with 0 breaks, count down and complete as `.expired`. Test: Task 1 Step 1.
2. A late `intervalWillEndWarning(for:)` of break 1 arrives during break 2. It must not re-block, clear or end anything. Test: Task 2 Step 1 and the race check in Task 2 Step 5.
3. The app is killed during the waiting screen. The next reconcile after the grace must cancel the wait as of `waitEndsAt` + grace, credit only the paused time up to that point, and keep the break count. A wait that crosses the deadline of the previous break must never end as `.deadlineMissed`. Test: Task 2 Step 1.
4. The re-block finds no selection copy, or the store does not match. The session must end as `.recoveryInterrupted`, never stay in a break without an end. Test: Task 2 Step 1.
5. The gaps after the re-blocks, added together, use up more than the slack. The session must end as `.deadlineMissed` at the deadline, lift the restrictions, and give no focus time. This is true whether the person never taps "다시 집중하기" or taps it and then focuses past the deadline in `active`. Test: Task 2 Step 1 and Task 4 Step 1.
6. The person resumes with less than 15 minutes of focus left. The focus activity must be registered from `startedAt`, so the interval is at least the focus length. Test: Task 2 Step 1 and Task 3 Step 1.
7. The selection copy and the break activity exist only while the stored phase is `onBreak`, whatever process exit or thrown error came before. The next lock section removes every other copy and break activity, and in `waiting` it also corrects the registered focus activity end (spec [Break artifacts](../specs/2026-11-01-m2-break-pass-design.md#break-artifacts)). Test: Task 2 Step 1 and Task 3 Step 1.
8. A reconcile arrives late, after both the focus end and the deadline. The reason must come from comparing the two times (spec [Timed end](../specs/2026-11-01-m2-break-pass-design.md#timed-end)), not from the order of the checks. Test: Task 1 Step 1 and Task 2 Step 1.
9. A version 1 envelope is read and a transition saves it. The file must then hold `schemaVersion` 2, and the break-shape checks must apply to both versions. Test: Task 1 Step 1 and Task 2 Step 1.
10. A save fails after a transition overwrote the focus activity end. The registered end must again match the stored phase, or the session must end with the restrictions lifted (spec [Save failure after an overwrite](../specs/2026-11-01-m2-break-pass-design.md#save-failure-after-an-overwrite)). Test: Task 2 Step 1.

---

### Task 1: Break fields, timing and schema version 2 in `Shared/`

**Files:**

- Create: `Shared/BreakTiming.swift`
- Modify: `Shared/ControlTypes.swift`, `Shared/SharedControlStore.swift`, `Shared/TimeRules.swift`, `Shared/StartupRecovery.swift`, `App/FocusModel.swift` (new `TimeRules` call), `App/TodayHistoryView.swift` (a case for `.deadlineMissed` in the exhaustive `reasonText` switch; Task 4 writes the final copy), `README.md` (add `Shared/BreakTiming.swift` to the race-check `xcrun swiftc` command)
- Test: `CoreTests/BreakTimingTests.swift` (new), `CoreTests/SharedControlStoreTests.swift`, `CoreTests/TimeRulesTests.swift` (rewrite the six existing `TimeRules.remaining(startedAt:expiresAt:now:)` calls with the new signature), `CoreTests/StartupRecoveryTests.swift`

**Interfaces:**

- Produces:
  - `public struct BreakTiming: Equatable { public var waits: [TimeInterval]; public var breakLength: TimeInterval; public var slack: TimeInterval; public var staleWaitGrace: TimeInterval; public static let standard: BreakTiming; public static let maxBreaks = 3 }` (`standard` = waits `[15, 30, 60]`, break `180`, slack `600`, grace `10`).
  - `SessionPhase` adds `waiting`, `onBreak`, `breakOver`. `EndReason` adds `deadlineMissed`.
  - `ControlSession` adds the `public var` optional fields `breaksTaken`, `pausedSeconds`, `pausedAt`, `deadlineCredit`, `waitEndsAt`, `breakEndsAt` (spec table [Session fields](../specs/2026-11-01-m2-break-pass-design.md#session-fields)), and these `public` members. `FocusHistoryTests` imports `FocusCore` without `@testable`, so Task 4 needs them public:
    - `public func focused(at now: Date) -> TimeInterval`
    - `public var focusEnd: Date` (`expiresAt + pausedSeconds`)
    - `public func deadline(timing: BreakTiming) -> Date` (`expiresAt + deadlineCredit + timing.slack`)
    - `public func timedEnd(at now: Date, timing: BreakTiming) -> EndReason?` (spec [Timed end](../specs/2026-11-01-m2-break-pass-design.md#timed-end): `.expired`, `.deadlineMissed` or `nil`)
    - `public var breaksLeft: Int` (`BreakTiming.maxBreaks - breaksTaken`)
    - `public var isPaused: Bool` (`waiting`, `onBreak`, `breakOver`)
  - `ControlEnvelope.schemaVersion` defaults to `2`, and `FileControl.save` sets it to `2` before it encodes, so a version 1 envelope that a transition saves becomes version 2. `FileControl.load()` accepts 1 and 2, throws `unsupportedSchema` for others, and applies the break-shape checks to both versions.
  - `TimeRules.remaining(session: ControlSession, now: Date) -> Int` replaces `remaining(startedAt:expiresAt:now:)` and rounds up as in M1. Remove the old function when nothing calls it.
  - `StartupRecovery.endCurrent` uses `timedEnd(at:timing:) ?? .earlyExit`.

- [ ] **Step 1: Write the failing tests**

```swift
// CoreTests/SharedControlStoreTests.swift
func testVersion1EnvelopeFromM1BuildLoadsWithoutBreaks() throws {
    // Write the JSON literal of an M1 envelope: schemaVersion 1, phase "active", 1500 s, no break keys.
    let session = try XCTUnwrap(store.load().session)
    XCTAssertEqual(session.breaksTaken ?? 0, 0); XCTAssertFalse(session.isPaused)
    XCTAssertEqual(TimeRules.remaining(session: session, now: start.addingTimeInterval(60)), 1440)
}
func testSaveWritesVersion2AndUnknownVersionIsRejected() throws { /* save a new envelope, read raw JSON: schemaVersion == 2; write 3: load throws unsupportedSchema */ }
func testSavingALoadedVersion1EnvelopeWritesVersion2() throws { /* write the M1 literal, load it, save it unchanged, read raw JSON: schemaVersion == 2 */ }
func testStoreRejectsInvalidBreakShapes() throws {
    // Each shape is written as JSON with schemaVersion 1 and again with 2, and must throw ControlIssue.invalidState:
    // onBreak without breakEndsAt; waiting with breaksTaken 3; active with pausedAt; breaksTaken 4; negative pausedSeconds.
}
// CoreTests/TimeRulesTests.swift
func testRemainingStopsWhilePausedAndContinuesAfterResume() { /* pausedAt at +600: remaining at +600 and +900 are equal; pausedSeconds 300 and no pausedAt: remaining at +900 == 1500 - 600 */ }
// CoreTests/BreakTimingTests.swift
func testStandardTimingMatchesOperatorDecisions() {
    XCTAssertEqual(BreakTiming.standard.waits, [15, 30, 60]); XCTAssertEqual(BreakTiming.standard.breakLength, 180)
    XCTAssertEqual(BreakTiming.standard.slack, 600); XCTAssertEqual(BreakTiming.maxBreaks, 3)
}
func testDeadlineIsStartPlusLengthPlusBreakCreditPlusSlack() { /* length 1500, deadlineCredit 15 + 180: deadline == startedAt + 1500 + 195 + 600 */ }
func testTimedEndComparesFocusEndWithDeadline() {
    // active, length 1500, deadlineCredit 195 (deadline +2295):
    // pausedSeconds 895 (focus end +2395): nil at +2294, deadlineMissed at +2295 and at +9000.
    // pausedSeconds 600 (focus end +2100): nil at +2099, expired at +2100 and at +9000.
    // breakOver with deadline +2295: nil at +2294, deadlineMissed at +2295. waiting: nil at +9000.
}
// CoreTests/StartupRecoveryTests.swift
func testEndCurrentAfterBreakIsNotExpiredAtNominalEnd() throws { /* pausedSeconds 300, now == expiresAt: reason is earlyExit, not expired */ }
func testEndCurrentAfterDeadlineWithLateFocusEndIsDeadlineMissed() throws { /* pausedSeconds 895, deadlineCredit 195, now +9000: reason is deadlineMissed */ }
```

- [ ] **Step 2: Run `swift test` and confirm the new tests fail to compile or fail.**
- [ ] **Step 3: Implement the interfaces above.** Decode the new fields as optional. Keep the M1 validation, and add the conditions from the spec section [Session fields](../specs/2026-11-01-m2-break-pass-design.md#session-fields). Update the callers of the removed `TimeRules` function in this task, so that every target and test still compiles: `App/FocusModel.swift` and the six calls in `CoreTests/TimeRulesTests.swift`. Before you remove the function, run `grep -rn --include='*.swift' 'remaining(startedAt' .` and confirm that it prints nothing.
- [ ] **Step 4: Run `swift test`, then the simulator build from README. Expected: all tests pass, and the app, Monitor and Report targets compile.**
- [ ] **Step 5: Run the race check from README with `Shared/BreakTiming.swift` added to the command. Expected: `PASS: stale A cannot clear B`.**
- [ ] **Step 6: Commit** `feat(core): store break state and read version 1 sessions`.

### Task 2: Break transitions in `SessionControl`

**Files:**

- Modify: `Shared/ControlTypes.swift` (protocols), `Shared/SessionControl.swift`, `Tests/Fixtures/ControlRaceHelper.swift`
- Modify so that every target still compiles (each conformer and call site of the changed protocol and initializer):
  - `Integration/ScreenTimeAdapters.swift`: `registerBreak` throws `ControlIssue.breakUnavailable` until Task 3, so no break can start and no shield is cleared. `isBreakRegistered` returns `false`, `registeredBreaks` returns `[]`, and `stopBreak` calls `stopMonitoring` for the break name.
  - `Integration/DeviceDiagnostics.swift`: the wrapper forwards the new members to its base. `replay(current:)` calls `engine.handleCallback(activityName:now:authorized:)` and must pass `kind: .didEnd`, the kind that a stale focus activity delivers.
  - `App/Debug/UITestFixtures.swift`: fixture monitoring records break registrations in memory.
  - `App/FocusRuntime.swift` and `Monitor/FocusMonitor.swift`: pass a `BreakSelectionStore` whose `restoreShield` returns `false` until Task 3 (Monitor) and Task 5 (app), and pass `CallbackKind` from the existing callbacks.
  - `SDKTests/DeviceDiagnosticsTests.swift` and `SDKTests/FocusModelTests.swift`: fakes get the new members.
  - Do not add protocol-extension defaults. They would hide a missing implementation.
- Test: `CoreTests/BreakControlTests.swift` (new), `CoreTests/SessionControlTests.swift` and `CoreTests/StartupRecoveryTests.swift` (fakes get the new protocol members)

**Interfaces:**

- Consumes: Task 1.
- Produces:
  - `MonitoringClient` adds `registerBreak(id: UUID, index: Int, start: Date, end: Date, warning: TimeInterval) throws`, `isBreakRegistered(id: UUID, index: Int) -> Bool`, `var registeredBreaks: [(id: UUID, index: Int)] { get }` and `stopBreak(id: UUID, index: Int)`. `stop(id:)` stops the focus activity and every break activity of that session. `register(id:start:end:)` overwrites an existing schedule.
  - `protocol BreakSelectionStore { func restoreShield(id: UUID) -> Bool; func exists(id: UUID) -> Bool; func remove(id: UUID); func removeAll(except id: UUID?) }`. `restoreShield` applies the copy and returns `true` only when the store matches it. `removeAll(except: nil)` deletes every copy.
  - `enum CallbackKind { case didStart, didEnd, willEndWarning }`.
  - `SessionControl.init(store:monitoring:shield:breakSelection:timing:)`, with `timing` defaulting to `.standard`.
  - `func requestBreak(id: UUID, now: Date) throws -> ControlSession`
  - `func cancelWait(id: UUID, now: Date) throws`
  - `func startBreak(id: UUID, now: Date, saveSelection: () throws -> Void) throws`
  - `func resume(id: UUID, now: Date) throws`
  - `func handleCallback(activityName: String, kind: CallbackKind, now: Date, authorized: Bool) throws`
  - `reconcile` follows the spec section [Reconcile order](../specs/2026-11-01-m2-break-pass-design.md#reconcile-order) and takes the time-based reason only from `ControlSession.timedEnd(at:timing:)`. Every focus activity registration uses the end from the spec section [Monitoring activities](../specs/2026-11-01-m2-break-pass-design.md#monitoring-activities), so `active` registers `min(focusEnd, deadline)`. Every lock section, `start` included, runs the cleanup of the spec section [Break artifacts](../specs/2026-11-01-m2-break-pass-design.md#break-artifacts) right after it reads the envelope, and `handleCallback` runs it before the identity check. `end` follows the five numbered steps of spec transition 6. `read` failure also calls `breakSelection.removeAll(except: nil)`.
  - `ControlIssue` adds `breakUnavailable` (no breaks left, wrong phase, or the wait is not over).

- [ ] **Step 1: Write the failing tests** with a fake monitor that records every registration (name, start, end, warning), a fake shield, and a fake `BreakSelectionStore`:
  - `testThreeBreaksUseWaitsOf15And30And60SecondsAndNoFourth`.
  - `testCancelledWaitKeepsBreakCountAndWaitAndCreditsDeadline`.
  - `testStartBreakBeforeWaitEndsThrowsBreakUnavailable`.
  - `testStartBreakRegistersFifteenMinuteBreakWithTwelveMinuteWarningThenClearsShield` (the shield is cleared only after the save).
  - `testStartBreakFailureNeverClearsShieldAndReturnsToActive` (`registerBreak` throws; shield `clear` count is 0; phase `active`; the copy is removed).
  - `testStartBreakSaveFailureNeverClearsShieldAndRollsBack` (the save of `onBreak` throws once, after the copy and the break registration; shield `clear` count is 0; the break activity is stopped; the copy is removed; phase `active`; the last focus activity registration ends at `min(focusEnd, deadline)`).
  - `testStartBreakRollbackSaveFailureRestoresWaitingEnd` (the saves of `onBreak` and of `active` both throw: shield `clear` count is 0; the stored phase is `waiting`; the last focus activity registration ends at the `waiting` end).
  - Save failures after an overwrite (spec [Save failure after an overwrite](../specs/2026-11-01-m2-break-pass-design.md#save-failure-after-an-overwrite)). The fake store throws on the named save once, unless the test says otherwise:
    - `testRequestBreakSaveFailureRestoresActiveEnd` (the save of `waiting` throws: `requestBreak` throws; the stored phase is `active`; the last registration ends at `min(focusEnd, deadline)`).
    - `testCancelWaitSaveFailureRestoresWaitingEnd` (the save of `active` throws: the stored phase is `waiting`; the last registration ends at the `waiting` end; reconcile at that end cancels the wait as of `waitEndsAt` + grace).
    - `testResumeSaveFailureRestoresDeadlineEnd` (length 1500: break requested at +300, re-block at +495, resume at +600 and the save of `active` throws. The stored phase is `breakOver`. The last registration ends at the deadline +2295, not at the new focus end +1800. Reconcile at +2295 ends as `.deadlineMissed` with the shield cleared.)
    - `testStaleWaitCancelSaveFailureWithPastEndEndsSafely` (a `waiting` session reconciled 1 hour after `waitEndsAt` + grace, past its `waiting` end, and the save of `active` throws: the shield is cleared, the focus activity and the break activity are stopped, and the session ends as `.recoveryInterrupted`).
    - `testSaveAndRestoreFailureEndsAsRecoveryInterrupted` (resume; the store throws on every save, and the restore registration throws: shield `clear` count is 1; the focus activity is stopped; the stored phase is still `breakOver`; after the store accepts saves again, reconcile ends the session as `.recoveryInterrupted`).
  - `testWarningCallbackReBlocksStopsBreakActivityAndRemovesCopy`.
  - `testStaleBreakCallbackDoesNotTouchNewerBreak` (warning of `break.1` during break 2: phase stays `onBreak`, no shield call).
  - `testWarningCallbackAfterDeadlineEndsAsDeadlineMissed` (an `onBreak` session whose deadline is 5 s before the warning of its current break activity: the warning ends the session as `.deadlineMissed`, no save of `breakOver` is recorded, no shield is applied, and the store is cleared).
  - `testDidStartCallbackOfBreakNeverReBlocks`.
  - `testReBlockWithoutCopyEndsAsRecoveryInterrupted`.
  - `testStaleWaitIsCancelledAsOfWaitEndPlusGrace` (reconcile 1 hour later: `pausedSeconds` and `deadlineCredit` grow by the wait plus the grace only; the break count is unchanged).
  - `testWaitThatCrossesPreviousDeadlineDoesNotMissDeadline` (after break 1, the person uses 590 s of slack, then requests break 2 just before the focus end; reconcile during the 30 s wait keeps `waiting`, and the break starts).
  - `testStartBreakAfterGraceThrowsBreakUnavailable`.
  - `testDeadlineAfterReBlockEndsAsDeadlineMissedAndClearsRestrictions` (no resume; the focus activity end in `breakOver` is the deadline).
  - `testResumeAfterDeadlineEndsAsDeadlineMissed`.
  - `testResumeAfterOneLongGapEndsAtDeadlineNotAtFocusEnd` (length 1500: break requested at +300, re-block at +495, resume at +1195; deadline +2295, focus end +2395. The registered end is +2295. Reconcile at +2294 keeps `active`, and reconcile at +2295 ends as `.deadlineMissed` with the shield cleared.)
  - `testTwoGapsThatTogetherExceedSlackEndAtDeadline` (length 1500: break 1 at +100, re-block at +295, resume at +795; break 2 at +800, re-block at +1010, resume at +1510; deadline +2505, focus end +2905. Reconcile at +2505 ends as `.deadlineMissed`, never `.expired` at +2905.)
  - `testLateReconcileAfterBothTimesUsesTheEarlierOne` (reconcile at +9000: `.deadlineMissed` for the session of the previous test, `.expired` for a session whose focus end is before its deadline).
  - `testResumeRegistersFocusActivityFromStartedAtToNewFocusEnd` (resume with 10 minutes of focus left: the registration start is `startedAt`).
  - `testReconcileAtNewFocusEndExpiresAndNotBefore`.
  - `testBreakRequestOnVersion1SessionSavesVersion2` (write the M1 literal, `requestBreak`, read raw JSON: `schemaVersion` 2 and `phase` `waiting`).
  - `testStartRemovesLeftoverSelectionCopies`.
  - `testEveryLockSectionRemovesArtifactsTheStoredPhaseDoesNotAllow` (parameterized over no session and each stored phase, and over `reconcile`, `start`, and a callback whose name changes nothing. The fakes start with copies for the stored ID and for another ID, and with break activities 1 to 3 of both IDs. After the section, only the artifacts of the spec table [Break artifacts](../specs/2026-11-01-m2-break-pass-design.md#break-artifacts) remain. In `waiting` before the grace, the last focus activity registration ends at the `waiting` end.)
  - `testInterruptionAtEveryStepOfBreakAndEndTransitionsKeepsTheArtifactTable` (parameterized. The fakes record a snapshot of the whole fake world, which is the stored envelope, the focus and break registrations with their ends, the copies and the shield, after each effect of transitions 3 and 4, of the rollback of transition 3, of transition 6, and of the cleanup itself. Exit pass: for each snapshot, a new `SessionControl` over a copy of it runs `reconcile`. For the snapshots of transition 3 and its rollback, it runs once before the grace and once 1 hour after `waitEndsAt` + grace. Throw pass: each effect that can throw throws once, then `reconcile` runs. After that reconcile: only the table's artifacts exist; the last focus activity registration ends at the end that the spec section [Monitoring activities](../specs/2026-11-01-m2-break-pass-design.md#monitoring-activities) gives for the stored phase, or the focus activity is stopped in `terminal`; the shield is cleared only when the stored phase is `onBreak` or `terminal`.)
  - `testEndDuringBreakStopsBothActivitiesAndRemovesCopy`.
  - `testReadFailureStopsBreakActivitiesAndRemovesAllCopies`.
- [ ] **Step 2: Run `swift test --filter FocusCoreTests`. Expected: FAIL (members missing).**
- [ ] **Step 3: Implement the transitions** in the order of the spec section [Transitions](../specs/2026-11-01-m2-break-pass-design.md#transitions). Extend the race helper with a `stale-break` mode: process A delivers the warning of `break.1` while process B holds the lock during break 2. Process A must leave break 2 unchanged.
- [ ] **Step 4: Run `swift test`, then the simulator build from README. Expected: PASS, and every target compiles.**
- [ ] **Step 5: Run the race check. Expected: `PASS: stale A cannot clear B` and the new stale-break line.**
- [ ] **Step 6: Commit** `feat(core): add break, re-block, resume and deadline transitions`.

### Task 3: Break activity, selection copy and Monitor callback

**Files:**

- Create: `Integration/BreakSelectionFile.swift`
- Modify: `Integration/ScreenTimeAdapters.swift` (replace the Task 2 stub of `registerBreak`, `isBreakRegistered` and `registeredBreaks`), `Monitor/FocusMonitor.swift` (replace the Task 2 `BreakSelectionStore` placeholder with `BreakSelectionFile`)
- Test: `SDKTests/ScreenTimeAdapterTests.swift`, `SDKTests/BreakSelectionFileTests.swift` (new), `SDKTests/DeviceDiagnosticsTests.swift`

**Interfaces:**

- Consumes: Task 2.
- Produces:
  - `ScreenTimeMonitoring.breakSchedule(start: Date, end: Date, warning: TimeInterval, calendar: Calendar) -> DeviceActivitySchedule`, with `warningTime` as minute and second components.
  - `ScreenTimeMonitoring.sessionID(_:)` reads the 36 characters after `focus.` for both names. `breakIndex(_:) -> Int?` returns `n` for `focus.<UUID>.break.<n>` and `nil` for every other name. `registeredBreaks` lists the names in `DeviceActivityCenter().activities` that both parsers accept.
  - `final class BreakSelectionFile: BreakSelectionStore { init(directory: URL, shield: ScreenTimeShield); func save(_ selection: FamilyActivitySelection, id: UUID) throws }`. It writes `break-selection.<UUID>.json` with `.atomic` and `.completeFileProtectionUntilFirstUserAuthentication`, and it stores application and web domain tokens only.
  - `FocusMonitor` overrides `intervalWillEndWarning(for:)` and passes the callback kind to `handleCallback`.

- [ ] **Step 1: Write the failing tests:**
  - `testBreakScheduleIsFifteenMinutesWithTwelveMinuteWarning`.
  - `testSessionIDParsesFocusAndBreakNamesAndBreakIndexRejectsOthers` (`focus.<UUID>`, `focus.<UUID>.break.2`, `focus.bad`, `other.<UUID>`).
  - `testFocusScheduleFromStartedAtIsAtLeastTheFocusLength`.
  - `testBreakSelectionFileLifecycle` (in a temporary directory: `save` creates the file and `exists(id:)` then returns `true`, `remove(id:)` deletes only that ID, `removeAll(except:)` deletes every other `break-selection.*` file and nothing else, `removeAll(except: nil)` deletes every copy, `restoreShield` returns `false` when the file is missing).
  - `testDiagnosticMonitoringForwardsBreakRegistration`.
- [ ] **Step 2: Run** `xcodegen generate`, then the iOS test command with `-only-testing:FocusSDKTests`. Expected: FAIL.
- [ ] **Step 3: Implement the interfaces above.**
- [ ] **Step 4: Run the same command. Expected: PASS.** Compile the Monitor target with the simulator build from README.
- [ ] **Step 5: Commit** `feat(integration): re-block from the Monitor at the end of a break`.

### Task 4: Focus time in history

**Files:**

- Modify: `App/SessionRecord.swift`, `App/TodayHistoryView.swift`, `App/FocusView.swift` (today summary)
- Test: `HistoryTests/SessionRecordTests.swift`

**Interfaces:**

- Consumes: `EndReason.deadlineMissed` and the public `ControlSession` members (Task 1).
- Produces: `SessionRecord.focusDuration: TimeInterval` (`expiresAt - startedAt` for `.expired`, else 0). Today's total and the history row use it. `.deadlineMissed` has its own label. The SwiftData schema does not change.
- The `.earlyExit` label stays "중도 종료" in this task. Task 6 renames it together with the button, because three UI tests read that text (see Task 6 Step 1).

- [ ] **Step 1: Write the failing tests:**
  - `testExpiredRecordAfterBreaksGivesTheFullFocusLength` (a session with `pausedSeconds` 400, observed at `focusEnd`).
  - `testEarlyExitAndDeadlineMissedGiveNoFocusTime`.
  - `testDeadlineMissedReasonRoundTrips` (the raw value loads as `.deadlineMissed`, not `.recoveryInterrupted`).
- [ ] **Step 2: Run `swift test --filter FocusHistoryTests`. Expected: FAIL.**
- [ ] **Step 3: Implement** `focusDuration`, and use it in `TodayHistoryView` and in the today summary of `FocusView`. Write the `.deadlineMissed` label with the `user-facing-copy` skill.
- [ ] **Step 4: Run `swift test`, then the iOS UI tests `-only-testing:FocusUITests/FocusFlowTests/testTodaySummaryCountsOnlyCompletedSessions`. Expected: PASS.**
- [ ] **Step 5: Commit** `feat(history): count focus time only for completed sessions`.

### Task 5: Break actions in `FocusModel`

**Files:**

- Modify: `App/FocusModel.swift`, `App/FocusRuntime.swift` (create `BreakSelectionFile` in the App Group directory and pass it to the engine), `App/Debug/UITestFixtures.swift`
- Test: `SDKTests/FocusModelTests.swift`

**Interfaces:**

- Consumes: Tasks 2 and 3.
- Produces:
  - `FocusModel.isInSession` (`active` or paused). Selection editing, the settings button and the corner buttons use it instead of `isActive`.
  - `requestBreak()`, `cancelWait()`, `resume()`, `sceneDidLeaveForeground()` (cancels a wait).
  - `breaksLeft: Int`, `waitProgress: Double?` (0 to 1 while `waiting`), `breakRemaining: Int?`, `resumeRemaining: Int?` (in `breakOver`: seconds until `deadline - remaining`, the last tap on "다시 집중하기" that can still complete; 0 after that).
  - `tick()` starts the break when a wait is over (it passes `saveSelection` with the frozen selection), and it refreshes when a break is over or when `ControlSession.timedEnd(at:timing:)` gives a reason.
  - DEBUG fixture: argument `--break-timing short` uses waits `[1, 2, 4]`, break `3`, slack `5` and grace `2` seconds. It does not shorten the focus length. Fixture monitoring and a fixture `BreakSelectionStore` never touch real restrictions.
  - DEBUG fixture: mode `ending-soon` starts a session with the configured length that started 10 seconds before its focus end, in the same way as `expiring` (`-(length - 10)`). With `--break-timing short`, a break taken at once and never resumed reaches the deadline about 19 seconds after launch (10 s of focus, a 1 s wait, a 3 s break and a 5 s slack).

- [ ] **Step 1: Write the failing tests:**
  - `testRequestBreakPausesRemaining`.
  - `testLeavingForegroundCancelsWaitAndKeepsBreaksLeft`.
  - `testTickStartsBreakAfterWaitWithFrozenSelection`.
  - `testSelectionIsLockedDuringBreakAndAfterReBlock`.
  - `testResumeContinuesCountdownFromPausedValue`.
  - `testResumeRemainingReachesZeroWhenSessionCanNoLongerComplete`.
  - `testNoBreakActionAfterThirdBreak` (`breaksLeft == 0`, `requestBreak()` changes nothing).
- [ ] **Step 2: Run** the iOS tests with `-only-testing:FocusSDKTests/FocusModelTests`. Expected: FAIL.
- [ ] **Step 3: Implement the interfaces above.**
- [ ] **Step 4: Run the same command. Expected: PASS.**
- [ ] **Step 5: Commit** `feat(app): take, cancel and return from breaks`.

### Task 6: Break states on the timer screen

**Files:**

- Modify: `App/FocusView.swift`, `App/TodayHistoryView.swift` (`.earlyExit` label), `UITests/FocusFlowTests.swift`

**Interfaces:**

- Consumes: Task 5.
- Produces: identifiers `breakStart`, `breaksLeft`, `breakWait` (the filling button), `breakWaitCancel`, `breakCountdown`, `resume`, `deadlineNotice`. `end` reads "집중 종료" in every phase, and its confirmation says that the session gives no focus time. The `.earlyExit` history label in `TodayHistoryView` reads "집중 종료".

Behavior: while focusing, the screen shows the countdown, `breakStart` with `breaksLeft`, and `end`. `breakStart` is hidden after the third break. The waiting state shows `breakWait` filling over the wait, `breakWaitCancel`, and `end`. The break shows `breakCountdown` and `end`. After the re-block, the screen shows `resume`, `deadlineNotice` (from `resumeRemaining`, and the no-longer-counts notice at 0) and `end`. The fill animation respects Reduce Motion. Leaving the app during the wait calls `sceneDidLeaveForeground()`.

- [ ] **Step 1: Write the failing UI tests** (mode `--selected --break-timing short`):
  - `testBreakFlowReBlocksAndResumes`: `start` → `breakStart` → `breakWait` → `breakCountdown` → `resume` → `countdown` continues.
  - `testCancelWaitReturnsToFocusWithSameBreaksLeft`.
  - `testThirdBreakLeavesOnlyEnd`.
  - `testMissedDeadlineRecordsUnfocusedSession` (mode `ending-soon --break-timing short`, because the short timing alone leaves the deadline about 25 minutes away: `breakStart` at once → `breakCountdown` → `resume` appears and is not tapped → `deadlineNotice` shows the no-longer-counts notice → at the deadline, about 19 s after launch, `todaySummary` shows 0회 and the history row shows the missed-deadline label; wait up to 30 s).
  - Update the three tests that read "중도 종료" (`grep -n '중도 종료' UITests/FocusFlowTests.swift`):
    - `testStartupStorageFailureAllowsSafeEndAndRetry` and `testActiveSessionLocksSelectionAndEarlyExitCreatesHistory` wait for the history row. Change the text to "집중 종료".
    - `testCancellingEarlyExitKeepsTheSessionRunning` checks on the timer screen that no "중도 종료" text exists. After the rename the `end` button carries the same text, so a string swap would test the button. Replace the check with `countdown` still existing and `completion` not existing.
- [ ] **Step 2: Run** `-only-testing:FocusUITests`. Expected: the new and updated tests fail.
- [ ] **Step 3: Implement the states.** Write the copy with the `user-facing-copy` skill.
- [ ] **Step 4: Run the full iOS scheme, then the unsigned device Release build. Expected: both pass, 0 warnings.**
- [ ] **Step 5: Commit** `feat(focus): show waiting, break and return states on the timer`.

### Task 7: Documentation

**Files:**

- Modify: `AGENTS.md`, `README.md` (fixture argument `--break-timing short` and mode `ending-soon`), `docs/implementation-ledger.md`, `docs/specs/2026-10-26-focus-study-design.md`, `docs/specs/2026-10-31-m1-launch-flow-design.md`, `docs/notes/screen-time-device-matrix.md`

This task has no code test. Its failing check is a search for the text that it replaces (the M1 plan's Task 7 had no failing step; this task adds one).

- [ ] **Step 1: Run the failing check:** `grep -n 'no pause' AGENTS.md` and `grep -n -- '--break-timing' README.md`. Expected now: the first prints the scope line, and the second prints nothing.
- [ ] **Step 2: Update `AGENTS.md`** so that the project scope no longer says "no pause". It must say that a session has up to 3 breaks of 3 minutes, and link the M2 spec. Update the `Shared/` and `Monitor/` rows of the ownership table for the break transitions and the re-block.
- [ ] **Step 3: Add dated reconciliation sections** to the 2026-10-26 and M1 specs for each line in the M2 spec section [Superseded lines](../specs/2026-11-01-m2-break-pass-design.md#superseded-lines). Do not rewrite the original lines.
- [ ] **Step 4: Add the device-matrix rows** for the M2 steps in the spec section [Physical-device verification](../specs/2026-11-01-m2-break-pass-design.md#physical-device-verification), all marked unverified. Add the README fixture argument and a ledger entry (what M2 changed, what stays unverified on a device).
- [ ] **Step 5: Run** the two searches from Step 1 again, then `trunk check` on the changed files and the internal-link check. Expected: the first search prints nothing, the second prints the fixture argument, and the checks report no issues.
- [ ] **Step 6: Commit** `docs: record M2 break pass and deadline`.
