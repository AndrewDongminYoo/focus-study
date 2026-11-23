# Everyday screen redesign

Date: 2026-11-23.
Status: approved on 2026-11-23 under [issue #236](https://github.com/AndrewDongminYoo/focus-study/issues/236); no code implements it yet.
Source: the Figma mock frame node `6:2`, which adds editing elements to the mock node `3:7`, and the decisions below.
The engine rules of the everyday layer do not change: the screen offers fewer edits while the layer is locked than the engine accepts, never more.

It amends these specs:

- The [everyday schedule preview](2026-11-06-everyday-schedule-preview.md): the text rows become a card with a proportional bar and badge rows.
- The [everyday day clock](2026-11-09-everyday-day-clock.md): the screen no longer shows the day clock; this spec replaces it.
- The [off-for-today spec](2026-11-08-everyday-off-today.md), "Editing after the layer is off for today": the screen disables the edits that a locked layer refuses, instead of showing the strict-only line and refusing them at save.

## Why

- The daily range is the first fact on the screen, so the range shows large at the top.
- The weekdays, the unblocked windows, the apps and the preview are separate cards that can be read at a glance.
- A bar and a time table compare the length and the state of each interval more easily than the round chart.
- "제한" and "해제" are text badges, not only colors.
- The toolbar "완료" of this screen is removed, because the settings list has its own "완료"; a disabled save button says "변경 사항이 없어요".

## Decisions of 2026-11-23

1. Palette: the mock values, not the tokens of the [screen redesign](2026-11-23-screen-redesign-design.md) (see "Tokens").
2. Typeface: the system font, as in the screen redesign; sizes map to Dynamic Type text styles at 1/1.5 of the mock.
3. The editing elements that the mock `3:7` does not draw are in the mock `6:2`: a status card with the switch and "오늘만 끄기", and an unblocked window card.
4. The large range text opens the start and end time pickers; there are no separate start and end buttons.
5. The preview covers the whole daily range.
6. In the dark appearance, the range card is cream `#F7DFC0` with navy `#1E2744` text.
7. While the layer is locked, the screen disables the edits that loosen it, and it allows only the strict edits in "Locked editing".
8. Every save shows a confirmation that the layer cannot be loosened during its range.

## Layout

From top to bottom, in a scroll view with the save area fixed at the bottom:

1. The navigation bar: the system back button "설정" and no visible title, because the status card below says "매일 제한".
   The navigation title stays "매일 제한" for VoiceOver and the back stack, and the bar does not draw it.
   The toolbar "완료" (`settingsDone`) is removed from this screen; the settings list keeps it.
2. Status card (white): "매일 제한" in bold, 25 pt at the default text size and scaled with `.title2`, as the screen's header (`isHeader`), with the switch (`everydayToggle`) on the trailing side, and below it the full-width button "오늘만 끄기" (`everydayOffToday`) in the accent tint with accent text.
   The button shows only when `offersOffForToday` is true, as today.
   The card shows no status line; the saved status stays readable to VoiceOver as the switch's value.
3. Range card (navy in the light appearance): "설정 시간" with the weekday summary and "반복" ("매일 반복", "평일 반복" and so on) on the trailing side, hidden from VoiceOver because the weekday card says the same, the range in a large semibold monospaced font, and the line "이 시간 안에서 제한과 해제를 반복해요".
   The range is one button that opens a sheet with the two time pickers "제한 시작" (`everydayRangeStart`) and "제한 끝" (`everydayRangeEnd`).
   The range issue line (`everydayRangeIssue`) shows below the range inside the card.
4. Weekday card: "제한 요일" with the summary (`everydayWeekdaysSummary`) on the trailing side, then seven chips (`everydayWeekday.N`); a chosen chip is the accent tint with accent text, and a chip that is not chosen is the neutral tint with secondary text.
   The weekday issue line (`everydayWeekdaysIssue`) shows below the chips.
5. Unblocked window card: "잠시 풀어 두는 시간" with "N/3" on the trailing side, one row per window with its time range and "삭제", a divider, "+ 시간 추가하기" (`everydayAddWindow`), and the note "점심이나 등하교처럼 제한을 풀어 둘 시간을 3개까지 정할 수 있어요. 한 번에 15분에서 2시간까지예요."
   A window's time range opens its two time pickers, as the rows do today.
   The window issue line (`everydayWindowsIssue`) shows above the note.
6. App card: "제한할 앱" with "앱 N개 · 웹사이트 M개" and a chevron on the trailing side (`everydaySelection`, opens the picker), and the note "집중 시간에 제한할 앱과 따로 골라요."
   The selection issue line (`everydaySelectionIssue`) shows below the note.
7. Preview card (see "Preview").
8. Save area: the save feedback line ("변경 사항이 없어요" when there is no change, `everydayUnsavedChanges`, `everydaySaveSuccess` or `everydayRefusal`), then the full-width save button (`everydaySave`), 47 pt high.
   A disabled save button is `#E4E7ED` with `#626C7D` text; an enabled one is the accent with white text.

The off-for-today waiting screen (`everydayOffWait`, `everydayOffCancel`) keeps its behavior and takes the same background and card style.

## Preview

- The header row has "일정 미리보기" and the draft's daily range on the trailing side, then the weekday line ("제한 요일 · …", `everydayDraftWeekdays`) and the legend badges "제한" and "해제".
- A bar 9 pt high shows the segments of `EverydaySettingsModel.previewSegments` across the whole daily range, with widths in proportion to their lengths and 3 pt gaps; a restricted segment is the accent, an unblocked one is `#C8D0DD`.
- Below a divider, one row per segment: the time range on the leading side and a "제한" or "해제" badge on the trailing side.
  The rows keep their identifiers (`everydayDraftSegment.N`) and accessibility labels.
- The last row "저장된 일정 보기 ›" opens the stored schedule (`everydayStoredSegment.N`, `everydayStoredUnavailable`) in a disclosure below it.
- An invalid draft and a layer that is off show their lines (`everydayDraftInvalid`, `everydayDraftOff`) instead of the bar and the rows, as today.
- The bar is hidden from VoiceOver; the rows are the accessible alternative.

## Locked editing

The layer is locked when `EverydaySchedule.isLocked` is true for the stored schedule: the stored layer is on, today is a chosen weekday, and now is inside the stored range.
It stays locked when the layer is off for today, as the off-for-today spec says.

While it is locked:

| Element                                     | State                                                               |
| ------------------------------------------- | ------------------------------------------------------------------- |
| Switch                                      | Disabled                                                            |
| Range start                                 | Enabled; the picker allows only the stored start or an earlier time |
| Range end                                   | Enabled; the picker allows only the stored end or a later time      |
| Weekday chip, chosen in the stored schedule | Disabled                                                            |
| Weekday chip, not chosen                    | Enabled (adds a weekday)                                            |
| Window time range                           | Disabled                                                            |
| Window "삭제"                               | Enabled                                                             |
| "+ 시간 추가하기"                           | Disabled                                                            |
| App card                                    | Disabled                                                            |
| "오늘만 끄기"                               | As `offersOffForToday` says                                         |

- The pickers keep the engine bounds 00:00 and 23:55 and the 5-minute grid.
- A range that moves (for example 08:00–18:00 to 09:00–20:00) cannot be entered, because the start cannot move later.
- Every edit that the table allows is one that the engine accepts while locked, so a locked save is refused only when the stored state changed after the screen read it; the refusal line stays for that case.
- The strict-only line (`everydayStrictOnly`) is removed.
- The disabled elements use the system disabled appearance and keep their accessibility labels; VoiceOver reads them as dimmed.

## Save confirmation

- Every tap on an enabled save button first shows an alert: title "매일 제한을 저장할까요?", message "저장하면 제한 시간(HH:MM–HH:MM)에는 매일 제한을 끄거나 느슨하게 바꿀 수 없어요.", with the draft's range, and the buttons "저장" and "취소".
- A draft that turns the layer off shows no alert, because nothing locks.
- "저장" runs the save as today; "취소" keeps the draft.

## Tokens

The light values are the mock values; the dark values follow the screen redesign, except the range card.

| Role                                                       | Light                                                      | Dark                             |
| ---------------------------------------------------------- | ---------------------------------------------------------- | -------------------------------- |
| Background                                                 | `#F5F6F8`                                                  | `#202C46`                        |
| Card                                                       | `#FFFFFF`                                                  | `#27334E`                        |
| Primary text                                               | `#202C46`                                                  | `#FFF4E2`                        |
| Secondary text                                             | `#626D7E`                                                  | `FocusCreamSecondary`            |
| Accent (text, switch, restricted bar)                      | `#A84F05`                                                  | `#F4A64A`                        |
| Accent tint (chosen chip, restricted badge, "오늘만 끄기") | `#FFF0E1`                                                  | `#2B3650` (the dark `FocusPill`) |
| Neutral tint (unblocked badge, chip not chosen)            | `#EFF1F5`                                                  | `#37435C`                        |
| Unblocked bar                                              | `#C8D0DD`                                                  | `#48536C`                        |
| Divider                                                    | `#E6E9EF`                                                  | `#37435C`                        |
| Range card                                                 | `#202C46` with white and `#D2D9E6` text, `#FFE0BB` summary | `#F7DFC0` with `#1E2744` text    |
| Disabled save                                              | `#E4E7ED` with `#626C7D`                                   | system disabled                  |
| Destructive "삭제"                                         | `ErrorText`                                                | `ErrorText`                      |

The dark values are not drawn in a mock; the implementation captures them for approval.

## Identifiers

Every identifier of `App/EverydaySettingsView.swift` stays on the element that takes its role, except `everydayStrictOnly`, which is removed, and `settingsDone`, which stays only on the settings list.
The UI tests that tap `settingsDone` on this screen (`UITests/FocusFlowTests.swift`, for example line 654, which closes the sheet during the off-for-today wait) go back first or swipe the sheet down; the tests change with the implementation, and no test may lose its assertion.

## Evidence

- `App/EverydaySettingsModel.swift` at `46f7457`: `offersOffForToday`, `strictOnlyMessage`, `lockMessage` with the six refusals, and `previewSegments`.
- `Shared/EverydaySchedule.swift`: `isLocked` reads `enabled`, the weekdays and the range, never `offDay` (line 158); `Shared/SessionControl.swift` line 350 checks the lock and `lockReason` at save.
- WCAG contrast computed on 2026-11-23: `#A84F05` 5.55:1 on white, 4.97:1 on `#FFF0E1`, 5.13:1 on `#F5F6F8`; `#626D7E` 5.24:1 on white and 4.63:1 on `#EFF1F5`; `#677184` 4.55:1 on `#F5F6F8`; `#202C46` 12.86:1 on `#F5F6F8`; on `#202C46`: white 13.91:1, `#D2D9E6` 9.81:1, `#FFE0BB` 11.01:1; `#1E2744` 11.39:1 on `#F7DFC0`; white 5.55:1 on `#A84F05`.
- Dark: `#F4A64A` 5.96:1 on `#2B3650`; the other dark text pairs are the ones that the screen redesign measured.
- The restricted and unblocked bar colors measure 3.57:1 against each other, above the 3:1 of non-text contrast.

## Verification plan for the implementation

- SDK tests for the locked picker bounds and the enabled state of each element, with a locked, an off-for-today and an unlocked fixture.
- UI tests keep their assertions; the tests that used `settingsDone` on this screen change their navigation only.
- Captures in the light and the dark appearance, locked and unlocked, at the largest text size, then visual approval before the merge.
