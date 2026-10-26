# SDD ledger — plan: docs/superpowers/plans/2026-10-26-focus-study.md

2026-10-26: Local sequential implementation authorized. Project root: /Volumes/dongminyu/Development/01_personal/focus-study. Product name remains provisional.

Ruling: Use this fresh isolated repository on feature/focus-study rather than another worktree — user selected this new project directory; no existing user repository is touched.
Ruling: Add a Foundation-only Swift package for unsigned macOS core tests alongside three iOS product targets — simulator access is restricted in the initial sandbox; iOS build and UI tests will still be attempted.
Pre-flight: Task 1 selection validation feeds Task 2 start; Task 2 terminal metadata feeds Task 3 SwiftData history; Task 4 Report remains independent. No incompatible interfaces.

Task 1: SelectionTests RED 5 tests / 4 expected failures (empty, categories, 51 app/web); accept case passed.

Task 2: RED compile contract failed on absent SessionControl/ControlStore APIs before implementation (per plan). Ruling: ControlStore callback exposes explicit load/save under a single lock rather than auto-saving inout envelope — preparing and ending must be durable before SDK side effects; an end-of-closure save cannot meet that contract. SDK token storage stays outside Foundation package.

Task 2: GREEN swift test 25/25 tests, 0 failures. Foundation engine and store verified; real Screen Time adapters not yet executed.
