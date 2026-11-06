# Live Activity decision workflow

Date: 2026-11-06.
Status: product direction approved on 2026-11-06; execute the decision-documentation workflow below.
Contract: [Live Activity decision](../specs/2026-11-06-live-activity-decision.md).

## Scope and ownership

Use the current workspace on `docs/live-activity-decision`; create no worktree.
The root owns this plan, the paired decision spec, and a dated amendment in `docs/specs/2026-10-26-focus-study-design.md`.
No app, extension, target, dependency, signing, or device change belongs in this PR.
The documents serve repository knowledge targets 1 and 6: preserve the decision and give the later implementer a usable contract.

## Steps

1. Read #39/#41, current time/state projections, and Apple's lifecycle contract; distinguish current behavior, proposals, and unverified device behavior.
2. Prepare a concrete adoption proposal and a separate implementation-issue draft; check source claims, local links and anchors, Markdown quality, and diff whitespace.
3. Save the proposal and exact continuation in Git-local state, then request the operator decision required by #41.
4. After approval, mark the decision accepted, add the dated original-design amendment, create the separate implementation issue, and record its link and rationale in #41.
   The operator approved adoption on 2026-11-06; retain the initial proposal/approval steps above as the decision history.
5. Run the final content/link checks, `trunk check --no-fix`, and `git diff --check`; review all changed documents in one inline pass.
6. Commit the single documentation concern, push, open a PR closing #41 only, and complete current-head CI and hosted review.
   Read back the final title/body/checks before assigning the operator through the verified handoff.
7. Merge under the explicit `pr-loop` authority after all gates, verify the remote merge and #41 outcome, preserve a visible completion receipt, and retire only this loop's owned control state.

## Minimum verification and limits

The content review compares formulas and transitions with `Shared/ControlTypes.swift`, `App/FocusModel.swift`, and the linked M2 amendment.
The link reader must resolve changed documents' local files and anchors, with missing-file and missing-anchor negative controls.
Trunk reads the changed Markdown and repository style configuration; it cannot establish ActivityKit feasibility or product approval.
No executable behavior changes, so no new unit test or local mobile build is appropriate.
Existing full CI remains a required current-head gate after PR creation.
The adopted feature remains unimplemented and its physical-device scenarios remain unverified.
