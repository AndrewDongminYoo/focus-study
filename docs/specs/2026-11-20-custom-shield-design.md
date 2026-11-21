# Custom shield

Date: 2026-11-20.
Status: design approved on 2026-11-20 in [issue #186](https://github.com/AndrewDongminYoo/focus-study/issues/186); implemented under [issue #187](https://github.com/AndrewDongminYoo/focus-study/issues/187) as the `FocusShield` extension in `Shield/`, and run on a device on 2026-11-20 and 2026-11-21 ([device matrix](../notes/screen-time-device-matrix.md)).
The [shield name and open button design](2026-11-21-shield-name-and-open-button-design.md), proposed on 2026-11-21, would amend contract items 1, 2, 5 and 6 and the excluded open button.
The implementation and the device checks are [issue #187](https://github.com/AndrewDongminYoo/focus-study/issues/187).
Source: the [decision of 2026-11-20 in issue #184](https://github.com/AndrewDongminYoo/focus-study/issues/184#issuecomment-7013218213), which owns the palette and the colon mark, and the choices of 2026-11-20 in issue #186.
This document amends the [2026-10-26 design](2026-10-26-focus-study-design.md) only where [Superseded lines](#superseded-lines) says so.
This design changes no session, break, schedule, authorization, privacy or report rule.

## Why now

Refs [#40](https://github.com/AndrewDongminYoo/focus-study/issues/40).
On 2026-11-13, #40 deferred a custom shield, because each new extension bundle ID needs its own Family Controls (Distribution) entitlement request before App Store distribution.
The #184 decision of 2026-11-20 gives the app one visual direction, the navy focus room and the colon mark ([navy focus room design](2026-11-20-navy-focus-room-design.md)), and it names the shield as the next surface of that direction.
That decision supersedes the #40 deferral; the entitlement request cost stays and is part of #187.

## Contract

Decided on 2026-11-20:

1. The shield is one static configuration with this layout:
   - background: navy `#1E2744` (FocusNavy) as the tint of the system blur, the same value in the light and the dark appearance, as in contract item 4 of the [navy focus room design](2026-11-20-navy-focus-room-design.md#contract);
   - icon: the colon mark, a cream `#FFF4E2` ring over an amber `#F4A64A` dot, with the geometry that the [navy focus room design](2026-11-20-navy-focus-room-design.md#colon-mark-geometry) owns, on a navy rounded square in the proportion of the app icon;
   - title: "지금은 쉬는 앱이에요", in navy in the light appearance and in cream in the dark appearance;
   - subtitle: "온:공이 이 앱을 잠시 막고 있어요. 언제 풀리는지는 온:공에서 볼 수 있어요.", in the title's colors, with a line break before it and between the two sentences;
   - primary button: "닫기", with a navy label on a cream button in the light appearance and a cream label on a navy button in the dark appearance;
   - no secondary button.

   Amended on 2026-11-20 after the first device run ([device matrix](../notes/screen-time-device-matrix.md)): `ShieldConfiguration` has no spacing or alignment property, so the line breaks separate the title from the subtitle and keep each sentence on its own line, and a transparent space under the mark separates the icon from the title.
   iOS 27.0.1 drew the button label in its own light gray and not in the configured color, so the button is navy, not cream; the label keeps cream as its configured color.
   iOS also drew the background as a gray blur tinted by the navy, as the SDK describes `backgroundColor`.

   Amended on 2026-11-21 after the light and dark run ([device matrix](../notes/screen-time-device-matrix.md)): with no blur style the system blur follows the appearance, so the light appearance has a light background on which cream text and a cream ring cannot be read.
   The text and the button therefore follow the appearance; in the dark appearance iOS draws the label white whatever its color, and in the light appearance it draws the configured navy.
   A dark blur style kept the background dark in both appearances and was rejected, because the light appearance then looks like the dark one.
   The icon is one image for both appearances, because iOS 27.0.1 drew the light variant of a registered `UIImageAsset` in the dark appearance; the navy tile carries the mark on either background.

2. The same configuration is returned for all four `ShieldConfigurationDataSource` calls: an application, an application in a category, a web domain, and a web domain in a category.
3. The focus layer (`focusSession`) and the everyday layer (`everydayLayer`) show the same shield.
   The data source is not told which named `ManagedSettingsStore` applied a shield, and this design does not need to know.
4. The configuration contains no value that changes with time, such as a remaining time or a release time.
   iOS can keep a configuration after it asks for it, so a time value could show stale.
   The subtitle sends the user to the app for the release time.
5. The shield extension reads no data: no App Group, no selection, no session state, no history and no usage report data.
   The usage-report boundary of the [2026-10-26 design](2026-10-26-focus-study-design.md#타깃과-데이터-경계) stays as it is.
6. There is no ShieldAction extension.
   What the primary button does without an action extension is not documented in the SDK; #187 checks it on a device (see [Verification plan](#verification-plan)).
7. Copy is short and can change later without a design change; copy polish does not block the implementation.

"쉬는 앱" in the title does not collide with the break screen: a break lifts both layers, so no shield shows during a break.

Excluded: a remaining time or a release time on the shield; a different text for each layer; a secondary button; a button that starts a break, ends a session or opens the app; any reward shape, as excluded by the #184 decision.

## Targets and entitlements

The implementation adds one product target, a Shield Configuration extension:

- extension point `com.apple.ManagedSettingsUI.shield-configuration-service`;
- a principal class that subclasses `ShieldConfigurationDataSource`;
- an entitlements file with only `com.apple.developer.family-controls` set to true, and no App Group.

The product targets in `project.yml` become 6: FocusStudy (the app), FocusMonitor, FocusReport, FocusStudyIntents, FocusActivity (the widget and the Live Activity) and the new shield extension.
Test bundles are not counted.

No ShieldAction extension (`com.apple.ManagedSettings.shield-action-service`) is added.

The new bundle ID needs a Family Controls (Distribution) entitlement request before App Store distribution.
That request is part of #187; the review of the earlier targets ([#17](https://github.com/AndrewDongminYoo/focus-study/issues/17)) is closed and does not cover the new bundle ID.

The extension cannot read the asset catalog of the app.
#187 chooses how the extension gets the colors and the mark (for example, the same color sets and a mark image in the extension target), and the values must be the ones in [Contract](#contract) item 1.

## API

From the iOS 15 SDK, as read in the Apple documentation on 2026-11-20:

- `ManagedSettingsUI.ShieldConfiguration` has `backgroundBlurStyle`, `backgroundColor`, `icon` (a `UIImage` shown in the center of the shield), `title` and `subtitle` (`ShieldConfiguration.Label(text:color:)`), `primaryButtonLabel`, `primaryButtonBackgroundColor` and `secondaryButtonLabel`; every initializer parameter defaults to nil.
- `ShieldConfigurationDataSource` has `configuration(shielding: Application)`, `configuration(shielding: Application, in: ActivityCategory)`, `configuration(shielding: WebDomain)` and `configuration(shielding: WebDomain, in: ActivityCategory)`.

Out of scope:

- `secondaryButtonSubmenuItems` (iOS 26.4 and later);
- `ShieldActionResponse.openParentalControlsApp` (iOS 26.5 and later), which opens "your parental controls app" and is not verified for `.individual` authorization;
- `ShieldActionDelegate` and its responses `.close`, `.defer` and `.none`, because there is no action extension.

## Verification plan

The implementation in #187 is checked with:

1. The shield in the light and the dark appearance: the navy and the text colors are the same in both.
2. The largest text size: the title, the subtitle and "닫기" are not clipped.
3. A small screen: the mark, the text and the button fit.
4. An app shield and a Safari web-domain shield show the same configuration.
   Only Safari is checked; other browsers are not claimed ([issue #13](https://github.com/AndrewDongminYoo/focus-study/issues/13) recorded the earlier browser results).
5. "닫기" without an action extension, on a device: record what it does.
   If it does not close the shielded app, #187 stops and asks for a decision before it adds a ShieldAction extension or changes the button.
6. The focus layer and the everyday layer shield the same app at the same time: the same shield shows.

Simulator captures do not prove the shield on a device; each device result goes to the [device matrix](../notes/screen-time-device-matrix.md), and an unchecked item stays unverified.

## Superseded lines

In the [2026-10-26 design](2026-10-26-focus-study-design.md):

- "앱 본체와 Monitor 및 Report 확장의 3개 제품 타깃을 사용하고 기본 시스템 shield를 사용한다." (purpose and scope): the shield is the custom shield of this design, and the product targets are the 6 in [Targets and entitlements](#targets-and-entitlements).
- "기본 시스템 shield 사용" (M1 amendment): replaced by the custom shield of this design.
  The other scope decisions of that line do not change.
