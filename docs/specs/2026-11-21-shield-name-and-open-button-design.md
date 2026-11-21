# Shield name and open button

Date: 2026-11-21.
Status: proposed in [issue #198](https://github.com/AndrewDongminYoo/focus-study/issues/198) and approved on 2026-11-21 in [PR #199](https://github.com/AndrewDongminYoo/focus-study/pull/199), with "온:공 열기" as the primary button; implemented under [issue #200](https://github.com/AndrewDongminYoo/focus-study/issues/200) as the `FocusShieldAction` extension in `ShieldAction/` and per-call configurations in `Shield/`, and run on a device on 2026-11-21 ([device matrix](../notes/screen-time-device-matrix.md)); the clipped primary label at the largest accessibility text size with Display Zoom is the known issue [#201](https://github.com/AndrewDongminYoo/focus-study/issues/201).
Source: the choices of 2026-11-21 in this conversation and issue #198, and the device spike of [issue #197](https://github.com/AndrewDongminYoo/focus-study/issues/197) recorded in the [device matrix](../notes/screen-time-device-matrix.md).
This document amends the [custom shield design](2026-11-20-custom-shield-design.md) only where [Superseded lines](#superseded-lines) says so.
It includes the website copy of [issue #196](https://github.com/AndrewDongminYoo/focus-study/issues/196).
This design changes no session, break, schedule, authorization, privacy or report rule.

## Why now

The custom shield shows one static text for every shielded item, so a person who is stopped by it does not see which app the shield is about, and a website shield says "앱".
Another blocking app shows the name of the shielded app and a button that opens the blocking app, so that a person who is stopped can go straight to a break or the end of a session.
On 2026-11-21 the name and the open button were chosen for 온:공; a different text for each app and a count of today's shields were left out (see [Excluded](#excluded)).

## Contract

Proposed on 2026-11-21:

1. The title names the shielded item when the system gives a name:
   - an application, in both application calls: `Application.localizedDisplayName`;
   - a website, in both web domain calls: `WebDomain.domain`.

   A name is used after trimming white space, and only when it is not empty.
   The title is "{name}, 지금은 쉬어요", which needs no Korean particle: a particle after a name would depend on its last syllable, which cannot be decided for a Latin name.
   With no name, the title is "지금은 쉬는 앱이에요" for an application and "지금은 쉬는 사이트예요" for a website.

2. The subtitle is "온:공이 잠시 막고 있어요." for every call, with the line break before it of the custom shield design.
   Where the open button of item 4 is not shown, the subtitle keeps a second line, "언제 풀리는지는 온:공에서 볼 수 있어요.", because then it is the only way the shield sends the person to the app.
   Copy stays short and can change later without a design change, as in contract item 7 of the custom shield design.
3. The configuration is built for each call from the fixed parts of the custom shield design (background, icon, colors and the primary button colors) and the title, subtitle and buttons of items 1, 2 and 4.
   It still contains no value that changes with time (custom shield design, contract item 4).
4. On iOS 26.5 and later the primary button is "온:공 열기" and the secondary button is "닫기".
   A person whose app is shielded every day will feel stuck, so the shield leads with the way to a break or the end of a session; "닫기" stays one tap away.
   The primary button keeps the colors of the custom shield design; iOS draws the secondary button as a text button.
   Below iOS 26.5 the primary button is "닫기" and there is no secondary button: the system has no response that opens the app there, and a notification that the person taps to open the app would need a notification permission that the app does not ask for.
5. A Shield Action extension handles both buttons:
   - on iOS 26.5 and later, the primary button answers `.openParentalControlsApp` and the secondary button answers `.close`;
   - below iOS 26.5, the primary button answers `.close`, and the secondary button, which is not shown, also answers `.close`.

   The app opens on its normal launch route; there is no deep link to a screen.

6. Neither extension reads stored data: no App Group, no selection, no session state, no history and no usage report data.
   The name comes from the arguments of the configuration call, and the configuration extension runs in a sandbox that keeps it from sending the name out.
   The action extension receives tokens only, not names.
   Neither extension logs a name.

### Excluded

- A different text for each app (for example, a joke about each major app): the list would need upkeep and a tone review against the calm direction of the #184 decision.
- A count of today's shields for an app: iOS can reuse a configuration without calling the extension, so a call count is not a count of shields shown, and an accurate count would need an extension to write data, against item 6.
- A deep link from "온:공 열기" to a screen, a notification fallback below iOS 26.5, and `secondaryButtonSubmenuItems`.

## Device findings that shape this design

From the #197 spike on an iPhone 16 Pro with iOS 27.0.1, a signed Debug build installed over the app (see the [device matrix](../notes/screen-time-device-matrix.md)):

- With individual authorization, "온:공 열기" answered with `.openParentalControlsApp` opened 온:공 from an app shield and from a Safari shield of `youtube.com`, and "닫기" answered with `.close` closed the shielded app and the page.
  In the spike "온:공 열기" was the secondary button; this design moves it to the primary button.
- The action extension had no entitlements and was signed with the team's wildcard development profile.
- The configuration of `example.com`, shielded before the spike build, stayed without the secondary button after the install and after the selection was removed and applied again; `youtube.com`, shielded for the first time, showed it.
  iOS keeps a configuration for a shielded item and reuses it, across an install of a new build; when it asks again is not known.
  So an item shielded under an earlier build can keep its one "닫기" button while the action extension answers the primary button with `.openParentalControlsApp`; a tap on that "닫기" then opens 온:공. No build with the earlier shield was distributed (the shield extension's distribution entitlement was not requested; see the [device matrix](../notes/screen-time-device-matrix.md)), so the first distributed build ships the configuration and the action extension together, and only development devices can see the mismatch.
  After the first distributed build, a change to what a button does must keep the meaning of the label that a cached configuration may still show.

Not yet known:

- `[UNCERTAIN]` whether `localizedDisplayName` is filled on the `Application, in: ActivityCategory` call, which a selection of a whole category uses.
- `[UNCERTAIN]` how iOS draws the secondary button label, now "닫기", in each appearance; the primary button label ignored its configured color in the dark appearance.

## Targets and entitlements

The implementation adds one product target, a Shield Action extension:

- extension point `com.apple.ManagedSettings.shield-action-service`;
- a principal class that subclasses `ShieldActionDelegate`;
- bundle ID `kr.donminzzi.focusStudy.shieldaction`;
- an entitlements file with only `com.apple.developer.family-controls` set to true, and no App Group.

The product targets in `project.yml` become 7.
Test bundles are not counted.

Amended on 2026-11-21: the extension first shipped with no entitlements file, because the spike worked without one on the wildcard development profile.
Apple's [request guide](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement) asks for the same Family Controls request for every Screen Time extension it names, Shield Action among them, so the extension now carries the entitlement on an explicit App ID, like the other Screen Time targets.
Its distribution entitlement is requested with the others; the [device matrix](../notes/screen-time-device-matrix.md) records the state.

## Verification plan

Because iOS reuses the configuration of an item that it shielded before, every device check uses an app and a website that were not shielded before with the build under test.
A copy change, a name and the iOS 26.5 gate do not reach an item whose configuration iOS has kept, and a check on such an item is not evidence.

The implementation is checked with:

1. An app shield shows the app's name in the title, and a website shield shows the domain.
2. An app selected through a whole category: record whether the title has its name or the fallback.
3. "온:공 열기" opens 온:공 from an app shield and from a Safari website shield; "닫기" closes the app and the page.
4. The light and the dark appearance: both button labels can be read.
5. The largest text size with a long app name, with and without Display Zoom: the title, the subtitle and both buttons fit without clipping.
6. Unit tests: the title for a name, for an empty name and for no name, for an application and a website; the subtitle with and without the open button; the action response for each button.
   A simulator cannot show a shield, and `localizedDisplayName` is empty outside the extension, so the unit tests check the configuration that the extension returns and the fallback path only.

Below iOS 26.5 the shield cannot be checked on a device here; that row stays unverified.

## Superseded lines

In the [custom shield design](2026-11-20-custom-shield-design.md):

- Contract item 1, the title and the subtitle lines: replaced by items 1 and 2 of this design.
- Contract item 1, the primary button "닫기" and "no secondary button": replaced by item 4 of this design on iOS 26.5 and later; below iOS 26.5 they stay.
- Contract item 2, "The same configuration is returned for all four calls": replaced by item 3 of this design.
- Contract item 5: replaced by item 6 of this design, which keeps its rule and adds the action extension.
- Contract item 6, "There is no ShieldAction extension": replaced by item 5 of this design.
- Excluded, "a secondary button; a button that … opens the app": superseded by the choice of 2026-11-21 to add "온:공 열기".
- Targets and entitlements, "No ShieldAction extension … is added" and the count of 6 product targets: replaced by [Targets and entitlements](#targets-and-entitlements) of this design.
- API, the out-of-scope lines for `ShieldActionResponse.openParentalControlsApp` and `ShieldActionDelegate`: both are in scope in this design.
