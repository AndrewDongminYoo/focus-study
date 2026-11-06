# Sheet and theme refinement

## Approved direction

The operator requested predictable sheet heights, semantic color tokens, and restrained Liquid Glass based on the supplied references.
Keep iOS 17, the approved accent and label assets, current Korean copy, and all session and privacy rules.
Primary sources: `App/FocusTheme.swift`, `App/FocusSheetStyle.swift`, and `App/FocusView.swift`.

## Implementation

- [x] Define app-wide semantic colors, error variants, spacing, and native glass button styles in `FocusTheme.swift`.
- [x] Apply a single large editor-sheet policy to settings, history, and real and synthetic selection editors.
- [x] Replace session-end popovers with a short confirmation sheet using a scaled height token, with a scrollable large-text alternative.
- [x] Use a single item-based sheet route, preserving explicit continue and destructive end actions.
- [x] Apply tokens and native glass controls while keeping content surfaces stable and readable.
- [x] Regenerate the project from `project.yml` source globs and align SwiftPM exclusions for new app-only files.

## Verification

First exercise continuation visibility and bottom placement against the old session-end dialog.
Run affected UI flows for editor height, continue/end, selection, dirty dismissal, and largest text.
Capture light, dark, and reduced-transparency variants from the new build.
Read all four error-color variants and verify their text contrast against the corresponding background, including a failing contrast fixture.
Run host tests after manifest changes and compile unsigned Release to verify the availability-guarded production code.
Review the complete follow-up diff independently, run Trunk and internal-link checks, and retain local evidence.
These checks do not establish physical Screen Time behavior or iOS 17 runtime support.
