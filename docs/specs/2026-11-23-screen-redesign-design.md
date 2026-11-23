# Home, break wait and focus screen redesign

Date: 2026-11-23.
Status: approved on 2026-11-23 under [issue #228](https://github.com/AndrewDongminYoo/focus-study/issues/228); no code implements it yet.
Source: three Figma mock frames: node `3:93` (idle screen), node `3:105` (break wait) and node `3:99` (timer screen of an active session).
This design changes no session, break, authorization, privacy or product rule.

It amends two earlier decisions:

- The [navy focus room design](2026-11-20-navy-focus-room-design.md), contract 3: the idle screen and the break screen no longer keep the system background (see contract 2 below).
- The UI accent pair approved in issue #23: the light accent `#A85F10` becomes `#AE5519` for fills and `#985019` for text (see contract 3 below).
  The dark accent `#F4A64A` and the icon palette do not change.

## Decisions of 2026-11-23

1. Scope: the idle screen (home), the break screen and the timer screen of an active session.
   The everyday settings screen has its own redesign frame and its own issue; this spec does not cover it.
2. Palette: the approved navy `#1E2744`, cream `#FFF4E2` and amber `#F4A64A` stay.
   Where a mock color is close to one of them, the approved color is used; colors that the mock adds for new surfaces become new tokens.
3. Typeface: the system font stays.
   The mock's Noto Sans KR and Inter are not bundled; sizes and weights map to Dynamic Type text styles.
4. Dial: the amber dot on the ring shows progress (rules in "Dial").
5. Light accent: the mock values `#AE5519` and `#985019` replace `#A85F10`, because `#A85F10` measures 4.48:1 on the new light background `#F8F5F0`.
6. Dark appearance of the idle and the break screens: a dark navy background `#202C46`.

## Scale

The frames are 603 × 1311, which is the 402 × 874 pt screen of iPhone 16 Pro and iPhone 17 Pro at 1.5×.
Every size in this spec is the mock value divided by 1.5, rounded to the nearest point.

## Contract

1. All three screens use one layout, from top to bottom:
   a header row (a label on the leading side and a pill or buttons on the trailing side), a two-line title, the dial with a label, the clock and a status line inside it, one line below the dial, and an action area at the bottom.
2. Backgrounds:
   - The timer screen of an active session and the completion card keep the navy room (`FocusNavy` in both appearances), as in the navy focus room design.
   - The idle and the break screens use `FocusCanvas`: `#F8F5F0` in the light appearance and `#202C46` in the dark appearance.
   - In the dark appearance, `#202C46` and `#1E2744` measure 1.06:1, so the background does not visibly change when a session starts; the header, the title and the dial colors still change.
3. Accent: `AccentColor` becomes `#AE5519` in the light appearance and keeps `#F4A64A` in the dark appearance.
   A new `AccentText` is `#985019` in the light appearance and `#F4A64A` in the dark appearance; it colors small accent text (the dial status line, the pill text, the everyday status row and the break wait notes).
   This changes every app view that reads the accent, including settings, onboarding and the history sheet.
   The `FocusActivity` extension (home screen widget and Live Activity) does not compile `App/Assets.xcassets` and does not change.
4. Text:
   - On `FocusCanvas` and on light cards, primary text is `FocusNavy` in the light appearance and `FocusCream` in the dark appearance.
   - Secondary text is `#626D7E` in the light appearance and `FocusCreamSecondary` in the dark appearance.
   - In the room, text stays as the navy focus room design says: cream, and cream at 62 % for dimmed text.
     The mock's blue-gray dimmed text (`#CCD4E3`, `#B9C3D7`) is not used.
5. The destructive "집중 종료" keeps `ErrorText`.
6. Existing accessibility identifiers and the accessibility labels that `UITests/FocusFlowTests.swift` reads stay (see "Identifiers").
7. Reduce Motion: the dot moves only once per minute in a focus session, and does not animate between positions (see "Dial").
8. Every dot before a status text ("●" in the mock) is a separate `Circle`, hidden from VoiceOver, as the status line is drawn today; no label contains "●".

Excluded, as in the navy focus room design: any shape that reads as a reward, and any color or shape that changes with the number of completed sessions.

## Tokens

| Token                     | Light     | Dark                  | Use                                                     |
| ------------------------- | --------- | --------------------- | ------------------------------------------------------- |
| `AccentColor`             | `#AE5519` | `#F4A64A`             | Fills and tints; the start button with a white label    |
| `AccentText` (new)        | `#985019` | `#F4A64A`             | Small accent text                                       |
| `FocusCanvas` (new)       | `#F8F5F0` | `#202C46`             | Background of the idle and the break screens            |
| `FocusCard` (new)         | `#FFFFFF` | `#27334E`             | Cards on the canvas and in the room                     |
| `FocusPill` (new)         | `#F2E5D5` | `#2B3650`             | Status pill in the header; the room uses the dark value |
| `FocusChip` (new)         | `#F2E5D5` | `#37435C`             | The "N번 남음" chip; the room uses the dark value       |
| `FocusCreamFill` (new)    | `#F7DFC0` | `#F7DFC0`             | The break button in the room, with a `FocusNavy` label  |
| `FocusSecondaryInk` (new) | `#626D7E` | `FocusCreamSecondary` | Secondary text on the canvas and on cards               |

The room uses the dark values of `FocusCard`, `FocusPill` and `FocusChip` in both appearances, as it does for its background.

## Dial

The dial is 276 pt square at the default text size, centered, and drawn in code (no image asset).
It has, from the outside in:

- a band disc, radius 136.7 pt;
- an inner disc, radius 110.7 pt, with a 0.7 pt stroke;
- 60 ticks between radius 119.3 and 128.7 pt (major) or 123.3 and 128.7 pt (minor): every fifth tick is major, 1.7 pt wide; the others are 1 pt wide;
- one dot, 6.7 pt in diameter, centered on the inner circle (radius 110.7 pt), at 12 o'clock when its progress is 0.

| Part         | Light (idle, break) | Dark (idle, break) and room |
| ------------ | ------------------- | --------------------------- |
| Band disc    | `#F1E6D9`           | `#232F4A`                   |
| Inner disc   | `#FBF8F2`           | the screen background       |
| Inner stroke | `#DFC7AF`           | `#435069`                   |
| Minor ticks  | `#D7BDA5`           | `#48536C`                   |
| Major ticks  | `#B96326`           | `#B7C0D4`                   |
| Dot          | `AccentColor`       | `FocusAmber`                |

The dot moves clockwise by its progress, from 0 at 12 o'clock to 1 at a full turn:

| Screen state             | Progress                           |
| ------------------------ | ---------------------------------- |
| Idle, completion card    | 0 (the dot does not move)          |
| Countdown session        | elapsed time ÷ focus length        |
| Open session (count-up)  | (elapsed time mod 60 min) ÷ 60 min |
| Break wait (`waiting`)   | elapsed wait ÷ wait length         |
| On break (`onBreak`)     | elapsed break ÷ break length       |
| Break over (`breakOver`) | 1                                  |

With Reduce Motion off, the dot moves with the 1 s tick and a linear animation.
With Reduce Motion on, in a focus session it moves to the progress of the last full minute, and in the wait and the break it moves to the progress of the last full second, without animation in both cases.
Only the drawn ring (discs, ticks and dot) is hidden from VoiceOver (`accessibilityHidden`).
The label, the clock and the status line inside the dial stay accessibility elements, with the identifiers and labels in "Identifiers".

Dynamic Type: the label, the clock and the status line inside the dial use `minimumScaleFactor(0.5)` and one line each.
At the accessibility text sizes (`isAccessibilitySize`), the dial is not drawn, and the label, the clock and the status line show as a column, as the clock shows today.

## Screens

Sizes are in points.
Insets: 24 horizontal; the header row is 32 high; 15 between the header row and the title; 11 between the dial area and the action area; 11 between cards.
Cards and full-width buttons have a corner radius of 16; full-width buttons are 51 high; card padding is 16 horizontal and 13 vertical.

| Mock size (px) | Text style                              | Weight                            |
| -------------- | --------------------------------------- | --------------------------------- |
| 43, 39         | `.title`                                | bold                              |
| 86             | clock, 57 pt, scaled with `.largeTitle` | medium, monospaced digits         |
| 35             | `.title2`                               | semibold, monospaced digits       |
| 25             | `.headline`                             | bold                              |
| 23, 22, 21     | `.subheadline`                          | regular or medium, as in the mock |
| 20, 19, 18     | `.footnote`                             | regular or medium, as in the mock |

### Idle screen (`3:93`)

- Header: "제한할 앱" on the leading side and "설정" on the trailing side, each a text button on a `FocusCard` capsule.
  The settings button shows the text "설정" instead of the gear icon; its accessibility label stays "설정".
- Title: "작은 시작,\n깊은 몰입."
- Dial: label "집중할 시간", the clock of the focus length, status line "집중 준비 완료" in `AccentText`.
- Line below the dial: "\(N)분 동안, 한 가지에만." with N the focus length in minutes.
- Action area:
  - "집중 시작하기" with a `play.fill` symbol, `AccentColor` fill and a white label (`AccentLabel` keeps its dark value).
  - Card "집중 중 제한": "집중 중 제한" on the leading side, "앱 N개 · 웹사이트 M개" on the trailing side; a separator; then the everyday status row ("● 매일 제한 중" in `AccentText`, the end time and a chevron).
    The second row shows the text of `EverydaySettingsModel.timerLine` under its current conditions, including "매일 제한을 확인해 주세요" when the everyday status has an issue, and opens the everyday settings as today; the dot shows only for the "매일 제한 중" text.
    When `timerLine` returns no text, the card shows only the first row.
  - Card "오늘의 집중": "오늘의 집중" and "기록 보기 ›" in the title row; the minutes and the count of completed sessions below, numbers in `.title2`, units "분" and "회" in `.subheadline`.
    The whole card is the history button.
- The start blocker, the error and the retry button show between the dial line and the action area, as they do today.

### Timer screen of an active session (`3:99`)

- Header: "나의 집중" on the leading side; a `FocusPill` capsule with an amber dot and "집중 진행 중" in `FocusAmber` on the trailing side.
  The pill is hidden from VoiceOver, because the status line inside the dial says the same.
- Title: "지금은,\n나에게 집중할 시간"
- Dial:
  - Countdown: label "남은 집중 시간", the remaining time, status line "● 집중 시간 진행 중" in `FocusAmber`.
  - Open session: label "집중한 시간", the elapsed time (`h:mm:ss` from one hour), status line "● 집중 모드를 끌 때까지 이어져요".
- Line below the dial: "지금 이 순간에 머물러요".
- Action area:
  - While breaks are left, a `FocusCard` card: "잠깐 쉬어가도 괜찮아요" with a `FocusChip` chip "N번 남음" in `FocusAmber`, then the full-width button "쉬는 시간 갖기" in `FocusCreamFill` with a `FocusNavy` bold label.
    While a break request is pending, the request feedback replaces the button inside the card.
    With no break left, the card is not shown.
  - "집중 종료" as a text button in `ErrorText`, 45 high.

### Break screen (`3:105`)

The mock shows the `waiting` phase; the `onBreak` and `breakOver` phases use the same layout with their own text.

| Part                | `waiting`                                                                                                                        | `onBreak`                    | `breakOver`                 |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ---------------------------- | --------------------------- |
| Header label        | "잠깐의 쉼"                                                                                                                      | "잠깐의 쉼"                  | "잠깐의 쉼"                 |
| Pill                | "휴식 전환 대기"                                                                                                                 | "쉬는 시간"                  | "다시 집중할 시간"          |
| Title               | "쉬기 전에,\n잠시만 기다려요"                                                                                                    | "제한을 잠시\n풀어 두었어요" | "쉬는 시간이\n끝났어요"     |
| Dial label          | "쉬는 시간까지"                                                                                                                  | "남은 쉬는 시간"             | "쉬는 시간 끝"              |
| Clock               | the wait left                                                                                                                    | the break left               | "00:00"                     |
| Dial status         | "N초 후 휴식 시작"                                                                                                               | "끝나면 다시 제한해요"       | "다시 제한했어요"           |
| Line below the dial | "기다리는 동안에는 계속 제한해요."                                                                                               | none                         | none                        |
| Card                | "지금 · N초 대기 → 쉬는 시간 시작"; "다른 앱으로 나가면 집중으로 돌아가요."; "이번 쉬는 시간을 쓰면 N번 남아요." in `AccentText` | none                         | the deadline notice         |
| Primary button      | "집중으로 돌아가기", `FocusNavy` fill (light) or `FocusCreamFill` (dark), contrasting label                                      | "다시 집중하기", same style  | "다시 집중하기", same style |
| End                 | "집중 종료" text button in `ErrorText`                                                                                           | same                         | same                        |

The pill uses `FocusPill` with `AccentText`.
While a break action is pending (`model.pendingBreak`), the break feedback (`breakProgress`) shows as today: in `waiting`, it replaces the first card line; in `onBreak` and `breakOver`, it shows below the primary button.
While it shows, the primary button and "집중 종료" are disabled, as today.
The progress bar of the wait is replaced by the dial.
Its identifier `breakWait`, with the label "쉬는 시간 준비 중" and the value "N초 남음", moves to the first card line; the dial clock keeps `breakWaitCountdown`.
The second and third card lines are one accessibility element with the identifier `breaksLeft` and the label of today, "다른 앱으로 나가면 집중으로 돌아가요. 이번 쉬는 시간을 쓰면 N번 남아요."
The texts of `onBreak` and `breakOver` that the mock does not show are proposals and go through the copy review with the captures.

## Identifiers

| Identifier                                                                                                        | New element                                                                          | Label read by `UITests/FocusFlowTests.swift`                                                                             |
| ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| `countdown`                                                                                                       | the dial clock of the timer screen                                                   | countdown: "남은 시간 N분 N초"; open session: "집중한 시간 N시간 N분 N초", the hours only from one hour (both unchanged) |
| `sessionStatus`                                                                                                   | the status line inside the dial                                                      | "집중 모드를 끌 때까지 이어져요" for an open session (unchanged)                                                         |
| `breaksLeft`                                                                                                      | timer screen: the chip; break screen: the second and third card lines as one element | "쉬는 시간 N번 남았어요" and the wait sentence (unchanged accessibility labels; the chip shows "N번 남음")               |
| `breakStart`                                                                                                      | the "쉬는 시간 갖기" button                                                          | none                                                                                                                     |
| `end`                                                                                                             | the "집중 종료" text button on both screens                                          | none                                                                                                                     |
| `todaySummary`                                                                                                    | the "오늘의 집중" card                                                               | "오늘 집중 N분 · N회" (unchanged accessibility label)                                                                    |
| `restrictionSummary`                                                                                              | the trailing text of the "집중 중 제한" card                                         | none                                                                                                                     |
| `everydayStatusRow`                                                                                               | the second row of the "집중 중 제한" card                                            | none                                                                                                                     |
| `start`, `selection`, `settingsButton`                                                                            | the start button and the two header buttons                                          | none                                                                                                                     |
| `breakCountdown`, `breakWaitCountdown`, `breakWait`, `breakWaitCancel`, `resume`, `deadlineNotice`, `breakScreen` | the matching elements of the break screen                                            | as today                                                                                                                 |

## Not carried

- The Noto Sans KR and Inter typefaces, and the clock tracking of −4.3 px.
- The mock's navy `#1C263F` and `#202C46` as the room color, cream `#FFF6E9` and `#FFF5E6`, amber `#FFC487` and `#FFD2A4`, blue-gray dimmed text, and the destructive colors `#F3ACA0` and `#AB4539`; the approved tokens replace them (contract 2 to 5).
- The drawn status bar and home indicator; the system draws them.

## Out of scope

The completion card (it keeps the navy focus room design), the everyday settings screen, onboarding, the settings and history sheets except for the accent change, the custom shield, the home screen widget and the Live Activity.

## Evidence

- Figma frames `3:93`, `3:99` and `3:105`, read on 2026-11-23: colors, sizes and texts above; the dial SVGs give the band, inner disc, stroke, tick and dot colors and the 1.5 and 2.5 px tick widths.
- WCAG contrast, computed on 2026-11-23 with the sRGB relative luminance formula:
  - `AccentColor` light `#AE5519`: white label 5.11:1; as text on `#F8F5F0` 4.69:1.
  - `AccentText` light `#985019`: 5.52:1 on `#F8F5F0`, 6.01:1 on white, 4.85:1 on `#F2E5D5`.
  - The old light accent `#A85F10`: 4.48:1 on `#F8F5F0`.
  - Secondary `#626D7E`: 4.82:1 on `#F8F5F0`, 5.24:1 on white.
  - `FocusNavy` text: 13.51:1 on `#F8F5F0`, 11.39:1 on `#F7DFC0`.
  - On `#202C46`: `FocusCream` 12.77:1, `FocusAmber` 6.89:1, `FocusCreamSecondary` (composited) 5.87:1, dark `ErrorText` 8.19:1.
  - `FocusAmber` 5.96:1 on `#2B3650` and 4.91:1 on `#37435C`; `FocusCream` 11.55:1 on `#27334E`.
  - `#202C46` against `#1E2744`: 1.06:1.
- `UITests/FocusFlowTests.swift` compares the labels of `breaksLeft`, `countdown`, `sessionStatus` and `todaySummary` with fixed strings (lines 40 to 76, 214 to 240 and 1163 to 1226 at `d5ca9c7`); it checks only that `breakWait` exists (lines 213 and 1222).
- `project.yml`: only the `FocusStudy` target sets `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor`; the `FocusActivity` target compiles `Widget/`, `Activity/` and two `Shared/` files, and no asset catalog of `App/`.
- `App/Assets.xcassets/AccentColor.colorset` is `#A85F10` light and `#F4A64A` dark at `d5ca9c7`; `App/`, `Widget/` read it through `Color.accentColor`, `FocusTheme.Palette.accent` or `FocusPrimaryAction`.

## Verification plan for the implementation

- `SDKTests/FocusRoomPaletteTests.swift` extends to the new tokens with the contrast values above.
- UI tests pass with the identifiers and labels in "Identifiers".
- Captures of the three screens on the iOS 26.5 simulator in the light and the dark appearance, at the largest text size, on the 6.9-inch and the smallest supported screen, with Reduce Motion on; then visual approval before the merge.
