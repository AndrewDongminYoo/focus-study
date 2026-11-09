# Everyday schedule preview

## Contract

Complete the remaining preview scope of [issue #69](https://github.com/AndrewDongminYoo/focus-study/issues/69).
The save success, refusal, unsaved, and strict-only guidance already present in the interface remains unchanged.
Primary sources are the issue, [M3 design](2026-11-01-m3-schedule-layer-design.md), and `App/EverydaySettingsModel.swift`.

## Behavior

- Show the editable schedule as chronological text rows within its daily range, explicitly labeled as a preview that takes effect after saving.
- Show the current stored schedule separately in a disclosure, using `status.schedule` rather than the draft.
- Partition 08:00–18:00 with lunch 12:00–13:00 into restricted 08:00–12:00, unblocked 12:00–13:00, and restricted 13:00–18:00.
- Support zero and three windows, sort by start, preserve touching unblocked windows without zero-length restricted rows, and suppress all segments for an invalid schedule.
- For a disabled layer, show that no everyday restriction runs; for an unreadable or unavailable stored schedule, do not invent a stored preview.
- State that times outside the daily range have no everyday restriction; focus-session restrictions remain separate.
- Preserve save and failure semantics, reentry behavior, existing accessibility identifiers, storage, engine validation, and maximum window count.
- Use text rather than color to distinguish intervals, one accessibility label per row in chronological order, natural wrapping, and semantic theme colors.
- Reconciliation (2026-11-09, #85): a 24-hour clock now shows above the text rows of each preview, as the [everyday day clock](2026-11-09-everyday-day-clock.md) spec says; the text rows and their labels stay.

## Verification and boundaries

SDK tests inspect interval partitions and draft/stored independence through edits, refusal, failure, save and refresh.
The DEBUG `--everyday-fixture preview` option stores an enabled 08:00–18:00 schedule with lunch 12:00–13:00 and one synthetic app in memory.
Synthetic UI tests inspect rendered labels, reentry, invalid drafts, light/dark appearance, and largest Dynamic Type; capture review media.
Compile the iOS app and extensions, test the affected SDK/UI suites, and run the declared documentation/configuration check.
No shared engine behavior changes, new dependencies, real authorization, real shields, or device installation are in scope.
Simulator accessibility labels and audits cannot establish actual spoken VoiceOver behavior or real Screen Time restrictions.
Explicit operator visual approval is required before merge.
