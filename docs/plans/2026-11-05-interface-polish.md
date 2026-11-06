# Interface polish implementation plan

## Approved scope

The operator approved the preceding HIG review and requested parallel execution on 2026-11-05.
Reference screenshots inform hierarchy, grouping, and feedback; they do not add backgrounds, breathing exercises, hold gestures, or new session rules.
Preserve iOS 17, existing accessibility identifiers, approved accent colors, synchronous process-lock sections, and report privacy boundaries.
No dependency changes or physical-device operations are included.
Initial implementation approval excluded commits and publication; the operator separately authorized commits and PR publication on 2026-11-06.

## Ownership and sequence

- [x] Onboarding worker: `App/OnboardingView.swift`, `App/SettingsView.swift`; make large text scrollable, show setup progress, replace six segments with standard menu pickers, and protect settings dismissal when everyday edits are pending.
- [x] Root and start investigator: inspect `App/FocusModel.swift` and runtime adapters; provide visible start feedback without moving actor-isolated services unsafely or suspending a lock section.
- [x] Everyday worker: `App/EverydaySettingsModel.swift`, `App/EverydaySettingsView.swift`, related SDK tests; track semantic edits, confirm discard, expose save success and local validation.
- [x] Root: `App/FocusView.swift`, `App/TodayHistoryView.swift`, `App/UsageReportHost.swift`, UI tests; improve touch targets, history affordance, summary hierarchy, truthful report help, and meaningful phase accessibility feedback.
- [x] Root: integrate tests, inspect affected documentation, run one independent review and address verified findings.

## Verification

Capture the existing largest-text onboarding failure before changing it (completed in the preceding review).
Update menu-selection UI queries, and add behavioral regressions for reachable onboarding controls, start-state admission, dirty-save/discard, and minimum touch bounds.
Run affected SDK/UI suites on the booted iOS 26.5 simulator, with one heavy mobile job at a time and the declared Xcode.
Run host tests and the separate-process race check if session execution changes.
Run an unsigned device Release build if fixture wiring or target configuration changes.
Review light/dark and largest-text captures from the newly built app, not a previously installed build.
Run the repository Trunk check for changed documentation and inspect its complete log.
Simulator evidence does not establish real Screen Time behavior or iOS 17 runtime support.
