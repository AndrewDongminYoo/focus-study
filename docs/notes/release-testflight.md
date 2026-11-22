# Release to TestFlight

How 0.1.0 (1) reached TestFlight on 2026-11-22, and what the next upload needs.
The distribution entitlement state and the first upload's history live in the [device matrix](screen-time-device-matrix.md#배포-entitlement-상태); the request process lives in the [Family Controls request note](2026-11-21-family-controls-distribution-request.md).

## Before an archive

- **Version.** `project.yml` owns `MARKETING_VERSION` (SemVer; `0.1.0` for the first TestFlight build, `1.0.0` from the first App Store submission) and `CURRENT_PROJECT_VERSION` (an integer build number); every Info.plist reads them, so the app and its extensions cannot drift apart. A build number that App Store Connect already accepted cannot be uploaded again; one that it rejected at upload could be reused.
- **Extension packaging.** The Device Activity Report and App Intents extensions are ExtensionKit extensions (`type: extensionkit-extension`, `EXAppExtensionAttributes`, embedded in `Extensions/`); the Monitor, Shield, Shield Action and widget extensions are NSExtensions in `PlugIns/`. App Store Connect rejects a Device Activity Report extension built as an NSExtension with error 91179.
- **Privacy manifests.** Every bundle that uses a required-reason API needs its own `PrivacyInfo.xcprivacy`. On 2026-11-22 the app and the Intents extension declare `35F9.1` (system boot time, for elapsed time), `CA92.1` (the bundle's own user defaults) and `1C8F.1` (user defaults shared within the App Group); the Monitor declares `35F9.1`; the widget's manifest declares no API; the Report and the two shield extensions use none. Before an upload, check each bundle of a Release build, for example with `strings -a <executable> | grep -x systemUptime` and `nm -u <executable> | grep NSUserDefaults`, and compare with the manifests. Apple's [NSPrivacyAccessedAPIType](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) reference lists each reason's text before its code.
- **Export compliance.** The app declares `ITSAppUsesNonExemptEncryption` as false: it makes no network requests and has no encryption of its own.
- **SDK.** From April 2027 App Store Connect accepts only builds made with the iOS 27 SDK (Xcode 27 or later); the 2026-11-22 upload, built with the iOS 26.5 SDK, carried that warning.

## Archive and upload

1. Archive with the development signing that the project already uses:

   ```plaintext
   xcodebuild archive -project FocusStudy.xcodeproj -scheme FocusStudy -configuration Release -destination 'generic/platform=iOS' -archivePath <dir>/FocusStudy-<version>-<build>.xcarchive -derivedDataPath DerivedData
   ```

2. Export and upload with an export options file, run by the Account Holder, because it creates distribution certificates and profiles and publishes the build:

   ```plaintext
   xcodebuild -exportArchive -archivePath <archive> -exportOptionsPlist <dir>/ExportOptions.plist -exportPath <dir>/export -allowProvisioningUpdates
   ```

   The export options used on 2026-11-22:

   ```plaintext
   destination: upload
   manageAppVersionAndBuildNumber: false
   method: app-store-connect
   signingStyle: automatic
   teamID: 393JTTV68D
   uploadSymbols: true
   ```

   Xcode Organizer's "Distribute App" › "App Store Connect" › "Upload" does the same.

## After the upload

- App Store Connect processes the build for a few minutes; a problem found then arrives by email with an ITMS number.
- A TestFlight build installed over a development build keeps the app's data: the App Group container, the selection, the everyday layer and the history store stay.
- The history sheet shows today's sessions only, so it is empty on a day with no session; that is not data loss. To check the store, copy it from the device and count the rows:

  ```plaintext
  xcrun devicectl device copy from --device <udid> --domain-type appGroupDataContainer --domain-identifier group.kr.donminzzi.focusStudy --source "Library/Application Support" --destination <dir>
  sqlite3 <dir>/default.store "select date(ZSTARTEDAT+978307200,'unixepoch','localtime') d, count(*) from ZSESSIONRECORD group by d"
  ```

  This worked on the TestFlight build on 2026-11-22.
