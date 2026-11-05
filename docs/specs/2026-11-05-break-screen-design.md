# Dedicated break screen and early return

## Intent and approved direction

During the physical-device investigation for [issue 33](https://github.com/AndrewDongminYoo/focus-study/issues/33), the focus screen felt crowded below its timer.
The requested change moves the break flow to a separate screen and allows an early return with “다시 집중하기”.
Ending the whole focus session remains a separate existing action.

Primary sources: `App/FocusView.swift`, `Shared/SessionControl.swift`, and the [M2 contract](2026-11-01-m2-break-pass-design.md).
This design supersedes M2's exclusion of early break endings and its shared timer-screen layout.
It changes no other session, authorization, privacy, or product limit.

## Screen flow

- The focus countdown and status retain the center of the focus screen.
  Break actions and the existing destructive session end sit in a separate lower action area.
- Tapping “쉬는 시간 갖기” opens a dedicated full-screen break surface as soon as the stored phase becomes `waiting`.
  The surface follows the existing `waiting`, `onBreak`, and `breakOver` phases rather than a second navigation state.
- The waiting surface shows its progress, seconds remaining, break allowance, and the existing “집중으로 돌아가기” action.
  Cancelling the wait returns to the focus screen without using a break.
  Leaving the app still cancels a wait under the existing rule.
- During the break, show the break countdown and “다시 집중하기”.
  Tapping it restores the restrictions and immediately resumes the focus countdown on the focus screen.
- At the normal three-minute end, keep the break surface visible with the existing return action and deadline guidance.
  The focus timer still waits for the person's return action.
- Keep “집중 종료”, confirmation, errors, retry, and DEBUG diagnostics reachable where they are currently required.
  Preserve existing accessibility identifiers; add an identifier for the dedicated break surface.
- This is a state-driven screen replacement, not a dismissible sheet that could hide an active break.
  Avoid a decorative page transition or new animation requirement.

## Early return transaction

Extend the existing `resume(id:now:)` operation to accept the current `onBreak` as well as `breakOver` phase.
Keep all effects in synchronous process-lock sections with no suspension inside the lock.

1. Load, clean up, and verify the session identity before effects for early return.
2. For `onBreak`, use the existing re-block mechanism to restore the focus shield and the everyday shield when its schedule requires one.
   Verify the focus shield before claiming the break ended.
3. Save `breakOver` as a recovery point before deleting the current break activity and selection copy.
   In this same save, shorten `breakEndsAt` to the actual early end and subtract the unused break seconds from `deadlineCredit`, bounded at zero.
   Preserve the existing break count and the start of the open pause.
4. Run the existing resume transition from that saved state: add actual paused time, register the correct focus end bounded by the deadline, and save `active`.
5. If re-block or saving fails, never report a resumed focus timer.
   If focus registration fails after the recovery point, retain a restricted `breakOver` state so the person can retry.
   Preserve existing rollback and recovery behavior if even the recovery schedule cannot be restored.

A repeated resume on an active session does not subtract credit or consume another break.
A stale callback from the ended break must not interrupt an active session or a newer break.
Natural expiry and late return keep their current accounting; only the explicit early return shortens the granted break credit.
The maximum break remains three minutes, with at most three breaks per session and the existing 15/30/60-second waits.

## Alternatives and scope

A modal sheet would introduce independent presentation and dismissal state for a stored session phase.
A state-driven full-screen surface fits the requested separate screen and restores correctly after foreground refresh, so it is the proposed implementation.
Adding only a return button to the existing stack would leave the reported crowding unresolved.

No notification, new dependency, schema migration, physical-device installation, or automatic real restriction action is included.
The separate start-feedback decision from issue 33 still follows its [measurement contract](2026-11-05-start-latency-design.md).

## Acceptance

- Early return re-blocks before focus resumes, charges only the actual pause, and keeps the used break count.
- Failure and interruption tests cover the re-block save and focus registration boundaries, including a retry.
- Core and everyday-layer tests cover restoration, deadline accounting, duplicate actions, and stale callbacks.
- SDK model and synthetic UI tests prove early return, separate break states, wait cancellation, normal expiry, and session end.
- Existing host suites and the separate-process race check pass; affected iOS targets compile and relevant SDK/UI tests pass.
- Rendered light/dark and large-text evidence is reviewed before the visual approval gate.
  Simulator checks do not establish real shield timing or iOS 17 runtime support.
