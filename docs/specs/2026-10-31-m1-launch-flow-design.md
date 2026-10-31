# M1: Launch flow and focus length

Date: 2026-10-31.
Status: design for approval. Milestone `M1` in the GitHub project "Focus Study".
Source: an operator brainstorm on 2026-10-31.
This document changes the product limits in [the 2026-10-26 design](2026-10-26-focus-study-design.md) only where it says so.
Where they differ, this document is the newer decision.

## Intent

The operator wants the app to feel like "open it and start focusing".
The focus timer is the main flow, and everything else is secondary.
Students must reach the start button in one step, and the screen must stay quiet.

Today the first screen is a long list.
That list mixes the timer, permission, selection, errors, history and the usage report.
After M1, a person with completed setup sees only the timer screen when the app opens.
A person without setup sees onboarding first.

## Roadmap context

The operator set this order: M1 launch flow and focus length, M2 break pass and deadline, M3 everyday schedule blocking layer, M4 stricter notification handling.
M2 to M4 get their own design documents.
M1 must not block them, but M1 does not build them.

## Goals

- When setup is complete, the app opens on the timer screen.
- When setup is not complete, the app opens on onboarding.
- The focus length is a personal setting from 25 to 50 minutes, in 5-minute steps.
- The session engine, storage validation, history and copy use the session's own length instead of a fixed 25 minutes.

## Non-goals in M1

- Breaks, pause, the 3-minute pass and the deadline rule (M2).
- The everyday schedule blocking layer (M3).
- Notification silencing (M4).
- The home-screen display name (issue #21 stays open).
- Any change to the default system shield (issue #40 stays a separate decision).

## Anti-goals (never, by operator decision)

- Rankings, leaderboards, or any comparison with other people.
- Friend presence or any feature that sends focus state off the device.
- Anything that makes the first-screen line "데이터는 기기에만 저장돼요" false.

## Decisions by the operator

### Launch routing

1. If setup is complete, show the timer screen.
2. If setup is not complete, show onboarding.
3. If Screen Time access is denied or revoked at any time, return to the permission step of onboarding.
4. The app shows the system permission prompt only on the first request. When a person comes back to the permission step, the step does not request again. It explains how to turn Screen Time access on manually in the system Settings app.
5. A person who wants to use the app without Screen Time access is not part of the main flow. The permission step has no exit to history or other screens.

### Timer screen (layout A)

The operator chose layout A from three mockups.

- The timer fills the screen. The center shows the configured length (for example `25:00`) and the "집중 시작하기" button.
- A one-line summary of the focus-session restriction (for example "앱 4개 · 웹사이트 2개 제한") is under the button.
- The top-left corner has "제한할 앱". It opens the focus-session selection.
- The top-right corner has a settings button. It opens settings.
- The bottom has one line, "오늘 집중 N분 · N회". It opens today's history.
- Only sessions that complete count toward that total.

### Focus length

- The focus length is a personal setting, not a per-session choice.
- Allowed values: 25, 30, 35, 40, 45 and 50 minutes.
- Settings holds the control.

### Onboarding

The operator decided that a person with no settings goes through onboarding and sees the timer screen only after setup.

## Decisions by Claude (the operator can change them)

- "Setup is complete" means all three conditions are true:
  - Screen Time access is approved.
  - The focus-session selection has at least one app or website.
  - The person has finished onboarding once. The app stores this as a flag in `UserDefaults` when the last onboarding step ends.
- Without the flag, saving a selection in step 3 would already satisfy the first two conditions and skip step 4. The flag prevents that, and it also makes a relaunch in the middle of onboarding resume at the first unfinished step.
- Migration: on the first launch of the M1 build, if access is approved and a selection exists, the app sets the flag. An existing user therefore skips onboarding after the update.
  - Reconciliation (2026-10-31, final review): the shipped migration reads only the selection; `FocusSettings.migrateIfNeeded(hasSelection:)` is the authority, pinned by `testExistingSelectionMigratesEvenWhenFirstAccessReadIsNotApproved`. The one-time read of access at launch could not be retried, so a wrong read would keep an existing user in onboarding. A selection can exist at that point only from a pre-M1 build, because launch runs the migration before any onboarding screen can save one. An existing user without access still sees the permission step, through the route rule below.
- If access is revoked and then approved again, the flag is still set, so the app returns straight to the timer screen. Only the permission step is shown again.
- Onboarding steps, in this order:
  1. Intro: what the app does, and "데이터는 기기에만 저장돼요". This replaces the "시작하기 전에" section on today's first screen.
  2. Screen Time permission, with the reason and a "권한 허용하기" button.
  3. Choose apps and websites, with the existing validation (at least 1, at most 50 of each).
  4. Choose the focus length. 25 minutes is preselected.
- Each onboarding step is one screen. The person can go back one step.
- Onboarding starts at the first step whose data is missing.
- "Completed" in the today total means sessions that ended with `.expired`, the same rule that `completedSessionID` uses today.
- `AuthorizationService` keeps its one-request limit (the `individualAuthorizationRequested` key and the `status == .notRequested` guard). The returning permission step uses the existing `.denied` state to show the Settings guide instead of the request button.
- A changed focus length applies from the next session. A running session keeps its length.
- The usage report moves off the first screen. Today's history screen links to it.
- The focus length is stored in the app's `UserDefaults`. Only the app reads it. The Monitor extension does not need it, because each session stores its own `expiresAt`.
- While a session is active, the timer screen shows only the remaining time, a short status line, and the existing "중도 종료" button with its confirmation. M2 renames that button and adds breaks.
- No copy may state "25분" when the configured length is different.
  - This applies to the start button, the completion state, the purpose line and the history reason labels.
  - The builder writes the length-aware copy with the `user-facing-copy` skill, in 해요체.
  - The current label "25분 만료" (issue #35) must at least become length-aware in M1. Issue #35 keeps the wording decision.

## Constraints

- iOS 17 or later, SwiftUI, Observation, SwiftData, iPhone only, portrait only (PR #45).
- Keep the architecture in `AGENTS.md`. `Shared/` must not import Screen Time SDK modules.
- `project.yml` is the source of the Xcode project. Regenerate with `xcodegen generate`. Keep `Package.swift` aligned when files are added under `App/`.
- Keep the accessibility identifiers that `UITests/FocusFlowTests.swift` uses. When a screen moves, the builder updates the tests to the new path and keeps the behavior that each test checks.

## Code that assumes 25 minutes today

| Location                             | Current behavior                                                                                      |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| `Shared/ControlTypes.swift:14`       | `ControlSession.init` sets `expiresAt` to `startedAt + 1500`.                                         |
| `Shared/SharedControlStore.swift:35` | Stored sessions are rejected unless `expiresAt - startedAt` is 1500 seconds.                          |
| `Shared/TimeRules.swift:3`           | `remaining` is capped at 1500 seconds.                                                                |
| `App/FocusModel.swift:40`            | With no session, `remaining` is 1500.                                                                 |
| `App/SessionRecord.swift:15`         | A record's duration is capped at 1500 seconds.                                                        |
| `App/FocusView.swift`                | Copy says "25분" in the start button, completion state, purpose line and the `.expired` reason label. |

Required changes:

- A session takes its length when it is created, and stores `expiresAt` from it.
- Storage validation accepts a stored session only if its length is one of the six allowed values.
  A session stored by the current build (1500 seconds) stays valid.
  The schema version stays `1`, because the JSON shape does not change.
- `remaining` and the record duration are capped by the session's own length, not by 1500.
- With no session, the timer shows the configured length.
- `SessionRecord` already stores `startedAt` and `expiresAt`, so the SwiftData schema does not change.
- `Integration/ScreenTimeAdapters.swift` registers the monitor from the session's `start` and `end`. It needs no change, because 25 minutes or more is above the DeviceActivity minimum interval [UNCERTAIN: the minimum is believed to be 15 minutes; verify against the SDK].

## Verification

Follow `AGENTS.md` and [README verification](../../README.md#실행과-검증).

- `Shared/` changes:
  - Run `swift test`.
  - Run the separate-process race check.
  - Add host tests for the allowed lengths and for the rejection of other lengths.
  - Add a host test that a stored 1500-second session still loads.
- `App/` changes:
  - Run the SDK and UI tests.
  - Add DEBUG fixture modes for "no setup" (onboarding) and for a non-default length (for example 40 minutes).
  - Add UI tests for routing, onboarding order, back navigation, the length setting, and the length-aware copy.
- Target and fixture wiring: run the unsigned device Release build.
- Simulator results do not prove real Screen Time behavior.
  - The exact Settings path for turning Screen Time access back on is not verified on a device (issues #11 and #38).
  - Until a device check records that path, the Settings guide must not state a menu path as fact. It can open the app's settings page with `UIApplication.openSettingsURLString` and keep the path text generic [UNCERTAIN].
  - Do not build a private Screen Time deep link (decision in issue #38).

## Left to the builder

- Visual details of the timer screen, onboarding and settings: typography, spacing, colors, and motion that respects Reduce Motion.
- The settings screen layout and the control for the length (for example a picker or a stepper).
- How today's history and the usage report are presented, as long as the timer screen shows only the one-line summary.
- Exact copy, written with the `user-facing-copy` skill in 해요체.
- Updates to `AGENTS.md` and the 2026-10-26 design document so that they no longer state a fixed 25-minute session.
