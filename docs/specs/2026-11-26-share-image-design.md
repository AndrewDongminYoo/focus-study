# 순공 calendar share image design

Date: 2026-11-26.
Status: approved on 2026-11-26, implemented under issue #253.
Source: [issue #252](https://github.com/AndrewDongminYoo/focus-study/issues/252), under the paid build parent #244.
Authority: the [paid unlock decision](2026-11-24-paid-unlock-decision.md) (decisions 2 and 7) and the [순공 calendar design](2026-11-25-sungong-calendar-design.md).
Look: the approved HTML mockup "도장 달력 시안 v4", option B (horizontal lines only), and for the stamp only, Figma frame node `62:2`.
This document changes no code.
The implementation is issue #253, and it starts after this design is approved.

## Intent

The moment is a student who finishes a session on the 24th, opens the calendar, and sees that today's study is one of the twenty days of this month.
A total such as "35시간" alone reads like a report card.
A month of calendar days with a mark on each recorded day shows that the student rested on some days and came back.

So the image shows ordinary days of effort that fill a month.
It does not show the most special day or the day with the most study.
Every recorded day gets the same stamp: a day of 25 minutes and a day of 2 hours 30 minutes look the same.

The weekly review's share card tells the story of one week.
This image shows the shape of the days themselves.
The two images stay separate (the weekly review design lists this image as out of its scope).

The student does not need to wait for the end of the month: the image of the current month shows the days up to today.

## Goals

- One image of one month: the year, the month, a stamp calendar and a small summary line.
- One share button in the 순공 calendar, which opens the system share sheet with the image; the share sheet's own "이미지 저장" saves it to Photos.

## Non-goals

- No focus time in a day cell, no session list, no selected day and no streak.
- No heat map or other mark that makes a day with more study look stronger.
- No count of days without a record, no "20/30일" denominator and no "0" for an empty day.
- No other image layouts, no choice of theme and no text that the student adds.

## Anti-goals

These make the work a failure even when it works:

- Any day stands out from the other recorded days.
- The summary reads as a grade, for example a large "20일" by itself or a day count over the days of the month.
- The app sends the image or any data off the device by itself (decision 7).

## Contract

Decided on 2026-11-26:

1. **Entry.** The 순공 calendar sheet gets one share icon button, directly at the left of "닫기" in the header row.
   It opens the system share sheet with the image. The sheet has no separate save button: the share sheet's own "이미지 저장" saves the image to Photos.
   "순공시간" stays centered and "닫기" keeps its place and identifier (calendar design, item 2.1); the hidden copy at the left of the row that keeps the title centered grows by the width of the share button.
   At an accessibility text size the title may scale down or wrap; the controls keep their size.
   This differs from the weekly review, which keeps its two buttons.
2. **Which month.** The image is of the month that the calendar shows. When the student shows an earlier month, the image is of that month.
3. **When the button shows.**
   - With access `granted` or `unknown`, the button shows.
   - With access `locked`, the button does not show. The locked calendar has no month grid (calendar design, item 3), so there is nothing to share.
   - When the shown month has no recorded day, or the history read failed, the button shows disabled.
4. **What the image holds.** From top to bottom:
   1. the year in small text, and the month as a large word ("11월"), with the colon mark at the top right;
   2. the stamp calendar on a card: the weekday row, then one row per week of the month;
   3. a thin divider, then the summary line at the left and the word "온:공" at the right.
5. **Day cells.**
   - A day with at least one completed session shows its date and one stamp.
   - A day without a completed session shows only its date.
   - A day after today shows only its date, dimmed.
   - No day is highlighted: not today and not the selected day of the calendar sheet.
6. **Summary line.** One line, for example "20일에 걸쳐 35시간". Only the day part ("20일에 걸쳐") has visual weight; the time part is quiet.
   The day part counts the days of the month with a completed session, and the time part is the month total.
   Both are the same values as the calendar's month card.
7. **The image goes out only by the student's own action** (decision 7).
   The image holds no session time of a day, no start time and no weekly review note.

## Data rules

The image reads the same values as the 순공 calendar for the shown month, with the calendar's rules: local calendar days, a session belongs to the local day of its `startedAt`, and only a completed session counts (`SessionRecord.counts`).

- A day has a stamp when the calendar's cell for that day has a value (not "—").
- "Today" and "a day after today" use the same local day as the calendar.
- The weekday order is the calendar sheet's order (`calendar.firstWeekday`).
- The grid has as many week rows as the month needs, so the image height changes with the month (four to six rows).

Summary wording (writing session's calls, by the `user-facing-copy` rules):

- Two or more recorded days: "N일에 걸쳐", for example "20일에 걸쳐".
- One recorded day: "하루 동안".
- The time part drops a zero part: "35시간", "35시간 20분", "40분".

## Look

The values come from the approved mockup at the image's own size (402 pt wide).
Colors name the light value of the project token; the image is always drawn in the light appearance.

| Element            | Value                                                                                        |
| ------------------ | -------------------------------------------------------------------------------------------- |
| Image              | 402 pt wide, corner radius 20, padding 28 top, 32 sides, 24 bottom, `FocusCanvas` `#F8F5F0`  |
| Year "2026"        | 12, medium, `FocusSecondaryInk` `#626D7E`                                                    |
| Month "11월"       | 58, bold, line height 1.05, tracking −1, `FocusInk` `#1E2744`, 2 above and 22 below          |
| Colon mark         | top right, two dots of 11 pt with a gap of 7, 4 from the top, `AccentColor` `#AE5519`        |
| Calendar card      | `FocusCard` `#FFFFFF`, radius 16, padding 10 top, 8 sides, 6 bottom                          |
| Weekday row        | 12, medium, `FocusSecondaryInk`, 8 below                                                     |
| Week row           | 60 high, 4 top padding, a 1 pt horizontal line under the weekday row and under each week row |
| Row line           | `FocusInk` at 7% opacity; no vertical lines                                                  |
| Date               | 12, regular, monospaced digits, line height 16, centered, `FocusInk`                         |
| Date after today   | as the date, `#BCBAB5`                                                                       |
| Stamp              | 30 pt square, 3 below the date, centered in its column; see "Stamp"                          |
| Divider            | 1 pt `#DED8CE`, 14 below the calendar card, 12 above the summary                             |
| Summary, day part  | "20일에 걸쳐", 12, semibold, `FocusInk`                                                      |
| Summary, time part | " 35시간", 12, medium, `FocusSecondaryInk`                                                   |
| "온:공"            | 11, medium, `FocusSecondaryInk`, right-aligned on the summary line                           |

### Stamp

Taken from Figma node `62:2` ("주황색 순공 도장"); the rest of that frame is not carried.
The values are in a 44 × 44 unit box that is drawn at 30 pt.

- Ink color `#B65317`, the whole stamp at 93% opacity.
  This literal is used only in the share image; it is a little warmer than `AccentColor` and is decoration, not text that must meet a contrast ratio.
- Outer ring: a circle of radius 21.05, stroke 1.9.
- Inner ring: a circle of radius 17.55, stroke 0.9, at 90% opacity.
- The word "순공": 16, bold, centered, baseline at 27.5.
- Embossed impression: a shadow of the ink color at 23%, offset (0.2, 0.25), blur 0.33; and a highlight of white at 65%, offset (−0.35, −0.45), blur 0.1.
- Ink texture:
  - the stroke edge is slightly rough (Figma: fractal noise displacement of scale 0.56);
  - three "under-inked" gaps on the outer ring: ellipses of 0.9 × 1.8 along the ring at radius 21, turned along the ring, in the card color at 98%;
  - 23 small "paper grain" dots inside the stamp: ellipses of 0.3–0.8 × 0.2–0.5 in the box from 6 to 38, in the card color at 72%.
- Hand-stamped variation: each stamp turns by up to ±8°, moves by up to ±1.5 pt across and ±1 pt down or up, scales between 0.94 and 1.04, and places its gaps and dots differently.
  The variation is a function of the date only (year, month, day), never of the focus time. The same month always gives the same image.
  The stamp stays inside its own day column, so it is clear which date it belongs to.

### Not carried

- From Figma node `62:2`, everything except the stamp: its title size, its date size, its footer and the label "순공시간".
- The mock's text colors `#202C46` and `#6B6F7B`: `FocusInk` and `FocusSecondaryInk` replace them.
- Vertical lines between day columns (option A and C of the mockup).

## Rendering

- The image is rendered at a fixed width of 402 pt, scale 3, the default text size and the light appearance, as the weekly review's share card is, so it is the same at every text size and in the dark appearance of the device.
- The button follows the sheet's appearance and text size like the other header controls.

## Left to the builder

- The accessibility label and identifier of the button; keep every identifier that `UITests/FocusFlowTests.swift` reads.
- How the stamp is drawn in SwiftUI (for example `Canvas` or shapes) and how the rough edge is approximated; SwiftUI has no fractal noise filter.
- The pseudo-random function of the variation. It must not use Swift's `Hasher` or `hashValue`, because their seed changes per process.
- The DEBUG preview of the image for captures, like the weekly review's share image preview.
- The Photos usage text in the app's Info.plist today names only the weekly review image ("주간 회고 이미지를 사진 앱에 저장할 때만 사용해요."). The share sheet's "이미지 저장" also asks for the add-only permission with this text, so it must also cover this image; record the new text for the [store privacy declarations](../notes/store-privacy-declarations.md) under #255.
- Captures for approval: the image for a current month, a past month, a month of four rows and a month of six rows, and the calendar sheet with the button in light, dark and the largest accessibility text size, with access `granted` and `locked`.

## Builder decisions of issue #253

- The weeks of a month, the summary words and the stamp variation are in `App/CalendarShareRules.swift`, with host tests; the calendar sheet and the image read the same weeks.
- The stamp variation uses SplitMix64 seeded with `year * 10000 + month * 100 + day`. A host test pins the first value of the generator, so a change that would change every shared image fails.
- The image is `CalendarShareCard` in `App/CalendarShareCard.swift`. The stamp is drawn with `Canvas` in the 44-unit box; the fractal-noise roughness of the Figma edge has no SwiftUI filter, so the three gaps and the 23 grain dots carry the texture.
- The colon mark reads the `AccentColor` asset by name, because `Color.accentColor` resolves to the system blue inside `ImageRenderer`.
- The share button's glyph stops growing at the first accessibility text size. The hidden copy on the left mirrors the share button and "닫기", or "닫기" alone with access `locked`.
  When "순공시간" does not fit between the controls at its full size, as at the largest text sizes, the controls take their own row at the right and the title goes centered under them.
- The summary and the button read the same values as the month card (contract item 6), and the stamps stop at today (contract item 5). A clock set back can leave a completed session on a day after today; that day shows its dimmed date with no stamp, and the summary still counts it, as the month card does.
- The image renders again when the shown month, today or the recorded days change, never inside the view body. While there is nothing to share, the button stays a disabled button with the same identifier.
- The share preview title is "N월 순공 캘린더". The button's accessibility label is "공유하기" and its identifier is `calendarShare`.
- The Photos usage text is "주간 회고와 순공 캘린더 이미지를 사진 앱에 저장할 때만 사용해요."
- `--calendar-share-preview <mode>` shows the image in DEBUG with a fixed today of 2026-11-24, the Asia/Seoul time zone and Sunday first: `current` (November 2026, 20 days, 35 hours), `four` (February 2026), `six` (August 2026) and `one` (one day of 40 minutes).
