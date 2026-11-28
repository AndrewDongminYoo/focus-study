# Everyday screen redesign

Date: 2026-11-23.
Status: approved on 2026-11-23 under [issue #236](https://github.com/AndrewDongminYoo/focus-study/issues/236); implemented under [issue #241](https://github.com/AndrewDongminYoo/focus-study/issues/241).
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
   With unsaved changes, the back button stays the one that asks "변경 사항을 버릴까요?" (`everydayBack`), as today; the system back button shows only for a draft without changes.
2. Status card (white): "매일 제한" in bold, 25 pt at the default text size and scaled with `.title2`, as the screen's header (`isHeader`), with the switch (`everydayToggle`) on the trailing side, and below it the full-width button "오늘만 끄기" (`everydayOffToday`) in the accent tint with accent text.
   The button shows only when `offersOffForToday` is true, as today.
   The card shows no status line while the layer is off or blocks now, because the switch says them.
   It shows the status line (`everydayStatus`, `EverydaySettingsModel.statusLine`) below the switch in every other state, which the switch cannot say: a day that is not chosen, the next range or an unblocked window, off for today, and every issue (`EverydaySettingsModel.showsStatusLine`).
   Amended on 2026-11-24 during the implementation: the approved text hid the next range too, which left a day that is not chosen and the next range unreadable on the screen.
3. Range card (navy in the light appearance): "설정 시간" with the weekday summary and "반복" ("매일 반복", "평일 반복" and so on) on the trailing side, hidden from VoiceOver because the weekday card says the same, the range in a large semibold monospaced font, and the line "이 시간 안에서 제한과 해제를 반복해요".
   The range is one button that opens a sheet with the two time pickers "제한 시작" (`everydayRangeStart`) and "제한 끝" (`everydayRangeEnd`).
   The range button has the identifier `everydayRange`, and the sheet's "완료" has `everydayRangeDone`.
   The range issue line (`everydayRangeIssue`) shows below the card, because the error color does not read on the navy card; the sheet repeats it (`everydayRangeEditorIssue`).
4. Weekday card: "제한 요일" with the summary (`everydayWeekdaysSummary`) on the trailing side, then seven chips (`everydayWeekday.N`); a chosen chip is the accent tint with accent text, and a chip that is not chosen is the neutral tint with secondary text.
   The weekday issue line (`everydayWeekdaysIssue`) shows below the chips.
5. Unblocked window card: "잠시 풀어 두는 시간" with "N/3" on the trailing side, one row per window with its time range and "삭제", a divider, "+ 시간 추가하기" (`everydayAddWindow`), and the note "점심이나 등하교처럼 제한을 풀어 둘 시간을 3개까지 정할 수 있어요. 한 번에 15분에서 2시간까지예요."
   A window's time range is its two time pickers, as the rows are today; the row shows no kind name ("점심" and so on), as in the mock.
   The window issue line (`everydayWindowsIssue`) shows above the note.
6. App card: "제한할 앱" with "앱 N개 · 웹사이트 M개" and a chevron on the trailing side (`everydaySelection`, opens the picker), and the note "집중 시간에 제한할 앱과 따로 골라요."
   The selection issue line (`everydaySelectionIssue`) shows below the note.
7. Preview card (see "Preview").
8. Save area: the save feedback line ("변경 사항이 없어요" when there is no change, `everydayUnsavedChanges`, `everydaySaveSuccess` or `everydayRefusal`), then the full-width save button (`everydaySave`), 47 pt high.
   A disabled save button is `#E4E7ED` with `#626C7D` text; an enabled one is the accent with the `AccentLabel` text: white on `#A84F05` (5.55:1) in the light appearance, navy `#1E2744` on `#F4A64A` (7.28:1) in the dark appearance.

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
- When the lock starts while the screen is open (the status read after a boundary), every field that the table disables returns to its stored value in the draft: the switch, the stored weekdays and the selection, and the windows keep only the stored windows that the draft still has (see the window rule below); a range start later than the stored start and a range end earlier than the stored end return to the stored values too.
  The strict edits in the draft stay, and the save feedback line says "제한 시간이 시작되어 느슨해지는 변경을 되돌렸어요."
  So the draft never holds an edit that the screen cannot undo and the engine refuses.
- The model returns these edits at every status read while the layer is locked, not only at the boundary, so a refused save also leaves a draft without the refused edit; the refusal line and the return line (`everydayLockRevert`) both show.
  The return line stays until the next edit, save or reload, also when a later status read finds nothing to return, and a failed save keeps its refusal line after the read.
- A lock that starts on a later day is read only at that day's next status read (`statusReadDelay` reads at today's range edges, the next change and midnight); until then a loosening save is refused by the engine with its reason.
- A window has no identity, so the draft keeps only the stored windows that it still has: a window that the draft added or changed goes away, and a stored window that the draft removed stays removed.
- The disabled switch and time pickers use the system disabled appearance; the disabled chips, the app card and "+ 시간 추가하기" draw at 45 % opacity. All keep their accessibility labels, and VoiceOver reads them as dimmed.
  The [lock mark amendment of 2026-11-28](#lock-mark-amendment-2026-11-28) replaces the 45 % opacity.

### Lock mark amendment (2026-11-28)

On a device run on 2026-11-28, the locked screen did not say whether a dimmed weekday chip was chosen, or whether an element was locked only now: the chosen chips at 45 % opacity measure 1.90:1 (`#A84F05` on `#FFF0E1` over white), and no line said why the elements were disabled.
While the layer is locked:

- Each element that the table above disables shows a lock mark (`lock.fill`, `.caption2`) and draws at full opacity:
  - A chosen weekday chip keeps its chosen look, with the mark after the day in the accent.
  - The switch has the mark on its leading side, in the secondary text color; the switch keeps the system disabled appearance.
  - Each window row has the mark before its times; the time pickers keep the system disabled appearance, and "삭제" stays enabled.
  - "시간 추가하기" shows the mark in place of "+", in the secondary text color.
  - The app card shows the mark in place of its chevron.
- The status card shows the lock note (`everydayLockNote`) below the switch: "제한 시간에는 (lock mark) 표시한 항목을 바꿀 수 없어요.", read by VoiceOver as "제한 시간에는 잠긴 항목을 바꿀 수 없어요."
- The marks are hidden from VoiceOver; the elements stay disabled, so VoiceOver reads them as dimmed.
- "+ 시간 추가하기" with three windows on an unlocked screen still draws at 45 % opacity, because nothing locks it.

## Save confirmation

- Every tap on an enabled save button first shows an alert: title "매일 제한을 저장할까요?", message "저장하면 제한 시간(HH:MM–HH:MM)에는 매일 제한을 끄거나 느슨하게 바꿀 수 없어요.", with the draft's range, and the buttons "저장" and "취소".
- A draft that turns the layer off shows no alert, because nothing locks.
- "저장" runs the save as today; "취소" keeps the draft.

## Tokens

The light values are the mock values; the dark values follow the screen redesign, except the range card.

| Role                                                       | Light                                                      | Dark                          |
| ---------------------------------------------------------- | ---------------------------------------------------------- | ----------------------------- |
| Background                                                 | `#F5F6F8`                                                  | `#202C46`                     |
| Card                                                       | `#FFFFFF`                                                  | `#27334E`                     |
| Primary text                                               | `#202C46`                                                  | `#FFF4E2`                     |
| Secondary text                                             | `#626D7E`                                                  | `FocusCreamSecondary`         |
| Accent (text, switch, restricted bar)                      | `#A84F05`                                                  | `#F4A64A`                     |
| Accent tint (chosen chip, restricted badge, "오늘만 끄기") | `#FFF0E1`                                                  | `#553F22`                     |
| Neutral tint (unblocked badge, chip not chosen)            | `#EFF1F5`                                                  | `#37435C`                     |
| Unblocked bar                                              | `#C8D0DD`                                                  | `#48536C`                     |
| Divider                                                    | `#E6E9EF`                                                  | `#37435C`                     |
| Range card                                                 | `#202C46` with white and `#D2D9E6` text, `#FFE0BB` summary | `#F7DFC0` with `#1E2744` text |
| Disabled save                                              | `#E4E7ED` with `#626C7D`                                   | `#37435C` with cream at 62 %  |
| Destructive "삭제"                                         | `ErrorText`                                                | `ErrorText`                   |

The dark values are not drawn in a mock; the implementation captures them for approval.

## Identifiers

Every identifier of `App/EverydaySettingsView.swift` stays on the element that takes its role, except `everydayStrictOnly`, which is removed, and `settingsDone`, which stays only on the settings list.
The UI tests that tap `settingsDone` on this screen (`UITests/FocusFlowTests.swift`, for example line 654, which closes the sheet during the off-for-today wait) go back first or swipe the sheet down; the tests change with the implementation, and no test may lose its assertion.

## Evidence

- `App/EverydaySettingsModel.swift` at `46f7457`: `offersOffForToday`, `strictOnlyMessage`, `lockMessage` with the six refusals, and `previewSegments`.
- `Shared/EverydaySchedule.swift`: `isLocked` reads `enabled`, the weekdays and the range, never `offDay` (line 158); `Shared/SessionControl.swift` line 350 checks the lock and `lockReason` at save.
- WCAG contrast computed on 2026-11-23: `#A84F05` 5.55:1 on white, 4.97:1 on `#FFF0E1`, 5.13:1 on `#F5F6F8`; `#626D7E` 5.24:1 on white and 4.63:1 on `#EFF1F5`; `#677184` 4.55:1 on `#F5F6F8`; `#202C46` 12.86:1 on `#F5F6F8`; on `#202C46`: white 13.91:1, `#D2D9E6` 9.81:1, `#FFE0BB` 11.01:1; `#1E2744` 11.39:1 on `#F7DFC0`; white 5.55:1 on `#A84F05`.
- Dark: `#F4A64A` 4.9:1 on `#553F22`; the warm tint differs from the navy card `#27334E` by hue, because no dark tint differs from it much by luminance (1.27:1). The other dark text pairs are the ones that the screen redesign measured.
- The restricted and unblocked bar colors measure 3.57:1 against each other, above the 3:1 of non-text contrast.

## Verification plan for the implementation

- SDK tests for the locked picker bounds and the enabled state of each element, with a locked, an off-for-today and an unlocked fixture.
- An SDK test that crosses the lock boundary with a loosening and a strict edit in the draft, and checks that only the loosening edit returns to the stored value.
- Palette tests for the save button in both appearances, and for the status line colors.
- UI tests keep their assertions; the tests that used `settingsDone` on this screen change their navigation only.
- Captures in the light and the dark appearance, locked and unlocked, at the largest text size, then visual approval before the merge.
