# Choosing the weekdays of the everyday layer

Date: 2026-11-13.
Status: design for approval.
Reconciliation (2026-11-13, #126): implemented with the recommended answer of each open point and not yet run on a device; the code in `Shared/EverydaySchedule.swift`, `Shared/SessionControl.swift`, `Integration/EverydayLayerFile.swift` and `App/EverydaySettingsModel.swift` and the weekday tests in `CoreTests/`, `SDKTests/` and `UITests/FocusFlowTests.swift` are the authority. The names left to the builder are `EverydaySchedule.weekdays` (`[Int]?`) with `chosenWeekdays`, `EverydayScheduleIssue.noWeekdays`, `EverydayLockReason.removesWeekday`, `EverydayOffRefusal.dayIsOff` (checked after the revision and before the range) and `EverydayStatus.dayIsOff`, and the fixture value `--everyday-fixture weekday-off`.
Source: [issue #126](https://github.com/AndrewDongminYoo/focus-study/issues/126) and the decision of 2026-11-13 in [issue #71](https://github.com/AndrewDongminYoo/focus-study/issues/71); parent issue #39.
This document amends the [M3 design](2026-11-01-m3-schedule-layer-design.md) and its amendments only where it says so: [off for today](2026-11-08-everyday-off-today.md), [everyday status on the timer screen](2026-11-08-everyday-status-on-timer.md), [schedule preview](2026-11-06-everyday-schedule-preview.md) and [day clock](2026-11-09-everyday-day-clock.md).
It reads the [registration marker](2026-11-10-registration-marker-design.md), [stop marker](2026-11-10-stop-marker-design.md) and [access-state](2026-11-11-access-state-design.md) designs and changes none of their rules.
This document changes no code and edits none of those documents.
The implementation PR adds dated reconciliation lines to them (see [Superseded lines](#superseded-lines)).
The implementation is later work and needs the approval of this design first.

## Contract

Decided on 2026-11-13:

1. The everyday layer keeps one schedule: one daily range, at most 3 unblocked windows and one selection. The person can choose the weekdays on which the schedule applies.
2. A stored schedule without weekdays means every day, so an existing schedule keeps its behavior.
3. The strict-only editing of M3 stays. Removing today's weekday must not be a way around a restriction that applies now.
4. The decision rests on the assumption that weekday and weekend hours differ. It does not rest on a survey of how students use the app (issue #71).

Out of scope: a different range, different windows or a different app list for each weekday, more than one preset, and a range that crosses midnight.

## Evidence

### Apple documentation (read 2026-11-13)

The JSON endpoint `https://developer.apple.com/tutorials/data/documentation/deviceactivity/deviceactivityschedule.json` and the pages of its members were read on 2026-11-13.

<!-- cspell:ignore occuring -->

| Page                                                   | What it says                                                                                                                                                                                                                                                                                                      |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `DeviceActivitySchedule`                               | "A calendar-based schedule for when to monitor a device's activity." "Create a new schedule using `DateComponents` that allows your app to monitor the person's device activity during a period of time. You can set a schedule for your app to monitor on a regularly occuring basis." (spelling as on the page) |
| `intervalStart`                                        | "The date components that represent the start time for a schedule's interval." "The system uses these components to compute `nextInterval.start`."                                                                                                                                                                |
| `intervalEnd`                                          | "The date components that represent the end time for a schedule's interval." "The system uses these components to compute `nextInterval.end`."                                                                                                                                                                    |
| `repeats`                                              | "A Boolean value that indicates whether the schedule recurs." "Use `repeats` to create an activity schedule that repeats until the activity-monitoring stops."                                                                                                                                                    |
| `init(intervalStart:intervalEnd:repeats:warningTime:)` | For `repeats`: "If `false`, the extension stops receiving callbacks when the interval ends for the first time." If the current date is between the start and the end, `intervalDidStart(for:)` is called at once; otherwise it "calls at the next date matching `intervalStart`."                                 |
| `nextInterval`                                         | "`nil` if `intervalStart` and `intervalEnd` don't match any future dates." "This interval is computed using the provided date components and the `nextTimePreservingSmallerComponents` policy for the `calendar` of both date components." Without a calendar, "the system uses `Calendar.current`."              |
| `nextInterval`                                         | "The system doesn't call these methods unless the device is used during the interval."                                                                                                                                                                                                                            |

What these pages do not say, so each point stays `[UNCERTAIN]`:

- No page names a date component. None of them mentions `weekday`, `day` or any other component that a schedule may or may not carry.
- No page gives the period of a repeating schedule. "On a regularly occuring basis" and "repeats until the activity-monitoring stops" are the only sentences about repetition, and neither says that a schedule with a `weekday` component repeats once a week.
- No page says whether `intervalStart` and `intervalEnd` must carry the same components.
- The sentences about "the next date matching `intervalStart`" and the matching policy suggest that a `weekday` component would match one day a week. That is my inference, not a documented rule.
- The M3 list of [undocumented points](2026-11-01-m3-schedule-layer-design.md#apple-documentation-checked-2026-11-01) still applies: how late a callback of a repeating activity arrives, whether a repeating activity stays listed between its intervals, and what a repeating schedule does on the day of a time zone or clock change.

### Current code and specs

| Fact                                                                                                                                                                                                                                                                                                                                                             | Source                                                                                                                                                  |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| The stored schedule has `revision`, `enabled`, `rangeStart`, `rangeEnd`, `windows` and the optional `offDay`. It has no weekday.                                                                                                                                                                                                                                 | `EverydaySchedule` in `Shared/EverydaySchedule.swift`                                                                                                   |
| The range ends at 23:55 or earlier and starts before it ends, so no range crosses midnight.                                                                                                                                                                                                                                                                      | `EverydaySchedule.latestRangeEnd`, `EverydaySchedule.issue`; M3 [Times](2026-11-01-m3-schedule-layer-design.md#times)                                   |
| The schedule part of the rule is `!isOff(at:calendar:) && blocks(second:)`. The day key and the second of the day come from the same `now` and the same calendar.                                                                                                                                                                                                | `EverydaySchedule.blocks(at:calendar:)`, `dayKey(of:calendar:)`                                                                                         |
| `nextChange` looks at today and at the next day only.                                                                                                                                                                                                                                                                                                            | `EverydaySchedule.nextChange(after:calendar:)`                                                                                                          |
| The gate of the editing conditions is `stored.enabled` and `stored.isInsideRange`. It does not read `offDay`. The order of the conditions is `turnsOff`, `rangeExcludesNow`, `rangeEndsEarlier`, `unblocksTime`, then `removesSelection`.                                                                                                                        | `EverydaySchedule.lockReason`, `SessionControl.saveEveryday`, `EverydayLockReason`                                                                      |
| A layer that is on registers one range activity and one activity for each window, with the components `hour`, `minute` and `second` and `repeats: true`.                                                                                                                                                                                                         | `SessionControl.everydayActivities`, `ScreenTimeMonitoring.everydaySchedule(start:end:)`                                                                |
| An everyday callback uses its name only to take the everyday route. The convergence then reads the stored file and the time.                                                                                                                                                                                                                                     | `SessionControl.handleCallback`, `SessionControl.converge`                                                                                              |
| The file is decoded with `JSONDecoder` into a `Codable` struct. `schemaVersion` is `1`, `offDay` is optional, and the load fails on a schedule that is not valid.                                                                                                                                                                                                | `EverydayLayerFile` in `Integration/EverydayLayerFile.swift`                                                                                            |
| The timer screen calls `FocusModel.refresh()` on `NSCalendarDayChanged` and `NSSystemTimeZoneDidChange` (unless a start is in progress) and on `NSSystemClockDidChange`. The refresh runs a reconcile section and then reads the everyday status.                                                                                                                | `App/FocusView.swift`, `FocusModel.refresh` in `App/FocusModel.swift`                                                                                   |
| The settings status line for a day that is off for today names the next block as "내일". The line after the range end is "켜져 있어요 · 08:00부터 제한해요", with no day word, and an SDK test pins it.                                                                                                                                                          | `EverydaySettingsModel.statusLine`; `testStatusShowsBlockingNowAndTheNextChange` in `SDKTests/EverydaySettingsModelTests.swift`                         |
| The section "제한 시간" of the everyday form holds the toggle and the rows "제한 시작" and "제한 끝", with the footer "매일 이 시간에 고른 앱과 웹사이트를 제한해요. 앱을 열지 않아도 돼요.". The section "일정 미리보기" has the footer "편집 중인 일정이에요. 저장하면 매일 반복해요. 제한 시간 밖에는 매일 제한이 꺼져요. 집중 시간의 제한은 따로 적용해요.". | `form` in `App/EverydaySettingsView.swift`                                                                                                              |
| Each preview draws the clock first and the text rows below it. A schedule with an issue shows "시간을 확인하면 미리보기를 볼 수 있어요." with the identifier `everydayDraftInvalid` or `everydayStoredInvalid`.                                                                                                                                                  | `schedulePreview` in `App/EverydaySettingsView.swift`; `EverydaySettingsModel.previewSegments`                                                          |
| The section "잠시 풀어 두는 시간" shows `windowsIssue` as `everydayWindowsIssue`. `windowsIssue` is every schedule issue that `rangeIssue` does not take.                                                                                                                                                                                                        | `form` in `App/EverydaySettingsView.swift`; `EverydaySettingsModel.windowsIssue`, `rangeIssue`                                                          |
| The everyday screen reads the status again only when `FocusModel.everydayStatus` changes its value, and at the times of `statusReadDelay`: `nextChange` and today's range start and range end. `EverydayStatus` is `Equatable` and holds no day.                                                                                                                 | `App/EverydaySettingsView.swift` (`onChange`, `followStatus`); `EverydaySettingsModel.statusReadDelay`; `EverydayStatus` in `Shared/ControlTypes.swift` |
| `EverydaySchedule.issue` checks the rules in the order of `EverydayScheduleIssue`: `offGrid`, `outOfDay`, `rangeTooShort`, `tooManyWindows`, `windowLength`, `windowOutsideRange`, `windowsOverlap`, `windowsCoverRange`.                                                                                                                                        | `Shared/EverydaySchedule.swift`                                                                                                                         |
| The strict-only rule is pinned by `testSaveInsideTheRangeRefusesLooserEdits`, `testSaveRefusesARangeEndPulledBackToATrailingWindow`, `testAcceptedEditsKeepTheLockUntilTheStoredRangeEnd` and `testOffForTodayThenALooserEditIsRefusedUntilTheStoredRangeEnd`, and by `testLockReasonNamesTheFirstFailedConditionInTheSpecOrder`.                                | `CoreTests/EverydayControlTests.swift`, `CoreTests/EverydayScheduleTests.swift`                                                                         |
| M3 counts at most 10 registered activities of the 20 that the system allows: the focus activity, one break activity, 4 everyday activities of the stored revision, and 4 of the earlier revision during an edit.                                                                                                                                                 | M3 [Monitoring activities](2026-11-01-m3-schedule-layer-design.md#monitoring-activities)                                                                |

### Weekday numbers

A host run on 2026-11-13 (`swift`, macOS) read `Calendar.component(.weekday, from:)` for one moment, Friday 2026-11-13 12:00 UTC, in nine calendars: Gregorian, Buddhist, Japanese, one Islamic calendar, Hebrew, Chinese, ISO 8601, Persian and Republic of China.
Each one returned 6.
`firstWeekday` was 1 in eight of them and 2 in ISO 8601.
So in these calendars the weekday number of a day does not depend on the calendar system, and Sunday is 1.
`[UNCERTAIN]` This is a host observation of nine calendars, not a documented rule for every calendar, and it was not run on iOS.

## Design

### Open points for approval

These are product choices.
Each has a recommended answer in the section that it names.

1. **The control and its copy.** A row of seven day buttons in the schedule form, with a summary such as "평일" (see [The settings screen](#9-the-settings-screen)). All copy and layout there is for visual approval.
2. **The empty set.** Recommended: not allowed. A schedule needs at least one weekday, and the existing toggle stays the only way to turn the layer off (see [Strict-only editing with weekdays](#4-strict-only-editing-with-weekdays)).
3. **The timer screen on a day that is off.** Recommended: no row, as for every state in which the layer does not block now (see [The settings screen](#9-the-settings-screen)).
4. **Removing another weekday inside today's range.** Recommended: refused until the stored range end, as the removal of an app is. The alternative accepts it, because it does not loosen the rest of today (see [Alternatives considered](#alternatives-considered)).
5. **The name "매일 제한".** Recommended: keep it. A rename is not part of this design.
6. **The day word in the status line.** Recommended: the existing line after the range end keeps its copy when the next block is tomorrow, and a weekday name shows only when the next block is later than tomorrow (see [The status rows](#the-status-rows)). The alternative adds "내일" to that line for every schedule (see [Alternatives considered](#alternatives-considered)).

### Terms

- **A day that is on**: a local calendar day whose weekday is in the stored weekdays, or any day when the stored schedule has no weekdays.
- **A day that is off**: a local calendar day whose weekday is not in the stored weekdays. This is not "off for today", which is the stored `offDay` of the [off-for-today](2026-11-08-everyday-off-today.md) design.
- **The weekday of a moment**, `weekday(now)`: the weekday number of the local calendar day of `now` in the engine calendar (`SessionControl.calendar`), 1 for Sunday to 7 for Saturday. It uses the same `now` and the same calendar as `dayKey(now)` of the off-for-today design ([Today](2026-11-08-everyday-off-today.md#today)), so the two always describe the same local day.

### 1. Where the weekday rule lives

Recommended: candidate (a).
The registered schedules stay daily and time-only, and the blocking rule decides by the weekday of the local day of `now`.
A callback on a day that is off starts a lock section as on any day, and the convergence gives "not block".

| Point                                  | (a) The rule decides by the local day                                                                                                                                         | (b) The schedules carry `weekday`                                                                                                                                                                                                                                            |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Apple documentation                    | Uses only what M3 already uses: `hour`, `minute`, `second` and `repeats: true`.                                                                                               | `[UNCERTAIN]` No page that was read mentions `weekday` or the period of a repeating schedule (see [Evidence](#apple-documentation-read-2026-11-13)). A device check would have to come before the design.                                                                    |
| Registered activities                  | No change: at most 4 for a revision, and at most 10 of 20 in total, as M3 counts.                                                                                             | One activity for each chosen weekday and each part: up to 28 for one revision (7 ranges and 21 windows), above the limit of 20. With weekday ranges and daily windows it is 10 for a revision and 20 during an edit, and 22 with the focus and break activities.             |
| Activity names and the Monitor's route | No change. A name holds the revision and the part.                                                                                                                            | A new name part for the weekday, a new parser, and new rows in the marker designs, which list the everyday names.                                                                                                                                                            |
| A day change with the app not running  | Callbacks arrive on every day. On a day that is off, each one converges to "not block", so it also clears a store that a lost range-end callback left on.                     | `[UNCERTAIN]` If a `weekday` component matches one day a week, which no page says, no callback arrives on a day that is off. A store that a lost range-end callback left on then stays on through every day that is off, until the app runs or the next day that is on ends. |
| A callback of an older revision        | No change. The callback carries no weekday, and the convergence reads the stored file.                                                                                        | The name of an older revision carries a weekday that the stored file may no longer have.                                                                                                                                                                                     |
| Change to the gap tables               | No new step and no new gap. The rows keep their shape, and a day that is off adds rows in which the rule gives "not block" (see [Gaps between steps](#6-gaps-between-steps)). | New rows for a save that registers up to 7 times as many activities, for a partly registered week, and for the hybrid of weekly and daily activities.                                                                                                                        |
| Cost                                   | Up to 8 callbacks on a day that is off start a lock section that changes nothing.                                                                                             | `[UNCERTAIN]` None on a day that is off, under the same condition.                                                                                                                                                                                                           |

The shipped off-for-today design already decides by the local day inside the blocking rule: `offDay != dayKey(now)` is a line of the schedule part, and the activities stay registered on the day that is off.
The weekday line has the same form and sits next to it.
`offDay` is a one-day exception that the person makes inside the range, and the weekdays are a standing part of the schedule.
Both are read through the schedule part of the rule (`EverydaySchedule.blocks(at:calendar:)`), so every caller of the rule gets both.

### 2. The stored value and its migration

`everyday-layer.json` gets one optional field:

| Field      | Type     | Meaning                                                                                                                                 |
| ---------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `weekdays` | `[Int]?` | The weekday numbers on which the schedule applies, 1 for Sunday to 7 for Saturday, sorted and without repeats. Missing means every day. |

- `EverydaySchedule` in `Shared/` carries the value, because `Shared/` sees every field except the tokens.
- "Every day" has one stored form. A save with all seven weekdays writes no `weekdays` key.
- `schemaVersion` stays `1`, as it did for `offDay` ([Earlier builds and schema](2026-11-08-everyday-off-today.md#earlier-builds-and-schema)). The reason is the same: a bump would make an earlier build fail the read and clear the store, which is the looser direction.
- A file without `weekdays` loads as a schedule that applies every day. No migration step runs, and no file is rewritten at launch.
- The load never fails on the numbers in `weekdays`. It drops a number outside 1 to 7 and a repeated number, and when nothing is left it reads the value as missing (every day). Each of these readings blocks on the same days as the literal value or on more days, so it is the stricter direction. A read failure would clear the store, which is the looser direction; the off-for-today design treats a malformed `offDay` in the same way ([Stored off day](2026-11-08-everyday-off-today.md#stored-off-day)).
- A `weekdays` value of another JSON type fails the decode, so it is a read failure as any corrupt file is.
- Only the save writes the field, and the save refuses an empty set (see [Strict-only editing with weekdays](#4-strict-only-editing-with-weekdays)), so the load rule above is for a file that this build did not write.
- The off-for-today write replaces the whole file with the same schedule, so it keeps `weekdays` as it keeps the revision.

Earlier builds:

- A build from before this change decodes the file with `JSONDecoder`, which ignores the unknown key. That build blocks on every day, which is the stricter direction.
- A save by such a build writes no `weekdays`, so the chosen days are lost and the schedule applies every day (stricter).
- So a downgrade matters only in the stricter direction, and this design accepts it. M3 already says that a downgrade is not supported ([Earlier builds](2026-11-01-m3-schedule-layer-design.md#earlier-builds)).
- `ControlEnvelope.schemaVersion` stays `2`. `control.json` gets no field.

### 3. The blocking rule

The rule gets one line in its schedule part, before the `offDay` line:

```plaintext
everyday store blocks = the file is readable
                    and enabled
                    and (weekdays is missing or weekdays contains weekday(now))
                    and offDay != dayKey(now)
                    and access is approved (when the section knows it)
                    and rangeStart <= minute(now) < rangeEnd
                    and no window has start <= minute(now) < end
                    and not (stored focus phase == onBreak and now < breakEndsAt)
```

- The access line keeps its reconciled meaning: only a `denied` read turns the rule off ([access-state design](2026-11-11-access-state-design.md#what-each-state-does)).
- The new line belongs to the schedule part, as the `offDay` line does, and not to the break line. So M3 transition 4 (the re-block, which uses the rule without its last line) and the M3 step in transition 6 read it too, and neither applies the everyday shield on a day that is off.
- The rule is a conjunction, so the order of its lines does not change the result. The order fixes only which state the status names when two lines fail together: a day that is off is reported as a day that is off, also when `offDay` is today's key (see [Stored states and side artifacts](#5-stored-states-and-side-artifacts)).
- `weekday(now)`, `dayKey(now)` and `minute(now)` come from the same `now` and the same engine calendar.
- On a day that is off, nothing blocks. The range has no effect on that day, and the windows have no effect either, because a window only lifts a block that the range makes.
- `EverydaySchedule.nextChange` must look further than the next day. It walks from today to the same weekday of the next week (day offsets 0 to 7) and returns the first edge at which the schedule part changes. With at least one weekday chosen, the walk always reaches a day that is on.

### 4. Strict-only editing with weekdays

#### The gate

M3 applies its conditions "inside today's stored range".
A day that is off has no range, so the gate becomes:

```plaintext
the save is locked = the stored layer is enabled
                 and the stored weekdays contain weekday(now) (or are missing)
                 and stored rangeStart <= minute(now) < stored rangeEnd
```

The gate reads `enabled`, the weekdays and the range.
It does not read `offDay`, as today, and it does not read the windows.
When the save is not locked, every edit is accepted, as M3 accepts every edit outside the range.

#### The conditions

A locked save checks six conditions in this order and refuses with the first one that fails.
Condition 4 is new; the others are the five of the off-for-today design ([Refused save: conditions and their order](2026-11-08-everyday-off-today.md#refused-save-conditions-and-their-order)).

1. The layer stays on.
2. The new range contains `now`.
3. The new range ends at or after the stored range end.
4. The new weekdays contain every stored weekday. A stored schedule without weekdays has all seven.
5. At every time from `now` to the stored range end, the new schedule blocks wherever the stored schedule blocks.
6. The new selection contains every app and website of the stored selection.

- Condition 4 comes before condition 5, so the removal of today's weekday is named as a weekday change. Without that order, a schedule that no longer applies today would fail condition 5, whose message is about the windows.
- After condition 4, the new schedule applies today, so condition 5 compares times of the day only, as `blocksWherever` does today.
- Condition 4 is the same kind of rule as condition 6: inside the lock, the person can add and cannot remove.
- The refusal gets a reason for condition 4 (for example `EverydayLockReason.removesWeekday`), between `rangeEndsEarlier` and `unblocksTime`.

Besides the conditions, a schedule is valid only with at least one weekday.
The save refuses an empty set in every state, also when the layer is off, with a draft issue as for the rules of M3 [Times](2026-11-01-m3-schedule-layer-design.md#times).
The new `EverydayScheduleIssue` case comes last in the order that `EverydaySchedule.issue` checks, after `windowsCoverRange`, so every existing issue keeps its place and a draft with a time problem and no weekday names the time problem first.
[The control](#the-control) says where the screen shows the new issue and where it does not.
An empty set would mean "on, and never blocks".
That is a second way to say "off" that keeps `enabled` and the registered activities, and it would need its own strict-only rule.
The toggle stays the only way to turn the layer off, and condition 1 already covers it.

#### Single edits

"Locked" means that the gate above holds.
"Not locked" covers three cases: the stored layer is off or no layer is stored, today is a day that is off, or `now` is outside the stored range.

| Edit                                                                                | For the rest of today                          | Locked                                                                                  | Not locked                                                                           |
| ----------------------------------------------------------------------------------- | ---------------------------------------------- | --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Add a weekday that is not today                                                     | neither                                        | accepted                                                                                | accepted                                                                             |
| Add today's weekday (today is a day that is off)                                    | stricter, when `now` is inside the range       | does not occur: a locked day is already on                                              | accepted; inside the range the layer blocks at once and the save is locked from then |
| Remove a weekday that is not today                                                  | neither; looser for that later day             | refused (condition 4), until the stored range end                                       | accepted                                                                             |
| Remove today's weekday while the range contains `now`                               | looser                                         | refused (condition 4), until the stored range end                                       | does not occur: this state is locked                                                 |
| Remove today's weekday outside the range (before its start, or at or after its end) | looser before the start; neither after the end | does not occur: outside the range the save is not locked                                | accepted, as M3 accepts turning the layer off outside the range                      |
| Change weekdays together with a range, window or selection change                   | by each part                                   | each condition is checked; the first that fails names the refusal, and nothing is saved | accepted                                                                             |
| Save an empty set of weekdays                                                       | looser                                         | refused as a draft issue                                                                | refused as a draft issue                                                             |

Each row is the same while the layer is off for today, because the gate and the conditions do not read `offDay`:

| Edit while the layer is off for today                      | Locked (today is on, the range contains `now`)                                | Not locked (at or after the stored range end)                       |
| ---------------------------------------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| Add a weekday                                              | accepted; the save keeps today's `offDay`, so nothing blocks until today ends | accepted; the save keeps today's `offDay`                           |
| Remove a weekday that is not today                         | refused (condition 4)                                                         | accepted; the save keeps today's `offDay`                           |
| Remove today's weekday                                     | refused (condition 4)                                                         | accepted; the save keeps today's `offDay`, which then has no effect |
| Weekdays together with a range, window or selection change | the six conditions in their order                                             | accepted; the save keeps today's `offDay`                           |

The off-for-today section gets one more refusal in its step 1: today is a day that is off.
The app offers the action only on a day that is on, so the refusal is reached only when the local day changes during the wait (a time zone or clock change).
The gate of the action in the app (`EverydaySettingsModel.offersOffForToday`) and the strict-only message (`strictOnlyMessage`) read the new gate.

#### The lock holds after sequences of accepted edits

M3 promises that after any sequence of accepted edits, editing opens no earlier than the stored range end that the screen showed.
"The stored range end" is always the range end of today, a day that is on.
It never names a time of tomorrow: no range crosses midnight, and on a day that is off the save is not locked, so there is no lock end.
When tomorrow is a day that is off, the lock still ends at today's stored range end, and editing then stays open at least until the range start of the next day that is on.

Why the promise holds with weekday edits:

- Take a locked save at time `t` on day D, with the stored range end `E`. An accepted save keeps the layer on (condition 1), keeps `now` in the range (2), ends the range at or after `E` (3), and keeps D's weekday (4).
- So at every later time before `E`, the stored file is on, applies on D and has a range that contains that time. `E` is at 23:55 or earlier, so that time is still on day D. The gate holds, and the next save is locked again, with a range end at or after `E`.
- By induction over the accepted saves, no sequence of accepted edits opens editing before `E`. A weekday edit adds nothing to the argument except condition 4.
- A save that is not locked can make any change, as in M3. It can also start a lock (add today's weekday inside the range, or turn the layer on inside the range); that is the stricter direction.

Sequences, with the stored schedule Monday to Friday, 08:00-18:00, lunch 12:00-13:00, unless the row says otherwise:

| Sequence                                                                                    | Result                                                                                                                                                                                    |
| ------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Monday 10:00, remove Monday                                                                 | Refused by condition 4. The lock ends at 18:00.                                                                                                                                           |
| Monday 10:00, remove Wednesday                                                              | Refused by condition 4. The same edit is accepted from 18:00.                                                                                                                             |
| Monday 12:30, during lunch, remove Monday                                                   | Refused by condition 4. The gate reads the range, not the window.                                                                                                                         |
| Monday 10:00, add Saturday; Monday 10:05, remove Saturday                                   | The first save is accepted. The second is refused by condition 4, because Saturday is now stored. It is accepted from 18:00, as the removal of an app that was added inside the range is. |
| Monday 10:00, add Saturday and move the range end to 20:00; Monday 18:30, remove Monday     | The first save is accepted, and the lock now ends at 20:00. The second is refused, because 18:30 is inside the stored range.                                                              |
| Monday 10:00, add Saturday and move the range start to 10:00; Monday 10:05, remove Monday   | The first save is accepted, as M3 accepts a range that still contains `now`. The second is refused by condition 4. The lock still ends at 18:00.                                          |
| Monday 10:00, remove Monday and add an app and remove the lunch window in one save          | Refused by condition 4. Nothing of the save is stored, also not its stricter parts.                                                                                                       |
| Monday 10:00, turn the layer off for today; Monday 10:05, remove Monday or Wednesday        | Refused by condition 4. The gate does not read `offDay`.                                                                                                                                  |
| Monday 10:00, turn the layer off for today; Monday 10:05, add Saturday                      | Accepted. The save keeps today's `offDay`, and Saturday blocks by the schedule.                                                                                                           |
| Monday 18:00, remove Monday                                                                 | Accepted. Monday's range is over, and no later Monday blocks. M3 accepts turning the layer off at the same moment.                                                                        |
| Monday 19:00, remove Tuesday; Tuesday 10:00                                                 | Accepted on Monday. Tuesday is a day that is off: nothing blocks, and every edit is accepted. M3 accepts turning the layer off on Monday at 19:00, with the same result for Tuesday.      |
| Monday 07:59, remove Monday                                                                 | Accepted, as M3 accepts every edit before the range start.                                                                                                                                |
| Saturday 10:00 (a day that is off), add Saturday; Saturday 10:05, remove Saturday           | The first save is accepted, the layer blocks at once, and the save is locked until 18:00. The second is refused by condition 4.                                                           |
| Saturday 10:00 (a day that is off), turn the layer off, remove an app, or shorten the range | Accepted. Nothing blocks today, so no edit loosens a restriction that applies now.                                                                                                        |
| Sunday 23:58, remove Monday                                                                 | Accepted. Monday is then a day that is off. M3 accepts turning the layer off at the same moment.                                                                                          |
| Monday 10:00, a stricter save; Monday 12:00, a callback of the earlier revision             | The callback takes the everyday route, and the convergence reads the stored file. The callback carries no weekday.                                                                        |
| Monday 10:00, the file is unreadable, then a save                                           | Treated as no stored layer, as in M3, so any weekdays are accepted. The person could already save any schedule in that state.                                                             |
| Monday 10:00, a time zone or clock change makes the local day a Sunday                      | The gate and the rule read the new local day: nothing blocks, and the save is not locked. M3 does not protect against a clock change, and this design keeps that.                         |
| Monday 10:00, an earlier build saves the schedule                                           | That build writes no `weekdays`, so the schedule applies every day (stricter).                                                                                                            |

One loosening of later days is already possible inside the lock in M3 and stays: a range start moved up to `now` unblocks the earlier hours of every later day.
This design does not change that rule and adds no second path of that kind.

### 5. Stored states and side artifacts

The M3 [tables](2026-11-01-m3-schedule-layer-design.md#stored-states-and-side-artifacts) and the off-for-today [table](2026-11-08-everyday-off-today.md#stored-states-and-side-artifacts) stay, and they get one more stored everyday state: "On, a day that is off", which means `enabled` and a `weekdays` value that does not contain `weekday(now)`.
"S" is the stored everyday selection, and "empty" is a store without a shield setting.

| Stored everyday state                                            | Everyday store after the convergence              | Everyday activities                                           | Everyday file                                         | What removes the rest                                                      |
| ---------------------------------------------------------------- | ------------------------------------------------- | ------------------------------------------------------------- | ----------------------------------------------------- | -------------------------------------------------------------------------- |
| No file, or a layer that is off                                  | empty                                             | none                                                          | none, or kept                                         | Convergence step 3 clears the store. Step 2 stops every everyday activity. |
| On, a day that is on, the schedule blocks now                    | S; empty only during a break before `breakEndsAt` | the stored revision, and others only while it is not complete | kept; a save or the off-for-today section replaces it | Convergence step 3 applies S. Step 2 stops the other revisions.            |
| On, a day that is on, the schedule does not block now (the time) | empty                                             | the stored revision, and others only while it is not complete | kept; a save or the off-for-today section replaces it | Convergence step 3 clears the store. Step 2 stops the other revisions.     |
| On, a day that is off (the weekday)                              | empty, in every focus phase                       | the stored revision, and others only while it is not complete | kept; only a save replaces it                         | Convergence step 3 clears the store. Step 2 stops the other revisions.     |
| On, off for today (a day that is on)                             | empty, in every focus phase                       | the stored revision, and others only while it is not complete | kept, as the off-for-today table says                 | Convergence step 3 clears the store. Step 2 stops the other revisions.     |

- The rows "File unreadable", "Access not approved" and "`control.json` unreadable" of the M3 tables do not change.
- On a day that is off, the activities of the stored revision stay registered. They are the only source of callbacks on the next day that is on, as on a day that is off for today.
- A day that is off does not change the focus layer. The focus phase changes the everyday store only through the break line, and on a day that is off the store is empty with or without a break.
- A schedule whose `offDay` is today's key on a day that is off is the state "On, a day that is off". It can be stored only by a save outside the range that removes today's weekday after the off-for-today action.
- The save and the off-for-today section write only with no session or a `terminal` session, as today.

### 6. Gaps between steps

No transition gets a new step.
The save keeps its five steps and their order, and it registers the same activities for any weekdays.
The convergence keeps its three steps.
The off-for-today section keeps its three steps.
What changes is the check in step 1 of the save and of the off-for-today section, and the result of the rule in convergence step 3.
So the M3 [gap table](2026-11-01-m3-schedule-layer-design.md#gaps-between-steps) and the off-for-today [gap table](2026-11-08-everyday-off-today.md#gaps-between-steps) keep their rows, and the tables below give each gap again for a weekday edit and for a day that is off.
A thrown error at a step gives the state of a process exit after the step before it, or the rollback that the transition states.
"Next section" means the next lock section in any process: an everyday or focus callback, an app launch or foreground, or an app action.

The save (M3 [Save](2026-11-01-m3-schedule-layer-design.md#save-turn-on-edit-turn-off): check, register, write, stop, converge):

| Gap                                                                                                                      | Everyday file | Everyday activities                 | Everyday store                                               | Repair and direction                                                                                                            |
| ------------------------------------------------------------------------------------------------------------------------ | ------------- | ----------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| Step 1 refuses (also for condition 4 or an empty set) or throws                                                          | earlier       | earlier                             | earlier state                                                | Nothing changed by the save.                                                                                                    |
| Exit after step 2, or step 2 or 3 throws                                                                                 | earlier       | earlier, and new ones after an exit | earlier state                                                | As the M3 row: the next section stops the new ones, and a thrown error stops them at once. No change in blocking.               |
| Exit after step 3 or 4; the save added today's weekday and `now` is inside the range                                     | new           | new, and earlier ones after step 3  | empty, looser than the new file                              | The next section applies the selection. Looser until then, and never looser than the earlier file, which blocked nothing today. |
| Exit after step 3 or 4; the save removed today's weekday (accepted only outside the range, or with a layer that was off) | new           | new, and earlier ones after step 3  | empty; blocking only if a range-end callback was lost before | With an empty store, nothing to repair. A store that was left on is cleared by the next section. Stricter until then.           |
| Exit after step 3 or 4; the save changed only weekdays that are not today                                                | new           | new, and earlier ones after step 3  | by the earlier file, which gives the same result today       | Nothing to repair in the store. The next section stops the earlier revision.                                                    |
| Exit after step 3 or 4; a locked save that also added weekdays                                                           | new           | new, and earlier ones after step 3  | by the earlier file, looser than the new one or equal        | As the M3 row "Save, exit after step 3 or 4". The added weekdays change nothing today.                                          |
| The store does not match after step 5                                                                                    | new           | new                                 | partly applied                                               | As the M3 row: each later section applies again, and the settings show the issue.                                               |

The convergence (M3 [Everyday convergence](2026-11-01-m3-schedule-layer-design.md#everyday-convergence): read, registrations, store):

| Gap                                                                                                                  | Everyday file | Everyday activities                      | Everyday store           | Repair and direction                                                                                                           |
| -------------------------------------------------------------------------------------------------------------------- | ------------- | ---------------------------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| A day that is on: range start or window end, callback lost, late, or exit before step 3                              | stored        | stored                                   | not blocking             | As the M3 row. The next section. Looser until then.                                                                            |
| A day that is on: range end or window start, callback lost, late, or exit before step 3                              | stored        | stored                                   | blocking                 | As the M3 row. The next section. Stricter until then, also after midnight when the next day is off.                            |
| A day that is off: any edge, callback lost, late, or exit before step 3, with an empty store                         | stored        | stored                                   | empty                    | The rule gives "not block" at every edge of the day. Nothing to repair.                                                        |
| A day that is off: range start, callback lost, late, or exit before step 3, with a store that the day before left on | stored        | stored                                   | blocking                 | The next section clears it: a later edge of the same day, a focus callback, or an app section. Stricter until then.            |
| Step 2 throws on a day that is off                                                                                   | stored        | stored revision incomplete, earlier kept | empty, by step 3         | As the M3 row: each later section that may register registers again. A missing part matters from the next day that is on.      |
| Step 1: the file is unreadable                                                                                       | unreadable    | unchanged                                | empty                    | As the M3 rows. On a day that is off, the store is empty in both cases, so there is no change in blocking.                     |
| Midnight between a day that is on and a day that is off, with no section                                             | stored        | stored                                   | empty                    | The range ended at 23:55 or earlier, so a store that followed the schedule is already empty. No section is needed at midnight. |
| A time zone or clock change moves the local day to another weekday                                                   | stored        | stored                                   | by the earlier local day | As the M3 rows: the app converges on the change, and without the app the next callback does. Either direction until then.      |

The off-for-today section (check, write, converge):

| Gap                                               | Everyday file | Everyday activities | Everyday store | Repair and direction                                                                                                                                                       |
| ------------------------------------------------- | ------------- | ------------------- | -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Step 1 refuses because today is a day that is off | stored        | by the convergence  | empty          | As the off-for-today row "Section step 1 refuses for another reason": the section writes nothing, and its convergence runs as in every app section. No change in blocking. |
| Every other gap of the section                    | as its row    | as its row          | as its row     | The off-for-today rows apply unchanged. The write keeps `weekdays`.                                                                                                        |

The marker designs list the registrations and stops of each lock section by activity name.
This design adds no registration, no stop and no name, so their rows do not change.

### 7. One-shot callbacks and their recovery

No callback becomes an edge action.
Each one still starts a lock section, and the convergence makes the store match the rule at the time of the section.

No edge is at the day change, except a range that starts at 00:00.
A store that follows the schedule is empty from the range end to midnight, so the weekday changes while nothing is blocked.

| Callback                                                  | Result of the rule                                                      | A lost callback costs                                                                                             | Recovery                                                                                                                 |
| --------------------------------------------------------- | ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Range start on a day that is off                          | not block                                                               | Nothing, when the store is empty. A store that the day before left on stays on.                                   | Each later edge of that day (window start, window end, range end) clears it, as does a focus callback or an app section. |
| Window start or window end on a day that is off           | not block                                                               | Nothing, when the store is empty.                                                                                 | As above.                                                                                                                |
| Range end on a day that is off                            | not block                                                               | Nothing, when the store is empty.                                                                                 | As above; then the next day's range start.                                                                               |
| Range end of a day that was on                            | not block                                                               | The layer stays on after the range end, into the night and the next morning (stricter). This is the M3 row.       | The next section. When the next day is off, its range start is the first everyday callback that clears the store.        |
| Range start of a day that is on, after a day that was off | block, unless a window starts too                                       | The layer starts late (looser). This is the M3 row.                                                               | The next section: a window end of the same day, a focus callback, or an app section.                                     |
| Window start or window end of a day that is on            | as M3                                                                   | As M3.                                                                                                            | As M3.                                                                                                                   |
| Range start at 00:00, delivered before midnight           | by the earlier day: not block, because no range contains 23:55 to 00:00 | The new day starts late (looser). `[UNCERTAIN]` M3 and the off-for-today design expect that no callback is early. | The next section.                                                                                                        |
| Any callback that is delivered after midnight             | by the new local day, because the section reads its own `now`           | Nothing.                                                                                                          | None needed.                                                                                                             |

Worst cases:

- **A day that is off stays blocked.** This needs a lost range-end callback on the day before. From that range end to the range start of the day that is off, the store stays on with no everyday callback due; that is the M3 row "the layer stays on after the range end", which M3 already has on every day. From the range start of the day that is off, each of its 2 to 8 edges clears the store when it is delivered, so the block lasts past the range start only while every one of them is lost and the app does not run. The system delivers a callback only when the device is used, so the first use at or after the range start is the first time that the block can clear without the app.
- **A day that is on stays open.** This needs a lost range-start callback on that day. The layer stays off until the next section, and with no window and no app use, until the range end of that day. That is the M3 worst case, and it is no longer with weekdays: the callbacks of a day that is off before it do not change it, and the next day that is on has its own range start.
- `[UNCERTAIN]` With candidate (b), if a `weekday` component matches one day a week, the first worst case would last through every day that is off, until the app runs or the next day that is on ends, because no callback would be due on those days. This is one reason for candidate (a).
- How late a callback of a repeating activity arrives is `[UNCERTAIN]`, as in M3.

The callback routing in `handleCallback`, the bounded lock retry and the marker rules do not change.
A callback on a day that is off can still reach the M3 late-break reconcile for a session, as on any day.

### 8. Day changes

| Case                                             | What happens                                                                                                                                                                                                                                                                                                                                                      |
| ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Midnight                                         | Confirmed from M3 [Times](2026-11-01-m3-schedule-layer-design.md#times) and `EverydaySchedule.issue`: the range starts before it ends and ends at 23:55 or earlier. So no blocked time contains midnight, and every blocked moment has one weekday. No section has to run at midnight.                                                                            |
| A range that starts at 00:00                     | The range activity's `intervalDidStart(for:)` is due at 00:00 and evaluates the new day. With the app in front, `NSCalendarDayChanged` also runs a lock section.                                                                                                                                                                                                  |
| A time zone change                               | `weekday(now)`, `dayKey(now)` and `minute(now)` are computed again in the new zone. When the local date changes, a day that is on can become a day that is off (looser) or the reverse (stricter). The app converges on `NSSystemTimeZoneDidChange`; without the app, the next callback does. `[UNCERTAIN]` What a repeating schedule does on that day, as in M3. |
| A manual clock change                            | As a time zone change, in either direction. A clock set to a day that is off unblocks the layer. M3 does not protect against a clock change, and this design keeps that.                                                                                                                                                                                          |
| The app not running for several days             | Nothing stored has to be advanced. Each day's callbacks start lock sections in the Monitor, and each section evaluates the rule for its own local day. A stale `offDay` matches no later day.                                                                                                                                                                     |
| A callback of an older revision                  | It takes the everyday route, and the convergence reads the stored file and the time. The name carries no weekday, so an older revision cannot bring back a weekday that a save removed.                                                                                                                                                                           |
| A daylight saving change                         | The rule reads the local calendar day and the wall-clock time, as M3 does. A day of 23 or 25 hours has one weekday.                                                                                                                                                                                                                                               |
| A change of the calendar system or of the region | The stored numbers do not depend on the first weekday, which changes only the order on the screen. `[UNCERTAIN]` Whether every calendar gives the same weekday number for the same day (see [Weekday numbers](#weekday-numbers)).                                                                                                                                 |

### 9. The settings screen

All copy and layout in this section is for visual approval.
The implementation PR shows captures in light, dark and the largest text size, and waits for approval before the merge.
The builder checks the copy with the `user-facing-copy` skill, in 해요체.

#### The control

- The section "제한 시간" of the everyday settings form gets one row below "제한 끝": the label "제한 요일", the summary of the chosen days at the trailing edge, and a row of seven day buttons below them.
- The buttons are in the order of the calendar's first weekday (`firstWeekday` of the engine calendar). Their labels are 일, 월, 화, 수, 목, 금 and 토.
- Reconciliation (2026-11-13, #126): the buttons fill one line at the standard text sizes and wrap into more lines at the accessibility sizes; their text and circles stop growing at the first accessibility size (`DynamicTypeSize.accessibility1`), because the summary next to the label carries the days at every size. A chosen day is filled and bold, a day that is not chosen is outlined.
- Each button is a toggle with a tap target of at least `FocusTheme.Layout.minimumTapTarget`. A chosen day and a day that is not chosen differ by more than color, and each button has the selected trait when its day is chosen.
- A new layer starts with all seven days chosen.
- With no day chosen, the row shows the draft issue "제한할 요일을 하나 이상 골라 주세요.", and the save button is disabled, as for the other draft issues.
- The weekday issue shows only in this row. `EverydaySettingsModel.windowsIssue` now returns every schedule issue that `rangeIssue` does not take, so it must leave out the weekday issue; otherwise the section "잠시 풀어 두는 시간" shows the weekday message as `everydayWindowsIssue`. `rangeIssue` already returns `nil` for it.
- The draft preview must not name the times as the cause of the weekday issue. When the weekday issue is the only issue of the draft, the preview line is "요일을 고르면 미리보기를 볼 수 있어요." in place of "시간을 확인하면 미리보기를 볼 수 있어요.", with the same identifier `everydayDraftInvalid`. The stored preview never reaches this state, because the load reads an empty set as every day.
- A weekday change counts as an unsaved change. `EverydaySettingsModel.sameEditableSchedule` compares the weekdays as sets, with a missing value equal to all seven.

The summary:

| Chosen days              | Summary                                                                   |
| ------------------------ | ------------------------------------------------------------------------- |
| All seven                | 매일                                                                      |
| Monday to Friday only    | 평일                                                                      |
| Saturday and Sunday only | 주말                                                                      |
| Any other set            | The short names in the order of the first weekday, for example 월, 수, 금 |
| None                     | 요일 없음                                                                 |

Other copy that changes with the control:

| Place                                              | Copy                                                                                                                                             |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Footer of the section "제한 시간"                  | 고른 요일마다 이 시간에 고른 앱과 웹사이트를 제한해요. 앱을 열지 않아도 돼요.                                                                    |
| Footer of the section "일정 미리보기"              | 편집 중인 일정이에요. 저장하면 고른 요일마다 반복해요. 제한 시간 밖과 고르지 않은 요일에는 매일 제한이 꺼져요. 집중 시간의 제한은 따로 적용해요. |
| Refused save, condition 4                          | 제한 시간에는 요일을 뺄 수 없어요. (followed by the existing sentences about the time that editing opens and the off-for-today action)           |
| Off-for-today section refuses on a day that is off | 오늘은 제한하지 않는 요일이에요.                                                                                                                 |
| Draft preview with no day chosen                   | 요일을 고르면 미리보기를 볼 수 있어요.                                                                                                           |

#### The schedule preview and the day clock

- The preview and the day clock keep showing the schedule of a day that is on: the range and its windows. They do not depend on today, as now.
- Each preview gets one text row above its clock: "제한 요일 · " and the summary, for example "제한 요일 · 평일". The stored preview reads the stored weekdays, and the draft preview reads the draft.
- The clock does not change. It is not dimmed and not hidden on a day that is off, because the preview describes the schedule that is saved or edited, and the status line says what applies today.
- A layer that is off and a schedule that is not valid show no weekday row, as they show no clock and no text rows.
- The weekday row above the clock makes the sentences of the day clock and preview specs about "above the text rows" imprecise (see [Superseded lines](#superseded-lines)). The clock stays above the segment rows, which is what the existing UI test compares.

#### The status rows

`everydayStatus(now:authorized:)` also says whether today is a day that is on.
`blocksNow` is `false` on a day that is off, and `nextChange` is the first blocked time of the next day that is on.

| Row                                                     | State                                                      | Copy                                                                                                                   |
| ------------------------------------------------------- | ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Settings row and the status line of the everyday screen | On, a day that is off                                      | 오늘은 제한하지 않는 요일이에요 · 내일 08:00부터 제한해요                                                              |
| Settings row and the status line of the everyday screen | On, off for today                                          | 오늘은 꺼 두었어요 · 내일 08:00부터 다시 제한해요 (no change when tomorrow is on; the day word follows the rule below) |
| Settings row and the status line of the everyday screen | On, a day that is on, after the range end, tomorrow is on  | 켜져 있어요 · 08:00부터 제한해요 (no change)                                                                           |
| Settings row and the status line of the everyday screen | On, a day that is on, after the range end, tomorrow is off | 켜져 있어요 · 월요일 08:00부터 제한해요                                                                                |
| Timer screen row and the completion card row            | On, a day that is off                                      | No row, by the existing rule: with no issue and `blocksNow == false` the row is hidden.                                |

The day word in front of the time of `nextChange`:

| The local day of `nextChange` | In the two lines that say that today does not block (a day that is off, off for today) | In the line "켜져 있어요"          |
| ----------------------------- | -------------------------------------------------------------------------------------- | ---------------------------------- |
| Today                         | does not occur: the next block is on a later day                                       | none, as now: "08:00부터 제한해요" |
| Tomorrow                      | 내일                                                                                   | none, as now: "08:00부터 제한해요" |
| A later day                   | The weekday, for example 월요일                                                        | The weekday, for example 월요일    |

- This rule replaces the fixed "내일" of the off-for-today line, which is wrong when tomorrow is a day that is off.
- A schedule without weekdays keeps every line that it has now (Contract 2): its next block is never later than tomorrow, so no weekday name shows. `testStatusShowsBlockingNowAndTheNextChange` and the off-for-today status test keep their expected strings.
- The line "지금 제한하고 있어요 · 18:00까지" does not change, because its `nextChange` is always today.
- The day word is computed from the time of the status read, not from a later clock read: `statusLine` gets that time as a parameter (`statusReadAt` on the everyday screen; the settings row has no such value now, so the builder adds one).
- Any `issue` keeps its existing line in the settings and `매일 제한을 확인해 주세요 ›` on the timer screen, on every day.
- The strict-only message of the everyday screen shows only when the new gate holds, so it does not show on a day that is off.
- The off-for-today action is offered only on a day that is on.

At midnight the weekday changes without an edge of the schedule.

- The timer screen calls `FocusModel.refresh()` on `NSCalendarDayChanged`, and the everyday screen reads the status again when that refresh changes the value of `FocusModel.everydayStatus`.
- The status value changes at a midnight between a day that is on and a day that is off, because it says whether today is a day that is on, and at the midnight that ends an off-for-today day, because `offForToday` changes.
- The status value does not change at a midnight between two days that are on or between two days that are off: `nextChange` is the same moment before and after. Between two days that are on, the line has no day word, so it stays right. Between two days that are off, a weekday name can become "내일".
- So `statusReadDelay` gets one more boundary for the settings row and the everyday screen: the next local midnight, while the stored layer is on and the line has a day word. The read after it gives the line a new read time, and the line is drawn again with the day word of the new day, also when the status value is equal.
- `[UNCERTAIN]` Whether SwiftUI draws the line again after an assignment of an equal status value was not run. The builder makes the read time part of what the row observes, and an SDK test pins the line on both sides of a midnight between two days that are off.

#### Accessibility identifiers

Every existing identifier stays.

| Element                           | Identifier                                                                                   |
| --------------------------------- | -------------------------------------------------------------------------------------------- |
| Day button                        | `everydayWeekday.1` to `everydayWeekday.7`, by weekday number (1 is Sunday), not by position |
| Summary in the row "제한 요일"    | `everydayWeekdaysSummary`                                                                    |
| Draft issue for no day            | `everydayWeekdaysIssue`                                                                      |
| Weekday row of the draft preview  | `everydayDraftWeekdays`                                                                      |
| Weekday row of the stored preview | `everydayStoredWeekdays`                                                                     |

- The row of buttons gets no identifier on its container, so that it does not hide the identifiers of the buttons.
- The accessibility label of a button is the full name of the day, for example 월요일.

### 10. Superseded lines

See [Superseded lines](#superseded-lines) below; the list is a top-level section, as in the other designs.

### 11. Verification

See [Physical-device verification](#physical-device-verification) and [Verification for the implementation](#verification-for-the-implementation) below.

## Alternatives considered

**Schedules with a `weekday` component, one activity for each chosen weekday (candidate (b)).**
Rejected for the reasons in [Where the weekday rule lives](#1-where-the-weekday-rule-lives): the behavior of `weekday` in a repeating schedule is not documented, the count passes the limit of 20 activities, and, if the component matches one day a week (`[UNCERTAIN]`), a day that is off would have no callback that clears a store left on.

**Register the activities only on days that are on, by a daily section.**
The app would stop the activities before a day that is off and register them again before a day that is on.
Without the app, no section runs at midnight, so the Monitor would have to do it from a callback, and an `intervalDidStart(for:)` section never registers (M3 convergence).
It adds a stored "registered for which day" state with its own gaps.

**Accept the removal of a weekday that is not today inside the lock.**
The M3 conditions speak of "the rest of today", and such a removal does not loosen the rest of today.
Rejected as the recommendation, and listed as open point 4: the off-for-today design refused "every edit is accepted once the layer is off for today" because it makes a later day looser without a wait until the stored range end.
With one rule for all weekdays, the person and the tests have no case that depends on which day is removed, and the wait is the same as for the removal of an app.

**Allow the empty set of weekdays.**
Rejected: it is a second "off" with `enabled` still `true`, and inside the lock it would be the removal of today's weekday.

**A read failure for a malformed `weekdays` value.**
Rejected: a read failure clears the store (looser), and the reading in [The stored value and its migration](#2-the-stored-value-and-its-migration) blocks on at least the same days.

**`schemaVersion` `2`.**
Rejected, as for `offDay`: an earlier build would fail the read and clear the store.

**Store the days that are off, or a 7-bit mask.**
A list of the days that are on reads directly in the file and in the rule, and a missing value already means every day.

**Add "내일" to the line "켜져 있어요 · 08:00부터 제한해요" after the range end.**
One day-word rule for every line is simpler to state.
Rejected as the recommendation, and listed as open point 6: it changes the copy of a schedule without weekdays, which Contract 2 keeps, it fails `testStatusShowsBlockingNowAndTheNextChange`, and "내일" would be wrong after a midnight between two days that are on, where the status value does not change.

**Dim the day clock, or show a row on the timer screen, on a day that is off.**
The preview would then depend on today, and the idle timer screen shows no row for any state in which the layer does not block now.
The second is open point 3.

## Superseded lines

The implementation PR adds dated reconciliation lines (it does not rewrite the original lines) for these.

M3 design:

- Intent, "The layer runs every day without the app.", and Goals, "The layer turns on and off every day without the app.": the callbacks arrive every day, and the layer blocks only on the chosen weekdays.
- Goals, "The same range applies every day of the week.": on every chosen weekday.
- Non-goals, "Rules per weekday, or a different range on some days.": the choice of weekdays is now allowed; a different range on some days stays excluded.
- Decisions by me, 2, "The same rules apply every day.": on every chosen weekday.
- [Editing rules](2026-11-01-m3-schedule-layer-design.md#editing-rules), "Outside today's stored range (before its start or at or after its end), every edit is accepted" and "Inside today's stored range": a day that is off has no range, and the conditions get the weekday condition; the reconciliation line of 2026-11-08 that says "the five conditions" becomes six.
- [Stored schedule](2026-11-01-m3-schedule-layer-design.md#stored-schedule), the field table: the optional `weekdays`.
- [The blocking rule](2026-11-01-m3-schedule-layer-design.md#the-blocking-rule): the weekday line.
- [Range start and end, window start and end](2026-11-01-m3-schedule-layer-design.md#range-start-and-end-window-start-and-end), the row "Range activity `intervalDidStart`: block (unless a window starts too)" and the sentence "a lost range-start or window-end callback leaves the layer off until the next day's range start": on a day that is off, every edge gives "not block".
- [Stored states and side artifacts](2026-11-01-m3-schedule-layer-design.md#stored-states-and-side-artifacts): the state "On, a day that is off".
- [Status for the app](2026-11-01-m3-schedule-layer-design.md#status-for-the-app), "the next time that the result changes": it can be up to 7 days ahead, and the status says whether today is a day that is on.
- [Status for the app](2026-11-01-m3-schedule-layer-design.md#status-for-the-app), the reconciliation line of 2026-11-08, "its next change is the next day's first blocked time": the first blocked time of the next day that is on.
- Device verification, step 4, "Check on the next day that the layer starts again at the range start without the app.": on the next day that is on.

Off-for-today design:

- Contract, 3, "the next day's range blocks again by the stored schedule": the range of the next day that is on.
- Contract, 4, "the existing strict rule (M3 Editing rules, five conditions)", and Contract, 5, "which of the five conditions failed": six conditions, and the gate also reads the weekdays.
- [The blocking rule](2026-11-08-everyday-off-today.md#the-blocking-rule), the rule block: the weekday line.
- [The off-for-today section](2026-11-08-everyday-off-today.md#the-off-for-today-section), the refusals of step 1: one more, for a day that is off.
- [Refused save: conditions and their order](2026-11-08-everyday-off-today.md#refused-save-conditions-and-their-order), "the five M3 conditions": six, with the weekday condition as the fourth.
- [Editing after the layer is off for today](2026-11-08-everyday-off-today.md#editing-after-the-layer-is-off-for-today), "inside today's stored range, with the stored layer on, the five conditions apply" and "The gate reads `enabled` and the range, not `offDay`": six conditions, and the gate also reads the weekdays.
- [Gaps between steps](2026-11-08-everyday-off-today.md#gaps-between-steps), the row "Next day's first blocked time: callback lost, late, or exit before step 3": the first blocked time of the next day that is on.
- [Callbacks](2026-11-08-everyday-off-today.md#callbacks), "the first time on the next day that the rule can give 'block'" and "A lost or late callback at the next day's first blocked time": on the next day that is on.
- [Guards across sequences of accepted actions](2026-11-08-everyday-off-today.md#guards-across-sequences-of-accepted-actions):
  - The row "Off for today at 10:00, then a looser edit at 10:05", "Refused by the five conditions": six.
  - The row "Off for today at 10:00, then a stricter edit at 10:05", "block from the next day's range": from the range of the next day that is on.
  - The row "Off for today, then a looser edit after the stored range end, then the next day", "the next day blocks by the new schedule": the next day that is on.
  - The row "Off for today on day D, then the next day", "The range blocks by the stored schedule, the five conditions apply inside it": on the next day that is on, with six conditions.
- [Status for the app](2026-11-08-everyday-off-today.md#status-for-the-app), "`nextChange` is the first time at or after the start of the next local day" and the settings row that names the next day: the next day that is on, with the day word of [The status rows](#the-status-rows).
- [Status for the app](2026-11-08-everyday-off-today.md#status-for-the-app), "The everyday settings screen keeps its strict-only message inside the range, also when the layer is off for today, because the five conditions still apply.": six conditions, and the message shows only on a day that is on.
- [Status for the app](2026-11-08-everyday-off-today.md#status-for-the-app), "`EverydaySettingsModel.followStatus` reads the status again at `nextChange` as before, and the everyday settings screen also reads it at today's stored range start and range end": the settings row and the everyday screen also read at the next local midnight while the line has a day word.
- Device verification, step 16, "on the next day the shield comes back at the range start", and step 17, "nothing is shielded until the next day", and the unverified note "the next day's first blocked edge after a day that was off": the next day that is on.
- Verification for the implementation, "the five refusal reasons in their order": six.

Day clock and schedule preview:

- [Day clock](2026-11-09-everyday-day-clock.md), "The draft preview and the stored preview each show one clock above their text rows." and "The text rows stay below the clock with their text, accessibility labels and identifiers": the weekday row is a text row above the clock; the segment rows stay below it.
- [Schedule preview](2026-11-06-everyday-schedule-preview.md), the reconciliation line of 2026-11-09, "a 24-hour clock now shows above the text rows of each preview": above the segment rows and below the weekday row.
- [Schedule preview](2026-11-06-everyday-schedule-preview.md), "State that times outside the daily range have no everyday restriction": also the days that are not chosen; each preview gets the weekday row.

Other documents:

- [Everyday status on the timer screen](2026-11-08-everyday-status-on-timer.md), the two marker designs and the access-state design: no line becomes false.
- `AGENTS.md` project scope, "it runs every day without the app": on the chosen weekdays.

The copy that changes in code (the two footers, the off-for-today status line and the invalid-preview line) is in [The settings screen](#9-the-settings-screen).
The list was checked on 2026-11-13 with a search of the M3 and off-for-today designs for "five", "every day", "next day" and "tomorrow", and of the preview, day clock and timer-status specs for "every day", "next day", "above" and "below".

## Physical-device verification

Record each result in the [device matrix](../notes/screen-time-device-matrix.md), with device, OS version, scheduled time and observed time.
Each install and each run that applies real restrictions needs its own explicit approval.
Simulator results and synthetic tests cannot establish any of these results.

1. Save a layer with one app, a range that starts in about 10 minutes and lasts at least 60 minutes, and every weekday chosen except today's. Close the app. Use the device across the range start, with the app not running. Record that the app stays free before and after the range start.
2. On the same day, inside the range, open the everyday screen. Record the status line, that the strict-only message and the off-for-today action are absent, and that a removal of an app is accepted.
3. Leave the layer as in step 1 until the next day, which is a day that is on, with the app not running. Record when the shield appears at the range start.
4. On a day that is on, inside the range, try to remove today's weekday, then another weekday. Record that each save is refused with the weekday message. Add a weekday and record that the save is accepted and the shield stays.
5. On a day that is off, inside the range, add today's weekday. Record when the shield appears, and that a removal of today's weekday is then refused.
6. On a day that is on, after the range end, remove the next day's weekday. On the next day, repeat step 1 without a new save.
7. On a day that is on, leave the device unused from before the range end until the next day, a day that is off, so that the range-end callback is late. Record the shield state at the first use before the range start and at the first use after it.
8. On a day that is on, turn the layer off for today, then check on the next day that is on that the shield comes back at the range start, with a day that is off between them if the calendar allows.

Unverified until those steps run:

- That a day that is off stays unblocked across the range start with the app not running.
- That the next day that is on blocks at the range start with the app not running.
- When a store that a late range-end callback left on is cleared on a day that is off `[UNCERTAIN]`.
- The behavior on the day of a time zone or clock change `[UNCERTAIN]`, as in M3.
- The iOS 17 runtime.

## Verification for the implementation

Follow `AGENTS.md` and [README verification](../../README.md#실행과-검증).

- `Shared/` changes, host tests in `CoreTests/`:
  - The rule for each weekday case: a day that is on, a day that is off, a schedule without weekdays, one chosen day, and the rule without its break line (the re-block) and with `ending` (the session end) on a day that is off.
  - `nextChange` across days that are off, up to the same weekday of the next week, and together with an `offDay`.
  - Validity: an empty set is a schedule issue, and it is the last one in the order of `EverydaySchedule.issue`.
  - The gate and the six conditions in their order, each single edit of [Single edits](#single-edits), and every row of the sequence table of [Strict-only editing with weekdays](#4-strict-only-editing-with-weekdays) as a sequence of saves, with the lock end checked after each accepted save.
  - The same sequences while the layer is off for today, and the new refusal of the off-for-today section.
  - Day changes with fixed calendars and time zones: 23:59:59 and 00:00:00 around a change between a day that is on and a day that is off, a range that starts at 00:00, a time zone change that moves the local day, a daylight saving day, and the weekday number in the calendars of [Weekday numbers](#weekday-numbers).
  - A convergence on a day that is off clears a store that was left on and keeps the activities of the stored revision.
  - The existing tests keep their meaning with a schedule without weekdays.
- The separate-process race check, because the check inside the `saveEveryday` section changes. It keeps its `PASS` lines.
- `Integration/` changes, SDK tests: the file with and without `weekdays`, a file that an earlier build wrote, the load of a malformed value (numbers outside 1 to 7, repeats, an empty array), a save of all seven days that writes no key, and the off-for-today write that keeps `weekdays`. The repeating schedules keep their components.
- `App/` changes, SDK tests: the summary for each row of its table in calendars with a first weekday of Sunday and of Monday, the draft issue (shown in the weekday row, with `windowsIssue` and `rangeIssue` both `nil`), the preview line for a draft with no day, the unsaved-change comparison, the status line for each state with each day word, the status line on both sides of a midnight between two days that are off, the `statusReadDelay` boundary at the next local midnight, the unchanged strings of `testStatusShowsBlockingNowAndTheNextChange` and of the off-for-today status test for a schedule without weekdays, the timer line on a day that is off, the refusal message for condition 4, and `offersOffForToday` and `strictOnlyMessage` on a day that is off.
- UI tests with a DEBUG fixture that never touches real restrictions: the day buttons and their identifiers, the summary, a save that is refused for condition 4, and a launch on a day that is off (a new `--everyday-fixture` value). Captures in light, dark and the largest text size for the visual approval.
- Compile the App and the Monitor, and build an unsigned device Release build.
- The [physical-device verification](#physical-device-verification) above. Without it, the behavior on a real device stays unverified.

## Left to the builder

- The type of the weekdays in `Shared/` (for example a set) and the name of the accessor that gives all seven days for a missing value.
- The names of the new lock reason, the new schedule issue, the new off-for-today refusal and the new status value.
- How the settings row and the everyday screen pass the read time to `statusLine` and draw the line again after the midnight read.
- The layout of the day buttons at the largest text size, and how a chosen day differs from a day that is not chosen.
- The exact copy, checked with the `user-facing-copy` skill, within what the visual approval accepts.
- The DEBUG fixture value for a day that is off.
