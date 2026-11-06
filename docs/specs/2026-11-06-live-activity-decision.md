# Live Activity adoption decision

Date: 2026-11-06.
Status: adoption approved on 2026-11-06; implementation is under #74; release verification remains separate.
Scope: [decision #41](https://github.com/AndrewDongminYoo/focus-study/issues/41), prioritized by [parent #39](https://github.com/AndrewDongminYoo/focus-study/issues/39).
Primary sources: issue #41, the [M2 contract](2026-11-01-m2-break-pass-design.md) with its early-return amendment, and [Apple's Live Activities guide](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) (accessed 2026-11-06).
Current behavior was checked at `4075ea83625bf5fba32e6251f4c2bb6a9794165a` against `Shared/ControlTypes.swift`, `App/FocusModel.swift`, `App/FocusView.swift`, and `project.yml`.

## Decision and rationale

Adopt one optional, local, read-only Live Activity for the current focus session, subject to the feasibility and release gates below.
The [implementation feasibility record](../notes/2026-11-06-live-activity-feasibility.md) tracks the implemented lifecycle and its remaining release limits.
The immediate value is checking break and return timing while using another app, without opening the focus screen solely to read time.
The value is a hypothesis from the current flow and issue #41; no student usability study or device trial establishes its effect.

Prefer this surface over adding a completion notification (#42) or a home widget/streak (#43) in the same change.
A completion notification addresses a single event and requires a separate permission decision; a home widget requires leaving the current app and does not replace the proposed Lock Screen surface.
Neither issue is adopted, rejected, or closed by this decision.
The older competitor survey's lack of adoption evidence remains a limitation; matching Opal's feature count is not the rationale.

## Adopted scope

- Keep the iOS 17 minimum and existing focus, break, deadline, history, authorization, and everyday-layer rules.
- Add one WidgetKit extension for the Live Activity, without a home widget, notification request, push token, server, account, or new dependency.
- Offer the Lock Screen presentation on supported iPhones and compact, minimal, and expanded Dynamic Island presentations where the hardware supports them.
- Start at most one activity after a successful foreground session start, if allowed; reconcile an already-running session on foreground entry.
- A Focus-filter session started while the app is not foregrounded remains fully functional without a new activity; attach the display on the next foreground entry if still relevant.
- Open the existing app on tap; starting, ending, taking a break, and resuming remain app actions.
- A person dismissing the activity does not end the session; do not recreate a dismissed activity for the same session.
- If unavailable, disabled, dismissed, or starting/updating fails, retain the app's countdown and break screen without blocking session operations or requesting notification permission.

## State and time projection

Display timestamps derived from a reconciled engine snapshot, never accumulated timer ticks.
The projection is not a second session engine and never proves restrictions were applied or lifted.

| Stored state                                             | Proposed display                                                                                 | Time boundary                                                                                                       |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| `preparing`, `ending`, `terminal`, absent, or unreadable | No new activity; retire an existing display when execution allows                                | Never infer successful start or completion                                                                          |
| `active`                                                 | Remaining focus time plus an explicit deadline limitation if applicable                          | `focusEnd = expiresAt + pausedSeconds`; the earlier of focus end and session deadline is the next validity boundary |
| `waiting`                                                | Stop presenting a running focus countdown; direct the person back to the app                     | No external waiting countdown or automatic break start; background departure still cancels the wait                 |
| `onBreak`                                                | Break time remaining and the planned return time; focus time remains paused                      | `breakEndsAt` is the next validity boundary; it is not evidence of actual re-blocking                               |
| `breakOver`                                              | Time left to return and still complete, with the absolute session deadline separately identified | `latestResume = deadline - (length - focused(at: now))`                                                             |

When `latestResume` has passed, do not describe its zero as session completion or as restrictions lifting.
The session can remain in `breakOver` until its later absolute deadline; this is the existing M2 rule.
After focus completion or end, remove the session activity rather than declaring all restrictions lifted: the everyday layer may remain active.
No everyday-only activity is introduced.
Exact Korean copy and layout are left to the implementation's visual review.

## Lifecycle and uncertainty

Apple documents foreground starts, updates/ends during available execution, and launch-time reconciliation of surviving activities.
Its `staleDate` marks content outdated; it is not an end request or a guaranteed wake-up for the session engine.
These APIs do not establish that a countdown reaching zero causes a process callback or confirms shielding.
Do not base an iOS 17 design on newer scheduled-start APIs.

Perform display side effects after releasing the existing process lock; never hold it across an ActivityKit `await`.
Revalidate the session ID and projection before publishing, serialize display operations, and retire a stale session's display without touching a newer session.
On foreground entry, enumerate surviving activities, reconcile authoritative state, and remove or update orphaned content.
ActivityKit failures cannot roll back or delay a successful engine transition or history import.

For a known transition in an executing process, publish the new projection or end with immediate dismissal.
This includes early return, manual end, Focus-filter off, authorization loss, and an observed clock change.
Time-zone changes preserve absolute session times and only change formatted local times.
When a Monitor callback changes state, its ability to update/end the activity within the extension's runtime is an unverified feasibility question, not a promised delivery path.
The implementation must verify the available API and execution context before selecting this path.

For suspension, termination, delayed callbacks, or a clock change while no process runs, exact update/removal is not guaranteed.
Set a validity boundary for the next possible transition and include the last confirmed state and its scheduled times so an old card does not assert current blocking or a completed session.
Test stale rendering and countdown behavior in every presentation; neither a timer nor a stale marker alone establishes a timely label change.
If this cannot communicate uncertainty clearly without timely background execution, defer release and report the failed gate; do not add remote push or change the engine to make the display work.

## Local data boundary

Activity attributes/content contain only a session UUID, display phase, timing values, and a projection freshness marker.
They contain no selected apps, category tokens, website tokens/domains, report data, history rows, or student identity.
The widget receives the ActivityKit payload and must not read control storage, selection files, SwiftData, or the report extension.
Do not grant the new extension App Group access or broaden the Report boundary.
Do not add a separate authoritative state file; retain existing engine metadata as the authority.
Review system presentation on paired devices separately; local application data handling does not promise that iOS displays the card only on this iPhone.

## Implementation and release gates

1. First prototype the iOS 17-compatible local lifecycle, the Monitor execution path, stale rendering, dismissal persistence, and background Focus-filter behavior.
   Record device/OS, expected transition time, observed display time, and gaps; a simulator does not establish real background delivery.
2. Test projection values for all phases, late return, early return, missed deadline before focus end, missing/unreadable state, clock/time-zone changes, duplicate activities, delayed old operations, and session A ending after session B starts.
3. Test the disabled/denied/error path without changing session success, privacy boundaries, history, or everyday restrictions.
4. Compile App, Monitor, Report, and the new extension; run affected host, race, SDK/UI suites and an unsigned device Release build after target/fixture changes.
5. Obtain visual approval for Lock Screen and each Dynamic Island presentation, including light/dark, larger text, unavailable content, and stale/elapsed boundaries.
6. Before release, verify locked/unlocked background, force quit/relaunch, ordinary focus end, break end, early return, last-return boundary, missed deadline, Focus-filter off, access revocation, and dismissed/disabled activities on explicitly approved devices.
   Cover iOS 17 and devices without Dynamic Island separately; keep unavailable combinations unverified.

## Decision follow-through

The operator approved this adoption decision on 2026-11-06.
The [original design amendment](2026-10-26-focus-study-design.md#live-activity-adoption-amendment-2026-11-06) records the scope change separately from current implementation.
Record adoption and its limits in #41; [implementation #74](https://github.com/AndrewDongminYoo/focus-study/issues/74) tracks the separate work using these gates.
The decision PR closes only #41; #39 and unrelated decisions remain open.
The implementation issue must distinguish adoption from release readiness and preserve failed feasibility results as a reason to defer shipment.
The original adoption PR #75 changed documentation only; implementation #74 requires the technical and visual gates above.
