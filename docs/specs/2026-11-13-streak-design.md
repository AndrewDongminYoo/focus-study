# Display-only streak

Date: 2026-11-13.
Status: design for approval.
Source: [issue #125](https://github.com/AndrewDongminYoo/focus-study/issues/125), and the decision in [issue #43](https://github.com/AndrewDongminYoo/focus-study/issues/43).
The [2026-10-26 design](2026-10-26-focus-study-design.md) excludes rewards ("리워드는 제외한다"); that line stays, and decision 2 of the [Contract](#contract) states where a reward starts.
This document changes no code.
The implementation is later work under issue #125 and starts after this design is approved.

## Contract

Decided on 2026-11-13:

1. The app shows a streak: the number of consecutive local days, ending today or yesterday, on which at least one focus session was completed.
2. The streak is a display-only record.
   Points, badges, unlocks, rankings, comparison with friends and a "streak about to break" notification are rewards and stay out of scope.
3. Only a completed session counts, by the same rule that today's history uses for completed focus time.
   An interrupted session or a session that missed its deadline does not count.
4. The main screen stays the focus-start screen.

Out of scope: the implementation, the home screen widget of issue #124, and any change to the session rules.

## Evidence

- `App/SessionRecord.swift`: `SessionRecord` stores `id` (unique), `startedAt`, `expiresAt`, `endedAt`, `observedAt` and `reasonRaw`, and declares no other attribute option.
  `reason` decodes `reasonRaw`, and an unknown value reads as `.recoveryInterrupted`.
  `focusDuration` is above 0 only for `reason == .expired`, and `SessionSummary` counts only the records with `reason == .expired`.
- `Shared/ControlTypes.swift`: `EndReason` has `expired`, `earlyExit`, `authorizationRevoked`, `startFailed`, `recoveryInterrupted`, `clockChanged` and `deadlineMissed`.
- `Shared/TimeRules.swift`: `TimeRules.today(now:calendar:)` is the interval from `calendar.startOfDay(for: now)` to one calendar day later.
- `SessionHistory.records(on:calendar:)` returns the records whose `startedAt` is inside that interval, newest first.
  So a session belongs to the local day of its start; `testRecordCrossingMidnightBelongsToStartDay` and `testTodayUsesStartDateAcrossMidnight` in `HistoryTests/SessionRecordTests.swift` pin this.
- `SessionHistory.importTerminal` inserts one record for a terminal session, with the session's own `startedAt`, and then acknowledges it; a record with the same `id` is not inserted again.
- `App/FocusModel.swift`: `refresh()` imports a terminal session and then reads `history.records(on: now, calendar: .current)` in one `do` block.
  A failure there sets `errorMessage` ("기록을 불러오지 못했어요. …") and keeps the control session.
  `tick()` does not read the history.
- `App/FocusFilterHandler.swift` also calls `history.importTerminal`, so a record can arrive without the timer screen.
- `App/FocusView.swift`: the idle screen shows `todaySummary`, which opens the history sheet; the button is absent during a session and while the completion card shows.
  The view calls `refresh()` on `.NSCalendarDayChanged` and `.NSSystemTimeZoneDidChange` while no start is pending, and `refresh(clockChanged: true)` on `.NSSystemClockDidChange`.
- `App/TodayHistoryView.swift`: with `errorMessage`, the first section shows `historyError` and `historyRetry` and no summary; without it, it shows `historySummary`.
- `App/FocusRuntime.swift`: the store is `ModelContainer(for: SessionRecord.self, configurations: ModelConfiguration(cloudKitDatabase: .none))`.
- `Package.swift`: the host module `FocusHistory` compiles `App/SessionRecord.swift` only, and `HistoryTests/` tests it.
- `project.yml`: the Monitor target compiles `Shared/`; the Report target compiles `Report` and `Presentation` only; the `FocusActivity` target compiles `Widget`, two files of `Activity/` and `Shared/FocusActivityContent.swift`.
  None of them compiles `App/`.
- The 2026-10-26 design says that a clock change seen during a session interrupts it, and that a completed record is not a certificate of study.
- `[UNCERTAIN]` How long a SwiftData fetch with a predicate on `reasonRaw` and a sort on `startedAt` takes for a long history; no measurement exists.

## Design

### Open points for approval

These three choices need a product decision.
Each one has a recommended choice below.

1. **Placement.** Recommended: one line in today's history sheet only. See [Placement and copy](#placement-and-copy).
2. **Copy.** Recommended: `연속 집중 N일` for every value, with 0 included. See [Placement and copy](#placement-and-copy).
3. **Today before its first completed session.** Recommended: the streak keeps its value through today. See [Counting rule](#counting-rule).

The copy and the placement are for visual approval: the implementation PR shows light, dark and largest-text captures and waits for approval before the merge.

### Counting rule

- A record counts when its `reason` is `.expired`.
  Every other end reason does not count, and an unknown `reasonRaw` does not count either.
  This is the rule of `SessionSummary`, and the implementation uses one definition for both.
- The day of a record is `calendar.startOfDay(for: startedAt)`.
  The calendar is the one that `refresh()` passes to `records(on:calendar:)`, and "today" is the day of the same `now`.
- A day counts when it has at least one record that counts.
  More sessions on one day do not change the number.
- The streak is the length of the unbroken run of days that count and that ends today.
  If today does not count, it is the length of the run that ends yesterday.
  If neither day counts, the streak is 0.
- So the number does not fall to 0 in the morning.
  It falls to 0 only after one whole local day with no completed session.
- The step from a day to the day before it is a calendar step (`calendar.date(byAdding: .day, value: -1, to:)`), not 86,400 seconds, so a day of 23 or 25 hours is one day.
- A record whose day is after today does not count and does not break a run.
  Such a record exists only after the clock or the time zone moved back.
- No history gives 0.
- The streak has no maximum, no best-streak value, and no way to repair a missed day.

### Edges

| Case                            | Result                                                                                                                                                                                                                                                                                                   |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A session that crosses midnight | It counts for the day of its start, as in today's history. The day on which it ended needs its own completed session, and the streak holds through that day without one.                                                                                                                                 |
| A time zone change              | No day is stored, so every day comes from `startedAt` in the new calendar. The number can change in either direction: two days can become one, or a day without a session can appear. The app does not correct this.                                                                                     |
| A manual clock change           | A session that is in progress ends as `.clockChanged` and does not count. Stored records keep their `startedAt`. With the clock two or more days ahead the streak reads 0, and it reads the old value again when the clock returns. The app does not claim to detect a changed clock while it is closed. |
| A day with no record            | It breaks the run. An interrupted session on that day changes nothing.                                                                                                                                                                                                                                   |
| A record imported late          | It counts for the day of its own `startedAt`, whenever the import happens. `refresh()` computes the streak after its import, so one refresh shows the number with that record. Before the import, the number can be lower than after it.                                                                 |
| A lost end reason               | A session whose end reason was lost is recorded as `.recoveryInterrupted` and does not count. The streak does not guess.                                                                                                                                                                                 |
| Deleted history                 | A new or empty store gives 0, the same as no history.                                                                                                                                                                                                                                                    |
| An unreadable history           | The streak has no value, and no streak line shows. The history sheet shows its existing error and retry. A number from an earlier read never shows after a failed read.                                                                                                                                  |

### Computation

- The rule is a pure function in the `FocusHistory` module: it takes the start times of the records that count, the current time and a calendar, and it returns the number of days.
  It does not import SwiftData or any Screen Time framework.
- `SessionHistoryProviding` gets one new read that returns the streak for a time and a calendar.
  `SessionHistory` implements it with a fetch of the records with `reasonRaw == "expired"`, sorted by `startedAt` from the newest.
- The read is bounded: it takes the newest rows first, and it reads older rows only while the run still reaches the oldest row that it has.
  It stops at the first gap.
  So the cost follows the length of the current run plus one batch, not the length of the whole history.
- `FocusModel.refresh()` calls the read in the `do` block that reads today's records, after the import.
  `tick()` does not call it, so a running session adds no query.
- The model holds the value as an optional number.
  It is `nil` until a read succeeds and after every refresh that does not finish the history read.
- No new stored state: no SwiftData attribute, no migration, no `UserDefaults` key and no file.
  The value is derived again at each refresh.

### Placement and copy

- The history sheet shows one line in its first section, directly below `historySummary`.
- The line shows only when `errorMessage == nil` and the streak has a value.
- The timer screen does not change: no streak on the idle screen, on the in-progress screen, on the break screen or on the completion card.
- The line is plain text.
  It has no icon, no color of its own, no animation, no haptic and no tap action.
- The same line shows whether or not today has a completed session.
  No copy says that today's session is still missing, because that is the "about to break" message of decision 2.

| State  | Copy            |
| ------ | --------------- |
| 0 days | `연속 집중 0일` |
| 1 day  | `연속 집중 1일` |
| N days | `연속 집중 N일` |

The label form follows `오늘 집중 25분 · 1회` of the summary above it, which also shows its zero state as numbers.
The existing 해요체 sentences of the sheet stay as they are.
The line uses the secondary text color, a smaller text style than the summary and monospaced digits; the exact style is part of the visual approval.

### Accessibility

- Identifier: `historyStreak`.
- Spoken label: the visible text, for example "연속 집중 3일".
  It is one static text element with no added trait or hint.
- The line wraps at the largest text sizes and is not truncated.
- Every existing identifier stays.

### Privacy

- The streak comes only from the local `SessionRecord` store of the app.
- It is not written to the App Group, to `UserDefaults`, to a file, to a log or to the network.
- The Monitor, the Report extension and the Live Activity do not get it.
  The function is in `App/`, which the Monitor, Report and Widget targets do not compile.
- A home screen widget that shows the streak is a new data path and needs its own decision under issue #124.

### What does not change

- Session, break and deadline rules, and the rule for a completed session.
- The control store, the lock contract and every Screen Time call.
- `SessionRecord` and its stored fields, and the terminal import and acknowledgement.
- `SessionSummary`, the today summary on the idle screen, and the completion card.
- The Monitor, Report, Widget and Focus filter code.

### Scope sentence for `AGENTS.md`

The implementation PR replaces the last scope sentence of "Project scope" with these two sentences:

```plaintext
The history sheet shows a display-only streak, the number of consecutive local days with a completed session (see the [streak design](docs/specs/2026-11-13-streak-design.md)).
Keep changes within this baseline unless the task explicitly expands it: no other pause, parental management, Android client, accounts, backend, AI, or rewards, where rewards include points, badges, unlocks, rankings, comparison with friends and a notification that a streak is about to break.
```

The same PR changes the documentation-list line of this spec from "a design for approval" to its status then.

## Alternatives considered

**The streak is 0 until today's first completed session.** The rule is shorter, but the number falls to 0 every morning and returns after one session.
It is rejected because a number that drops each day reads as a warning.

**A session that crosses midnight counts for both days, or for the day of its end.** It is rejected because today's history places a session on its start day, and two rules for one record would let the sheet disagree with itself.

**Store the local day in each record at import.** A later time zone change would then keep the number.
It is rejected because it needs a schema change and a migration, and because an import that happens late or in another time zone would store the wrong day.

**Store the streak, or a last-counted day, in `UserDefaults`.** The read would be one key.
It is rejected because stored state can disagree with the records after a failed save, a late import or a clock change, and the bounded read is small.

**The rule in `FocusCore` (`Shared/`).** It is host-testable there too.
It is rejected because the Monitor target compiles `Shared/`, and the streak has no use outside the app.

**One fetch per day, backwards until the first gap.** The bound is the same.
It is rejected because a run of N days costs N + 1 fetches where one or two batches do.

**One unbounded fetch of every completed record.** It is the shortest code.
It is rejected because its cost grows with the whole history at every refresh.

**The streak on the idle timer screen.** It is seen at every launch.
It is rejected as the recommended choice because the idle screen already has the restriction summary, the everyday status row and the today summary, and decision 4 keeps it the focus-start screen.

**The streak on the completion card.** It is the moment when the number changes.
It is rejected as the recommended choice because a number that grows at completion reads as a prize for the session, which is the side of decision 2 that stays out.

**No line at 0 days, or a sentence such as `아직 이어진 날이 없어요`.** Hiding the line is quieter after a missed day.
It is rejected as the recommended choice because a line that appears and disappears changes the sheet's layout, and the summary above it already shows its zero state as numbers.

**A hint that today has no completed session yet.** It is rejected; see [Placement and copy](#placement-and-copy).

## Verification for the implementation

Follow `AGENTS.md` and [README verification](../../README.md#실행과-검증).
Simulator and fixture results establish nothing about real Screen Time behavior.

- Host tests in `HistoryTests/` for the counting rule, each with a fixed calendar and time zone:
  - no record gives 0; one completed session today gives 1; one yesterday and none today gives 1; the newest one two days ago gives 0;
  - a run of several days with and without today; a gap inside older history ends the run at the gap;
  - several sessions on one day count once;
  - each end reason other than `.expired`, and an unknown `reasonRaw`, does not count and does not join two runs;
  - a session that starts before midnight and ends after it counts for its start day only;
  - the same records give the expected numbers in two time zones;
  - a run across a daylight-saving change, in a calendar that has one;
  - a record after today does not count and does not break a run;
  - a record imported after newer records counts for its own start day;
  - a run longer than one batch gives the full number, and a short run in a long history reads no more than the bound allows.
- SDK tests of `FocusModel`: the value is `nil` after a history read failure and after a retry that fails, it has the number after a retry that succeeds, and a stale number is not kept; the test doubles of `SessionHistoryProviding` get the new read.
- Synthetic UI tests in `UITests/FocusFlowTests.swift`:
  - an empty history shows `historyStreak` with `연속 집중 0일`;
  - a DEBUG fixture that seeds completed records on today and on earlier days shows the expected `연속 집중 N일`;
  - `history-failure` shows `historyError` and no `historyStreak`;
  - the timer screen has no `historyStreak` when idle, during a session, on break and on the completion card.
- The seeded fixture stays behind `#if DEBUG` and uses the in-memory store.
  A seed of today and the days before it still reads the same number just after midnight, because the run then ends yesterday.
- Captures of the history sheet with 0 days and with N days, in light, in dark and at the largest text size, and explicit approval before the merge.
- Compile the App target; `Shared/`, `Integration/`, `Monitor/` and `Report/` have no change.
- The `AGENTS.md` change of [Scope sentence for `AGENTS.md`](#scope-sentence-for-agentsmd).

## Left to the builder

- The names of the function, of the protocol read and of the model property, and whether the function stays in `App/SessionRecord.swift` or gets its own file with the `Package.swift` and `project.yml` alignment that `AGENTS.md` asks for.
- The batch size, and how the batches feed the pure function.
- The name and the arguments of the seeding fixture, and its line in `docs/notes/development-launch-arguments.md`.
- The text style and spacing of the line, within the visual approval.
