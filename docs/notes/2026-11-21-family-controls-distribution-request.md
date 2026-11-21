# Family Controls distribution request

Date: 2026-11-21.
Refs [issue #188](https://github.com/AndrewDongminYoo/focus-study/issues/188).
The [request guide](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement) asks for the same request for the app and for each Screen Time extension.
The state of each bundle ID lives in the [device matrix](screen-time-device-matrix.md#배포-entitlement-상태), not here.

## What the request is

Read on 2026-11-21 in the developer account:

- Each App ID's Capability Requests tab has "Family Controls (Distribution)", which links to the [request form](https://developer.apple.com/contact/request/family-controls-distribution/).
- The form is for the developer account, not for a bundle ID: it holds the name, the email and the Team ID, filled in from the account, the terms, and a "Get Entitlement" button. It asks for no app description and no bundle ID.
- The terms allow the framework only for parental supervision through Family Sharing, or for an individual's focus, timers, task management or personal device usage management. They exclude ad blocking, organizational use and managing another adult's device, and they limit device and usage data to providing those controls, with no sharing beyond the individual and no advertising use.
  온:공 is the second case: individual authorization, a focus timer and personal blocking, and no data leaves the device.
- Only the Account Holder submits it, and submitting accepts the terms.

The request was approved at once on 2026-11-21. Before it, the app's App ID listed only "Family Controls (Development)"; after it, the App ID editor of every bundle ID below showed "Family Controls (Development)" and "Family Controls (Distribution)" checked and "Family Controls App and Website Usage" unchecked, and Xcode showed the capability as distribution. One assignment covers every bundle ID of the team.

## Bundle IDs that use Family Controls

| Target            | Bundle ID                              |
| ----------------- | -------------------------------------- |
| FocusStudy        | `kr.donminzzi.focusStudy`              |
| FocusMonitor      | `kr.donminzzi.focusStudy.monitor`      |
| FocusReport       | `kr.donminzzi.focusStudy.report`       |
| FocusStudyIntents | `kr.donminzzi.focusStudy.intents`      |
| FocusShield       | `kr.donminzzi.focusStudy.shield`       |
| FocusShieldAction | `kr.donminzzi.focusStudy.shieldaction` |

`kr.donminzzi.focusStudy.activity` (the widget and the Live Activity) does not use Family Controls.

## Capabilities that are not needed

- Family Controls App and Website Usage (`com.apple.developer.family-controls.app-and-website-usage`, iOS 26.4 and later) lets an app read usage data, such as installed bundle identifiers and visited domains, under the `approvedWithDataAccess` status. 온:공 reads none of that data, so no target enables it; `Integration/ScreenTimeAdapters.swift` only treats that status as approved if the system reports it.
- No new App Group: the app, the Monitor, the Intents extension and the widget already share `group.kr.donminzzi.focusStudy`, and the two shield extensions have no App Group by design.

## After the assignment

For each bundle ID above, check in the developer account that Family Controls (Distribution) is assigned and that Provisioning Support lists App Store and TestFlight, then update the device matrix row.
With automatic signing, Xcode switches the Family Controls capability to distribution by itself.
