# Navy focus room and colon mark

Date: 2026-11-20.
Status: implemented under [issue #189](https://github.com/AndrewDongminYoo/focus-study/issues/189); the captures wait for visual approval before the merge.
Source: the [decision of 2026-11-20 in issue #184](https://github.com/AndrewDongminYoo/focus-study/issues/184#issuecomment-7013218213), which owns the palette, the colon mark geometry and the excluded forms.
The palette is the one approved in issue #23 for the app icon.
This design changes no session, break, authorization, privacy or product rule.

## Contract

Decided on 2026-11-20:

1. While a focus session is active, the timer screen is a navy room: the background of the whole screen is navy `#1E2744`, text is cream `#FFF4E2`, and one amber `#F4A64A` dot precedes the status line.
   This holds for a countdown session and for the count-up of an open session that a Focus filter started.
2. The completion card uses the same room, and the colon mark replaces the checkmark icon.
   The colon mark is a cream ring over an amber dot, with the geometry of the icon v5 below and no background.
3. The idle screen, the onboarding and the break screen (the `waiting`, `onBreak` and `breakOver` phases) keep the system background.
4. The navy is the same in the light and the dark appearance; there is no darker navy for the dark appearance.
5. The background and the text colors change with a short crossfade of about 0.35 s.
   With Reduce Motion on, they change without animation.
   The controls follow the appearance at once, and a line that appears with the room (the status line, the completion text) shows in its room color from the start of the fade.
6. The room reads in the dark appearance, so that the glass and the solid buttons, the destructive end action, the error text and the status bar read light on navy.
   Every text and every secondary control in the room is cream, including the "제한할 앱" and the settings buttons on the completion card and the break request feedback.
   When the room ends, the window goes back to the system appearance.
   Sheets presented from the room (the end confirmation, and the settings from the completion card) follow the same dark appearance.
7. Dimmed text in the room is cream at 62 % opacity, which gives at least 4.5:1 on navy.
8. Existing accessibility identifiers stay: `countdown`, `sessionStatus`, `completion`, `releaseDelayNote`, `completionDismiss`, `breakStart`, `breaksLeft` and `end`.

Excluded, as in the decision: medals, ribbons, badges, stars or any shape that reads as a reward; a color or a shape that changes with the number of completed sessions; any animation that moves with Reduce Motion on.

Out of scope: the break screen, the home screen widget, the Live Activity, and the custom shield of issues #186 and #187.

## Colon mark geometry

The decision gives the mark as an SVG with this view box:

```plaintext
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 35 256 180">
<path fill="#FFF4E2" fill-rule="evenodd" d="M128 35.3a39.1 39.1 0 1 1 0 78.2a39.1 39.1 0 1 1 0 -78.2Z M128 57.4a17 17 0 1 0 0 34a17 17 0 1 0 0 -34Z"/>
<path fill="#F4A64A" d="M128 136.5a39.1 39.1 0 1 1 0 78.2a39.1 39.1 0 1 1 0 -78.2Z"/>
</svg>
```

The app draws it in its own bounds, from y 35.3 to y 214.7 (179.4 units high, 78.2 units wide).
The ring has an outer radius of 39.1 and an inner radius of 17, both centered 39.1 units below the top, with an even-odd fill.
The dot has a radius of 39.1 and is centered 140.3 units below the top.

## Evidence

- `App/FocusView.swift` (base `5ab9631`): the clock is drawn by `clock(_:countsDown:)` with the default foreground; the status line `sessionStatus` and the dimmed lines use `FocusTheme.Palette.secondaryText`; the completion card starts with `Label(…, systemImage: "checkmark.circle.fill")` in the accent color, with the identifier `completion`.
- `App/FocusView.swift`: the break screen shows when `model.current?.isPaused == true`; `Shared/ControlTypes.swift` defines `isPaused` as the `waiting`, `onBreak` or `breakOver` phase, and `FocusModel.isActive` as the `active` phase.
- `App/FocusView.swift`: during a session, the end confirmation is a sheet; on the completion card, the settings button and the everyday status row open sheets.
- `App/FocusTheme.swift`: `FocusTheme.Palette` reads `.label` and `.secondaryLabel`; `FocusSecondaryAction` tints with `primaryText`, which is white, not cream, in the dark appearance.
- `App/Assets.xcassets/ErrorText.colorset`: the light value `#B42318` is dark red, which does not read on navy; the dark value `#FFB4AB` does.
- `PendingFeedbackView` in `App/FocusView.swift` is a UIKit label; at base it used `.secondaryLabel`, which is gray, not cream, in the dark appearance.
  It shows in the room as the break request feedback, and on the break screen, which keeps the system color; so `BreakFeedback` takes the text color from its screen.
- An animation keyed to the room over the whole screen left the glass buttons of the completion card light lavender on navy, with cream text on them, still 3 s after the room appeared (iOS 26.5 simulator, 2026-11-20); with the animation on the background only, the same capture shows dark glass.
  So the text colors crossfade through an animation scoped to each `foregroundStyle` (`animation(_:body:)`, iOS 17), and nothing else in the screen is animated by the room.
- `UITests/FocusFlowTests.swift` reads `staticTexts["sessionStatus"].label` and `staticTexts["countdown"].label`, and finds `completion` through `descendants(matching: .any)`.
- `SDKTests/FocusRoomPaletteTests.swift` reads the colors `FocusNavy`, `FocusCream`, `FocusCreamSecondary` and `FocusAmber` from `App/Assets.xcassets`, which `project.yml` compiles into the test bundle, resolves each in the light and the dark appearance, and checks the WCAG contrast on navy: cream about 13.5:1, amber about 7.28:1, and secondary cream (composited over navy in sRGB) about 6.1:1.
- The dark system red `#FF453A` of the destructive "집중 종료" measures about 4.3:1 on navy by the same formula, below 4.5:1 for body text; so the end action keeps its destructive role and draws its text in the dark `ErrorText` (`#FFB4AB`, and `#FFDAD5` with increased contrast), which `SDKTests/FocusRoomPaletteTests.swift` checks at 4.5:1 or more on navy.
- `UITests/FocusFlowTests.swift` reads a background pixel beside the content in sRGB: navy for the countdown, the count-up and the completion card, and not navy on the idle screen after the end of a session and after the completion card is dismissed.
- Captures on the iOS 26.5 simulator (2026-11-20) of the countdown, the count-up, the completion card and the idle screen after it, in the light and the dark appearance, at the largest text size and with Reduce Motion on: the status bar reads light in the room in each, and the idle screen after the room is light in the light appearance and black in the dark one.
  They show end states only, so they do not show the crossfade.
- `[UNCERTAIN]` The status bar during a sheet presented from the room, and the room on an iOS 17 runtime; neither was captured.

## Amendment of 2026-11-23

The [screen redesign](2026-11-23-screen-redesign-design.md), approved under issue #228, replaces contract 3 once it is implemented: the idle screen and the break screen use `FocusCanvas` (`#F8F5F0` light, `#202C46` dark) instead of the system background.
The other contracts stay.
