# Implementation ledger

Plan: [FocusStudy implementation](plans/2026-10-26-focus-study.md).
This is a chronological record of decisions and observations from the original implementation and PR follow-up.
Test totals, signing observations, and branch/remote statements describe those runs, not the current checkout.
Use the [verification record](notes/screen-time-device-matrix.md) for acceptance status and [README](../README.md#실행과-검증) for commands.

2026-10-26: Local sequential implementation authorized. Product name remains provisional.

Ruling: Use this fresh isolated repository on feature/focus-study rather than another worktree — user selected this new project directory; no existing user repository is touched.
Ruling: Add a Foundation-only Swift package for unsigned macOS core tests alongside three iOS product targets — simulator access is restricted in the initial sandbox; iOS build and UI tests will still be attempted.
Pre-flight: Task 1 selection validation feeds Task 2 start; Task 2 terminal metadata feeds Task 3 SwiftData history; Task 4 Report remains independent. No incompatible interfaces.

Task 1: SelectionTests RED 5 tests / 4 expected failures (empty, categories, 51 app/web); accept case passed.

Task 2: RED compile contract failed on absent SessionControl/ControlStore APIs before implementation (per plan). Ruling: ControlStore callback exposes explicit load/save under a single lock rather than auto-saving inout envelope — preparing and ending must be durable before SDK side effects; an end-of-closure save cannot meet that contract. SDK token storage stays outside Foundation package.

Task 2: GREEN swift test 25/25 tests, 0 failures. Foundation engine and store verified; real Screen Time adapters not yet executed.

Task 3/4: RED missing TimeRules/SessionHistory/UsageSummary before implementation. First GREEN found a test fixture defect: retry test created two UUIDs; corrected to retry the same session. No production change needed.

UI RED: built unsigned iOS targets successfully, then denied-permission UI test failed (settings button absent) against placeholder screen. Implemented real services and DEBUG-only fixture UI. All fixture startup branches avoid AuthorizationCenter/ManagedSettings/DeviceActivity calls.
Ruling: Report v1 shows total daily current-device usage without exporting per-app data — sufficient first usage report; per-app breakdown remains future work, not required for sessions. DeviceActivityFilter devices:nil is current-device per Apple docs.

Ruling: supersede the earlier total-only report ruling: include token-labeled app/web breakdown inside Report memory to better support identifying distractions; no transport or persistence added.
Ruling: installed SDK adds approvedWithDataAccess on iOS 26.4; recognize it as authorized without requesting broader authorization or reading raw activity data. Real start gates read AuthorizationCenter fresh instead of a queued observation snapshot.
Ruling: ceil the schedule end to whole seconds (less than 1s overhead) — otherwise fractional session expiry could cause the only end callback to be rejected as early. Control expiry remains exactly 1500s.
UI run 1: 4/5 passed; denied test failed because settings Link/report row were offscreen or queried as buttons. Adjusted test to scroll and find settings by identifier without assuming its accessibility role.

Task 1/2/3/4 integration: unsigned Simulator build succeeded. swift test GREEN 37/37 (28 core + 5 SwiftData + 4 report). iOS Simulator GREEN 10/10 (5 SDK/repository + 5 UI); actual Screen Time requests/restrictions were not run. Two-process race helper PASS. All four implementation tasks have executable coverage; device acceptance remains blocked.

Regression RED: testRegistrationFailureNeverShowsActiveAndCanRetry failed its new selection-disabled assertion. Fixed UI to block editing while state is uncertain; softened error text so it does not claim an unverified cleanup. SwiftData explicitly disables CloudKit.

Regression GREEN: full iOS Simulator suite 10/10 passed, 0 failures, including error-state selection lock and retry. Unsigned Release generic iOS build succeeded; no fixture implementation in Release. Added supported orientations to address iPad packaging warning.
Task 5: automated acceptance complete; physical-device acceptance blocked on agreed identifiers/Team/development signing and device-owner consent. No actual restrictions were applied.

Final review (independent, afbee63): two Important findings accepted. (1) Cleanup + failed writes or transient read failure can leave active metadata that is later trusted. (2) Bootstrap depends on selection/history initialization, blocking recovery and early exit if those stores fail. No Critical findings; no minor findings. Beginning one TDD fix pass.

Final RED evidence: four new core regressions failed real assertions; startup UI test failed because recovery actions were absent.
Fix pass: on unreadable metadata, clear the owned store and stop only registered `focus.<UUID>` activities under the lock; active metadata without its registration becomes interrupted, never re-shielded.
Split startup runtime from selection/SwiftData, reconcile first, retain terminal until history saves, expose safe end/retry on initialization errors.
Known durable ending reason/time is retained; if both durable writes failed, restart records an honest recovery interruption rather than inventing the lost cause/time.
Ruling: unreadable control metadata permits namespace-filtered cleanup of this app’s own focus registrations under the shared lock — no reliable current UUID can be decoded, and leaving the registration active would later falsely restore active UI after shield cleanup. Other activity namespaces are excluded.

Final: fixed stale-active-after-cleanup — two SessionControl restart regressions RED→GREEN. Final: fixed bootstrap recovery blocked by selection/history — two StartupRecovery tests and one UI recovery test RED→GREEN. Full suites: macOS 41/41 (32 core +5 SwiftData +4 report), Simulator 11/11 (5 SDK/repository +6 UI), all 0 failures. Two-process race PASS; unsigned Release generic iOS BUILD SUCCEEDED after fixes. No second reviewer requested; no deferred minor findings. Student-facing startup error copy omits App Group/README internals; developer details remain in documentation.

Final fix-pass edge: extended the cleanup-write regression to restoration after expiry; observed expired-vs-interrupted assertion fail. Registration-loss detection now precedes ordinary expiry so previously cleaned-up metadata cannot later become a normal completion. Without durable ending data, a missing registration is conservatively an interruption, including after expiry; physical-device registration lifecycle remains an explicit validation item.

Ruling: actual App interfaces use throwing SelectionRepository initialization plus read-only selection/counts, and AuthorizationProviding maps request failures to denied rather than exposing async throws — this keeps failed selection loads explicit and permission-denial UI deterministic. FocusModel is the planned UI coordinator; FocusRuntime/StartupRecovery isolate bootstrap safety. Report returns an in-extension ReportConfiguration containing UsageSummary plus token rows, and both ends use the same focus.today context string. Cost if these API choices are wrong: integration changes are needed, not data export or permissions expansion.

Final: Ruling: reviewer declined to assert physical-device authorization/shields/callback timing/report refresh/iOS17 runtime and DeviceActivity calendar interpretation — preserve these as required unverified device-acceptance items rather than claiming simulator proof; cost is runtime defects may remain until signed-device testing.
At the end of the local fix pass, the previously recorded suites, process race, and unsigned Release build passed.
Xcode emitted AppIntents-metadata-skipped tooling warnings.
The branch was retained locally at that stage; the following entries record subsequent PR review work.

PR #1 review 4374580364 (P2): verified against 8b3cd11. Added FocusModel history-failure regression: RED lost active ID/early exit and left restrictions active. Split control and history failures; confirmed active control survives fetch failure while a real control read failure still invalidates it. GREEN FocusSDKTests 7/7 and SwiftPM 41/41. History dependency is injected at its storage boundary; no actual Screen Time requests occur in tests.

PR #1 review 4374580376 (P2): verified same-day reload retained child SwiftUI state (RED timeout). Extracted a shared report container so a synthetic stateful child exercises the same lifecycle as the real report; applying a separate .id(refreshID) recreates content on explicit reload without accessing usage data. GREEN full Simulator 14/14 (7 SDK/model/storage +7 UI); unsigned device Release BUILD SUCCEEDED.

## Backlog follow-up: 2026-10-26

Working tree based on `c25f60c`, before a new commit.
Issues #6, #7, and #15 add verification paths rather than claiming new physical-device evidence.

- #6: `SharedControlStoreTests.testAtomicReplacementFailurePreservesFileAndAllowsRetry` uses an immutable destination to make the production atomic write fail, then checks original bytes, a new lock acquisition, and a successful retry.
  Removing the filesystem failure condition produced the expected throw/byte/identity assertion failures; restoring it passed.
  The production store implementation did not need a change.
- #7: `Presentation/UsageSummarySection` preserves the existing report rendering and is shared with synthetic DEBUG state fixtures.
  Three new UI tests failed against the old host/fixture rendering, then passed with waiting, unavailable, and actual-zero states.
  Captures exposed an `EmptyView` fixture that collapsed the report area; a transparent content view preserves its geometry, and the affected test and capture were checked again.
  The host does not receive actual report data or infer a system loading signal.
- #15: the opt-in DEBUG monitoring wrapper registers through the real adapter before throwing a one-shot error; stored stale activity names are replayed through the same session engine used by Monitor.
  SDK tests use real file locking and the session engine with an observed SDK boundary, not real Screen Time calls.
  Omitting the injected error and replaying the current activity instead of the saved activity both produced assertion failures; the restored implementation passed.
  The underlying registration-error case also verifies that a genuine SDK error is preserved and consumes the injection.
- #8/#9: the operator selected Team `393JTTV68D` and the `kr.donminzzi.focusStudy` prefix.
  Updated the XcodeGen source, related configuration, generated project, and spelling dictionary.
  The source and generated project use the same App/Monitor group, and Report has no App Group entitlement.
  iOS 17 device coverage remains unavailable in this run.

Final local checks: `swift test -j 2` passed 42 XCTest cases (33 core, 5 history, 4 report); the separate-process helper printed `PASS: stale A cannot clear B`.
The full iOS 27.0 Simulator scheme passed 10 SDK tests and 10 UI tests; the final waiting-fixture geometry change then passed its targeted UI test.
The unsigned generic-device Release build succeeded.
A binary-content check rejected the Debug app as a negative control and found none of the checked diagnostic/fixture markers in the Release App, Monitor, and Report executables.
These checks do not establish physical Screen Time behavior or iOS 17 runtime support.

The signed Debug build without provisioning updates failed because the available wildcard profile lacks Family Controls (Development) and, for App/Monitor, App Groups.
At that verification boundary, no physical-device installation, launch, authorization request, or restriction had been performed.
Developer-portal registration/profile changes remain a separate authorization boundary.

Oracle retrieval was `[PARTIAL]`: the canonical wiki project identity could not be verified, so no precedent was retrieved or used.

## Development provisioning and installation: 2026-10-26

After explicit operator approval for development-profile creation and updates, `xcodebuild build -allowProvisioningUpdates` succeeded for Team `393JTTV68D` and the three `kr.donminzzi.focusStudy` product identifiers.
Strict signature verification passed for the app and embedded extensions.
Decoded signed entitlements and embedded profiles confirmed the requested identifiers, Family Controls development capability, target-device eligibility, and App/Monitor-only App Group access.
An entitlement-validation negative control rejected missing Family Controls before the real target checks passed.

Installed the Debug app with `devicectl device install app` on the operator's iPhone 16 Pro.
A subsequent exact-bundle-ID query confirmed version `0.1`, build `1` on the device.
The app was not launched; no Screen Time authorization request or real restriction was applied.
Physical behavioral acceptance and distribution entitlement review remain open.
The installed build comes from the local working tree based on `c25f60c`, not a newly committed release.

## Category selection and copy correction: 2026-10-26

The operator confirmed authorization, selection, and actual app shielding on the installed build, then reported that selecting every item in a category prevented saving.
Supplied screenshots also establish report rendering with actual app usage; they do not establish website shielding, expiry, or report refresh behavior.

Five new repository tests use synthetic Codable tokens rather than private device tokens.
Before the fix, four failed: new and reopened selections did not enable category expansion, and expanded selections were rejected as `categoriesUnsupported`.
The existing collapsed-category rejection still passed.
The repository now opens the picker with `includeEntireCategory: true`, preserves individual application and website tokens, removes category policy tokens before persistence, and validates each individual count before writing.
The tests check stored tokens, reopening, the 50/51 boundary, and unchanged file bytes and selection after rejection.
This follows Apple's [category expansion initializer](<https://developer.apple.com/documentation/familycontrols/familyactivityselection/init(includeentirecategory:)>).
The operator subsequently confirmed that category selection saves successfully on the updated device build on 2026-10-27.

Applied the requested `user-facing-copy` workflow with a default warm voice because no project voice line exists, while retaining the existing formal register.
Kept selection limits, delayed restriction removal, browser limitations, permission purpose, and retry actions.
Dropped the following facts or explanations from UI copy:

- Internal report-extension placement: implementation detail with no user action.
- Study-proof and continuous-blocking disclaimers: not needed beside the timer; the design contract retains these limits.
- URL-path terminology: replaced with whole-website restriction wording.
- Explicit blank-versus-zero explanation: replaced with a conditional reload instruction; real zero remains a separate rendered state.
- Individual token persistence and storage internals: replaced with category-selection support and app-data wording.
- Repeated reflection prompts: shortened to the next selection action.

The full simulator scheme passed 15 SDK tests and 10 UI tests after the repository and copy changes.
The empty-report screenshot shows the revised text without clipping.
Other exported captures were incomplete, so they are not treated as visual proof.
`trunk check --no-fix` passed for 30 modified files, the local documentation checker passed 63 links with missing-file and missing-anchor negative controls, and `git diff --check` passed.

The signed Debug build succeeded using the existing development profiles, and strict signature verification passed.
Installed it over the existing iPhone app without uninstalling or launching it; an exact bundle-ID query confirmed version `0.1`, build `1`.
The device now retains this working-tree Debug build, including the category-selection fix and revised copy.
The targeted waiting-report test then passed again; its recaptured screenshot shows the revised instruction, preserved empty report area, and reload button without clipping.

## PR handoff: 2026-10-27

The operator confirmed that category selection now saves successfully on the installed build.
They also reported an authorization-revoked history entry without manually revoking permission.
The cause and any relation to app termination or an install-over-existing update remain unverified.
The operator explicitly deferred that investigation, so this PR does not change authorization classification or historical records.
The displayed history time is the session start time, not the observed interruption time.
