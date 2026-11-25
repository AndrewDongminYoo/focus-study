# Weekly review design

Date: 2026-11-25.
Status: approved on 2026-11-25, implemented under issue #251.
Source: [issue #250](https://github.com/AndrewDongminYoo/focus-study/issues/250), under the paid build parent #244.
Authority: the [paid unlock decision](2026-11-24-paid-unlock-decision.md) (decisions 2, 7 and 8), the [paid access design](2026-11-24-paid-access-design.md) and the [순공 calendar design](2026-11-25-sungong-calendar-design.md) for the data rules.
Look: the tokens of the [screen redesign](2026-11-23-screen-redesign-design.md); there is no Figma frame yet.
This document changes no code.
The implementation is issue #251, and it starts after this design is approved.

Items marked "(writing session's call)" were not discussed with the user. They are defaults that the approval of this document can change.

## Intent

The weekly review is a handoff to the student of next week, not a report card.
When the student closes it, the student should feel: "this is what I did this week, and I know where to start again next week."

A weekly total alone does not need its own screen; the calendar already shows it.
The review adds three things: what the student did, a moment from this week that the student can use again, and a note from the student to the student of next week.
A review that ends without an action is of no use, so the note is the main part of the screen.

The review must have value with only two days of records, so that a student sees it inside the 3-day trial.

## Goals

- Show what the student did first, in counts of completed sessions and days, never as a rate of a plan.
- Give one concrete clue from the app's own records: when a session actually started.
- Let the student write a note to the next week, and show that note at the top of the next review.
- Reach the student by a local notification on a weekday that the student can change or turn off.

## Non-goals

- Tips or feature guidance inside the review. They were tried in the mockup and broke the flow of the screen.
- Any analysis of app or website usage. The app never reads the usage of the selection (the Report extension is isolated), and this is a separate scope.
- A weekly plan, a target count or an achievement rate. The app stores no plan.
- The 순공 calendar share image of issue #252. The review has its own share card (contract item 7); #252 stays a separate design.

## Anti-goals

The review fails, also when it works, if it does one of these:

- It reads as an attendance check, for example "3일 중 2일".
- It interprets the student, for example "저녁에 집중이 잘돼요".
- It turns missed sessions into homework for next week.
- It blames a day without records. A day without a completed session is "온:공 기록 없음", not a day without study.
- It grades, tracks or reminds about the note. The note is a promise to oneself, not to the app.
- It sends a notification to a person without access to the paid features, which would be a paywall reminder.
- It adds any reward of the AGENTS.md baseline, such as a notification that a streak is about to break.

## Contract

Proposed on 2026-11-25:

1. **Paid feature.** The weekly review is a paid feature (decision 2).
   With access `granted` or `unknown`, the student can open it.
   With access `locked`, there is no entry to it and no review notification.
2. **Content, from top to bottom.**
   1. **Last note**: the note that the student wrote in the previous review period, under the label "지난주의 내가 남긴 말".
      It shows only when such a note exists and is not empty.
   2. **What I did**: one sentence with the number of days and of completed sessions, the total focus time under it, and a row of day bars, one per day of the period, so one to seven bars.
   3. **A moment to use again**: one sentence chosen by the [moment rule](#moment-rule).
      When the rule finds nothing, this part is absent.
   4. **To me next week**: the title "다음 주의 나에게", the prompt "다음엔 어디서 다시 시작할까요?" and a text field.
      This part is the most prominent part of the screen.
   5. **Review notification row**: the weekday and time of the review notification, and a way to change them or to turn the notification off.
3. **Two forms.**
   - **Form B, pages**: while the access is granted by the trial, the review shows its parts as pages that the student swipes or advances with "다음": what I did, a moment to use again (absent when the rule finds nothing), to me next week.
     The last note does not show in form B, because a trial has only one review.
     The notification row is on the last page.
   - **Form A, one sheet**: in every other `granted` or `unknown` case (a purchase, an earlier user), the review is one scrolling sheet with every part of item 2.
     Reason: form B makes a better first impression; a review that the student opens every week must show the note without three page turns.
4. **Presentation.** The review is a sheet at the large detent, presented through the idle screen's existing `.sheet(item:)`, like the calendar, settings and paywall sheets.
   It has a close control.
5. **Entries.**
   - A tap on the review notification opens the app with the review sheet of the period that the notification announces.
   - The 순공 calendar sheet has an entry to the review of the current period, for example "이번 주 돌아보기", with access `granted` or `unknown` (writing session's call).
     On the day after a period ends, the current period has one day; its review shows the note of the ended period as the last note, and that note is still editable from the review of the ended period, which the notification opens.
     With access `locked` the calendar shows its locked card, and the entry is absent.
   - The review never opens by itself at launch. The notification replaces the launch popup that was discussed and rejected.
6. **Notification schedule.**
   - **Day 1** is the local day on which paid access starts for this person: the trial start day (`PaidAccessFacts.trialStartedAt`), the purchase day of the unlock when there was no trial, or, for an earlier user, the day the paid build first runs on the device.
     While the paid gate is off (`PAID_UNLOCK_ENABLED` is not set, as in Release until #255), every person is treated as an earlier user: day 1 is the day the first build with the review runs, and the review uses form A (writing session's call).
   - On day 1 the app asks for notification permission, after a short explanation in the app of what the notification is for.
     The system prompt never shows before that explanation.
   - The explanation shows once, as a sheet of the idle screen, the first time the idle screen shows on or after day 1 with access `granted` and the permission not yet determined (writing session's call).
     For a trial, that is right after the paywall closes on the trial start. It never shows over a running session or a break.
     It has an action that asks for the permission and an action that closes it; after either, it never shows again.
     A student who closes it can turn the notification on later in the review's notification row.
   - The first review notification is on day 3, at 20:00 local time (writing session's call for the time).
     Day 3 at 20:00 is always before the trial ends, because the trial ends 72 hours after its start on day 1.
   - The default weekday of later notifications is the weekday of day 3. The default time is 20:00.
   - The student can change the weekday and the time, or turn the notification off, in the review's notification row.
     Without a change, the notification comes every week on that weekday at that time.
   - The notification is a local notification. Its text is fixed when it is scheduled, so it holds no numbers, for example "이번 주 회고가 준비됐어요" (writing session's call; the final copy follows the `user-facing-copy` rules).
   - The notification comes every week also when the student does not open the app (writing session's call for the mechanism):
     - for the unlock or an earlier user, the app schedules one repeating notification on the chosen weekday and time;
     - for a trial, the app schedules only the day 3 notification, which is before the trial end;
     - with access `unknown` or `locked`, the app schedules nothing.
   - When access becomes `locked` (a trial end or a refund), the app removes the pending notification at its next refresh.
     A notification that fires before the app sees a refund is an accepted edge.
   - A change of the weekday or the time replaces the pending notification.
   - When the student denies the permission, the app does not ask again. The review stays available from the calendar, and the notification row says that notifications are off in Settings (writing session's call).
7. **Share and save.**
   - Two icon buttons at the top of the review: save the image to Photos, and share the image through the system share sheet.
   - The image holds only the dates of the period and "what I did": the sentence, the day bars and the colon mark.
   - The image never holds the note, the last note or the moment (writing session's call for the moment: start times are personal).
   - The image goes out only by the student's own action (decision 7).
8. **Note storage.**
   - One note per review period, stored on the device only, in the app's own storage. It never goes into the App Group, the widget or the share image.
   - The note of a period stays editable until the end of the next period, so a student who opens the review the morning after the notification can still write it (writing session's call).
     The note of an older period is read-only.
   - The "last note" of a review is the note of the period just before the shown period.
   - An empty note is not stored, and then the next review has no last note.

## Data rules

The review reads the same session history as the 순공 calendar, with the same rules: local calendar days, a session belongs to the local day of its `startedAt`, and only a completed session counts (`SessionRecord.counts`).
Its focus time is `focusDuration`.

### Review period

- A review period is seven local days that end on the review weekday.
- The first period is shorter: it runs from day 1 to day 3.
- A period is never longer than seven days. After the student changes the weekday (writing session's call):
  - when the new weekday comes on or after today and on or before the last day of the current period, the current period ends on that day, and it is shorter once;
  - otherwise the current period keeps its last day, and the next period runs from the day after it to the first following occurrence of the new weekday, which is one to seven days.
  - So no day falls between two periods, and no day belongs to two periods.
- When the review opens before the last day of its period, it shows the period up to today.
  Days after today show as dimmed bars without a value.

### What I did

- The sentence counts the days of the period with at least one completed session, and the completed sessions.
- While today is on or before the last day of the period, the sentence starts with "이번 주 지금까지,", because the notification comes at 20:00 and the day is not over.
  After the last day of the period, it starts with "이번 주".
  Example, the first review of a trial that started on Monday, opened on Wednesday (day 3): "이번 주 지금까지, 이틀에 걸쳐 5번 집중했어요."
- Days use native Korean words: 하루, 이틀, 사흘, 나흘, 닷새, 엿새, and "일주일 내내" for seven (writing session's call).
- With no completed session in the period, the sentence is replaced by a message that does not blame, in the sense of "집중이 기록되지 않았더라도 괜찮아요. 다음엔 온:공과 함께해요." The note part still shows.
- A day without a completed session reads "온:공 기록 없음" to VoiceOver.

### Moment rule

The rule looks only at the first completed session of each local day of the period, by `startedAt`.
Later sessions of the same day are never a repetition.

1. **Repetition at a similar time.** Two different days whose first sessions started within 60 minutes of each other by time of day (writing session's call for 60 minutes; no wrap across midnight).
   When more than one pair qualifies, take the pair with the smallest difference; on a tie, the pair whose later day is more recent.
   Example: "수요일 오후 7시 10분, 금요일 오후 7시 40분에 그날 첫 집중을 시작했어요."
2. **Return after a gap.** When rule 1 finds nothing: a day with a completed session whose previous day is inside the period and has no completed session.
   When more than one day qualifies, take the most recent.
   Example: "목요일엔 온:공 기록이 없었고, 금요일 오후 4시에 시작한 세션을 마쳤어요."
3. **Nothing.** When neither rule finds a moment, the part is absent. The rule never fills it with something else.

The sentence states only days and actual start times. It never names a part of the day as good or bad, and it never compares the student with anything.

## Look

- Form A follows the calendar sheet: `FocusCanvas` background, `FocusCard` cards, `FocusNavy` and `FocusCream` text, `AccentText` labels.
- The "다음 주의 나에게" part is the most prominent card: a navy card (`FocusNavy` fill with `FocusCream` text in light mode), with a text field of at least three lines.
- The last note is a quiet card above "what I did", in `FocusSecondaryInk`.
- Save and share are two icon buttons next to the close control, not full-width buttons.
- Form B shows one part per page, with a page indicator and a "다음" button; the "what I did" sentence is larger than in form A.
- The share image is a navy card with the dates, the sentence, the day bars and the colon mark.
- Captures for approval: light, dark and the largest accessibility text size, for form A, form B and the share image.

## Left to the builder

- Where the rules of the review period and the moment live. Writing session's call: an SDK-independent rule in `Shared/`, with host tests, like the today snapshot rule.
- The storage of the notes and of the notification settings, inside the app's own container.
- How the app records day 1 for an earlier user, which no stored value holds today.
- The text of the explanation before the permission prompt, the notification and the empty-week message, by the `user-facing-copy` rules.
- The control for the weekday and the time in the notification row.
- New accessibility identifiers; keep the existing ones that `UITests/FocusFlowTests.swift` reads.
- Saving to Photos needs `NSPhotoLibraryAddUsageDescription` in the app's Info.plist; record it for the [store privacy declarations](../notes/store-privacy-declarations.md) under #255.
- The app has no notification code today (no `UNUserNotificationCenter` in `App/`, `Shared/`, `Integration/` or `Monitor/`); the review adds the first one, in the app target only.
  The AGENTS.md project scope gains one sentence for the weekly review and its notification in the same change.
- The UI test fixtures must keep the permission explanation sheet from showing, so the existing flows of `UITests/FocusFlowTests.swift` do not change.

## Builder decisions of issue #251

- The period, wording, moment and notification-plan rules are in `Shared/WeeklyReview.swift`, with host tests. The form, day 1 and access-kind reads of paid access are in `Shared/PaidAccess.swift`, because the Monitor does not compile that file.
- The schedule stores day 1, the notification time and switch, and a list of segments: each segment is the last day of a period and the weekday of the periods after it. A weekday change keeps the segments before the current period and adds one, so an ended period never moves.
- Notes, the schedule, the first run and the explanation flag are in the app's standard user defaults. A note is keyed by the first day of its period.
- Day 1 of an earlier user, and of every person while the gate is off, is the local day of the first review refresh after launch with a build that has the review.
- One completed day reads "하루 동안", two to six days read the native day word followed by "에 걸쳐", such as "이틀에 걸쳐", and seven days read "일주일 내내".
- The moment card is labelled "다시 꺼내 볼 순간". The notification body is "이번 주 회고가 준비됐어요". The explanation asks "주간 회고 알림을 받아 볼까요?" with "알림 받기" and "다음에 할게요". The Photos usage text is "주간 회고 이미지를 사진 앱에 저장할 때만 사용해요."
- The empty-week message is the sentence of the "what I did" rule, "집중이 기록되지 않았더라도 괜찮아요. 다음엔 온:공과 함께해요.", without a change.
- The notification row has a switch, a weekday menu and a time picker. Turning the switch on asks for the permission only when it was never asked and the explanation has already shown; before the explanation, the switch only saves, and the explanation stays due.
- A weekday change during the first period never ends it before day 3, so the trial's day 3 notification always opens the first review; the new weekday applies from the next period.
  Day 3 keeps its notification at the review time. When the next fire of the new weekday comes after day 3, the app also schedules the repeating notification.
  When it comes before the end of the first period, the app schedules the end of the first period and the ends of the next 51 periods as single notifications, so they come also when the app does not run; the first refresh after the first period replaces them with the repeating notification.
- Form A leaves out the notification row while access is `unknown` and day 1 is not fixed yet, because without day 1 there is no weekday or time to show and nothing is scheduled. The row shows from the first review after access reads `granted`.
- The new accessibility identifiers are `calendarReview` for the calendar's entry; `reviewDone`, `reviewSave`, `reviewShare`, `reviewSaveMessage`, `reviewPeriod` and `reviewError` for the sheet's controls and messages; `reviewLastNote`, `reviewSummary`, `reviewTotal`, `reviewDay-<n>` (0 for the first day of the period, up to 6), `reviewMoment` and `reviewNote` for the parts; `reviewPageIndicator` and `reviewNext` for the pages of form B; `reviewNotificationToggle`, `reviewWeekday`, `reviewTime` and `reviewNotificationsOff` for the notification row; `reviewExplanation`, `reviewExplanationAllow` and `reviewExplanationClose` for the explanation; and `reviewShareImage` for the DEBUG share image preview. Every identifier that `UITests/FocusFlowTests.swift` read before stays.
- After the first period, a weekday change whose new weekday comes after the current period moves the repeating notification to the new weekday, so the kept last day of the current period gets no notification.
- A notification tap opens the period whose last day holds the fire date. When a time zone change moved the local day of the fire date to the day after that last day, the tap still opens that period.
  Known limit: when a weekday change made a one-day period, and the time zone changes by many hours or the notification time moves by many hours between the fire and the tap, the tap can open the period next to the announced one. The notification carries no period, so the fire date is the only input; the other review stays open to the calendar entry or to its own notification.
- The calendar entry always opens the period that holds today, also on day 4 of a trial. The first period then opens from its day 3 notification.
- The first run is recorded when the runtime makes the review model at launch, so onboarding on a later day does not move day 1.
- A single notification, such as the trial's day 3 notification, fires at an absolute time in the time zone of its scheduling, so a move to another time zone cannot push it past the trial end. The repeating notification follows the local time.
- Every refresh of an open review, such as a return to the foreground, reads its history again.
- A stored day is a Gregorian year, month and day in the local time zone, also when the device uses the Buddhist or the Japanese calendar.
- The idle screen refreshes the review, so the onboarding route does not remove a notification after a refund; this is inside the accepted edge of contract item 6.
- A notification tap with access `locked` opens nothing and shows no paywall. A tap during a session waits for the idle screen, and a tap while a sheet other than the calendar is open waits for that sheet to close.
  A session that starts while the review or the explanation shows, such as from a Focus filter, closes it; the review and the explanation show again after the session.
- An open review reads the history again at a foreground refresh and at a day or time zone change, so after its period ends it no longer reads "지금까지" and follows the note's edit window.
- In the dark appearance the navy note card has an amber border, because the dark canvas is almost the same navy.
- The share image is rendered at a fixed width and the default text size, so it is the same at every text size of the device.
- A word joiner inside each word keeps Korean words such as "5번" on one line; the accessibility label keeps the plain text.
