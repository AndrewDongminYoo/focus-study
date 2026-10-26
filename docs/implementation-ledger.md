# SDD ledger — plan: docs/superpowers/plans/2026-10-26-focus-study.md

2026-10-26: Local sequential implementation authorized. Project root: /Volumes/dongminyu/Development/01_personal/focus-study. Product name remains provisional.

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
