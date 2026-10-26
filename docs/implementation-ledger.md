# SDD ledger — plan: docs/superpowers/plans/2026-10-26-focus-study.md

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

Final RED evidence: four new core regressions failed real assertions; startup UI test failed because recovery actions were absent. Fix pass: on unreadable metadata, clear the owned store and stop only registered focus.<UUID> activities under the lock; active metadata without its registration becomes interrupted, never re-shielded. Split startup runtime from selection/SwiftData, reconcile first, retain terminal until history saves, expose safe end/retry on initialization errors. Known durable ending reason/time is retained; if both durable writes failed, restart records an honest recovery interruption rather than inventing the lost cause/time.
Ruling: unreadable control metadata permits namespace-filtered cleanup of this app’s own focus registrations under the shared lock — no reliable current UUID can be decoded, and leaving the registration active would later falsely restore active UI after shield cleanup. Other activity namespaces are excluded.

Final: fixed stale-active-after-cleanup — two SessionControl restart regressions RED→GREEN. Final: fixed bootstrap recovery blocked by selection/history — two StartupRecovery tests and one UI recovery test RED→GREEN. Full suites: macOS 41/41 (32 core +5 SwiftData +4 report), Simulator 11/11 (5 SDK/repository +6 UI), all 0 failures. Two-process race PASS; unsigned Release generic iOS BUILD SUCCEEDED after fixes. No second reviewer requested; no deferred minor findings. Student-facing startup error copy omits App Group/README internals; developer details remain in documentation.

Final fix-pass edge: extended the cleanup-write regression to restoration after expiry; observed expired-vs-interrupted assertion fail. Registration-loss detection now precedes ordinary expiry so previously cleaned-up metadata cannot later become a normal completion. Without durable ending data, a missing registration is conservatively an interruption, including after expiry; physical-device registration lifecycle remains an explicit validation item.

Ruling: actual App interfaces use throwing SelectionRepository initialization plus read-only selection/counts, and AuthorizationProviding maps request failures to denied rather than exposing async throws — this keeps failed selection loads explicit and permission-denial UI deterministic. FocusModel is the planned UI coordinator; FocusRuntime/StartupRecovery isolate bootstrap safety. Report returns an in-extension ReportConfiguration containing UsageSummary plus token rows, and both ends use the same focus.today context string. Cost if these API choices are wrong: integration changes are needed, not data export or permissions expansion.

Final: Ruling: reviewer declined to assert physical-device authorization/shields/callback timing/report refresh/iOS17 runtime and DeviceActivity calendar interpretation — preserve these as required unverified device-acceptance items rather than claiming simulator proof; cost is runtime defects may remain until signed-device testing.
Final verification after complete fix pass: swift test 41/41, iOS Simulator 11/11, two-process race PASS, unsigned Release generic iOS BUILD SUCCEEDED. Xcode only emitted its AppIntents-metadata-skipped tooling warnings. No source/test failures remain. Task 1: complete; Task 2: complete; Task 3: complete; Task 4: complete; Task 5: automated portion complete, physical-device portion pending. Branch is intentionally retained without merge/push/CI/remote creation.

PR #1 review 4374580364 (P2): verified against 8b3cd11. Added FocusModel history-failure regression: RED lost active ID/early exit and left restrictions active. Split control and history failures; confirmed active control survives fetch failure while a real control read failure still invalidates it. GREEN FocusSDKTests 7/7 and SwiftPM 41/41. History dependency is injected at its storage boundary; no actual Screen Time requests occur in tests.

PR #1 review 4374580376 (P2): verified same-day reload retained child SwiftUI state (RED timeout). Extracted a shared report container so a synthetic stateful child exercises the same lifecycle as the real report; applying a separate .id(refreshID) recreates content on explicit reload without accessing usage data. GREEN full Simulator 14/14 (7 SDK/model/storage +7 UI); unsigned device Release BUILD SUCCEEDED.
