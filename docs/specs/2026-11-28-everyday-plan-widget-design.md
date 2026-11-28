# Everyday plan widget

Date: 2026-11-28.
Status: design for approval.
Source: [issue #270](https://github.com/AndrewDongminYoo/focus-study/issues/270), with its open points decided on 2026-11-28, and Figma frame `93:602`.
This document amends the [home screen widget design](2026-11-13-home-widget-design.md) only where [Contract](#contract) and [Data path](#data-path) say so, and that design carries a dated reconciliation line that points here.
It changes no code, and the implementation needs its approval first.
Current code was read at `116ffd4`.

## Contract

Decided on 2026-11-28:

1. A second home screen widget shows today's plan of the everyday layer: the range, the restricted and unblocked spans, where now is in them, and the next change.
   It is a separate widget kind next to `TodayFocusWidget`, in the same `FocusActivity` extension, in the `systemMedium` family only.
2. Contract 3 of the home screen widget design does not apply to this widget kind.
   This widget says "제한" and "해제" for the spans of the stored schedule, as planned times, the way the idle timer screen says `매일 제한 중 · HH:MM까지` ([everyday status on the timer screen](2026-11-08-everyday-status-on-timer.md)).
   It never says that a restriction was applied or lifted, and it shows no selection token, app name, domain or usage data.
   `TodayFocusWidget` keeps contract 3.
3. The widget shows the plan only.
   It does not read a session state, so a focus break, which lifts the everyday layer for up to 3 minutes ([M3](2026-11-01-m3-schedule-layer-design.md#break-interaction)), does not change it.
   The visible title `오늘의 제한 계획`, the accessibility text and the widget gallery description say that it is a plan.
   The frame's title `오늘의 매일 제한` is not used, because a break or a revoked access would then read as a false statement.
4. On a day without restriction the timeline is empty, and one line says why.
5. The widget is free: it shows the plan whatever the paid access is, because the everyday layer stays free ([paid unlock](2026-11-24-paid-unlock-decision.md)).

Out of scope: the small, large and accessory families, StandBy (it offers square widgets only), a tap target other than opening the app, any control in the widget, and any read of the engine's status (`EverydayStatus`) by the widget.

## Data path

- The app writes `TodaySnapshot/everyday-plan.json` in the App Group container, next to `today.json`.
  It holds only the plan fields of `EverydaySchedule`: `enabled`, `rangeStart`, `rangeEnd`, `windows` (kind, start, end), `weekdays` and `offDay`, a `needsCheck` flag and a schema version.
  It holds no token, revision or engine state other than that flag.
- The app is the only writer of `everyday-layer.json` (`App/FocusRuntime.swift`, `services.writeEveryday` and `services.writeEverydayOffDay`); the Monitor and the App Intents extension only read it.
  So the app writes the plan file after each successful everyday save, after "off for today" succeeds, and at each launch and each everyday status read when the content differs from the file, and then asks WidgetKit to reload the new kind.
- What the app writes for each read of the everyday file:

| App read                                                              | Plan file                           |
| --------------------------------------------------------------------- | ----------------------------------- |
| A schedule, and the everyday status has no `issue`                    | the schedule, `needsCheck == false` |
| A schedule, and the everyday status has an `issue` or access `denied` | the schedule, `needsCheck == true`  |
| The file is missing                                                   | no schedule                         |
| A read or decode error                                                | no write: the last plan file stays  |

- Known gap: after a `denied` access read, the shared engine stops every everyday activity and clears the shield but leaves `enabled` in the file as it is.
  The plan file shows that state only after the app reads it and writes `needsCheck == true`; until then the widget shows a plan that blocks nothing.
- The widget reads that one file.
  The `FocusActivity` target compiles one new `Shared/` file with the plan value, its pure rules and the weekday summary, and still compiles no file that can open the control store, a selection file, the registration marker or the history store; `CoreTests/WidgetSourceListTests.swift` pins the new source list.
  `EverydaySettingsModel.weekdaySummary` moves to that file, and the settings screen calls it there.
- The widget computes everything else from the stored plan and its own calendar: whether today is a chosen weekday, whether `offDay` is today, the spans and the next change.
  So a new day needs no write from the app.

## States

| Plan state                                | View                                                       |
| ----------------------------------------- | ---------------------------------------------------------- |
| No file, or a file with no schedule       | Empty timeline; `앱에서 매일 제한을 정해 보세요`           |
| The widget cannot read or decode the file | Empty timeline; `앱에서 확인해 주세요`                     |
| `needsCheck == true`                      | Empty timeline; `앱에서 확인해 주세요`                     |
| `enabled == false`                        | Empty timeline; `매일 제한이 꺼져 있어요` (the app's copy) |
| Today is not a chosen weekday             | Empty timeline; `오늘은 제한하지 않는 요일이에요`          |
| `offDay` is today                         | Empty timeline; `오늘은 매일 제한을 꺼 두었어요`           |
| A restriction day                         | Timeline and the two blocks below                          |

The lines of the empty states are proposals for the copy review.

## Spans

- The spans of a day are merged runs: adjacent windows (12:00–13:00 and 13:00–13:30) form one unblocked span, and the restricted spans are the parts of the range outside every window.
- A window may start at the range start or end at the range end (`EverydaySchedule.issue` refuses only a window outside the range and windows that cover the whole range), so the first or the last span of a day can be unblocked.
- The next change is the start of the next span of the other kind, or the range end.

## Layout

From Figma frame `93:602`, 364 × 170, scaled like the medium focus widget.
Every text has a Dynamic Type style, stops at `xxLarge`, and each line shrinks to 70% and then ends in an ellipsis.
The frame's 9 and 10 pt texts become `caption2` (11 pt), as the dial look amendment did for the small widget.
Every secondary text, the axis and the weekdays included, uses `#525866` in the light appearance, not the frame's `#6B6F7B` ([medium size amendment](2026-11-13-home-widget-design.md#medium-size-amendment-2026-11-27)).

| Part               | Position and size                                                         | Content                                                                                                  |
| ------------------ | ------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Title              | leading 18, top 15                                                        | `오늘의 제한 계획`, `caption` bold                                                                       |
| Weekdays           | trailing 16, top 14                                                       | `매일`, or the weekday summary, `caption2` medium                                                        |
| Axis               | leading 16 and trailing 16, top 35                                        | the range start and end only, `caption2` medium                                                          |
| Timeline groove    | 16, 51, 332 × 21, radius 6                                                | the range from start to end                                                                              |
| Spans              | inside the groove, inset 2, height 17, radius 3, 1.4 apart                | restricted: `#B65317` with a sheen; unblocked: white 72% with a sheen                                    |
| Now ticks          | at now on the axis, 1.8 × 5, above (top 43) and below (top 75) the groove | engraved ticks like the dial's; absent outside the range                                                 |
| Divider            | 182, 98, 1 × 46                                                           | ink at 8%                                                                                                |
| Left block (now)   | leading 18, tops 96, 112, 137                                             | `지금 HH:MM` (`caption2`); `제한` in `#AE5519` or `해제` in ink (`headline` bold); the span (`caption2`) |
| Right block (next) | leading 198, tops 96, 112, 137                                            | the same three styles, with the content of the next table                                                |

### Now and next

| Now                                             | Left block                                   | Right block                                                        |
| ----------------------------------------------- | -------------------------------------------- | ------------------------------------------------------------------ |
| Before the range start                          | `지금 HH:MM`, `제한 전`, `HH:MM부터` (start) | the first span: `제한` or `해제`, `HH:MM부터`, `HH:MM까지`         |
| In a restricted span, a later unblocked span    | `지금 HH:MM`, `제한`, the span               | `다음 해제`, `HH:MM부터 N분`, `그다음 제한 HH:MM–HH:MM` or nothing |
| In a restricted span, no unblocked span left    | `지금 HH:MM`, `제한`, the span               | `제한 끝`, `HH:MM` (the range end), `남은 해제 없음`               |
| In an unblocked span, a later restricted span   | `지금 HH:MM`, `해제`, the span               | `다음 제한`, `HH:MM부터`, `HH:MM까지` (the end of that span)       |
| In an unblocked span that runs to the range end | `지금 HH:MM`, `해제`, the span               | `제한 끝`, `HH:MM` (the range end), `남은 제한 없음`               |
| After the range end                             | `지금 HH:MM`, `제한 끝`, `HH:MM에 끝났어요`  | `다음 제한`, the next restriction day and its start (`내일 08:00`) |

A duration of 60 minutes or more is written in hours and minutes (`1시간 30분`).

## Timeline

- The entries are at each span boundary of today and at every 5 minutes, so `지금 HH:MM` and the now ticks are at most 5 minutes behind.
  The time shown is the entry's own time, rounded down to 5 minutes.
- The last entry is the next local midnight, and the policy is `.atEnd`, so the next day is computed without the app.
- `[UNCERTAIN]` Whether WidgetKit renders every 5-minute entry on time, and whether 288 entries a day stay within its limits.
  If not, the entries fall back to the span boundaries, and the left block and the now ticks drop the current time.

## Rendering modes

- Full color: the light palette above; the dark palette uses the dial's dark values, with restricted spans in `#F4A64A` and unblocked spans in cream at 20%.
- Accented and vibrant: flat, with the restricted spans, the now ticks and `제한` in the accent group, and every other part white with an opacity, as the dial look amendment does.
- The dark values and the flat look are proposals that a code-rendering board shows before the implementation.

## Accessibility

One element: the title, then `지금 14:20 제한, 13:00부터 16:00까지, 다음 해제 16:00부터 30분`, or the title followed by the line of an empty state.
The title in the accessibility text says "계획" in every case.

## `AGENTS.md` changes for the implementation PR

- The sentence about the Widget target: it compiles the new plan file of `Shared/`, and its App Group access is for reading `TodaySnapshot/today.json` and `TodaySnapshot/everyday-plan.json` only.
- The architecture table: the plan file, its writer in `App/` and the new widget in `Widget/`.
- The spec list: this spec as implemented.

## Verification for the implementation

- Host tests of the pure rules: the spans of a schedule with merged windows, the current span and the next change for every row of the Now-and-next table, a window at the range start and one at the range end, a non-chosen weekday, `offDay` today and on another day, midnight, and the first restriction day after a range that ends at 23:55.
- Host tests of the writer's table: each app read gives its plan file, and a read error writes nothing.
- A source-list test that the `FocusActivity` target compiles only the allowed files.
- A DEBUG preview with fixed plans and the UI test of its accessibility label.
- Captures in light, dark and the flat look, then a device check in light, dark, clear and tinted.

## Left to the builder

- The names of the plan type, the writer and the widget kind.
- Whether the plan value reuses `EverydaySchedule` or copies its fields, within the source-list rule.
- The day-key function shared with `offDay`.
