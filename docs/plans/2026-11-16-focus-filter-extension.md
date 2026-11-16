# Focus Filter Extension Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking. Run the tasks in order; each task ends with its tests green and one commit.

**Goal:** A Focus with the FocusStudy filter starts a session without the app, and a filter-started session keeps its restrictions until the Focus turns off (issue #152).

**Architecture:** `Shared/` gets the open-session rules: the stored fields `activation`, `baseLength` and `filterCallAt`, rollover inside the M2 reconcile order, the open focused time, one length-validation rule and the stale-call check. The focus selection, the focus length, the last refusal and the pending card move to the App Group. A new App Intents extension target `FocusStudyIntents` compiles the filter type, the handler and an extension runtime; the app keeps the same type and handler. The timer screen and the Live Activity count up after the base length.

**Tech Stack:** Swift 5 mode, SwiftUI, Observation, SwiftData, AppIntents, FamilyControls, DeviceActivity, ManagedSettings, XCTest, XcodeGen.

**Spec:** [`docs/specs/2026-11-16-focus-filter-extension-design.md`](../specs/2026-11-16-focus-filter-extension-design.md), approved on 2026-11-16. The [M4 design](../specs/2026-11-01-m4-focus-filter-design.md) stays the authority for every rule this spec does not change.

**Start condition:** Tasks 1 to 6 need no signing change. **Task 7 needs a separate explicit approval** before any change to `project.yml` targets, entitlements, App IDs or profiles (spec decision 1). Stop after Task 6 and ask for it. Do not use `-allowProvisioningUpdates`.

## Global Constraints

- iOS 17 or later, iPhone only, portrait only. `ControlEnvelope.schemaVersion` stays `2`; every new field is optional.
- `Shared/` must not import Screen Time SDK modules or `AppIntents`. Only `App/FocusStudyFilter.swift` imports `AppIntents`.
- Every transition is one `withExclusiveAccess` section on `control.lock`, reads the envelope again, runs the M2 cleanup and ends with the M3 everyday convergence. No `await`, SwiftData call or UI wait inside the lock.
- Every section saves the envelope that it decoded, so `activation`, `baseLength` and `filterCallAt` survive Monitor callbacks, the everyday sections and `acknowledgeTerminal`.
- No new `EndReason`. An open session ends as `.expired`, `.earlyExit`, `.deadlineMissed` or `.authorizationRevoked` (spec decision 4).
- `project.yml` is the Xcode project source; run `xcodegen generate` after each file change that the project needs. `Package.swift` excludes each new `App/` file by name from `FocusHistory`.
- A new `Shared/` file is added to the race-check `xcrun swiftc` command in `README.md` and `.github/workflows/verify.yml`.
- All new user-facing copy is Korean 해요체, written with the `user-facing-copy` skill, with short labels.
- Keep every accessibility identifier that `UITests/FocusFlowTests.swift` uses.
- Simulator results do not prove Focus filter delivery, extension Screen Time access or rollover timing on a device.
- Verification commands are the ones in [README 실행과 검증](../../README.md#실행과-검증). Check `uptime` before a simulator or Release build, and run one at a time.

## Review Focus

1. A rollover runs only for an open session in `active`, at its focus end, not after the deadline, and within the one-week bound; a manual session or a session whose activation was cleared never rolls over. Test: Task 2.
2. Every end of a session that was open at the start of the section (Focus off, activation check, "집중 종료") records the open focused time, not capped at `length`, also after a lost rollover. Test: Task 2.
3. The filter end decides openness before it clears the marker, so its reconcile neither rolls over nor ends the session with the timed `.expired`. Test: Task 2.
4. A rolled-over or finalized session saves and reloads through `FileControl`, and the Live Activity projection accepts it; a length outside the rule throws `invalidState`. Test: Task 1.
5. A stale filter call changes nothing of its own, also across two processes, and an activation-check clear makes an earlier on call stale. Test: Task 3 and the race check.
6. A filter start with `unknown` access passes both verification reads in `SessionControl.begin`; `denied` still rolls back. Test: Task 2.
7. Migration never loses a selection or a length, and the extension never starts with a length the person did not choose. Test: Task 4.
8. The extension compiles no SwiftUI view and nothing of `Report/`, and has only the App Group and Family Controls entitlements. Test: Task 7.

---

### Task 1: Stored fields and length validation in `Shared/`

**Files:**

- Modify: `Shared/ControlTypes.swift` (`ControlSession.activation`, `ControlSession.baseLength`, `ControlEnvelope.filterCallAt`; `isOpen(in:)`; `openFocused(at:)`; the length rule as one function, for example `ControlSession.hasValidLength`)
- Modify: `Shared/SharedControlStore.swift` (`FileControl.load()` uses the length rule), `Shared/FocusActivityProjection.swift` (the guard uses the length rule)
- Test: `CoreTests/SharedControlStoreTests.swift`, `CoreTests/FocusActivityTests.swift`

- [ ] **Step 1:** Write failing tests: a version 2 file without the new fields decodes; each row of spec [Length validation](../specs/2026-11-16-focus-filter-extension-design.md#length-validation) saves and reloads, including a 40-minute base rolled over twice and an `.expired` terminal session of 47.5 minutes; a non-multiple length, a length above one week and a non-finite length throw `invalidState`; the projection of a rolled-over `active` session is not `nil`.
- [ ] **Step 2:** Implement the fields and the rule. `openFocused(at:)` is `focused(at:)` without the cap at `length`, capped at `TodaySnapshot.maxFocusSeconds` (spec decisions 5 and 8). If `TodaySnapshot.swift` is not in the race-check file list, move the bound into a constant that is.
- [ ] **Step 3:** `swift test` green. Commit `feat(shared): store open-session fields and validate rolled-over lengths`.

### Task 2: Rollover, open-session ends and filter-start access in `SessionControl`

**Files:**

- Modify: `Shared/SessionControl.swift` (rollover in the reconcile order; `startFromFocusFilter` saves `activation` and `baseLength`, and passes an access check that accepts `unknown` to `begin`; `endFromFocusFilter`, `clearFilterActivation(matching:)` and `finish()` end an open session with the reason order of spec decision 4, and only an `.expired` end sets `expiresAt = startedAt + openFocused`; every other reason keeps the stored length, a whole multiple of the base), `Shared/StartupRecovery.swift` only if the reconcile order lives there
- Test: `CoreTests/FocusFilterControlTests.swift`, `CoreTests/SessionControlTests.swift`

- [ ] **Step 1:** Write failing tests for each spec rule: rollover at the focus end; catch-up after a late callback; no rollover for a manual session, a cleared activation, a deadline before the focus end, or a length at the one-week bound (the session then ends as `.expired`); a rollover registration failure ends as `.expired` with the focused time; Focus off before and after the base length; Focus off after a lost rollover records the uncapped time; Focus off during `onBreak`; the activation check ends an open session; "집중 종료" during an open session gives `.expired` past the base length and keeps the marker; a filter start with `unknown` access starts, with `denied` rolls back; the gap rows of spec [Gaps between steps](../specs/2026-11-16-focus-filter-extension-design.md#gaps-between-steps) (a thrown save after the rollover registration, a process exit modelled as a reload).
- [ ] **Step 2:** Implement. The rollover registers `min(focusEnd, deadline)` as `focusActivityEnd` already computes, and a failed registration ends the session through M2 transition 6 (spec [Rollover](../specs/2026-11-16-focus-filter-extension-design.md#rollover) step 5).
- [ ] **Step 3:** `swift test` and the race check green. Commit `feat(shared): roll an open session over until its Focus turns off`.

### Task 3: Call order across processes

**Files:**

- Modify: `Shared/SessionControl.swift` (`calledAt` on `startFromFocusFilter`, `endFromFocusFilter`; a `stale` result; `clearFilterActivation(matching:now:)` stores its time), `Shared/ControlTypes.swift` (`FocusFilterStart.stale`)
- Modify: `Tests/Fixtures/ControlRaceHelper.swift` and the PASS list in `README.md`: a new line such as `PASS: an older on call cannot start after a newer off call`
- Test: `CoreTests/FocusFilterControlTests.swift`

- [ ] **Step 1:** Write failing tests: a stale on call and a stale off call change nothing of their own and save only what the cleanup saves; an equal `calledAt` keeps the lock order; an activation-check clear makes an earlier on call stale; a missing `filterCallAt` makes no call stale. Add the two-process interleaving to the race helper.
- [ ] **Step 2:** Implement spec [Call order across processes](../specs/2026-11-16-focus-filter-extension-design.md#call-order-across-processes).
- [ ] **Step 3:** `swift test` and the race check (now twelve PASS lines) green. Commit `feat(shared): reject stale Focus filter calls across processes`.

### Task 4: App Group storage and migration

**Files:**

- Modify: `App/SelectionRepository.swift` (the App Group path `FocusSelection/selection.json`), `App/FocusSettings.swift` (the App Group suite for the focus length, the last refusal and the pending card; the onboarding flag stays in `UserDefaults.standard`), `App/FocusRuntime.swift` (the migration on launch, before the first read)
- Test: `SDKTests/FocusSettingsTests.swift`, a new `SDKTests/AppGroupMigrationTests.swift` (add it to `FocusSDKTests` in `project.yml`)

- [ ] **Step 1:** Write failing tests with temporary directories and suites: the migration order of spec decision 16 (length first, then selection); a failure at each step keeps the old value and retries; the app reads the App Group value, else the old one; no stored length writes `FocusLength.defaultMinutes`.
- [ ] **Step 2:** Implement. Keep the same keys and encodings. DEBUG fixtures keep their temporary storage.
- [ ] **Step 3:** `FocusSDKTests` green on the simulator. Commit `feat(app): move the focus selection and length to the App Group`.

### Task 5: Handler changes

**Files:**

- Create: `App/FocusServicesFactory.swift` or similar: the services that the handler needs, built without `FocusModel`, so that the extension can compile them in Task 7. Move `FocusServices` out of `App/FocusModel.swift` into its own file if the extension would otherwise compile `FocusModel`.
- Modify: `App/FocusFilterHandler.swift` (`calledAt` taken when `perform()` begins; the step 1 refusals: no selection gives `selection`, a selection with no allowed length gives `error`; the today snapshot write only in the app process; the Darwin notification `kr.donminzzi.focusStudy.control-changed` after a call that changed the stored state, not after a stale call), `App/FocusRuntimeHolder.swift`, `App/FocusStudyApp.swift` (refresh on the Darwin notification), `App/FocusStudyFilter.swift` (pass `calledAt`)
- Test: `SDKTests/FocusFilterHandlerTests.swift`

- [ ] **Step 1:** Write failing tests for the refusals, the stale result (no refusal stored), and the notification closure being called only after a change.
- [ ] **Step 2:** Implement.
- [ ] **Step 3:** `FocusSDKTests` green. Commit `feat(app): pass the call time and post control changes from the filter handler`.

### Task 6: Timer screen, completion card and Live Activity

**Files:**

- Modify: `App/FocusView.swift` (count-up after the base length and the short line that the session continues while the Focus is on), `App/FocusModel.swift` (the open state from the snapshot), `Shared/FocusActivityProjection.swift` and `Shared/FocusActivityContent.swift` (a count-up phase with no planned end, spec decision 25), the Activity views, `App/Debug/UITestFixtures.swift` (a fixture for an open session past its base length)
- Test: `CoreTests/FocusActivityTests.swift`, `UITests/FocusFlowTests.swift`

- [ ] **Step 1:** Write failing tests: the projection of an open session past its base length is a count-up with no end; the fixture screen shows the count-up and keeps the break controls and "집중 종료".
- [ ] **Step 2:** Implement, with copy from the `user-facing-copy` skill.
- [ ] **Step 3:** Tests green. Capture light, dark and the largest text size, and open the PR with `--no-merge` for the visual approval gate. Commit `feat(app): count up an open session after its base length`.

**Stop here and ask for the signing approval of Task 7.**

### Task 7: The `FocusStudyIntents` extension target (after the signing approval)

**Files:**

- Modify: `project.yml` (target `FocusStudyIntents`, type App Intents extension, bundle identifier `kr.donminzzi.focusStudy.intents`, embedded in the app; sources: `Shared/`, `Integration/`, `App/FocusStudyFilter.swift`, `App/FocusFilterHandler.swift`, the services file of Task 5, `App/SessionRecord.swift`, `App/FocusSettings.swift`, `App/SelectionRepository.swift`, `App/AuthorizationService.swift`, `Shared/TodaySnapshot.swift`), a new entitlements file with only `com.apple.security.application-groups` = `group.kr.donminzzi.focusStudy` and `com.apple.developer.family-controls`, `Package.swift` if a new file is excluded
- Create: `Intents/` with the extension entry point and an extension runtime that builds one engine, one selection repository and one `ModelContainer` for the process
- Test: unsigned device Release build of every target; `FocusSDKTests`

- [ ] **Step 1:** Confirm the approval covers the App ID, the profile and the entitlements. Then add the target and regenerate the project.
- [ ] **Step 2:** Build unsigned for the device in Release. Check with `nm` or the build log that the extension links no SwiftUI view and nothing of `Report/`.
- [ ] **Step 3:** If the build or the App Intents metadata processor refuses one type in two targets (spec decision 9), stop and raise it before moving the type.
- [ ] **Step 4:** Commit `feat(intents): add the App Intents extension for the Focus filter`.

### Task 8: Documentation

**Files:**

- Modify: the reconciliation sections listed in spec [Superseded lines](../specs/2026-11-16-focus-filter-extension-design.md#superseded-lines) (M4, M1, 2026-10-26, Live Activity, home widget designs), `AGENTS.md` (the architecture table row for `Intents/` and the moved values; the spec line status), `README.md` (the race-check file list and PASS lines, the new target in the Release build row), `docs/implementation-ledger.md`, `docs/notes/screen-time-device-matrix.md` (device steps 1 to 11 as unverified rows)
- Test: Trunk check on the changed files, internal links.

- [ ] **Step 1:** Write the reconciliation sections without rewriting earlier text.
- [ ] **Step 2:** `trunk check` on the changed files. Commit `docs: reconcile earlier designs with the Focus filter extension`.

## After the plan

The device steps of spec [Physical-device verification](../specs/2026-11-16-focus-filter-extension-design.md#physical-device-verification) run on the daily iPhone after a signed install, which needs its own announcement and approval. #152 closes when a device run shows a session that starts and ends with the app not running.
