# Interface polish verification

## Result and scope

The approved HIG improvements are implemented locally without changing focus lengths, break rules, authorization requirements, or report data boundaries.
Primary sources: the [design](../specs/2026-11-05-interface-polish-design.md), `UITests/FocusFlowTests.swift`, and `SDKTests/FocusModelTests.swift`.
The implementation and visual-review phase performed no provisioning change, physical-device installation, or real restriction action.
New Korean copy follows the existing warm 해요체; no separate project copy-voice declaration was found.

Onboarding now scrolls at accessibility text sizes and exposes setup progress.
Six existing focus lengths use standard menu pickers in onboarding and settings.
Timer controls have 44-point touch bounds, and the existing bottom history summary has a disclosure cue.
Everyday editing exposes local validation, unsaved changes, strict-only guidance, persistent save feedback, and confirmed dismissal from both the back and completion actions.
History emphasizes its completed-only summary, the report host offers neutral reload help, and break phase headings have accessibility focus and restrained feedback.

## Start feedback and limits

The UI reserves a UUID request before mounting a native spinner and static progress label.
Two distinct display-link ticks after attachment and layout provide a frame opportunity before the unchanged synchronous start body.
Cancellation and execution revalidation prevent stale requests, duplicate starts, and replacing a session started by a Focus filter.
All actor-isolated services and process-lock sections retain their original synchronous boundaries.

A recording of the synthetic three-second registration delay contains the progress label and disabled controls in three consecutive one-second samples.
The extracted frame was visually inspected, and Vision OCR independently recognized the progress text in all three samples.
This is evidence of displayed simulator feedback during a blocking synthetic operation, not proof of physical Screen Time latency or elimination of main-actor blocking.
The existing diagnostic measures the synchronous body and excludes the display-frame opportunity.

## Verification evidence

Environment: Xcode 26.6 (`17F113`), iPhone 17 simulator, iOS 26.5 runtime `23F73`, SDK build `23F81a`, Swift 5 language mode, signing disabled, and test parallelism disabled.
The SDK/runtime mapping was temporarily selected for each Xcode command, restored in `finally`, and compared with its original JSON mapping.
Dark appearance was also restored to the original light appearance after each capture run.

| Check                         | Observed result                                                                                                                                                   |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Baseline touch regression     | Failed as intended: selection height 20 pt, settings approximately 20.67 × 20 pt, history height 18 pt.                                                           |
| Host suites                   | 188 tests passed.                                                                                                                                                 |
| SDK suites                    | 103 tests passed, including pending-start and dirty/recovery regressions.                                                                                         |
| UI suite and affected reruns  | The initial implementation pass covered 42 distinct UI tests through the full run and scoped reruns.                                                              |
| Dark UI checks                | Five tests passed, covering saved settings, mixed history, deadline expiry, largest-text onboarding, and the delayed start.                                       |
| Final success-label color     | Light and dark checks passed; final captures were inspected.                                                                                                      |
| Separate-process race helper  | All four required stale-identity checks passed.                                                                                                                   |
| Unsigned device Release build | App, Monitor, and Report compiled successfully with signing disabled.                                                                                             |
| Trunk                         | Formatting and spelling were checked. A deliberate README typo was rejected, then the exact prior bytes were restored.                                            |
| Independent review            | Two read-only reviews found no blocking source regressions. The settings reviewer also checked the final explicit child completion callback and save-area repair. |

The first full UI run had 39 passing tests and three failing tests.
The failures exposed save/refusal feedback below the viewport and missing completion toolbar actions on a pushed screen.
The first toolbar repair also failed; the final implementation declares completion actions on both relevant screens and passes the child's current dirty state directly to the parent's shared dismissal handler.
The affected four-test rerun passed, including keep/discard and child-back behavior.
There was no second full UI run during that initial pass; its latest-result coverage combines the full run with affected reruns.

The local sibling directory `focus-study-interface-review-2026-11-05/` retains screenshots, the start recording, exported XCTest attachments, and sampled frames.
The suite logs and result bundles use the `/tmp/focus-interface-` prefix on this machine.
These local media are review evidence, not published release artifacts.

## Remaining manual acceptance

Real Screen Time start feedback, registration latency, restrictions, callbacks, and physical haptics remain unverified in this change.
iOS 17 runtime behavior, VoiceOver focus behavior with the screen reader enabled, and system Increase Contrast behavior require separate acceptance.
The simulator and unsigned Release build do not establish those properties.

## Follow-up: sheet height, tokens, and Liquid Glass

The operator requested this refinement after reviewing the first pass.
`App/FocusTheme.swift` now owns app text, accent, error, surface, progress, spacing, and compact-sheet roles.
The approved AccentColor and AccentLabel asset values are unchanged.
The ErrorText asset provides light, dark, and high-contrast variants; reading the asset and checking neutral surface pairs produced minimum contrast ratios of 5.89, 10.02, 8.34, and 13.16 respectively.
The contrast reader rejected the known low-contrast amber-on-white fixture before accepting these values.
The isolated Report target retains its system semantic colors and does not read app-only named assets.

Primary and secondary app actions use native Liquid Glass styles on iOS 26, grouped through GlassEffectContainer where appropriate.
Earlier systems and reduced-transparency or increased-contrast contexts use standard bordered styles.
The DEBUG `--solid-controls` fixture exercises that control-style branch without changing system settings; it does not simulate the system's entire accessibility presentation.
Glass is confined to controls; form content and feedback surfaces remain semantic system surfaces.

Editor presentations now use one explicit large detent, including real and synthetic selection editors.
The original session-end dialog omitted the continue action in the executed runtime; the new UI regression observed that failure before route integration.
An initial automatic fitted confirmation passed action tests but a capture still showed a full-height empty panel.
Image review caught that gap; the final confirmation uses a 320-point base height token scaled with body text, with a separate scrollable large presentation for accessibility sizes.
Window-relative position checks and new light/dark captures verify the compact bottom placement and visible continue action.
The same item-based route owns selection, settings, history, and end confirmation, preserving cancellation and session-end behavior.

Verification for this follow-up: SDK 103 tests passed, affected UI 15 tests passed, the five affected compact-height reruns passed, and five dark-mode checks passed.
Host tests passed again after the SwiftPM exclusion changes, and unsigned Release compiled App, Monitor, and Report successfully.
Existing XcodeGen source globs include the two new app-only files; regenerated output was stable on a repeated generation.
The independent reviewer found no blocking source regressions and checked the final compact light/dark captures.
Final formatting, spelling, and internal-link checks are recorded with the local gate logs.
The local sibling `focus-study-sheet-theme-review-2026-11-05/` directory retains the captures and XCTest attachments, with `/tmp/focus-glass-` logs for this pass.
Oracle query for sheet presentation and accent color returned **[no precedent found]**; current code, approved assets, Apple documentation, and rendered evidence determined the choices.
The iOS 17 fallback was compiled, but no iOS 17 runtime or physical-device acceptance was performed.

## Follow-up: reference spacing and save feedback

The operator supplied four Mirae Figma sections and approved using their spacing with native iOS controls.
The [design amendment](../specs/2026-11-05-interface-polish-design.md#reference-spacing-refinement) records the inspected frames and extracted values.
`FocusTheme.Layout` now distinguishes 4-point detail, 8-point inline, 12-point related, 16-point control, 20-point screen, and 24-point section spacing.
The timer, break, onboarding, editor, history, and report-host layouts use these roles while native form rows and controls keep their system geometry.
No reference artwork, typeface, Material control, or session behavior was imported.

The everyday save action now spans the screen inset without the enclosing white card.
Success feedback has an explicitly centered icon/text stack in a separate, text-scaled status region above the action.
An initial ten-test UI pass did not reveal that list content rendered behind the status region.
Capture review caught the overlap, and an opaque grouped system background now separates the bottom region from scrolling content without adding another card.
The final light and dark saved-state captures were read back after that correction.

Verification: ten affected UI tests passed in `/tmp/focus-spacing-ui.log`, including largest-text onboarding and break return, editor height, end continuation, save/unsaved/refusal behavior, history, report reload, and tap targets.
After the background correction, the two affected light tests passed in `/tmp/focus-spacing-light2.log`; three dark checks passed in `/tmp/focus-spacing-dark2.log`.
The first dark attempt was interrupted when machine load exceeded the core count and was not counted as a passing check.
The final jobs waited for acceptable load, ran sequentially, restored the SDK/runtime override, and restored light appearance.
The local sibling directory `focus-study-spacing-review-2026-11-05/` holds exported attachments and readable captures; `everyday-settings-light.png` and `everyday-settings-dark.png` are from the final build.
The large-text everyday save state, iOS 17 runtime, physical-device behavior, and actual accessibility settings were not exercised in this follow-up.
Host and SDK logic suites were not repeated because this refinement changes only presentation and documentation.

## 2026-11-06: explicit unsaved-edit choices

The operator's capture showed a discard confirmation with no visible keep-editing action.
Both the child back action and the settings completion action used `confirmationDialog`, whose cancel action was absent in the executed presentation.
The existing test accepted outside-popover dismissal, so it did not enforce an explicit safe choice.
Requiring the keep-editing button first failed against that implementation in `/tmp/focus-discard-red.log`.

Both routes now use the native alert with the existing loss explanation and cancel/destructive button roles.
No draft, save, dismissal, or restriction policy was changed.
The regression taps keep-editing and discard through both routes and verifies that keep-editing retains the draft.
A separate largest-text regression checks both choices, the reachable save area, and retained draft values.
The existing grouped bottom background was also checked with pending edits; no additional footer code change was needed.

The final light and dark runs each passed both tests in `/tmp/focus-discard-light2.log` and `/tmp/focus-discard-dark.log`.
The first light run executed only the existing test despite requesting both identifiers; its pass was not treated as evidence for the new largest-text test.
The follow-up light run explicitly executed both tests and exported all five expected captures.
Final captures for both appearances were read back, including the alert and pending-edit footer at default and largest text.
The local sibling directory `focus-study-discard-review-2026-11-06/` retains them and the exported XCTest attachment manifests.
SDK/runtime overrides and light appearance were restored after verification.
Host/SDK logic suites, unsigned Release, iOS 17 runtime, and physical-device checks were not repeated for this native presentation correction.
