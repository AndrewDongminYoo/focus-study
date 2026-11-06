# Everyday schedule preview implementation

## Scope and ownership

Use the current workspace on `feat/everyday-schedule-preview`.
The root owns `App/EverydaySettingsModel.swift`, `App/EverydaySettingsView.swift`, `App/Debug/UITestFixtures.swift`, `SDKTests/EverydaySettingsModelTests.swift`, `UITests/FocusFlowTests.swift`, and the paired spec and plan.
Inspect existing instruction and README claims; correct only implementation-caused drift.

## Steps

1. Add a UI regression against the absent preview and observe assertion failure before implementation.
2. Add a model-only interval projection using existing schedule validation, with literal partition expectations for zero/three/touching/overlapping windows and stored-state independence.
3. Render draft rows and a separate saved disclosure, disabled/invalid states, wrapping text and spoken time-range labels.
4. Add only the DEBUG synthetic fixture needed for stable saved/draft comparison; keep real restrictions untouched.
5. Run affected SDK/UI tests and compile app/extensions; verify unsigned Release when fixture wiring changes.
6. Inspect captured light, dark and largest-text screens; record accessibility evidence and limits, run `trunk check --no-fix`, and complete one structured local review.
7. Commit scoped paths, push, open the PR, finish hosted review and CI, and assign the operator only after the live body and technical gates are final.
8. Request visual approval with surviving artifacts; merge only after that approval and every required gate, then retire owned control state.

## Minimum commands

```sh
xcodebuild test -project FocusStudy.xcodeproj -scheme FocusStudy -destination 'platform=iOS Simulator,id=9F3F3CF4-2A0A-46D3-8235-385A3DC57A51' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:FocusSDKTests -only-testing:FocusUITests
xcodebuild build -project FocusStudy.xcodeproj -scheme FocusStudy -configuration Release -destination 'generic/platform=iOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
trunk check --no-fix
```
