# Home screen widget

Date: 2026-11-13.
Status: design for approval.
Reconciliation (2026-11-14, #124): the design was approved with its recommended choices (#134) and is implemented, not yet run on a device. `Shared/TodaySnapshot.swift`, `App/TodaySnapshotWriter.swift`, the write points in `App/FocusModel.swift` and `App/FocusFilterHandler.swift`, and `Widget/` are the authority, with the tests in `CoreTests/TodaySnapshotTests.swift`, `CoreTests/WidgetSourceListTests.swift`, `SDKTests/TodaySnapshotWriterTests.swift` and `UITests/FocusActivityTests.swift`.
Source: [issue #124](https://github.com/AndrewDongminYoo/focus-study/issues/124), and the decision of 2026-11-13 in [issue #43](https://github.com/AndrewDongminYoo/focus-study/issues/43).
This document amends the [Live Activity decision](2026-11-06-live-activity-decision.md) and the [2026-10-26 design](2026-10-26-focus-study-design.md) only where [Superseded lines](#superseded-lines) says so.
This document changes no code, and the implementation needs its approval first.
Current code was read at `5b75ca4`.

## Contract

Decided on 2026-11-13:

1. The app gets a home screen widget.
2. The main screen of the app stays the focus-start screen. The widget is a glance and an entry into the app, not a second control surface.
3. The widget shows no selection token, app name, domain or usage data, and it never states that restrictions are on or off. Like the Live Activity, it shows only what the app confirmed, as planned times or completed records.
4. Rewards stay out of scope: points, badges, unlocks, rankings, comparison with friends, and a "streak about to break" message. The display-only streak may appear only if this spec decides so and says why it is not a reward surface.

Out of scope: the implementation, any signing or profile change, any device install, and the streak itself (issue #125).

## Evidence

Code and documents of this repository:

- `project.yml`: the `FocusActivity` target is an app extension that compiles `Widget`, `Activity/FocusActivityAttributes.swift`, `Activity/FocusActivityViews.swift` and `Shared/FocusActivityContent.swift`. It has `Configuration/Activity-Info.plist` and no `CODE_SIGN_ENTITLEMENTS`. The app embeds it.
- `Widget/FocusActivityWidget.swift` holds one `@main` widget with an `ActivityConfiguration`, and `Widget/PrivacyInfo.xcprivacy` lists no accessed API type.
- `Configuration/App.entitlements` lists the App Group `group.kr.donminzzi.focusStudy`. `Configuration/App-Info.plist` and `Configuration/Monitor-Info.plist` have the key `FocusAppGroupIdentifier`; `Configuration/Activity-Info.plist` does not.
- `GroupConfiguration.directory()` (`Integration/ScreenTimeAdapters.swift`) returns the directory `SessionControl/` of the App Group container. The [privacy review of 2026-11-13](../notes/screen-time-device-matrix.md#개인정보-경계와-배포-entitlement-검토-2026-11-13) lists what that directory holds: the control file, the registration marker, and two files with selection tokens (the break selection copy and `everyday-layer.json`).
- [Live Activity decision, Local data boundary](2026-11-06-live-activity-decision.md#local-data-boundary): the activity payload holds only a session UUID, a phase, times and a freshness marker, and the extension gets no App Group access. [State and time projection](2026-11-06-live-activity-decision.md#state-and-time-projection): the display "never proves restrictions were applied or lifted".
- [2026-10-26 design, 세션 상태와 원자성](2026-10-26-focus-study-design.md#세션-상태와-원자성): the app places a session on the day of its start, shared files are replaced atomically, and a read and a write of `UserDefaults` are not treated as one atomic operation.
- `App/SessionRecord.swift`: `SessionHistory.records(on:calendar:)` returns the records whose `startedAt` is inside `TimeRules.today(now:calendar:)`. `SessionSummary` counts only `.expired` records, sums their `focusDuration`, and gives the text `오늘 집중 <duration> · <n>회`. The file imports SwiftData.
- `App/FocusModel.swift`: `refresh()` reconciles, imports a terminal session into the history, and then reads `records` for today with `Calendar.current`. `App/FocusView.swift` calls it when the scene becomes active, on `NSCalendarDayChanged`, on a time-zone change and on a clock change, and shows `SessionSummary(records:).text` at the bottom of the timer screen.
- `App/FocusFilterHandler.swift` and `App/FocusRuntimeHolder.swift`: a Focus on call imports a waiting terminal session through its own `SessionHistory` (`importPendingTerminal`), also in a background launch with no `FocusModel`. A Focus off call runs on the engine alone and imports nothing.
- `Shared/TimeRules.swift` uses `ControlSession`, so a target that compiles it also needs the control types.
- `App/FocusRuntime.swift`: the history uses `ModelContainer(for: SessionRecord.self, configurations: ModelConfiguration(cloudKitDatabase: .none))`, which names no `groupContainer` and no URL, and `process()` builds the fixture runtime for `--ui-testing`.
  `[UNCERTAIN]` Where the history store file is.
  The declaration in Apple's documentation gives the default `groupContainer: ModelConfiguration.GroupContainer = .automatic`, the page of `automatic` says "Tells SwiftData to use the app’s primary group container as the root location for the persistent storage.", and the app has one App Group.
  So the store is probably already inside the App Group container, outside `SessionControl/`.
  No document of this repository states the location, and it was not observed on a device or a simulator.
  This design is written to hold for both locations.
- [M4 design, Filter start](2026-11-01-m4-focus-filter-design.md#filter-start-focus-on): the Focus on call has five steps (inputs, history, start section, record, refresh), and the first row of its [gap table](2026-11-01-m4-focus-filter-design.md#gaps-between-steps) says of steps 1 and 2 "Nothing changed by the filter."
  In `App/FocusFilterHandler.swift`, `focusDidChange` runs `start()` or `end()` and then the `refresh` closure, which is step 5.
- The app has no URL scheme and no URL handler: `Configuration/App-Info.plist` has no `CFBundleURLTypes`, and a search of the Swift sources finds no `onOpenURL` and no `onContinueUserActivity`.
- `AGENTS.md`: "Widget compiles only `Shared/FocusActivityContent.swift` and Activity attributes/views, with no App Group or control-store access."
- `docs/specs/2026-11-13-streak-design.md` does not exist on this branch. The streak is a design under review in a separate PR, and this document cites none of its content.

Apple's documentation, read through the documentation JSON on 2026-11-13:

- [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date):
  - "your widget extension is not continually active, even if the widget is onscreen."
  - "For a widget the user frequently views, a daily budget typically includes from 40 to 70 refreshes."
  - Reloads do not count against the budget when "The widget’s containing app is in the foreground."
  - With the policy `never`, "WidgetKit doesn’t ask for another timeline until the app uses `WidgetCenter` to tell WidgetKit to request a new timeline."
  - "Your timeline provider should create timeline entries that are at least about 5 minutes apart. WidgetKit may coalesce reloads across multiple widgets, affecting the exact time a widget is reloaded."
  - "Although your widget timeline provider drives your reload schedule, WidgetKit sometimes reloads your widget to help keep its content fresh."
- [TimelineProvider](https://developer.apple.com/documentation/widgetkit/timelineprovider): "Have the containing app prepare data for the widget in advance of when the widget needs it. Use a shared group container to store the data." and "Call `reloadTimelines(ofKind:)` only when information the widget is currently displaying changes." For the widget gallery (`context.isPreview`), "use sample data instead." The reload limit is not imposed "when debugging your widget in Xcode."
- [Configuring app groups](https://developer.apple.com/documentation/xcode/configuring-app-groups): "You can also use an app group to share data between an app extension or App Clip and its host app." The page describes access to the shared container as a whole and names no limit to one file.
- [Linking to specific app scenes from your widget or Live Activity](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity): "By default, tapping or clicking your widget or Live Activity opens its corresponding app." Without a `widgetURL` or a `Link`, "the system opens the containing app and passes an `NSUserActivity`".
- [Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension): "You can include multiple widget types in your widget extension", and "For an app’s widget to appear in the widget gallery, a person must launch the app that contains the widget at least once after the app is installed." For an extension with the protection level `NSFileProtectionCompleteUntilFirstUserAuthentication` or `NSFileProtectionNone`, "WidgetKit uses its default behavior and displays a placeholder until a person authenticates after they reboot their device", and "iOS widgets are available as iPhone widgets on Mac."
- [Preparing widgets for additional platforms, contexts, and appearances](https://developer.apple.com/documentation/widgetkit/preparing-widgets-for-additional-contexts-and-appearances): its table says that `systemSmall` needs the `fullColor`, `accented` and `vibrant` rendering modes, and for StandBy and CarPlay "WidgetKit uses your `WidgetFamily.systemSmall` widget and scales it to fit available space."
- [Displaying the right widget background](https://developer.apple.com/documentation/widgetkit/displaying-the-right-widget-background): "mark your background views as removable for every widget size", with `containerBackground(_:for:)`.
- SwiftData, [`ModelConfiguration.init(_:schema:isStoredInMemoryOnly:allowsSave:groupContainer:cloudKitDatabase:)`](<https://developer.apple.com/documentation/swiftdata/modelconfiguration/init(_:schema:isstoredinmemoryonly:allowssave:groupcontainer:cloudkitdatabase:)>) and [`ModelConfiguration.GroupContainer.automatic`](https://developer.apple.com/documentation/swiftdata/modelconfiguration/groupcontainer-swift.struct/automatic): the two quotes about the history store in the list above.

A probe of the string search, run on 2026-11-13: one Swift file that passes seven literals to `appendingPathComponent` and prints the paths, built for macOS arm64 with `xcrun swiftc -O`, then `grep -caF` for each literal in the binary.
The binary had no match for `SessionControl`, `control.json`, `control.lock` and `default.store`, and one match each for `everyday-layer.json`, `break-selection` and `registration-marker`; the `-Onone` build had every literal.
The four literals without a match are 15 bytes or shorter.
So a string search of an optimized binary cannot show that such a short literal is absent.
The probe is not the iOS Release build of this project.

What these pages do not say:

- `[UNCERTAIN]` Whether WidgetKit shows a timeline entry at exactly its date, in particular an entry that is less than 5 minutes after the entry before it.
- `[UNCERTAIN]` How soon a reload request is served, in the foreground or in a background launch.
- `[UNCERTAIN]` Whether WidgetKit asks for a new timeline after a time-zone change or a manual clock change. The budget list names a locale change, not these.
- `[UNCERTAIN]` Whether the App Group container is available to an unsigned simulator build of the extension.
  Reconciliation (2026-11-14, #124): in the unsigned simulator Debug build of the app, `codesign -d --entitlements -` printed no entitlements and `simctl get_app_container … groups` listed no group, so the container is not available there; the widget was not added to the simulator home screen.
- `[UNCERTAIN]` Which iOS versions show the home screen widget in the `accented` mode.

## Design

### Open points for approval

These are product choices. Each has a recommended answer in the section that it names.

1. **Content.** The widget shows today's completed focus time and count, and nothing about a running session ([What the widget shows](#what-the-widget-shows)).
2. **Streak.** The first version shows no streak ([What the widget shows](#what-the-widget-shows)).
3. **Families.** The small home screen family only ([Sizes and families](#sizes-and-families)).
4. **Copy.** The Korean text of each state ([Copy and look](#copy-and-look)).
5. **Delay.** The number changes only when the app process runs. A session that ends while the app is closed appears in the widget after the next launch of the app, as it does in the app's own summary ([Data path](#data-path)).
6. **Extension.** The widget lives in the existing `FocusActivity` extension, which gets the App Group entitlement ([Target and project changes](#target-and-project-changes)).
7. **Access.** With that entitlement the system lets the extension process open every file of the App Group container: the files with selection tokens in `SessionControl/`, and the history store if it is there. Only the code of the target keeps the widget to its one file, and the checks of that code are a source list and a search of the built extension ([Data path](#data-path)).
8. **Midnight.** No cited page says that the Empty entry shows at exactly 00:00. Until it shows, the widget has yesterday's number under `오늘 집중`. The device plan accepts this up to 00:05, and the delay is not measured yet ([Refresh](#refresh)).

### What the widget shows

Recommended: today's completed focus time and the count of completed sessions.
These are the two numbers of the today summary on the timer screen, which the app computes from `.expired` records only.
A completed record is not a certificate of study or of blocking, as the 2026-10-26 design says for the history.

The first version shows no streak.
The streak design is not on this branch, so this spec cannot say what the number means or why it is not a reward surface.
A later amendment can add it with a new schema version of the snapshot, and it must then give that reason.

The widget has three views of its own:

| View     | When                                                                                             | Content                         |
| -------- | ------------------------------------------------------------------------------------------------ | ------------------------------- |
| Numbers  | The snapshot is for today and its count is above 0                                               | The title, the time, the count  |
| Empty    | The snapshot is for today with a count of 0, is for another day, or is missing                   | The title and an invitation     |
| Check    | The snapshot cannot be read, cannot be decoded, has another schema version or has invalid values | The title and "open the app"    |
| (system) | Placeholder, and before the first unlock after a restart                                         | A redacted layout, no real data |

The Empty view states no number and does not say that no record exists.
So no entry that the provider computes shows the number of an earlier day as today's, and none claims a zero that the app did not confirm.
This is a rule for the entries, not for the screen: the system can show the midnight entry late, and until then the screen has yesterday's number ([Refresh](#refresh), Limits).
On first use the file is normally there before the widget is: the cited page says that the widget is in the gallery only after one launch of the app, and that launch writes the file.
The widget gallery preview shows fixed sample numbers and never reads the snapshot.

### Sizes and families

Recommended: `systemSmall` only.
It holds the title, one large time and the count.
The cited page says that the system also uses this family in StandBy, scaled and without its background, so the view puts its background in `containerBackground(_:for:)`.

The Lock Screen accessory families are left for a later change.
They need the vibrant look, an Always-On check and their own captures, and the Lock Screen is where the Live Activity already is.
The medium and large families have no more content to show.

### Data path

Recommended: one small JSON file in the App Group container that the app writes and the widget reads.

**File.** `TodaySnapshot/today.json` in the container of `group.kr.donminzzi.focusStudy`, in its own directory next to `SessionControl/`.

| Field            | Type     | Meaning                                                                                 |
| ---------------- | -------- | --------------------------------------------------------------------------------------- |
| `schemaVersion`  | `Int`    | `1`.                                                                                    |
| `dayStart`       | `Date`   | The start of the local day that the app used for its history query (`TimeRules.today`). |
| `completedCount` | `Int`    | The count of `.expired` records that started on that day.                               |
| `focusSeconds`   | `Double` | The sum of the `focusDuration` of those records, in seconds.                            |

The file holds nothing else: no session UUID, no start or end time of a session, no end reason, no token, no app or website name, no domain, no Focus name and no usage.
It does not leave the device through any path of the app; the privacy review of 2026-11-13 found no network call in the sources.
The system can show an iPhone widget on a Mac, as the cited page says; that is a system feature, and this design does not control it.

**Day check.** The snapshot is for today only when `calendar.startOfDay(for: entryDate) == dayStart`, with the widget's own current calendar and the date of the timeline entry.
One `Date` comparison covers midnight, a time-zone change and a daylight-saving change.
A `dayStart` in the future counts as another day.

**Valid values.** `completedCount >= 0`, `focusSeconds` finite and `>= 0`, and the count is 0 exactly when the seconds are 0.
Every other content gives the Check view.

**Writer.** Only the app process writes the file, on the main actor, outside every process lock, and it never takes the control lock for it.
The write replaces the file atomically with the options of `control.json` (`SharedControlStore.fileWritingOptions`), so a reader gets the old file or the new one.
The writer is a closure of `FocusServices` that does nothing by default; only `FocusRuntime.real()` sets it, so a fixture runtime writes no snapshot and asks for no reload.

The app writes at two places:

- `FocusModel.refresh()`, after its history read of today succeeded, from the `records` and the `now` of that read.
  This covers a session end, an expiry that a tick observes, the foreground, the day change, a time-zone change and a clock change, because each of them runs `refresh()`.
- The Focus on call, in step 5 of the M4 [Filter start](2026-11-01-m4-focus-filter-design.md#filter-start-focus-on), after the `refresh` closure: the handler reads today's records through its own history and writes.
  This covers a background launch, which has no `FocusModel`.
  The write is after the start section and the record of step 4, so it never delays a start and never changes its result, and steps 1 and 2 stay without a change by the filter.
  With a `FocusModel` in the process, the write check finds the content that `refresh()` wrote, or writes it first; both give the same file.

A write happens only when the new content differs from the content of the file, or the file is missing or unreadable.
A failed history read writes nothing.
The Monitor never writes the snapshot, because it has no history.

**Delay.** The number is what the app last confirmed, not the state of the device.
A session that the Monitor ends while the app does not run, or that a Focus off call ends, has no history record yet, so the widget and the app's own summary both show it only after the next `refresh()` or the next Focus on call.
A session that starts before midnight and completes after it counts for the day of its start, as in the app.

**Privacy boundary that changes.** Today the widget extension has no App Group entitlement.
With this design it gets the entitlement, and the system then lets its process open every file of the container, also the files in `SessionControl/`; the cited page names no narrower grant.
If the history store is in the container, as [Evidence](#evidence) says is probable, the process can also open that store, with every start time and end reason.
The boundary is therefore the code of the target:

- The widget's code may read `TodaySnapshot/today.json`, and nothing else in the container. It writes nothing.
- The control file, the lock file, the selection files (`everyday-layer.json`, the break selection copy), the registration marker, the timing flag and the SwiftData history store stay off limits, wherever the store is.
- The target compiles no file that can open them: no `Shared/SharedControlStore.swift`, `Shared/SessionControl.swift`, `Shared/ControlTypes.swift`, `Shared/RegistrationMarker.swift` or `Shared/TimeRules.swift`, and nothing from `Integration/`, `App/` or `Monitor/`.
  `App/SessionRecord.swift` is in that list, so the target has no model type to open the store with.
- The target imports no FamilyControls, ManagedSettings, DeviceActivity or SwiftData.
- The snapshot type and its rule are one new file in `Shared/` that uses Foundation only, and the file reader is in `Widget/`.
- The reader builds one path, from the container URL and the two constants `TodaySnapshot` and `today.json`, and `Widget/` has no other call that opens a file or lists a directory.

The implementation observes where the history store is, in the simulator or on the device, and records it in the reconciliation line of the device matrix privacy review.
The location changes no rule above.

Three checks keep it so, each in [Verification for the implementation](#verification-for-the-implementation): a test that pins the `FocusActivity` source list of `project.yml`, the list of the frameworks that the built extension links, and the search of the built extension.
The first check is the one that covers the control file, the lock file and the store, because the search cannot see their short names.
No check proves that code in `Widget/` builds another path by hand; the review of `Widget/` covers that.

### Refresh

Each write point first compares the new content with the file; this document calls that the write check.
The app asks WidgetKit to reload the widget's kind after a write that changed the file, and once after the first write check of each app process that ends with a correct file, also when that check wrote nothing.
The second rule repairs a process that ended between a write and its reload request.
Every later check that writes nothing asks for nothing.

The provider reads the file once for each timeline and returns:

| State at the read                            | Entries                                                           | Policy  |
| -------------------------------------------- | ----------------------------------------------------------------- | ------- |
| For today, count above 0                     | Numbers at the current date, Empty at the next local start of day | `never` |
| For today with 0, or another day, or missing | Empty at the current date                                         | `never` |
| Unreadable or invalid                        | Check at the current date                                         | `never` |

The provider computes the view of each entry from the file and the date of that entry, with the day check above.
It never keeps a number in memory between two requests.

What the budget means here: the app's requests in the foreground do not count, and a request in a background launch for a Focus on call counts as one, at most one for each such launch plus one for each changed number.
The timeline itself asks for no reload, so the design stays far below the 40 to 70 refreshes of the cited page.

Limits, each `[UNCERTAIN]` in [Evidence](#evidence):

- The Empty entry at midnight can show late. Until it shows, the widget has yesterday's number under the title of today.
- After a time-zone change or a clock change while the app does not run, the entries keep the dates that the old calendar gave them until WidgetKit asks again or the app runs.
- A reload request can be served late.

The physical-device plan measures the first and the third limit.
If the midnight entry is late by more than a few minutes on the device, the amendment that records it decides another rule before release.

### Tap behavior

A tap opens the app, and nothing else.
The view has no `widgetURL` and no `Link`, so the default of the cited page applies, and the app shows the screen of its launch route, which is the timer screen for a person who finished onboarding.
The app has no URL scheme today, and this design adds none.
The app does not handle the `NSUserActivity` of the tap.

The widget starts nothing by itself: no button, no toggle and no App Intent in this version.
Opening the app runs `refresh()`, which also repairs the snapshot.

### Target and project changes

Recommended: the existing `FocusActivity` extension, with a `WidgetBundle` as its `@main` type that lists the Live Activity widget and the new widget.
The product target count stays at four.

- `Configuration/Activity.entitlements` (new): only `com.apple.security.application-groups` with `group.kr.donminzzi.focusStudy`.
- `Configuration/Activity-Info.plist`: the key `FocusAppGroupIdentifier`, as in the app and the Monitor.
- `project.yml`, target `FocusActivity`: `CODE_SIGN_ENTITLEMENTS: Configuration/Activity.entitlements`, and the new `Shared/` file in `sources`. `FocusSDKTests` gets the new app file of the writer.
  Reconciliation (2026-11-14, #124): the app target also compiles `Widget/TodayWidgetView.swift`, so that the DEBUG screen `--widget-preview` draws the production view; the `FocusActivity` source list is unchanged by this.
- `Package.swift`: the new `App/` file goes into the `exclude` list of `FocusHistory`; the new `Shared/` file is in `FocusCore` without a change.
- Regenerate `FocusStudy.xcodeproj` with `xcodegen generate` and review the diff.
- `Widget/PrivacyInfo.xcprivacy` stays as it is. `[UNCERTAIN]` Whether reading a file's content needs an entry; the builder checks Apple's list of required-reason APIs.
  Reconciliation (2026-11-14, #124): checked against [`NSPrivacyAccessedAPIType`](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) through the documentation JSON on 2026-11-14. Its categories are file timestamps, system boot time, disk space, active keyboards and user defaults. The widget calls `Bundle.main.object(forInfoDictionaryKey:)`, `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` and `Data(contentsOf:)`, none of which is in that list, so the file stays as it is.

Signing: the App ID `kr.donminzzi.focusStudy.activity` needs the App Groups capability with this group, and its development profile must include it.
That is a capability and profile change, so it needs explicit authorization under [`AGENTS.md`, Signing and physical-device boundary](../../AGENTS.md#signing-and-physical-device-boundary), and no build of this work uses `-allowProvisioningUpdates` without it.
The distribution entitlement review of the device matrix is not widened: the widget does not use Family Controls, so the Activity row keeps "해당 없음".

### Copy and look

Copy and look are for visual approval.
The implementation PR shows captures in light, dark, the accented home screen and the largest text size, and it waits for approval before the merge.

| Where                      | Text                                          |
| -------------------------- | --------------------------------------------- |
| Title, every view          | `오늘 집중`                                   |
| Numbers, time              | `1시간 15분` (the format of `SessionSummary`) |
| Numbers, count             | `3회`                                         |
| Empty                      | `앱에서 시작해 보세요`                        |
| Check                      | `앱에서 확인해 주세요`                        |
| Gallery name               | `오늘 집중`                                   |
| Gallery description        | `오늘 완료한 집중 시간과 횟수를 보여 줘요.`   |
| Accessibility, Numbers     | `오늘 집중 1시간 15분, 3회`                   |
| Accessibility, other views | The title and the line, as one element        |

- The Check line is the stale line of the Live Activity views, so both surfaces send the person to the app with the same words.
- No view says "차단", "제한" or "완료 인증", and no view shows a time of day.
- The view reads `widgetRenderingMode`: full color uses the app's accent for the time, the accented mode puts only the time in the accent group, and the vibrant mode depends on no color.
  Reconciliation (2026-11-14, #124): the extension has no asset catalog, so `TodayWidgetView.accent` holds the light and dark values of `App/Assets.xcassets/AccentColor` in code; the app's DEBUG preview uses the same constant.
- The time uses one line with a scale factor, so that the largest text size does not clip the count.

### Stored states and failure cases

| Snapshot state                                                       | View    |
| -------------------------------------------------------------------- | ------- |
| Missing                                                              | Empty   |
| For today, count above 0                                             | Numbers |
| For today, count 0                                                   | Empty   |
| For an earlier day, or a `dayStart` in the future                    | Empty   |
| Unreadable (I/O error, file protection), undecodable, invalid values | Check   |
| Another schema version                                               | Check   |

The app and the extension ship in one bundle, so another schema version comes only from a file of another build, and the next write replaces it.

| Gap in the app's write                                           | State after it                                                  | Repaired by                                                       |
| ---------------------------------------------------------------- | --------------------------------------------------------------- | ----------------------------------------------------------------- |
| The write throws                                                 | The old file, whole                                             | The next `refresh()` or Focus on call; the contents still differ  |
| The process ends between the history save and the snapshot write | The file lacks that record                                      | The next `refresh()`, which every launch and foreground runs      |
| The import saved the record, and the acknowledgement threw       | `refresh()` reports its error and reads no records, so no write | The next `refresh()`                                              |
| The process ends between the write and the reload request        | A new file under an old timeline                                | The first write check of the next app process asks for a reload   |
| The history read fails                                           | The old file                                                    | The next `refresh()` whose read succeeds                          |
| A session ends while the app does not run                        | No record yet, so the file is unchanged and matches the history | The next `refresh()` or Focus on call                             |
| The app is deleted and installed again                           | `[UNCERTAIN]` whether the container keeps the old file          | The first launch, which comes before the widget is in the gallery |

A failed snapshot write never sets `errorMessage`, never changes `records` and never blocks a session action.
In the second row the file can hold today's key with a count that is lower than the history, until the app runs again.
That number is a count that the app did confirm earlier today.
No entry that the provider computes has a number of another day or more than the history holds.
The screen can still show yesterday's number for a time after midnight, and old entries can stay after a time-zone or clock change, as the limits in [Refresh](#refresh) say; the device plan accepts the first up to 00:05.
So "never a wrong number for today" holds for the computed entries, and for the screen only as far as the system shows each entry at its date.

### What does not change

- Session, break, deadline, everyday and Focus filter rules. The Focus on call gets one addition in its last step, the snapshot write, which reads no control state and changes no result of the call.
- The control store, its lock and its files. The snapshot is a display copy of the history and not a second state file; the engine and the SwiftData history stay the authority.
- All Screen Time code, the Monitor and the Report extension. The Report still has no App Group access.
- The Live Activity: its payload, its views, its coordinator and its rule that it reads no file.
- The history schema and the today summary of the timer screen.

### `AGENTS.md` changes for the implementation PR

The scope paragraph gets this sentence after the Live Activity sentence:

```plaintext
A read-only home screen widget shows today's completed focus time and count from a snapshot that the app writes, never a session state or shielding (see [design](docs/specs/2026-11-13-home-widget-design.md)).
```

The sentence about the Widget target becomes:

```plaintext
Widget compiles only `Shared/FocusActivityContent.swift`, the today snapshot file of `Shared/`, Activity attributes/views and `Widget/`; its App Group access is for reading `TodaySnapshot/today.json` only, and it compiles nothing that can open the control store, a selection file, the marker or the history store.
```

The architecture table gets one row, with the file names of the implementation:

```plaintext
| the snapshot file of `Shared/`, the writer file of `App/`, `Widget/` | Today snapshot: the rule for "for today" and the timeline entries; the app's write after a history read; the home screen widget and its reader |
```

In this change, `AGENTS.md` gets only one line in its documentation list.

## Alternatives considered

**Today's numbers and the streak.** It is rejected for the first version, for the reason in [What the widget shows](#what-the-widget-shows).

**The state of a running session with its planned end.** The Live Activity already shows it on the Lock Screen and in the Dynamic Island.
It is rejected because the widget would need the control file or a second copy of the session state, and a timeline cannot follow a break request or an early return in time.

**A static start entry with no data.** It needs no App Group, but it shows nothing that the app icon does not.
It is rejected.

**A `UserDefaults` suite in the App Group.** It is rejected because the shared files of this project are JSON files with an atomic replace, and the 2026-10-26 design does not treat a `UserDefaults` read and write as atomic.

**The widget opens the SwiftData store in a shared container.** `[UNCERTAIN]` Whether the store is already in the App Group container ([Evidence](#evidence)); if it is not, this path also needs a move of the store with a migration.
In both cases the extension would compile `SessionRecord`, link SwiftData, and read the whole history with every start time and end reason, as a second process on a store that the app writes.
It is rejected because the widget needs two numbers.

**A new extension target for the home widget.** The Live Activity extension would stay without the entitlement.
It is rejected because it adds a fifth product and a new App ID with its own profile, and because the Live Activity code has no file access that the entitlement could widen; the compile list protects both widgets in the same way.
This is open point 6.

**The Monitor writes a hint when a session expires.** The widget would show a completion without the app.
It is rejected because the Monitor has no history, the file would get a second writer in another process, and the widget would then show a number that the history does not hold.

**A reload policy that asks again at midnight.** It costs one budgeted reload each day and shows the same Empty view as the midnight entry.
It is rejected.

## Superseded lines

The implementation PR adds a dated reconciliation line directly below each of these lines, and it does not rewrite them.
This change edits none of these documents.

- Live Activity decision, [Adopted scope](2026-11-06-live-activity-decision.md#adopted-scope): "Add one WidgetKit extension for the Live Activity, without a home widget, notification request, push token, server, account, or new dependency."
- Live Activity decision, [Local data boundary](2026-11-06-live-activity-decision.md#local-data-boundary): "Do not grant the new extension App Group access or broaden the Report boundary."
- 2026-10-26 design, [Live Activity adoption amendment](2026-10-26-focus-study-design.md#live-activity-adoption-amendment-2026-11-06): "The new extension will receive no App Group access, selections, report data, or history." and "No completion notification, home widget, interactive session control, server, or push transport is added to this scope."
- 2026-10-26 design, [타깃과 데이터 경계](2026-10-26-focus-study-design.md#타깃과-데이터-경계): the list of what the App Group holds, which gets the snapshot file.
- [Live Activity feasibility](../notes/2026-11-06-live-activity-feasibility.md): "It has no App Group, control-store reader, selection, report, history, notification request or push token."
- Device matrix, [privacy review](../notes/screen-time-device-matrix.md#개인정보-경계와-배포-entitlement-검토-2026-11-13): "Report와 Activity 확장은 App Group entitlement가 없어 이 파일들을 읽지 못한다.", and the reason in the Activity row of the entitlement table. The reconciliation line also records the observed location of the history store.
- M4 design, [Filter start](2026-11-01-m4-focus-filter-design.md#filter-start-focus-on): "5. **Refresh.** Tell the app's model to refresh", which gets the snapshot write of the handler.
- M4 design, [Gaps between steps](2026-11-01-m4-focus-filter-design.md#gaps-between-steps): the table gets a line for an exit or a throw in the snapshot write of step 5, with the repair of [Stored states and failure cases](#stored-states-and-failure-cases). Its first row stays true, because the write is not in steps 1 and 2.
- [README](../../README.md#실제-기기를-연결하기-전): "`group.kr.donminzzi.focusStudy` (App과 Monitor만 사용)".
- `AGENTS.md`: the sentence about the Widget target, as [above](#agentsmd-changes-for-the-implementation-pr).

## Physical-device verification

This section is a plan for a later run, not a result.
Record each result in the [device matrix](../notes/screen-time-device-matrix.md) and in issue #124.
Each install on a device needs its own explicit approval, and so does each run that applies real restrictions.
Simulator results do not establish any of these results.

1. Install a signed build of the implementation commit, and record the device and the iOS version. Launch the app once, then add the small widget from the gallery. Expected: the gallery shows the sample numbers, and the added widget shows the view of the current history.
2. Complete one session with the app in front, and go to the home screen. Record the time from the completion to the changed number.
3. Complete one session with the app in the background and the device locked. Unlock without opening the app, and record what the widget shows. Then open the app, go back, and record the time to the changed number.
4. With a number above 0 on the widget, leave the app closed across local midnight. Record what the widget shows at 00:00, 00:01 and 00:05.
5. Start a session by a Focus with the app closed, let it complete, and turn the Focus off and on again. Record whether the number changed without the app in front.
6. Restart the device, and record what the widget shows before and after the first unlock.
7. Record light, dark, the tinted home screen, the largest text size and StandBy.

Acceptance:

- Steps 2 and 3 show the number of the app's today summary after the app ran, and never a higher one.
- Step 4 shows no number of yesterday after 00:05. A later change is a failed check, and a new amendment decides the midnight rule.
- Step 6 shows a placeholder or the Check view before the first unlock, and never a wrong number.
- No view shows a token, an app name, a domain or a restriction state.
- The read-failure state is not reachable on a device without a fixture, so it stays verified by the host tests only.

## Verification for the implementation

Follow `AGENTS.md` and [README verification](../../README.md#실행과-검증).

- Host tests for the new `Shared/` file:
  - The state for a missing file, for today with a count above 0 and with 0, for an earlier day, for a future `dayStart`, for undecodable data, for another schema version and for each invalid value.
  - The day check across a daylight-saving change and after a time-zone change.
  - The entries: Numbers then Empty at the next start of day, and one entry for every other state.
- SDK tests with a seam for the writer and for the reload request:
  - `refresh()` writes after an import and after a day change, with the numbers of `SessionSummary`.
  - A failed history read writes nothing. A thrown write leaves `errorMessage` and `records` as they are, and the next `refresh()` writes again.
  - An unchanged content writes nothing and asks for no reload; the first check of a process asks once.
  - A Focus on call with no `FocusModel` writes in its last step, after a start and after a refusal, and a thrown write changes neither the result nor the stored refusal.
  - The fixture runtime never calls the writer.
    Reconciliation (2026-11-14, #124): `UITestFixtures.swift` is not in `FocusSDKTests`, so the SDK test establishes only that the default closure of `FocusServices` writes nothing; that `FocusServices.fixture` never sets it is a reading of the source.
- The view: a DEBUG screen that draws the production widget view for each state, as `--activity-preview` does for the Live Activity, with a UI test and captures in light, dark and the largest text size.
  This does not show the system's small size, the accented mode, the removed background or a reload.
  `[UNCERTAIN]` Whether a UI test can add a widget to the simulator's home screen; the plan does not depend on it.
- Compile the App, the Monitor and the extension, and build an unsigned device Release build.
- A host test reads `project.yml` and fails when the `sources` of `FocusActivity` differ from the approved list: `Widget`, the two `Activity/` files, `Shared/FocusActivityContent.swift` and the new `Shared/` file.
  Make it fail once with an added path before trusting it.
  This is the check for the control file, the lock file and the history store.
- List the frameworks that the Release `FocusActivity.appex` binary links, from the load commands of the binary: no SwiftData, FamilyControls, ManagedSettings or DeviceActivity. First confirm that the same command shows SwiftData for the app binary and the Screen Time frameworks for `FocusMonitor.appex`.
- Search every file of the Release `FocusActivity.appex` for `everyday-layer.json`, `break-selection` and `registration-marker`; all must be absent.
  First run the search for each string on the Release `FocusMonitor.appex`; a string that it does not find there is not evidence, so drop it from the search and name it in the PR.
  `SessionControl`, `control.json`, `control.lock` and `default.store` are not in this search: the probe in [Evidence](#evidence) shows that an optimized build keeps no searchable bytes for a literal that short, and a match for `SessionControl` in the Monitor can come from the type name alone.
  `[UNCERTAIN]` Whether the three longer strings are searchable in the iOS Release build; the Monitor run answers it.
- The [physical-device verification](#physical-device-verification) above. Without it, every refresh time and the midnight change stay unverified.

## Left to the builder

- The names of the snapshot type, the writer, the reader, the widget and its `kind` string.
- Whether `SessionSummary.text` and the widget format the time through one function of the new `Shared/` file.
- How the writer compares the new content with the file, and where the "first check of the process" flag is.
- An upper bound for `focusSeconds` in the valid-value rule.
- The layout, the fonts and the sample numbers of the gallery preview, within the visual approval.
- Where the test of the `FocusActivity` source list lives and how it reads `project.yml`.
