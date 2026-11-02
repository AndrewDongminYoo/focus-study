# M4: Focus filter that starts a focus session

Date: 2026-11-01.
Status: design for approval. Milestone `M4` in the GitHub project "Focus Study".
Source: operator requirements of 2026-10-31 and operator decisions of 2026-11-01.
This document changes [the 2026-10-26 design](2026-10-26-focus-study-design.md), [the M1 design](2026-10-31-m1-launch-flow-design.md), [the M2 design](2026-11-01-m2-break-pass-design.md) and [the M3 design](2026-11-01-m3-schedule-layer-design.md) only where it says so.
Where they differ, this document is the newer decision.
This PR does not edit those documents.
The implementation PR adds dated reconciliation sections to them (see [Superseded lines](#superseded-lines)).

## Intent

A focus session stops the student from opening distracting apps.
Notifications still interrupt the study time: a message preview or a game alert pulls the student back to the phone.
iOS already has a tool for this: a Focus, which filters notifications by the people and apps that the person allows.
M4 connects the two.
The student turns on one Focus, for example a Focus named "공부".
With that one action, iOS filters notifications by the Focus's own allowed people and apps, and FocusStudy starts a focus session.
The app does not decide which notification is urgent, and it does not change the Focus settings.
The settings sheet explains how to set up that Focus.

The operator noted on 2026-11-01 that the real behavior will show only during implementation, and that the internal logic of a shipped app with the same pattern is not known.
So this design marks each unverified point with `[UNCERTAIN]`, lists it under [Physical-device verification](#physical-device-verification), and gives the builder room in [Left to the builder](#left-to-the-builder).

## Roadmap context

The operator set this order: M1 launch flow and focus length (PR #46), M2 break pass and deadline (PRs #47 and #48), M3 everyday schedule blocking layer (PRs #49 and #50), M4 stricter notification handling.
This document is the M4 design.

## Goals

- A person adds the FocusStudy Focus filter to a Focus in the iOS Settings app and turns on its session option.
- When that Focus turns on, a normal focus session starts without opening the app: the personal focus length, the focus-session selection, and every M2 rule.
- iOS filters notifications during that Focus by the Focus's own settings. The app does not read or change them.
- When that Focus turns off, the session that the Focus started ends. The Focus change never ends a session that the person started by hand.
- One Focus activation starts at most one session.
- The settings sheet has a short guide for the Focus setup and shows why the last Focus start did not start a session.
- The app still opens on the focus-start screen. No new permission is requested.

## Non-goals in M4 (deliberately excluded)

- `INFocusStatusCenter` status checks, and any read of the person's Focus status outside the filter.
- A blocking choice in the filter, such as "no apps", "the focus selection" or "all apps". The session always uses the focus-session selection.
- An endless session, or a session that lasts as long as the Focus.
- A focus length chosen in the filter.
- Changes to onboarding or to the focus-start screen.
- Local notifications from the app, for example at session completion (issue #42).
- A separate App Intents extension target.
- An App Shortcut or a Siri phrase that starts a session (a later candidate).
- Changes to the everyday layer.
- Notification filtering through `FocusFilterAppContext`. The app sends no notifications, so the default app context stays.
- Protection against a person who turns the Focus off to end a session. Turning the Focus off is the person's action, like "집중 종료".

## Anti-goals (never, by operator decision)

- Rankings, leaderboards, or any comparison with other people.
- Friend presence, or any feature that sends the Focus state or the session state off the device.
- Anything that makes the first-screen line "데이터는 기기에만 저장돼요" false.
- Copy that promises which notifications come through. "Urgent" is never guessed by the app.

## Decisions by the operator

1. The session connects to iOS Focus through a Focus filter that starts a FocusStudy session when the Focus turns on. The reference is the Focus filter of a shipped Screen Time blocking app (operator screenshots, 2026-11-01): it starts a timer when the Focus turns on and stops it when the Focus turns off.
2. The setup guide is in the settings sheet only. No onboarding step, and no change to the focus-start screen. The app still opens on the focus-start screen.
3. "Urgent" is never guessed by the app. It means the system's urgent alerts plus the contacts and apps that the person chose. Three tracks:
   - Medical and disaster alerts: the app does not interfere. Each alert type is verified separately.
   - Chosen contacts: the Focus's allowed people. Do not assume that Messages and KakaoTalk behave the same.
   - Chosen apps: an allowed app lets all of its notifications through. Never describe an allowed app as "only medication reminders".
4. Copy says something like "공부 중에도 받을 연락과 알림을 설정해요", never "긴급 알림만 반드시 울려요".
5. An exception that the person sets in iOS and an exception that iOS actually applies are separate verification items.
6. The design marks what is unverified and leaves room for the builder, without hiding risk.

## Decisions by Claude (the operator can change them)

### What the filter starts

1. Focus on starts a normal focus session: the personal focus length (25 to 50 minutes, `FocusSettings`), the focus-session selection, and every M2 rule (up to 3 breaks, the deadline). No endless timer.
2. A scheduled Focus starts a session in the same way. The API does not tell the app why the Focus turned on.
3. The start conditions are the same as for the start button: access is approved, the focus selection is valid and not empty, and no session is stored. Onboarding completion is not a condition.

### One parameter

4. The filter has one parameter: a `Bool`, for example "집중 세션 시작", with the default `false`. The person turns it on when adding the filter.
   The reason: when the Focus turns off, the system calls `perform()` with the default parameter values (see [Apple documentation](#apple-documentation-checked-2026-11-01)). So the default value must mean "no session".
   A filter with the option off is the same as a Focus off for the app.
5. A blocking choice ("no apps / distracting apps / all apps") and a focus length per filter are later candidates, not M4 scope.

### Origin and end

6. Only a session that the filter started ends when the Focus turns off. Each session stores its origin: `ControlSession.origin`, `manual` or `focusFilter`. A missing value decodes as `manual`, as the M2 break fields do.
7. The end by Focus off is recorded as `.earlyExit` ("집중 종료" in history), unless time already ended the session. No new `EndReason`. The reasons:
   - The person turned the Focus off, by hand or by a schedule that the person set. That is the person's end, as "집중 종료" is.
   - `SessionRecord` and `TodayHistoryView` need no new label.
   - A new raw value of `EndReason` would make `control.json` unreadable to a build that does not know it, and the read failure path clears both stores (see [Earlier builds](#earlier-builds)).
   - The off call runs the M2 reconcile order first, so a session whose focus end has passed ends as `.expired` (or `.deadlineMissed`), not as `.earlyExit`. This is the rule of `StartupRecovery.endCurrent`: the timed end wins, else `.earlyExit`.
   - Reconciliation (2026-11-02, issue #53): the guarantee of "집중 종료", that the person's end lifts the restrictions also when the cleanup cannot save, now also holds for this end.
     When the cleanup or the reconcile of the off call throws, a filter-started session that is not `terminal` still ends (see [Filter end](#filter-end-focus-off)).
     The precedence stays: `.authorizationRevoked` without access, else the timed reason (`.expired` or `.deadlineMissed`) when the session's time is up, else `.earlyExit`.
     A stale wait whose time is up and whose wait cancel cannot save ends earlier, by the M2 registered-end rule, as `.recoveryInterrupted` (see the last item of the [Filter end](#filter-end-focus-off) reconciliation).

### Refused starts

8. No session starts when access is not approved, the focus selection is empty or invalid, or a session is stored in any phase.
   A `terminal` session that waits for the history import is imported first, in the same way as the app does it (see [Filter start](#filter-start-focus-on)). Only an import that fails refuses the start.
   Without this import, every activation after a Focus-off end would be refused: the Focus-off end leaves a `terminal` session while the app is in the background, and only `FocusModel.refresh()` imports it today.
9. A refused start records nothing in history, as a refused start button does.
   A start that fails after the save of `preparing` is not a refusal: it follows the M1 rollback and records "시작 실패", as today.
10. The settings sheet shows the last refusal reason and its time.
    This needs a stored value, because the filter usually runs in a background launch that no screen sees.
    The value is display-only and only the app process writes and reads it, so it is stored in the app's `UserDefaults` next to the focus length (`FocusSettings`), not in the App Group. A successful filter start clears it.

### One session per activation

11. If the session ends while the Focus stays on, no new session starts until the Focus turns off and on again.
    The system can call `perform()` again for the same activation, for example after a restart or a filter edit (`[UNCERTAIN]` how often). So the engine stores an activation marker: `ControlEnvelope.filterActivation`, a `UUID` that is set by the first on call of an activation and cleared by the next off call.
12. The marker is in the control envelope, not in a separate App Group value and not in the session. The reasons:
    - The start decision reads the session and the marker together under one lock, and one save writes both: the save of `preparing` writes the marker and the new session, and the save of `ending` clears the marker and ends the session.
    - It must outlive the session. `acknowledgeTerminal` removes the session from the envelope after the history import, while the Focus can still be on.
    - Every lock section saves the envelope that it decoded, in the app and in the Monitor, so every transition keeps the marker.
13. A refused on call also sets the marker. So a replayed on call cannot start a session later in the same activation, for example after a manual session ends or after access is approved.

### Where the filter runs

14. The intent type is in the main app target, not in a new App Intents extension. It is meant to run in the background without opening the app (see decision 15), and it never requests a permission. The reasons:
    - The focus-session selection is in the app's private storage (`PrivateSelection/selection.json`), not in the App Group. An extension would need a copy of the tokens in the App Group, which is a privacy boundary change.
    - The focus length is in the app's `UserDefaults`. The M1 design says that only the app reads it.
    - The history import needs the app's SwiftData store.
15. The selected SDK decides the syntax for the execution target. In the iOS 27.1 SDK, `allowedExecutionTargets` and `IntentExecutionTargets` are available from iOS 27.0 only, and `supportedModes` from iOS 26.0. CI pins Xcode 26.6 (`.github/workflows/verify.yml`), and the deployment target is iOS 17.
    So the design declares neither property. The intent type is compiled into the app target only, so the app process is the only process that can run it (Apple: "By default, an intent can be executed against any target"). `openAppWhenRun` keeps its default, but that value does not decide the runtime mode: "Code in your app bundle can run in either the foreground or background", and the location of the code, the type of the intent and the current system conditions also have an effect ([Configuring the runtime behavior of your app intents](https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents)). So the design expects that the system does not bring the app to the foreground, and this is `[UNCERTAIN]` until device steps 2 to 5 pass.
    The plan has an SDK probe step before any of this syntax is written. What the Xcode 26.6 SDK contains is inferred from the availability attributes of the 27.1 SDK, not checked.

### Interaction with M2 and M3

16. A filter-started session is a normal focus session for the everyday layer: both layers block the union of their selections, and a break lifts both. The everyday convergence runs at the end of the new lock sections, as in every section.
17. A Focus off during `waiting`, `onBreak` or `breakOver` ends the session in the same way: M2 transition 6, which removes the break artifacts, then the M3 everyday step.

### Permissions and entitlements

18. No new permission, no `INFocusStatusCenter`, and no new entitlement. If the builder finds that a Focus filter needs an entitlement or an `Info.plist` key, that is a target-configuration change (unsigned device Release build) and a privacy-boundary item: stop and raise it with the operator.

### Settings sheet guide

19. A section in the settings sheet with one short row opens a guide screen. The row label is two or three words, and the explanation goes in the footer and in the guide (operator preference for short labels).
20. The guide has text instructions only. No button opens the Focus settings: the only public URL, `UIApplication.openSettingsURLString`, opens the app's own settings page, which has no Focus settings. No private URL scheme is used.

## Constraints

- iOS 17 or later, SwiftUI, Observation, SwiftData, iPhone only, portrait only.
- Keep the architecture in `AGENTS.md`. `Shared/` must not import Screen Time SDK modules or `AppIntents`. Only the intent file imports `AppIntents`.
- No new product target. The app, Monitor and Report targets stay as they are.
- Keep the process-lock contract of the 2026-10-26 design: every state change reads the stored state again inside the `flock` section, makes the system changes, and writes JSON with an atomic replace. No `await`, no SwiftData call and no UI wait inside the lock.
- Keep the M1, M2 and M3 rules. This document adds an optional session field, an envelope field and three lock sections, and changes nothing else in the existing transitions. In the app model, only the completion card rules of [Foreground refresh](#foreground-refresh) change.
- Keep the accessibility identifiers that `UITests/FocusFlowTests.swift` uses.
- Simulator results do not prove real Screen Time or Focus behavior.

## Apple documentation (checked 2026-11-01)

The JSON endpoint `https://developer.apple.com/tutorials/data/documentation/<path>.json` was read for each developer page.
The iOS 27.1 SDK `AppIntents.swiftinterface` was also checked.

| Fact                                                                                                                                                                                                                                                                                                   | Source                                                                                                                                                                                                                                                                                                                                   |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| The person creates a filter in "Settings > Focus > Do Not Disturb (or another Focus) > Add Filter > Example Chat App". When the Focus turns on, "The system calls the perform function of the object conforming to `SetFocusFilterIntent`, and all @Parameters are available in the Focus filter."     | [Defining your app's Focus filter](https://developer.apple.com/documentation/appintents/defining-your-app-s-focus-filter)                                                                                                                                                                                                                |
| "When you turn off the modified Focus, the system provides the sample app's `SetFocusFilterIntent` conforming object with the following default parameters", and the sample's `Bool` parameter has `default: false`.                                                                                   | Same page                                                                                                                                                                                                                                                                                                                                |
| The sample "adds an App Intents extension to handle Focus filters while the app is in the background", and "uses App Groups, or custom services, to share filter data between the extension and the app."                                                                                              | Same page                                                                                                                                                                                                                                                                                                                                |
| `appContext` gives a `FocusFilterAppContext` with a notification filter predicate. The sample uses it to suppress the app's own notifications.                                                                                                                                                         | Same page, [`FocusFilterAppContext`](https://developer.apple.com/documentation/appintents/focusfilterappcontext)                                                                                                                                                                                                                         |
| `SetFocusFilterIntent` is available from iOS 16.0. Its topics are `current`, `suggestedFocusFilters(for:)`, `appContext` and `invalidateFocusFilterAppContext()`.                                                                                                                                      | [`SetFocusFilterIntent`](https://developer.apple.com/documentation/appintents/setfocusfilterintent)                                                                                                                                                                                                                                      |
| `current` is declared as `static var current: Self { get async throws }`. The page has no discussion.                                                                                                                                                                                                  | [`current`](https://developer.apple.com/documentation/appintents/setfocusfilterintent/current)                                                                                                                                                                                                                                           |
| `suggestedFocusFilters(for:)`: with an empty result, "The system will use the default value per parameters in this case."                                                                                                                                                                              | [`suggestedFocusFilters(for:)`](<https://developer.apple.com/documentation/appintents/setfocusfilterintent/suggestedfocusfilters(for:)>)                                                                                                                                                                                                 |
| `SetFocusFilterIntentError` has the cases `notFound` and (iOS 16.4) `missingParameterValue`. No page text explains them.                                                                                                                                                                               | iOS 27.1 SDK `AppIntents.swiftinterface`                                                                                                                                                                                                                                                                                                 |
| "Before calling this method, the system resolves your app intent's parameters to known values."                                                                                                                                                                                                        | [`perform()`](<https://developer.apple.com/documentation/appintents/appintent/perform()>)                                                                                                                                                                                                                                                |
| `openAppWhenRun` "is deprecated. Use `supportedModes` instead." `supportedModes` is available from iOS 26.0.                                                                                                                                                                                           | [`openAppWhenRun`](https://developer.apple.com/documentation/appintents/appintent/openappwhenrun), [`supportedModes`](https://developer.apple.com/documentation/appintents/appintent/supportedmodes)                                                                                                                                     |
| `allowedExecutionTargets`: "By default, an intent can be executed against any target." It and `IntentExecutionTargets` are available from iOS 27.0 (page metadata, and `@available(anyAppleOS 27.0, *)` in the iOS 27.1 SDK interface).                                                                | [`allowedExecutionTargets`](https://developer.apple.com/documentation/appintents/appintent/allowedexecutiontargets), [`IntentExecutionTargets`](https://developer.apple.com/documentation/appintents/intentexecutiontargets)                                                                                                             |
| The `ManagedSettingsStore` topic groups are account, cellular, date and time, passcode, shield, Siri, App Store, application, Game Center, media, Safari and web content. None is about notifications.                                                                                                 | [`ManagedSettingsStore`](https://developer.apple.com/documentation/managedsettings/managedsettingsstore)                                                                                                                                                                                                                                 |
| `INFocusStatusCenter` has `requestAuthorization(completionHandler:)`. `NSFocusStatusUsageDescription`: "Add this key before you use `INFocusStatusCenter`". `INFocusStatus`: "Use this information to display that the user is in a focus to other people in your communication service."              | [`INFocusStatusCenter`](https://developer.apple.com/documentation/intents/infocusstatuscenter), [`NSFocusStatusUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsfocusstatususagedescription), [`INFocusStatus`](https://developer.apple.com/documentation/intents/infocusstatus) |
| `timeSensitive`: notifications that "can break through system controls such as Notification Summary and Focus. The user can turn off the ability for time sensitive notification interruptions."                                                                                                       | [`UNNotificationInterruptionLevel.timeSensitive`](https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive)                                                                                                                                                                             |
| `critical`: "This interruption level requires an approved entitlement. The system always presents this notification, even when Do Not Disturb is active."                                                                                                                                              | [`UNNotificationInterruptionLevel.critical`](https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/critical)                                                                                                                                                                                       |
| A Focus can allow specific people, "allow repeated calls (two or more calls from the same person within 3 minutes)", allow specific apps, and turn on Time Sensitive Notifications, "which allows all apps to send time-sensitive notifications immediately". Emergency Bypass lets a contact through. | [Allow or silence notifications for a Focus on iPhone](https://support.apple.com/guide/iphone/allow-or-silence-notifications-for-a-focus-iph21d43af5b/ios) (iOS 27 page)                                                                                                                                                                 |
| "When Intelligent Breakthrough & Silencing is on, Apple Intelligence allows important notifications to interrupt you and silences notifications determined not to be important."                                                                                                                       | Same support page                                                                                                                                                                                                                                                                                                                        |

Conclusions for this design:

- The checked public APIs have no way to turn on a Focus or to change its allowed list. The Focus settings stay with the person and with iOS.
- An allowed app lets every notification of that app through, and a Focus with Time Sensitive Notifications on lets an app through only for the notifications that the app marks so. This supports the copy rule in [Decisions by the operator](#decisions-by-the-operator).
- A Focus can let more through than the allowed list (Time Sensitive, repeated calls, Emergency Bypass, Intelligent Breakthrough). So the copy never promises that nothing else comes through.
- The design does not depend on how a shipped app with a similar filter works. Its behavior shows only that the pattern exists.

Not documented, so these stay `[UNCERTAIN]` until a device check:

1. Whether the notifications of a shielded app still appear. No checked document answers this. The design holds either way: the session restricts opening the app, and the Focus decides the notifications.
2. Whether `perform()` runs reliably in the background in the main app process, on Focus on and on Focus off. How late it can arrive. Whether it repeats for one activation, and in which order the on and off calls arrive when the Focus turns off and on quickly.
3. Whether `DeviceActivityCenter` registration and `ManagedSettingsStore` writes succeed from a background `perform()`.
4. Allowed people for Messages versus KakaoTalk, allowed apps, repeated calls, and emergency and government alerts per type.
5. Whether a filter with one `Bool` parameter is shown and configurable in Settings as this design expects.
6. What `current` returns, or which error it throws, while the Focus is off.
7. Which values the system sends when the person switches directly from one Focus to another, with or without this filter.
8. Whether `perform()` can run before the first unlock after a restart, when the App Group files and the private selection file are not readable.

## Design

### Stored values

M4 adds two values to `control.json`, and two values to the app's `UserDefaults`.

| Value              | Where                                | Type             | Meaning                                                                                                 |
| ------------------ | ------------------------------------ | ---------------- | ------------------------------------------------------------------------------------------------------- |
| `origin`           | `ControlSession` in `control.json`   | `SessionOrigin?` | `manual` or `focusFilter`. Missing = `manual`. Set once in the save of `preparing` and never changed.   |
| `filterActivation` | `ControlEnvelope` in `control.json`  | `UUID?`          | The current Focus activation that the filter path has seen. Missing = no activation since the last off. |
| Last refusal       | App `UserDefaults` (`FocusSettings`) | reason and time  | Display-only. Reasons: `access`, `selection`, `busy`, `history`, `error`.                               |
| Pending card       | App `UserDefaults` (`FocusSettings`) | id and length    | Display-only. The completion card of an `.expired` session that the filter path imported.               |

- `ControlEnvelope.schemaVersion` stays `2`. Both new fields are optional, so a version 1 or 2 file of an earlier build decodes without them.
- The storage checks of M1 and M2 do not change. Any `origin` value is valid in any phase, and any marker value is valid with any session.
- `Shared/` defines `SessionOrigin`, the refusal reasons and the result of the start section. It does not import `AppIntents`.
- Data boundary: the marker tells only that a Focus with this app's filter turned on. It does not name the Focus. It stays on the device. The Monitor decodes it and saves it back unchanged, and never uses it. The Report extension still has no App Group access. This is not a change to the token boundary of M2 and M3.

### Side artifacts

M4 adds no side artifact: no monitoring activity, no named store and no file.
The two new values are inside `control.json`, so the M2 [break artifacts](2026-11-01-m2-break-pass-design.md#break-artifacts) table and the M3 [stored states and side artifacts](2026-11-01-m3-schedule-layer-design.md#stored-states-and-side-artifacts) tables apply unchanged to every stored phase, for both origins.
The last refusal is not a side artifact. Nothing removes it except the next filter start or refusal.
The pending card is not a side artifact either. The next `FocusModel.refresh()` removes it ([Foreground refresh](#foreground-refresh)).

### The filter intent

- One type in the app target that conforms to `SetFocusFilterIntent`, with one parameter `startsSession: Bool`, default `false`.
- `perform()` passes the value to the filter handler in `App/` and returns. The handler does the work, so tests can call it without the system.
- `appContext` keeps the default value. `suggestedFocusFilters(for:)` is not implemented, so the system uses the default value (`false`).
- No permission request, no `INFocusStatusCenter`, and no foreground transition.

### Calls and decisions

| Stored marker | Stored session                 | On call (`startsSession == true`)                                   | Off call (`false`)                                                                    |
| ------------- | ------------------------------ | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| none          | none                           | Set the marker. Start a session, or refuse for access or selection. | Reconcile only. No save if nothing changed.                                           |
| none          | `manual`, not `terminal`       | Set the marker. Refuse with `busy`.                                 | Reconcile only. The Focus-off rule does not apply to a manual session.                |
| none          | `focusFilter`, not `terminal`  | Set the marker. Refuse with `busy`.                                 | Reconcile, then end the session as `.earlyExit` if time did not end it.               |
| none          | `terminal` (the import failed) | Set the marker. Refuse with `history`.                              | Reconcile only.                                                                       |
| set           | any                            | Repeated call. Only the M2 cleanup of the section can save.         | Clear the marker. Reconcile, then end a `focusFilter` session that is not `terminal`. |

- "Reconcile" is the M2 reconcile order with the access value of the call, as an app reconcile does. A session whose time is up ends with its timed reason, and an `ending` session finishes.
- So an off call can end a manual session, but only for the reasons that any app reconcile has: access not approved, a timed end, a stored `preparing`, an `ending` to finish, or a focus activity that is not registered. The Focus-off rule itself never ends a manual session.
- The row "none, `focusFilter`" exists only after the [activation check](#activation-check-app-launch-and-foreground) cleared a marker, or after a process exit described in [Gaps between steps](#gaps-between-steps).
- The on call imports a pending `terminal` session before the lock section (see below), so the row "none, `terminal`" normally does not occur.

### Transitions

Each lock section below is one `withExclusiveAccess` section on `SessionControl`, on the existing `control.lock`.
Each one reads the envelope again, runs the M2 cleanup, and ends with the M3 everyday convergence, as every lock section does.
A lock timeout is retried up to 4 times with a fresh time, 250 ms apart, as `handleCallbackRetryingLock` does for the Monitor, because each filter call is the only trigger of its change.
The pause is outside the lock. In the async `perform()` it is a `Task.sleep`.

#### Filter start (Focus on)

The handler runs these steps in the app process:

1. **Inputs.** Refresh the authorization status. Read the focus length from `FocusSettings` and the focus selection from the selection repository, and check the selection with `SelectionValidator` and "at least one app or website". This gives `selectionReady` and the frozen selection.
2. **History.** Run the first part of `FocusModel.refresh()`: `reconcile`, `snapshot`, and, if the stored session is `terminal`, `SessionHistory.importTerminal`. The import saves the record in SwiftData and then calls `acknowledgeTerminal`, which is its own lock section. After the import of an `.expired` session, store the pending card ([Foreground refresh](#foreground-refresh)). A failure here does not stop step 3. The start section then refuses with `history` if a `terminal` session is still stored.
3. **Start section** (`startFromFocusFilter`):
   1. Read the envelope and run the M2 cleanup.
   2. If `filterActivation` is set: return "repeated". The section makes no change of its own. Only the cleanup of step 3.1 can register a focus activity or save, and only for a stale `waiting` session with a break copy (M2 transition 2 or the stored end). The everyday convergence at the end of the section runs as in every lock section.
   3. Set `filterActivation` to a new `UUID` in memory.
   4. Read the access value inside the lock, as `start` does. If access is not approved: refusal `access`.
   5. If `selectionReady` is `false`: refusal `selection`.
   6. If a session is stored: refusal `history` for `terminal`, `busy` for any other phase.
   7. For a refusal: save the envelope with the marker, and return the refusal.
   8. Otherwise run the M1 start steps with `origin = focusFilter`: save `preparing` (the same save writes the marker), register, verify, apply, verify, save `active`. A failure follows the M1 rollback: clear `focusSession`, stop the activity, save `terminal` with `.startFailed`. The rollback keeps the marker, so the activation is used.
4. **Record.** Store the refusal reason and its time, or clear the stored refusal after a start. A thrown error is stored as `error`.
5. **Refresh.** Tell the app's model to refresh (see [Foreground refresh](#foreground-refresh)).

#### Filter end (Focus off)

The handler runs one lock section (`endFromFocusFilter`), then step 5 of the start:

1. Read the envelope and run the M2 cleanup.
2. Clear `filterActivation` in memory. Every later save of this section writes the cleared marker.
3. Run the M2 reconcile order with the access value of the call.
4. If the stored session is still not `terminal` and its origin is `focusFilter`: end it with M2 transition 6 and `.earlyExit`. The save of `ending` writes the cleared marker. The M3 everyday step of transition 6 runs as usual.
5. If the stored envelope still has a marker after steps 3 and 4: save the envelope without it.

Reconciliation (2026-11-02, issue #53): a thrown error in step 1 or step 3 no longer stops the section before step 4 when the session in memory is a filter-started session that is not `terminal`.

- Step 2 clears the marker in memory also after a step 1 error, and step 3 does not run after a step 1 error.
- Step 4 ends the session with M2 transition 6 and this reason: `.authorizationRevoked` without access, else the session's timed end (`timedEnd`) when it is not nil, else `.earlyExit`.
- When that end completes, the section does not throw, as `finish()` drops the cleanup error when it ends the session.
  When the end itself throws, its error propagates.
- An `end` inside step 1 or step 3 sets `terminal` in memory before its last save, so its error never causes a second end, and it propagates as before.
- After a failed save of `breakOver`, the session in memory is still `onBreak` with the focus shield restored; transition 6 clears that shield, stops the focus and break activities and removes the break copy.
- A manual session, or a section without a filter-started session, keeps the earlier behavior: the error of step 1 or step 3 propagates.
- With the M2 transitions of this design, a caught error leaves only a `waiting` session (a failed wait cancel) or an `onBreak` session (a failed save of `breakOver`).
  The M2 registered-end rule and the re-block check the timed end first, so the reason in these cases is `.authorizationRevoked` or `.earlyExit`; the timed branch keeps the precedence for any later transition.
- One caught-error path records neither the timed reason nor `.earlyExit`: a stale wait whose time is up and whose wait cancel cannot save.
  The M2 registered-end rule inside the cleanup ends it as `.recoveryInterrupted` and releases the restrictions, its error propagates, and the activation check clears the marker, as for any caller of the cleanup.

A `terminal` session that this section leaves is imported by the next app refresh or by the next filter start, step 2.

#### Activation check (app launch and foreground)

The off call is one-shot. If it is lost, the marker stays set, and the next activation is treated as a repeated call.
The app repairs that when it opens:

1. Read the marker with `snapshot()`. If no marker is set, stop.
2. Outside any lock, read `current` of the filter type (`get async throws`).
3. If it gives `startsSession == false`, or throws `SetFocusFilterIntentError.notFound`: run the lock section `clearFilterActivation(matching:)` with the marker from step 1. It clears the marker only if the stored marker is still that value, and saves. It never starts or ends a session.
4. Any other result or error changes nothing.

The check runs on app launch and on each `UIApplication.didBecomeActiveNotification`, after the existing refresh.
The compare in step 3 keeps the check from clearing a newer activation: an off call and an on call between steps 1 and 3 store a different marker.

Direction of each error:

- A marker that is cleared while the Focus is on lets a repeated on call start a second session in that activation. That is the stricter direction.
- A marker that stays set after the Focus turned off skips the session of the next activation. That is the looser direction, so step 3 also clears on `notFound`.
- What `current` gives while the Focus is off is `[UNCERTAIN]` (see [Apple documentation](#apple-documentation-checked-2026-11-01)). Device step 13 records it.

#### Foreground refresh

The filter runs in the app process.
If the app's model exists, the handler tells it to refresh on the main actor after each filter call that changed the stored state, so a screen in the foreground shows the new session or its end.
The refresh is the existing `FocusModel.refresh()`. It imports a `terminal` session, as today.
If the app's screens were never loaded, for example in a background launch, nothing refreshes, and the next launch or foreground does.

The completion card (`completedSessionID` and `completedLength`) gets two rules, because a session can now start without `FocusModel.start()`, which is the only place that clears the card today:

1. The card belongs to an idle screen. `refresh()` clears it when, after its import, a session is stored and its phase is not `terminal`. No stored session (for example after the import of an `.expired` session, which `acknowledgeTerminal` removes) keeps the card. So a filter-started session never sits under a card that the person has not closed, which would hide the countdown, the break controls and "집중 종료". This changes nothing for a manual start, because `start()` clears the card before the session exists.
2. When the handler's own import (filter start, step 2) imports an `.expired` session of either origin, the handler stores its id and length as a pending card in the app's `UserDefaults` (`FocusSettings`), next to the last refusal. The next `refresh()`, in this process or after a later launch, takes the pending card and clears it before its own import. It sets the card from the pending card only if no session that is not `terminal` is stored. Then its own import of an `.expired` session sets the card, as today, and so overrides the pending card: the newer session wins. So the card of a manual session that ended by time is not lost when the filter path imports it first.

The pending card holds only an id and a length, and no token. If the process exits between the import and the store of the pending card, the card is not shown, and the history row stays.

#### One runtime per process

The filter and the app's screens use one engine, one selection repository and one `ModelContainer` in each process.
Two `ModelContainer` instances on the same store in one process could each import the same `terminal` session.
`FocusBootstrap` and the handler get the runtime from the same place. The builder chooses the mechanism.
In DEBUG fixture mode (`--ui-testing`), that place gives the fixture runtime, as `FocusBootstrap` does today.

### One-shot calls and their recovery

| Call                          | One-shot?                                       | If it is lost or fails                                                                                                                                                                                     | Direction |
| ----------------------------- | ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| On call                       | Yes for the app; the system may repeat it       | No session in this activation. A repeated on call before any save tries again. The person can start a session by hand; that session is `manual`, so the Focus off does not end it.                         | looser    |
| Off call                      | Yes                                             | The filter-started session runs to its own timed end (focus end or deadline, at most the M2 deadline after the start), or until the person ends it. The marker stays until the activation check clears it. | stricter  |
| Lock timeout in either call   | Retried 4 times                                 | After the retries, as a lost call.                                                                                                                                                                         | as above  |
| History import in the on call | Retried with the same rule for the lock timeout | Refusal `history`, shown in the settings sheet.                                                                                                                                                            | looser    |
| Activation check              | Runs on every launch and foreground             | Nothing to recover. The next launch or foreground runs it again.                                                                                                                                           | -         |

Reconciliation (2026-11-02, issue #53), row "Off call": an off call whose cleanup or reconcile throws no longer keeps a filter-started session, because the section still ends it (see [Filter end](#filter-end-focus-off)).
The row still holds for a lost call, for a lock timeout after the retries, and for a process exit before the section's first save.

Residual risk: if the off call is lost and the person does not open the app before the next activation, that activation starts no session.
The design accepts this.
The guide tells the person what to expect, and the settings sheet does not show a refusal for a repeated call.

### Gaps between steps

For each gap: a thrown error at a step gives the state of a process exit after the step before it, or the rollback that the transition states.
"Next section" means the next lock section in any process.
The focus restrictions follow the M1 start rules and the M2 [break artifacts](2026-11-01-m2-break-pass-design.md#break-artifacts) gap table, and the everyday store follows the M3 [gap table](2026-11-01-m3-schedule-layer-design.md#gaps-between-steps), in every row.

| Gap                                                                           | Stored phase               | Marker                  | Registered focus activity and shield | Repair and direction                                                                                                                                           |
| ----------------------------------------------------------------------------- | -------------------------- | ----------------------- | ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Start, exit or throw in steps 1 and 2 (inputs, history)                       | as before                  | as before               | as before                            | Nothing changed by the filter. After a SwiftData save without its acknowledgement, the next import finds the record and acknowledges it, as today.             |
| Start section, exit or throw before the save in step 3.7 or 3.8               | as before                  | as before (none)        | as before                            | The activation is not used. A repeated on call tries again. Otherwise no session in this activation (looser, the same as having no filter).                    |
| Start section, refusal saved, exit before step 4                              | as before                  | set                     | as before                            | The refusal is not shown. Nothing else to repair.                                                                                                              |
| Start section, exit after the save of `preparing`, up to the save of `active` | `preparing`, `focusFilter` | set                     | maybe registered, maybe applied      | The next reconcile ends `preparing` as `.recoveryInterrupted` (M1). History shows "중단된 세션 정리". The marker stays, so no second start in this activation. |
| Start section, a start step throws                                            | `terminal` `.startFailed`  | set                     | cleared and stopped by the rollback  | History shows "시작 실패". The handler stores `error`.                                                                                                         |
| Start section, the rollback save fails                                        | `preparing`                | set                     | cleared and stopped                  | The next reconcile ends `preparing` (M1).                                                                                                                      |
| Start section, exit after the save of `active`, before steps 4 and 5          | `active`, `focusFilter`    | set                     | registered and applied               | Nothing to repair. The app shows the session at its next refresh.                                                                                              |
| End section, exit or throw before any save                                    | as before                  | set                     | as before                            | As a lost off call: the session runs to its timed end, and the activation check clears the marker.                                                             |
| End section, reconcile (step 3) ends the session                              | `ending`, then `terminal`  | cleared with `ending`   | as M2 transition 6                   | As M2. The session ends with its timed or reconcile reason.                                                                                                    |
| End section, exit after the save of `ending`                                  | `ending`                   | cleared                 | as M2 transition 6 at that step      | The next reconcile finishes the end (M2 reconcile step 1).                                                                                                     |
| End section, the save of `ending` fails, the save of `terminal` succeeds      | `terminal` `.earlyExit`    | cleared with `terminal` | cleared and stopped                  | Nothing to repair.                                                                                                                                             |
| End section, the saves of both `ending` and `terminal` fail                   | earlier phase              | set                     | cleared and stopped                  | M2 reconcile step 5 ends the session as `.recoveryInterrupted` later. The activation check clears the marker.                                                  |
| End section, the marker-only save (step 5) fails                              | as before                  | set                     | as before                            | The activation check clears the marker.                                                                                                                        |
| Activation check, exit between steps 1 and 3, or a throw in step 3            | as before                  | as before               | as before                            | The next launch or foreground checks again.                                                                                                                    |

Reconciliation (2026-11-02, issue #53), for the end section:

- Row "End section, exit or throw before any save": a thrown error in the cleanup or the reconcile now ends a filter-started session as the [Filter end](#filter-end-focus-off) reconciliation states, and the saves of `ending` and `terminal` write the cleared marker.
  A process exit before the section's first save stays as a lost off call.
  A manual session keeps the row as written.
- Row "End section, the saves of both `ending` and `terminal` fail": the outcome does not change, and it applies also to the end after a caught error.
- A gap that the table did not list: a process exit after a save of the cleanup or the reconcile that does not end the session, for example a wait cancel or the save of `breakOver`.
  The stored phase is that phase, the focus activity stays registered, and the marker is as before after a cleanup save and cleared after a reconcile save (the row "none, `focusFilter`" of [Calls and decisions](#calls-and-decisions)).
  The session runs to its timed end, as after a lost off call, or until the person ends it.

### Guards across sequences of calls

Two guards compare a call with stored state: the marker ("one session per activation") and the origin ("only a filter-started session ends on Focus off").
Each must hold after a sequence of accepted calls, not only after one.

| Sequence                                                                                                | Result                                                                                                                          |
| ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| On, session S1 starts, S1 completes by time, the history import removes S1, a repeated on call          | The marker is set, so the repeated call starts nothing.                                                                         |
| The same, then off, then on                                                                             | The off call clears the marker. The next on call starts S2.                                                                     |
| A manual session M runs, on, off                                                                        | On refuses with `busy` and sets the marker. Off clears the marker. The Focus-off rule does not end M, because M is `manual`.    |
| On, S1 starts, the person ends S1 with "집중 종료", the person starts manual M, a repeated on call, off | The repeated call starts nothing. The Focus-off rule does not end M.                                                            |
| On, refused for access, the person approves access, a repeated on call                                  | Nothing starts until the next activation. The settings sheet shows the refusal.                                                 |
| On, S1 starts, the off call is lost, S1 ends by time, the app opens, the next on                        | The activation check clears the marker if `current` says off. The next on call starts S2.                                       |
| The same without opening the app                                                                        | The next on call is treated as repeated, and no session starts (residual risk above).                                           |
| On, S1 starts, the app opens while the Focus stays on                                                   | `current` gives `true`, and nothing changes.                                                                                    |
| On, S1 starts, S1 is in `waiting`, `onBreak` or `breakOver`, off                                        | S1 ends as `.earlyExit` with M2 transition 6, which removes the break artifacts.                                                |
| On, S1 starts, S1's focus end passes before the Monitor callback, off                                   | The reconcile order ends S1 as `.expired` first. The end by Focus off does not apply.                                           |
| Focus A (option on), S1 starts, the person switches to Focus B with this filter and the option off      | If the system sends `false` for B, S1 ends. `[UNCERTAIN]` (unverified item 7).                                                  |
| Focus A (option on), S1 starts, the person switches to Focus B with the option on                       | If the system sends only `true`, the call is repeated and S1 continues. If it sends `false` then `true`, S1 ends and S2 starts. |
| The off call of one activation arrives after the on call of the next one                                | The off call ends S2 and clears the marker while the Focus is on. No session until the next activation (looser). `[UNCERTAIN]`  |

A replayed on call cannot start a second session, because the marker changes only by an off call or by the compare-and-clear of the activation check.
The Focus-off rule cannot end a manual session, because the origin is set once in the save of `preparing` and never changes.
An off call ends a manual session only through the M2 reconcile order, for the same reasons as any app reconcile (see [Calls and decisions](#calls-and-decisions)).
The rows above assume that access stays approved and that no timed end is due, unless the row says otherwise.

### Process lock and recovery contract

- The three new sections use the same `control.lock`, the same 0.25-second timeout and the same atomic JSON replace. Lock order: no filter step holds the lock across another lock section. The history import and `current` run outside the lock.
- The Monitor needs no change. It compiles `Shared/`, so it decodes and saves both new fields.
- A failed read of `control.json` in a filter section follows the existing read failure path (M2, with the M3 addition): it clears both stores and stops the focus and break activities. A start is then not possible. The handler stores `error`.
- `StartupRecovery` is unchanged. `endCurrent` ends a session of either origin.
- An app in the foreground refreshes its state after a filter start or end ([Foreground refresh](#foreground-refresh)).

### Earlier builds

- An M3 or earlier build's data loads unchanged in M4: `origin` is missing, so every stored session is `manual`, and no marker is set.
- A downgrade to M3 is not supported. An M3 build ignores both keys when it decodes, and its next save drops them. A filter-started session then counts as `manual`. An M3 build has no filter type, so a filter that the person added in Settings does nothing (`[UNCERTAIN]` what Settings shows then).

### Status in the settings sheet

- A section with one row opens the guide. The row shows nothing about the Focus state, because the app does not read it.
- The guide shows the last refusal, with its time, when one is stored. A repeated call is not a refusal and shows nothing.

### Settings guide content

This is the content, not the final copy.
The implementation PR writes the Korean copy with the `user-facing-copy` skill, in 해요체, with short labels.

1. What it does: turning on a chosen Focus starts a focus session with the person's focus length and selection, and iOS applies the notification settings of that Focus.
   A Focus can let more through than its allowed people and apps: Time Sensitive notifications and repeated calls when the Focus allows them, a contact with Emergency Bypass, and Intelligent Breakthrough when it is on (see [Apple documentation](#apple-documentation-checked-2026-11-01)).
2. Make a Focus for study in Settings > Focus, for example "공부".
3. In that Focus, choose the allowed people, the allowed apps, and whether repeated calls come through.
4. Add the filter: in that Focus, Add Filter > FocusStudy, and turn on the session option.
5. What to expect:
   - One session for each time the Focus turns on. If the session ends while the Focus stays on, the next session starts the next time the Focus turns on.
   - Turning the Focus off ends a session that the Focus started. It does not end a session started with the start button.
   - A scheduled Focus works the same way.
6. Allowed apps let all of their notifications through.
7. Emergency alerts: the app does not change them. They follow iOS settings.
8. The last refusal, when one is stored, with what to do (approve access, choose apps, end the running session, open the app).

Forbidden promises:

- "긴급 알림만 반드시 울려요", or any claim that only urgent notifications come through.
- That an allowed app sends only some of its notifications, for example "only medication reminders".
- That messages from allowed people come through in every messenger. Messages and KakaoTalk are separate verification items.
- That the app silences, reads or changes notifications or the Focus settings.
- That nothing else comes through. Item 1 names what else can come through.
- A button or link that implies it opens the Focus settings.

## Superseded lines

The implementation PR adds dated reconciliation sections (it does not rewrite the original lines) for these:

- 2026-10-26 design, data boundary: "App Group에는 `ControlEnvelope.schemaVersion`과 선택적인 `session`을 저장한다." (the envelope also stores the activation marker) and "세션에는 UUID, 시작/만료 시각, 단계(`preparing/active/ending/terminal`), 종료 사유·관측 시각을 둔다." (a session also stores its origin).
- 2026-10-26 design, "세션 상태와 원자성", step 5: "종료는 ID 일치 확인 후": the Focus-off end selects the stored session by its origin under the lock, not by an ID that the caller holds.
- M2 design, [Session fields](2026-11-01-m2-break-pass-design.md#session-fields): the table gets `origin`, and the envelope gets `filterActivation`.
- `AGENTS.md` project scope: the words "designed for M4 and not built yet" in the Focus filter sentence, which this PR adds.
- `AGENTS.md` ownership table, for the intent, the handler and the guide screen.

## Physical-device verification

Blocked until issues #8, #9 and #10 are resolved (development team, identifiers and entitlements, signed install on an approved device).
Record every result in the [device matrix](../notes/screen-time-device-matrix.md), with device, OS version, the time of the Focus change and the observed time.
Do not apply real restrictions without the operator's explicit approval for that run.
Do not try to trigger an emergency or government alert, and do not use Emergency SOS for a test.

Steps:

1. Open Settings > Focus > (a test Focus) > Add Filter. Record whether FocusStudy is listed, and whether its filter has one switch that is off by default (unverified item 5).
2. Turn the switch on. Force-quit the app. Turn the Focus on from Control Center. Record whether a session starts, when, whether the app comes to the foreground, and whether the shield appears (unverified items 2 and 3).
3. Repeat step 2 with the device locked, and with a Focus schedule that starts while the device is locked.
4. Turn the Focus off. Record when the shield disappears, and the history row ("집중 종료").
5. While the Focus stays on, end the session with "집중 종료", then edit the filter and restart the device. Record each `perform()` call (DEBUG call log) and that no second session starts.
6. Start a session with the start button, then turn the Focus on and off. Record that the session keeps running, and the refusal `busy` in the settings sheet.
7. Shield an app and allow it in the Focus. Send it a notification. Repeat with the app not allowed. Record whether each notification appears (unverified item 1).
8. Allowed people: with a contact allowed and one not allowed, record calls and messages in Messages and in KakaoTalk from each. Record a repeated call (two calls within 3 minutes) from the contact that is not allowed (unverified item 4).
9. Allowed apps: record that an allowed app shows its notifications. Record, with Time Sensitive Notifications on and off, an app that sends a time-sensitive notification.
10. Emergency: record only what is safe to set up. Turn on Emergency Bypass for a test contact and call from that contact. Record the device's emergency alert settings without changing them. Record any real alert that arrives during the test period, with its type. Mark every other alert type unverified.
11. Revoke Screen Time access, then turn the Focus on. Record the refusal `access` in the settings sheet.
12. Switch directly from a Focus with the option on to another Focus with and without the filter. Turn a Focus off and on again within a few seconds. Record the order of the calls and the final state (unverified items 2 and 7).
13. With the DEBUG diagnostics, read `current` with the Focus off and with it on. Record the value or the error (unverified item 6).
14. Restart the device with a Focus schedule that starts before the first unlock. Record whether `perform()` runs and the stored refusal (unverified item 8).

Unverified until those steps run:

- Whether the notifications of a shielded app still appear `[UNCERTAIN]` (step 7).
- Whether `perform()` runs in the background in the main app process on Focus on and off, how late it arrives, whether it repeats for one activation, and the order of quick on and off calls `[UNCERTAIN]` (steps 2 to 5 and 12).
- Whether `DeviceActivityCenter` registration and `ManagedSettingsStore` writes succeed from a background `perform()` `[UNCERTAIN]` (steps 2 and 3).
- Allowed people in Messages and KakaoTalk, allowed apps, repeated calls, Time Sensitive notifications, and emergency and government alerts per type `[UNCERTAIN]` (steps 8 to 10).
- Whether a filter with one `Bool` parameter is listed and configurable in Settings, off by default `[UNCERTAIN]` (step 1).
- What `current` returns or throws while the Focus is off `[UNCERTAIN]` (step 13).
- Which values the system sends at a direct switch between two Focuses `[UNCERTAIN]` (step 12).
- Whether `perform()` runs before the first unlock after a restart `[UNCERTAIN]` (step 14).
- The iOS 17 runtime.

## Verification

Follow `AGENTS.md` and [README verification](../../README.md#실행과-검증).

- `Shared/` changes: run `swift test` and the separate-process race check. Extend the race helper with a Focus-off call that must not end a manual session that another process starts.
- `App/` changes: run the SDK tests for the filter handler and the UI tests for the settings guide with a DEBUG fixture that never touches real restrictions or a real Focus.
- The intent type: compile it with the Xcode that CI pins, and check that the built app contains the App Intents metadata.
- Target configuration: run the unsigned device Release build.

## Left to the builder

- The filter's title, description, parameter title and display representation, written with the `user-facing-copy` skill.
- The layout of the guide screen and the section and row labels.
- The mechanism that gives the app's screens and the filter one runtime per process (for example `AppDependencyManager` or one shared holder).
- Whether the result of the SDK probe needs `supportedModes` on iOS 26 and later, with an availability check, to keep the app in the background.
- The shape of the DEBUG call log for device steps 5 and 12 (time, value and result of each call; no tokens). DEBUG builds only.
