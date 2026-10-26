# SDD ledger — plan: docs/superpowers/plans/2026-10-26-focus-study.md

2026-10-26: Local sequential implementation authorized. Project root: /Volumes/dongminyu/Development/01_personal/focus-study. Product name remains provisional.

Ruling: Use this fresh isolated repository on feature/focus-study rather than another worktree — user selected this new project directory; no existing user repository is touched.
Ruling: Add a Foundation-only Swift package for unsigned macOS core tests alongside three iOS product targets — simulator access is restricted in the initial sandbox; iOS build and UI tests will still be attempted.
Pre-flight: Task 1 selection validation feeds Task 2 start; Task 2 terminal metadata feeds Task 3 SwiftData history; Task 4 Report remains independent. No incompatible interfaces.

Task 1: SelectionTests RED 5 tests / 4 expected failures (empty, categories, 51 app/web); accept case passed.
