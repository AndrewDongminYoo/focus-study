# Picker and Browser Device Acceptance

## Contract

Execute [issue #13](https://github.com/AndrewDongminYoo/focus-study/issues/13) against the existing installed app with the operator's scoped consent.
Use the [selection and shielding design](../specs/2026-10-26-focus-study-design.md) and append observed results to the [device matrix](../notes/screen-time-device-matrix.md).
The baseline source is `f171788acbed4abc19947ed6643605c393309e15`.
The previous installation record describes a working-tree Debug build with the category-selection correction, version `0.1`, build `1`; it does not prove that the installed binary was built from the merge commit.
Record that provenance limit with observations rather than relabeling the installed build.

No reinstall, authorization change, new browser installation, or investigation of the deferred authorization interruption is included.
Do not add a WKWebView test app solely to fill the environment matrix.
Do not export private tokens, application names, domains, browsing history, or usage data.

## Execution

1. Confirm consent to change saved selections and manually start and end a focus session on the daily iPhone.
  Record the observed OS version, app version/build, browser environments, and observation time.
  Use anonymous aliases such as selected site A and unselected site B.
2. Check the actual Picker boundary separately for applications and websites.
  Select 50 of one type and save; reopen to confirm that selection was retained.
  Add one more of that type and attempt to save.
  Confirm rejection, cancel the draft, and reopen to verify the saved 50-item selection remains.
  Keep the other type empty to avoid confusing the per-type limits.
  If the system Picker prevents constructing 51 items, or fewer than 51 selectable items exist, record the exact limitation; do not claim the application's 51-item rejection was exercised.
3. Before testing browser behavior, replace the large boundary selection with the operator's small approved test selection.
  Keep the browser app itself unselected so an application shield does not masquerade as website blocking.
  Confirm that selected site A and unselected site B load before the focus session.
  During the session, test A at two paths and B in Safari normal and private tabs, then repeat in an already available alternate browser and an identifiable WKWebView surface when available.
  Reload or navigate after starting the session; distinguish an existing page from a fresh request and a network failure from a system restriction screen.
4. End the session manually, record the observed removal delay, and restore the operator's intended selection.
  Do not claim an automatic 25-minute expiry was tested by a manual end.
5. Record expected and observed results with their environment and evidence source.
  Operator-reported observations must remain labeled as such.
  Unavailable combinations remain unverified; they do not become passing results.

## Acceptance Record

On 2026-10-27, the operator explicitly confirmed all three selection checks separately for applications and websites: saving 50, rejecting 51, and retaining the saved 50 after cancellation.
This is an operator-reported result on the existing installed build, not an independently captured token count.
The operator also reported that the missing visible selection count made validation inconvenient.

| Scenario | Expected observation | Current status |
| --- | --- | --- |
| Applications: 50 then 51 | 50 retained; 51 rejected without replacing the saved selection | Operator confirmed all three checks on 2026-10-27 |
| Websites: 50 then 51 | 50 retained; 51 rejected without replacing the saved selection | Operator confirmed all three checks on 2026-10-27 |
| Safari normal tabs | Selected site restricted at both paths; unselected site remains accessible | Operator reported one restriction message and one indefinite load on iOS 27.0.1; multiple-path and unselected-site controls unconfirmed |
| Safari private tabs | Record selected/unselected behavior at both paths, including any platform limitation | Operator confirmed a fresh private tab can access the same address blocked in a normal tab during the same active session; Apple intent unconfirmed |
| Alternate browser | Record actual results and the browser/OS combination | Chrome access reported on iOS 27.0.1; browser version and same-session conditions unconfirmed |
| WKWebView | Record actual results in an identified embedded-browser surface | Availability unconfirmed |
| Manual end and restore | Record restriction removal and restore the intended selection | Operator confirmed the loading failure disappears after ending the session; removal delay and selection restoration unconfirmed |

## Delivery and Checks

Owned paths are this plan, the device matrix, the selection design contract, `App/SelectionEditor.swift`, and `UITests/FocusFlowTests.swift`.
Add a visible summary of the current draft's application and website counts without changing selection limits or persistence.
Reuse the production summary in the synthetic editor for rendered update and cancel/reopen checks; this does not verify the real system Picker binding.
Capture the result for explicit operator visual approval before merge.
Update the implementation ledger only when new evidence or an actual correction warrants it.
Source changes require a reproduced defect and a focused regression within issue #13's scope.
Existing synthetic repository tests support diagnosis but cannot satisfy physical acceptance.

For documentation-only results, inspect claims against the observations, check relative links, run `git diff --check`, and run `trunk check --no-fix` on the changed documentation.
Do not mark issue #13 complete or publish a completion claim while required actual-device scenarios remain unobserved.
The operator subsequently requested publication of the current changes as a PR while the remaining device checks are still open.
Publish the count display and verified observations without an issue-closing keyword for issue #13.
Retain unobserved scenarios as follow-up acceptance work rather than waiving them or claiming the whole issue is complete.
Continue the authorized PR lifecycle for this bounded candidate after local checks and review.
