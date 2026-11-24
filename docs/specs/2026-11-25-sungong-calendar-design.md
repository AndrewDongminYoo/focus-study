# 순공 calendar design

Date: 2026-11-25.
Status: approved on 2026-11-25, not yet implemented.
Source: [issue #248](https://github.com/AndrewDongminYoo/focus-study/issues/248), under the paid build parent #244.
Authority: the [paid unlock decision](2026-11-24-paid-unlock-decision.md) (decisions 2 and 7, and "Behavior at the edges") and the [paid access design](2026-11-24-paid-access-design.md).
Look: Figma frames node `32:2` (light) and node `32:23` (dark), with the tokens of the [screen redesign](2026-11-23-screen-redesign-design.md).
This document changes no code.
The implementation is issue #249, and it starts after this design is approved.

## Contract

Decided on 2026-11-25:

1. **Entry.** The "오늘의 집중" control on the idle screen opens the 순공 calendar instead of today's history sheet.
   The calendar is a sheet at the large detent, presented through the idle screen's existing `.sheet` like the settings, history and paywall sheets, and its "닫기" control closes it.
   The idle screen has no `NavigationStack`, and a push would add one to the launch screen.
2. **Layout.** The screen is a grid calendar of one month, from top to bottom:
   1. a header: the title "순공시간" centered and "닫기" on the right, with the line "공부한 시간만, 하루하루 모아봐요." under it;
   2. a month card: the month's total completed focus time and the number of recorded days;
   3. a month grid card: the year and month, then "‹ 오늘 ›" on the right (previous month, today, next month), the weekday row and one cell per day;
   4. a selected-day card: the date, the day's total, the number of completed sessions, and one row per completed session; it has no "오늘" label;
   5. a note: "공부한 집중 세션의 기록을 합산해요." and "휴식 시간과 일반 스크린타임은 포함하지 않아요."
3. **Paid and free.** The calendar is a paid feature (decision 2); today's history and the streak stay free ("Behavior at the edges").
   - With access `granted` or `unknown`, the screen shows every part above.
   - With access `locked`, the month card and the month grid card are replaced by one card: "구매하면 순공 캘린더를 볼 수 있어요" and a button that opens the paywall.
     The selected-day card is fixed to today and stays visible, so today's history stays free.
   - The paywall is the one of the paid access design (temporary sheet now, #247 later).
4. **Streak.** The display-only streak of the [streak design](2026-11-13-streak-design.md) moves to the month card, under "기록한 날", as "연속 집중 N일".
   With access `locked`, it shows in the selected-day card instead, because the streak is free.
   When the streak is unavailable (`nil`), the line is absent, as in today's history sheet.
5. **No rewards.** No ranking, no comparison, no badge, and no notice that a streak is about to break (decision 7 and the AGENTS.md baseline).

## Data rules

The calendar reads the same session history as today's history and the streak.

- A day is a local calendar day (`Calendar.current`, as `TimeRules.today` uses).
  A session belongs to the local day of its `startedAt`, also when it ends after midnight.
- Only a completed session counts (`SessionRecord.counts`, end reason `expired`).
  Its focus time is `focusDuration`, which leaves out breaks: breaks are added to `pausedSeconds` and do not move `expiresAt`.
- A day's value is the sum of the focus time of its completed sessions.
  A day with no completed session shows "—". A day after today shows only its date, dimmed, and cannot be selected.
- The month card's total is the sum over the shown month's days. "기록한 날" counts the days of that month with at least one completed session.
- A session row shows the start and end clock times (`startedAt`–`endedAt`, so breaks are inside that span) and the focus minutes.
  So "09:00–09:55" with "50분" is a correct row for a session with a 5-minute break.
- Times in a cell use `H:MM` ("1:30", "0:50"). The selected-day total and the month total use the words of the mock ("2시간 30분", "35시간 0분").
  Session rows use minutes ("50분").
- Months: the first shown month is the month of today. The previous control goes back without a limit; the next control stops at the month of today.
  "오늘" sits between the two arrows. It shows the month of today and selects today.
  It stays in place and is disabled, in `FocusSecondaryInk`, while the month of today is shown and today is selected, so the arrows never move.
- On open, today is selected.
- A history read failure shows the error and the "다시 확인하기" retry of today's history sheet in place of the cards, and never an empty month.

## Look

Every size is the mock value divided by 1.5 (the frames are 603 × 1311, the 402 × 874 pt screen at 1.5×), rounded to the nearest point, as in the screen redesign.

| Element                           | Mock                   | Size (pt) and text style                         | Light                                    | Dark                                           |
| --------------------------------- | ---------------------- | ------------------------------------------------ | ---------------------------------------- | ---------------------------------------------- |
| Screen background                 | frame fill             | —                                                | `FocusCanvas` `#F8F5F0`                  | `FocusCanvas` `#202C46`                        |
| Cards                             | 555 wide               | `FocusCard` modifier: radius 16, padding 16 × 13 | `FocusCard` `#FFFFFF`                    | `FocusCard` `#27334E`                          |
| Title "순공시간"                  | 32 Bold                | 21, `.title2` bold                               | `FocusNavy`                              | `FocusCream`                                   |
| "닫기", "오늘"                    | 23 Medium, 22 Semibold | 15, `.subheadline` medium / semibold             | `AccentText`                             | `AccentText`                                   |
| Header line, session times, notes | 22 / 18 Regular        | 15 / 12, `.subheadline` / `.caption`             | `FocusSecondaryInk`                      | `FocusSecondaryInk`                            |
| Month total                       | 40 Semibold            | 27, `.title` semibold                            | `FocusNavy`                              | `FocusCream`                                   |
| Month card labels                 | 21 / 20                | 14 / 13, `.footnote`                             | `FocusSecondaryInk`                      | `FocusSecondaryInk`                            |
| Recorded days "20일"              | 27 Semibold            | 18, `.headline`                                  | `FocusNavy`                              | `FocusCream`                                   |
| Year and month                    | 29 Bold                | 19, `.title3` bold                               | `FocusNavy`                              | `FocusCream`                                   |
| Month controls "‹ ›"              | 34 Regular             | 23                                               | `AccentText`                             | `AccentText`                                   |
| Weekday row                       | 19 Medium              | 13, `.footnote` medium                           | `FocusSecondaryInk`                      | `FocusSecondaryInk`                            |
| Day number                        | 22 Medium              | 15, `.subheadline` medium, monospaced digits     | `FocusNavy`                              | `FocusCream`                                   |
| Day value                         | 18 Medium              | 12, `.caption` medium, monospaced digits         | `AccentText`                             | `AccentText`                                   |
| "—" and future days               | 18 / 22 Medium         | as above                                         | `FocusSecondaryInk`                      | `FocusSecondaryInk`                            |
| Selected day cell                 | 71 × 72, radius 12     | about 47 × 48, radius 8                          | fill `AccentColor` `#AE5519`, text white | fill `AccentColor` `#F4A64A`, text `FocusNavy` |
| Selected date "11월 24일 화요일"  | 25 Semibold            | 17, `.headline`                                  | `FocusNavy`                              | `FocusCream`                                   |
| Day total                         | 38 Semibold            | 25, `.title2` semibold                           | `FocusNavy`                              | `FocusCream`                                   |
| Session count, session minutes    | 21 Regular, 23 Medium  | 14 / 15                                          | `FocusSecondaryInk` / `FocusNavy`        | `FocusSecondaryInk` / `FocusCream`             |

Dynamic Type: every text uses its text style and scales. At an accessibility text size the grid cells keep seven columns; the day value may drop to a second line, and the screen scrolls.
Accessibility: each day cell reads as one element, for example "11월 24일, 2시간 30분" or "11월 8일, 기록 없음", with the selected trait on the selected day.
Keep the existing identifiers that `UITests/FocusFlowTests.swift` reads on the idle screen; new identifiers are the builder's.

### Not carried

- The mock's dark text `#FFFFFF` and dark secondary `#B8C2D3`: `FocusCream` and `FocusSecondaryInk` replace them, as in the screen redesign.
- The mock's light small accent text `#AE5519`: small accent text uses `AccentText` `#985019`, which measures 5.52:1 on `#F8F5F0` where `#AE5519` measures 4.69:1.
- The mock's status bar and home indicator.

## Left to the builder

- How the sheet reads the history for a month.
- Whether the locked card's button opens the paywall over the calendar sheet or in its place; the idle screen presents one `.sheet(item:)` today.
- The exact layout of the locked card, inside the card style above, with the copy written by the `user-facing-copy` rules.
- Captures for approval: light, dark and the largest accessibility text size, with access `granted` and `locked`.
