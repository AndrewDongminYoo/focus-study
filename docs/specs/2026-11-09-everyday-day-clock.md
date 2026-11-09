# Everyday schedule preview as a day clock

## Contract

Record the decision of [issue #85](https://github.com/AndrewDongminYoo/focus-study/issues/85): the everyday schedule preview also shows the day as a clock.
The decision was approved on 2026-11-09 and amends the [everyday schedule preview](2026-11-06-everyday-schedule-preview.md) spec, which showed the intervals only as text rows.
Primary sources are the issue, that spec, `EverydaySettingsModel.previewSegments` and `EverydaySettingsModel.dayClockFraction` in `App/EverydaySettingsModel.swift`, and `EverydayDayClock` in `App/EverydaySettingsView.swift`.

## Behavior

- The draft preview and the stored preview each show one clock above their text rows.
- The clock draws 24 hours as one turn, with midnight at the top and time running clockwise; the labels 0시, 6시, 12시 and 18시 mark the quarters.
- A restricted interval is a thick solid arc in the accent color.
  An unblocked interval is a dashed arc of the same width in the secondary text color.
  The time outside the daily range is a thin track.
- A text legend below the dial names the solid and the dashed styles, so the clock does not depend on color.
- The clock shows only when its text rows show: an invalid schedule and a layer that is off show no clock.
- `EverydaySchedule.issue` keeps every time between 00:00 and 23:55, so no arc passes midnight.
- The text rows stay below the clock with their text, accessibility labels and identifiers (`everydayDraftSegment.N`, `everydayStoredSegment.N`); they stay the accessible alternative.
- The clock is one accessibility element with the label "하루 일정표" and the identifier `everydayDraftClock` or `everydayStoredClock`.
  It is a separate row next to the text rows, and no container with an identifier holds both.
- The hour labels stop growing at the largest non-accessibility text size, because the text rows carry the times at every size.
- The stored schedule, the validation rules and the real restrictions do not change.

## Verification and boundaries

SDK tests check `dayClockFraction` at 00:00, the quarters and 23:55, and on a range that starts at 00:00 and ends at 23:55.
The synthetic preview UI tests check that each clock exists with its label, that an invalid draft shows no clock, and that at the largest Dynamic Type the clock's frame stays inside the app's width, is no taller than the space between the navigation bar and the save button, and sits above the text rows; they capture the clock.
The hour labels are hidden from accessibility, so the tests cannot read their frames; the captures show whether they clear the ticks and the band.
Light and dark captures and explicit visual approval are required before merge.
Simulator captures cannot establish spoken VoiceOver behavior or real Screen Time restrictions.
