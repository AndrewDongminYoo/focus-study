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

The weekly review of issue #251 adds the first usage description, `NSPhotoLibraryAddUsageDescription` in the app's Info.plist, for the save of its share image to Photos with add-only access, and the first local notification; the release of issue #255 repeats the checks above with them.

## Age rating

`[UNCERTAIN]` The questionnaire was not read for this note; answer it in App Store Connect from these facts: no violence, sexual content, profanity, drugs, gambling, horror or medical content; no user-generated content, messaging, web browsing or advertising.
The app is not a parental control app: it uses individual Screen Time authorization on the person's own device.
