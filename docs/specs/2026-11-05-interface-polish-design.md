# Interface polish

## Intent and approved scope

The operator approved the HIG findings on 2026-11-05 and supplied six reference screenshots.
Use their clear action hierarchy, grouped controls, and immediate feedback as reference.
Preserve the timer-first layout, approved warm accent pair, iOS 17 deployment target, and all existing session and privacy rules.
Primary sources: `App/OnboardingView.swift`, `App/FocusModel.swift`, and `App/EverydaySettingsModel.swift`.

## Behavior

Onboarding has a scrollable, wrapping body, a small accessible four-step indicator, and a separate bottom navigation area.
Both onboarding and settings use a standard menu picker for the existing six focus lengths, from 25 to 50 minutes in five-minute steps.
Timer controls have at least 44-point touch bounds; the existing bottom history summary gains an icon and disclosure cue without moving it or changing its accessible label.
History gives its completed-only summary more typographic emphasis and aligns completed and interrupted session rows.
The report host offers neutral reload help without claiming to know whether the isolated report extension finished loading.
Break phase headings receive accessibility focus when the phase changes, with restrained feedback on actual break transitions.

Everyday editing compares editable schedule fields and selected tokens against the last loaded or saved draft.
A changed draft exposes unsaved status; unchanged or invalid drafts cannot be saved through the UI.
A persistent bottom save area keeps the action, confirmation, and refusal visible while the form scrolls.
Successful saves show a confirmation and haptic; failed saves retain the draft and never claim success.
Validation appears near the related time or selection section, and the stored strict-only interval is explained before a save.
Back and settings completion confirm before discarding edits; interactive sheet dismissal is disabled while edits are pending.

The timer start action first reserves a unique pending request and displays a progress indicator with a static explanation.
After the indicator is attached and laid out, two display-link callbacks provide an opportunity to display feedback before the original synchronous start body executes.
The body rechecks authorization, selection, errors, and any session started elsewhere.
Entering the background, view removal, access changes, and clock changes cancel a pending request; stale callbacks cannot execute a newer request.
The existing synchronous `start()` API and monotonic start-body diagnostic measurement remain intact.
No actor-isolated services cross threads and no process-lock section suspends.
This improves visible feedback; it does not remove main-actor occupation during the synchronous operation or prove physical compositor presentation.

## Non-goals and verification

Do not add breathing exercises, audiovisual backgrounds, hold-to-start/end gestures, hard mode, longer sessions, or a new restriction policy.
Do not transport report data to the host, change signing, or perform physical-device operations.
Add SDK regressions for pending-start admission and cancellation, semantic dirty tracking, save outcomes, and localized validation.
Exercise menu selection, large-text onboarding, tap bounds, and keep/discard flows through UI tests.
Review new-build light/dark and large-text captures, and capture the delayed synthetic start during its actual blocking interval.
Use only the DEBUG synthetic monitoring delay for that check; physical Screen Time latency remains separately unverified.

## Sheet and material refinement

The operator requested a follow-up correction for ambiguous sheet heights and inconsistent color use.
The [sheet and theme plan](../plans/2026-11-05-sheet-theme.md) defines the updated presentation and visual scope.
`FocusTheme.swift` owns app color and spacing roles, with native Liquid Glass controls on iOS 26 and opaque accessibility fallbacks.
Settings, history, and selection use an explicit large editor presentation.
Session end uses a short confirmation with a scaled height token and an explicit continue action; accessibility text uses a scrollable large sheet.
The new error asset includes light, dark, and increased-contrast variants, while the approved accent and label assets remain unchanged.
No hold gesture or session-policy change is included.

## Reference spacing refinement

The operator approved using the Mirae layouts for spacing while keeping native iOS components.
The Figma [home](https://www.figma.com/design/zmuMyOEe7JC3fCBwYhZjDU?node-id=20-50), [settings](https://www.figma.com/design/zmuMyOEe7JC3fCBwYhZjDU?node-id=48-416), [quick alarm](https://www.figma.com/design/zmuMyOEe7JC3fCBwYhZjDU?node-id=33-2096), and [onboarding](https://www.figma.com/design/zmuMyOEe7JC3fCBwYhZjDU?node-id=83-523) frames were read through design context and screenshots.
Home, settings, and bottom actions share a 20-unit horizontal inset; settings rows use 16-unit vertical padding and 4-unit title/detail spacing, with 8-unit small groups elsewhere.
These are layout values extracted from components, not a published collection of spacing variables.

`FocusTheme.Layout` maps those values to a 20-point screen inset, 16-point control spacing, 4-point detail spacing, and 8-point inline spacing.
The existing 12-point related-content spacing and 24-point section spacing complete the app's small spacing scale.
Forms and lists retain native row geometry, separators, scrolling, and system-adaptive surfaces; their outer content margin shares the screen token.
Navigation, switches, pickers, editor presentations, and glass buttons retain native iOS behavior rather than copying the reference's Material components or fixed screen coordinates.

The everyday save action has no enclosing card and spans the shared screen inset.
Its feedback sits above it in a separate center-aligned area with a 44-point minimum height scaled with footnote text.
Long feedback grows naturally, and the form remains scrollable above the bottom action.
The status region reserves space even when empty so ordinary save feedback does not move the action.
Success, unsaved, refusal, and busy copy and their accessibility identifiers stay intact.

Unsaved edits use a native alert on both the everyday back action and settings completion.
The alert displays the existing loss explanation and explicit keep-editing and destructive discard actions.
Keep-editing preserves the current draft and screen; discard returns to settings or closes the editor according to the originating action.
Both actions must remain visible and reachable at accessibility text sizes.
