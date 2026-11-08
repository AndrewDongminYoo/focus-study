# Everyday status on the timer screen

## Contract

Record the decision of [issue #70](https://github.com/AndrewDongminYoo/focus-study/issues/70): the person can see on the timer screen that the everyday layer still blocks after a focus session ends.
The decisions were made on 2026-11-08 and amend two lines of the [M3 design](2026-11-01-m3-schedule-layer-design.md): the non-goal "A new element on the timer screen." and the placement rule "The timer screen does not change."
Primary sources are the issue, the M3 design, `EverydayStatus` in `Shared/ControlTypes.swift`, `EverydaySettingsModel.statusLine` in `App/EverydaySettingsModel.swift`, and the completion note of [PR #77](https://github.com/AndrewDongminYoo/focus-study/pull/77).
This document changes no code; a separate implementation issue follows it.

## Behavior

- The idle timer screen (the focus-start screen) shows a one-line everyday status row below the restriction summary (`restrictionSummary`, "앱 N개 · 웹사이트 N개 제한") and above the today summary (`todaySummary`).
- Tapping the row opens the settings sheet's everyday settings screen, the same destination as the settings row `everydayRow`.
- The row shows whenever the state below calls for it, whether or not a session just ended. No "just ended" state is added.
- No row shows while a focus session is in progress; the in-progress timer screen stays as it is.
  No row shows on the break screen either, because a break lifts both layers.
- The copy follows `FocusModel.everydayStatus`:
  - `issue == nil`, the layer is enabled and `blocksNow == true`: `매일 제한 중 · HH:MM까지 ›`, where HH:MM is `nextChange` in the clock format of `EverydaySettingsModel.statusLine`.
    Without `nextChange`: `매일 제한 중 ›`.
  - `issue == nil` and the layer is off, has no schedule, or `blocksNow == false`: no row.
    The idle screen shows no "HH:MM부터" line.
  - Any `issue` (`unreadable`, `registrationFailed`, `notApplied`, `notCleared`, `unchecked`): `매일 제한을 확인해 주세요 ›`.
    A state that the app could not confirm never shows as released.
    The settings screen keeps its detailed status line for the cause.
  - No status yet (`everydayStatus == nil`): no row.
- While the completion card shows (`completedSessionID != nil`), the same row follows the same rules below the release-delay note (`releaseDelayNote`, "제한이 풀리기까지 조금 걸릴 수 있어요."), so the person does not read that note as a promise that every restriction lifts.
- The row describes only the everyday layer.
  The focus restriction stays in the restriction summary and the in-progress screen, so a state where both layers block needs no separate copy.
- The row never says which restriction blocks a specific app.
  It states only the everyday layer's own state and planned end.
- The row's time is the schedule's planned change, as in settings, not a confirmed application or release.
- The row changes at a boundary while the app stays open on the idle screen or the completion card.
  While the idle screen or the completion card shows, whether or not the row shows, the timer screen reads the status again with `EverydaySettingsModel.followStatus`, as the settings row does, because `tick()` does not refresh `everydayStatus`.
  So, while `issue == nil`, the row follows each change of `blocksNow`: it appears when `blocksNow` becomes `true`, for example when the range starts or a window ends, and it disappears when `blocksNow` becomes `false`, for example when a window starts or the range ends.
  At a boundary where `blocksNow` stays `false`, the row does not appear: for example, a window that starts at the range start (the range 08:00-18:00 with the 등교 window 08:00-08:30), or a window that ends when the next window starts (12:00-13:00 and 13:00-13:30).
  An `issue` that `statusReadDelay` retries gets its one retry read.
  One exception: a read that times out on the lock keeps the passed `nextChange` and sets `unchecked`, so when a boundary read and its retry both time out, `followStatus` schedules no further read, and the row stays on `매일 제한을 확인해 주세요 ›` until the next refresh of the timer screen, such as when the app becomes active again or the day or time zone changes; the settings row behaves the same way, and the row never shows a release it did not read.
- The settings row and its status line do not change.

## Verification and boundaries

The implementation adds the accessibility identifier `everydayStatusRow` to the row and keeps every existing identifier.
Synthetic UI tests with `--everyday-fixture blocking` check that the row is present on the idle screen and opens the everyday settings screen, and that it is absent during a session and on break.
A launch with the `expiring` mode and `--everyday-fixture blocking` checks that the row shows below `releaseDelayNote` on the completion card and opens the everyday settings screen.
Three launches check that the row is absent while `issue == nil`:

- without the everyday fixture, for a layer with no schedule;
- with `--everyday-fixture preview`, for an enabled layer that does not block now, because the fixture's noon calendar puts launch inside the 12:00–13:00 lunch window;
- with a new DEBUG fixture value `--everyday-fixture off`, which stores the `preview` schedule with `enabled == false`, for a layer that is off.

An SDK test of the copy function covers every state of the Behavior list: no status, no schedule, a disabled layer, `blocksNow == false`, blocking with and without `nextChange`, and each `issue`.
The existing `statusReadDelay` tests in `SDKTests/EverydaySettingsModelTests.swift` cover the boundary read; the implementation review confirms that the idle screen and the completion card run `followStatus` for the status the row shows.
`testTimerScreenIsUnchangedWithTheLayerOn` in `UITests/FocusFlowTests.swift` asserts the old contract and changes with the implementation.
The doc comment of `FocusModel.everydayStatus` ("The timer screen does not show it.") states the old contract and changes with the implementation.
Review the row at the largest Dynamic Type size and in light and dark appearance.
No shared engine behavior, storage, new dependency, real authorization, real shield or device installation is in scope.
Simulator results cannot establish real Screen Time behavior; it stays unverified until a device check.
