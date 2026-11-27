# Store privacy declarations

This note owns the privacy answers of the App Store submission: the App Privacy answers in App Store Connect, the App Review notes and the privacy policy at `https://focus.donminzzi.kr/privacy` cite it.
Change it first when the app's data boundary changes, then update those three places in the same release.
The data boundary itself is owned by the [design contract](../specs/2026-10-26-focus-study-design.md#타깃과-데이터-경계); this note records the evidence that a build keeps it.

## App Privacy answers

- Data collection: **Data Not Collected**.
  The app and its extensions send nothing off the device: there is no account, no server, no analytics, no advertising and no crash reporting.
- Tracking: none.
  Every privacy manifest declares `NSPrivacyTracking` false and an empty `NSPrivacyCollectedDataTypes`.

Apple counts data as collected only when it leaves the device, so the data that stays on the device below needs no App Privacy answer.

## Data that stays on the device

- The app and website selection: opaque Screen Time tokens, in the app's own files and, during a break, in a session-scoped copy in the App Group.
- The session control state, the registration marker and the today snapshot in the App Group; none holds an app or website name, a Focus name or usage.
- Session history in SwiftData on the App Group, with CloudKit sync turned off (`cloudKitDatabase: .none`).
- Settings in user defaults.
- The weekly review's notes, review periods and notification settings, in the app's own user defaults and never in the App Group; its share image leaves the device only through the person's own share or save action.
- Screen Time usage, which only the Report extension reads and renders; it has no App Group access and writes nothing.
- The shield shows the app name or the website domain that iOS passes to the Shield extension; the extension stores nothing.

Deleting the app deletes all of it.

## Evidence for 1.0.0 (2), 2026-11-22

Source search over the 69 Swift files of `App/`, `Shared/`, `Integration/`, `Monitor/`, `Report/`, `Presentation/`, `Shield/`, `ShieldAction/`, `Intents/`, `Widget/` and `Activity/` for `URLSession`, `URLRequest`, `NWConnection`, `import Network`, `WKWebView`, `SFSafari`, URLs, CloudKit, `AdSupport`, `AppTrackingTransparency`, Firebase, analytics and crash SDKs, the pasteboard, location, contacts, HealthKit, photos, camera, StoreKit, iCloud, mail and `openURL`: the only matches are the three `cloudKitDatabase: .none` configurations.

Unsigned Release build of `project.yml` at 1.0.0 (2), all 7 executables (`FocusStudy`, `FocusActivity`, `FocusMonitor`, `FocusShield`, `FocusShieldAction`, `FocusReport`, `FocusStudyIntents`):

- `nm -u` finds no `URLSession`, `NSURLConnection`, `nw_connection`, `CFNetwork`, `NWConnection`, `ASIdentifierManager`, `ATTrackingManager`, `CKContainer` or `CLLocationManager` symbol; as a control, the app's `nm -u` lists 1299 Swift symbols.
- `otool -L` links none of Network, AdSupport, AppTrackingTransparency, CloudKit, CoreLocation or WebKit; the app, `FocusActivity` and `FocusStudyIntents` link the Swift overlay `libswiftCoreLocation.dylib`, with no location symbol referenced.
- No Info.plist of the 7 declares a usage description; Family Controls authorization needs none.

Repeat these checks before a release that adds a dependency, an extension, a usage description or a network call.

The weekly review of issue #251 adds the first usage description, `NSPhotoLibraryAddUsageDescription` in the app's Info.plist, for the save of its share image to Photos with add-only access (the 순공 calendar share image of issue #253 uses the same text, through the share sheet's "이미지 저장"), and the first local notification; the release of issue #255 repeats the checks above with them.

## Evidence for the paid build, 2026-11-27

Issue #255 repeats the checks above at `5316ad7`, which holds every paid-build feature; the paid build changes only its version, build number and the gate setting after this commit.

The App Privacy answers do not change: still **Data Not Collected** and no tracking.
Apple's [App Privacy details](https://developer.apple.com/app-store/app-privacy-details/) (read 2026-11-27) says that "Data that is processed only on device is not “collected” and does not need to be disclosed in your answers", and that "You are not responsible for disclosing data collected by Apple."
The app reads its StoreKit 2 transactions and `AppTransaction` on the device and sends nothing from them anywhere; the page does not mention in-app purchases directly, so this answer applies its general rule.
If a later build sends a transaction value off the device, Purchase History has to be declared.

Source search over the 80 Swift files of the same 11 directories, with the patterns of 1.0.0 plus `UNUserNotificationCenter` and `UIImageWriteToSavedPhotosAlbum`:

- `cloudKitDatabase: .none` in the same three configurations, and no URL in the source.
- `import StoreKit` only in `App/PaidAccessStore.swift`, the StoreKit 2 adapter of the [paid access design](../specs/2026-11-24-paid-access-design.md).
- `UNUserNotificationCenter` only in `App/WeeklyReviewNotifications.swift`: local notifications, scheduled on the device.
- `UIImageWriteToSavedPhotosAlbum` only in `App/WeeklyReviewView.swift`: the add-only save of a share image.
- No match for the network, tracking, location, contacts, health, camera, pasteboard, mail or `openURL` patterns.

Unsigned Release build at `5316ad7`, the same 7 executables (`FocusReport` and `FocusStudyIntents` are under `Extensions/`, the other extensions under `PlugIns/`):

- `nm -u` finds none of the network, tracking, CloudKit or location symbols of the 1.0.0 check in any executable; as a control, the app lists 1529 Swift symbols.
- `otool -L`: only the app links `StoreKit.framework` and `UserNotifications.framework`; no executable links Network, AdSupport, AppTrackingTransparency, CloudKit, CoreLocation, WebKit or Photos. The app still links the weak overlay `libswiftCoreLocation.dylib`.
- The app's Info.plist declares one usage description, `NSPhotoLibraryAddUsageDescription`; no extension declares one. A local notification needs no usage description.

## Age rating

`[UNCERTAIN]` The questionnaire was not read for this note; answer it in App Store Connect from these facts: no violence, sexual content, profanity, drugs, gambling, horror or medical content; no user-generated content, messaging, web browsing or advertising.
The app is not a parental control app: it uses individual Screen Time authorization on the person's own device.
