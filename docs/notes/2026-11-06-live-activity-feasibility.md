# Live Activity feasibility

Date: 2026-11-06.
Scope: [implementation #74](https://github.com/AndrewDongminYoo/focus-study/issues/74), governed by the [adoption contract](../specs/2026-11-06-live-activity-decision.md).
This is implementation evidence, not release approval.

## Architecture and failure policy

`FocusActivityProjection` derives display-only phase and timestamps from control metadata.
`FocusActivityCoordinator` serializes effects, re-reads after awaited operations, identifies both activity and session, and retires duplicates/orphans without ending sessions.
The app persists an attempted-session UUID in private UserDefaults before requesting an activity; dismissal or an ambiguous request failure uses the app fallback for that session.
Background processes never create an activity.
The Monitor schedules optional update/end work after its engine callback releases the process lock; callback lifetime does not guarantee that task will complete.

The widget compiles only the payload, Activity attributes and views.
It has no App Group, control-store reader, selection, report, history, notification request or push token.
Every state describes a plan and last confirmation, with app confirmation at stale/elapsed boundaries.
The return boundary is separate from the absolute session deadline; a zero countdown never asserts completion or shielding.

## Local evidence

Environment: Xcode 26.6 (17F113), iOS 26.5 simulator (23F73), iPhone 17.
The installed SDK selects an absent default simulator build; verification temporarily used the supported `simctl runtime match` override and restored the complete original mapping after every job.
The [existing toolchain note](2026-11-05-start-latency.md) describes the same environment issue.
The comparison guard rejected a deliberately changed mapping before it was trusted.

- The SDK declares the selected content request/update/end APIs available from iOS 16.2; App, Monitor and Widget compiled with an iOS 17 deployment target and extension API checks.
- An explicit DEBUG probe requested a real local ActivityKit activity using a temporary synthetic session, fake monitoring/shields and in-memory history.
  The system displayed compact Island content and a Lock Screen card after its Live Activity permission was allowed.
  This does not establish Screen Time behavior.
- On the dimmed Lock Screen, the system rendered timer seconds as dashes; no per-second locked refresh guarantee is inferred.
- Pure projection/coordinator tests cover distinct return/deadline values, invalid/expired state, early return, unavailable/dismissed/duplicate activities and session A changing to B during an awaited update.
  A deliberately removed serialization queue allowed two concurrent transport calls; restoring it passed the regression.
- Local review found that the existing recovery reader clears restrictions on a load error, and that manual end omitted its display hook after a reported write error.
  Failing SDK regressions reproduced both paths; a display-only locked reader now avoids recovery, and the end error path notifies the display.
  The repaired regressions passed in the full 115-test SDK suite, preserving shielding, registrations, break copies and everyday restrictions while invalidating the optional display.

The full local run passed 208 host tests, four separate-process race checks, 115 SDK tests and 53 UI tests.
A subsequent presentation-only repair passed its three affected UI tests again.
The actual expanded Island at accessibility maximum size clipped a redundant helper line; the final card keeps planned times and last confirmation visible and moves that helper into the confirmation item’s accessibility hint.
The stale app-confirmation message remains visible.
Actual synthetic probes confirmed focus-to-break and foreground return updates, compact/expanded and Lock Screen presentation, larger text and tap-to-open.
Return cards use one caption for the absolute deadline and last confirmation so both remain visible at the largest text size.
With the synthetic app process terminated, the break boundary was 10:19:28.848 UTC; the expanded card showed app confirmation by 10:20:04 UTC, with the transition preserved in a 106.42-second recording.
A separate focus-expiry probe, requested at 10:35:52 UTC with a ten-second boundary, still displayed zero with its planned end and last confirmation at the final observation before 10:37:40 UTC.
This is a delayed stale redraw, not verified prompt fallback.
The countdown reaching zero and stale redraw are separate observations, not a guarantee of timely removal or actual re-blocking.
Final command results and rendered probe outcomes are recorded with the PR review artifacts.
Static DEBUG previews reuse the production views and pure projection; they do not prove system delivery or stale redraw.

## Release boundary

Shipment remains deferred until the contract's physical-device scenarios pass on explicitly approved devices, including whether the delayed focus-expiry presentation communicates uncertainty clearly enough.
No physical installation, provisioning update, permission request or restriction change was performed for this implementation.
The new `.activity` bundle identifier's signing/profile readiness is unverified.

Still unverified: actual Monitor update/end delivery and callback lifetime, physical locked/unlocked background and force-quit timing, real Focus-filter transitions, access revocation, iOS 17 runtime, hardware without Dynamic Island, paired-device presentation and spoken VoiceOver output.
System dismissal could not be completed with the exposed simulator UI gestures; the private-ledger and coordinator dismissal/reconstruction regressions passed, but actual person-driven dismissal remains a device gate.
The minimal Island view was inspected through the shared DEBUG preview; a second system activity could not be launched on this simulator, so actual minimal presentation remains unverified.
Simulator compilation, synthetic runtime evidence and accessibility labels do not establish those properties.
Issue #74 stays open for these release gates even if the implementation PR merges.
If stale presentation cannot communicate uncertainty reliably on those devices, defer shipment; do not add push delivery or change the session engine to hide that failure.
