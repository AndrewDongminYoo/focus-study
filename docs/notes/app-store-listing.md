# App Store listing

The listing of the first App Store submission, 1.0.0 (2), for the Korea storefront only.
It is typed into App Store Connect by hand; this note is the source, so change it first and copy the change.
Privacy answers come from [store privacy declarations](store-privacy-declarations.md); the copy follows the landing site `https://focus.donminzzi.kr`.
Field limits are App Store Connect's: name and subtitle 30 characters, promotional text 170, keywords 100, description 4000; the field counter is the authority.

## App information

| Field              | Value                                                        |
| ------------------ | ------------------------------------------------------------ |
| Name               | 온:공 - 공부 집중, 앱 차단                                   |
| Subtitle           | 고른 앱만 잠그는 공부 집중 타이머                            |
| Primary category   | 생산성 (Productivity)                                        |
| Secondary category | 교육 (Education)                                             |
| Privacy policy URL | `https://focus.donminzzi.kr/privacy`                         |
| Support URL        | `https://focus.donminzzi.kr/`                                |
| Marketing URL      | `https://focus.donminzzi.kr/`                                |
| Price              | Free                                                         |
| Availability       | Korea only                                                   |
| Release            | Automatically release this version after App Review approval |
| Copyright          | 2026 donminzzi lab                                           |

The name in App Store Connect may differ if the app record was created with another name; the name is claimed per locale.

## Promotional text

```plaintext
공부할 때 자꾸 손이 가는 앱과 웹사이트만 골라서 잠가요. 계정 없이, 서버 없이, 내 iPhone 안에서만 동작해요.
```

## Description

```plaintext
공부할 때 자꾸 손이 가는 앱과 웹사이트를 직접 골라서, 집중하는 동안만 잠가요.

■ 고른 것만 잠가요
스크린 타임 권한으로, 내가 고른 앱과 웹사이트만 집중하는 동안 열리지 않게 해요. 잠긴 앱을 열면 온:공 화면이 나와요.

■ 집중 시간은 25분부터 50분까지
5분 단위로 정하고 시작해요. 설정에서 언제든 바꿀 수 있어요.

■ 잠깐 쉬어도, 흐름은 그대로
한 번의 집중에서 3분씩 최대 3번 쉴 수 있어요. 쉬는 시간은 짧은 대기 화면 뒤에 시작되고, 쉬는 동안에는 타이머가 멈추고 제한이 잠깐 풀려요.

■ 매일 같은 시간, 따로 신경 쓰지 않도록
학교 시간처럼 매일 반복되는 시간대에 따로 고른 앱을 막아요. 점심시간처럼 잠시 풀어 둘 시간도 3개까지 정할 수 있고, 앱을 열지 않아도 매일 적용돼요.

■ 집중 모드와 함께
iOS에서 "공부" 같은 집중 모드를 켜면 집중이 시작되고, 끄면 끝나요. 알림은 그 집중 모드에 설정한 대로 iOS가 걸러 줘요.

■ 오늘의 기록
오늘 한 집중과 끝난 이유, 며칠째 이어서 집중했는지를 보여 줘요. 오늘의 사용량은 스크린 타임 보고서로 확인하고, 홈 화면 위젯으로 오늘의 집중 시간을 볼 수 있어요.

■ 데이터는 기기에만 저장돼요
계정이 없고, 고른 앱 목록과 사용량을 서버로 보내지 않아요. 점수나 비교 대신, 나의 하루를 기록해요.

온:공은 본인이 본인의 iPhone에서 쓰는 앱이에요. 부모님이 관리하는 기능은 없어요. iPhone만 지원해요.
```

## Keywords

Provisional — not for submission until the scoring step is done.

```plaintext
스크린타임,앱잠금,폰잠금,디지털디톡스,뽀모도로,수험생,시험,학생,폰중독,사용시간,웹사이트,매일,루틴,자기관리,스마트폰
```

Owed: Apple Ads popularity for every term in a Korea ad group, recorded as `storefront | date | source | seed | term | score`.
The name and subtitle already index 온:공, 공부, 집중, 앱, 차단, 고른, 잠그는 and 타이머, so they are not repeated.

Expectation check, Korea storefront, 2026-11-22, first 12 unique apps of `apps.apple.com/kr/iphone/search`:

- `앱차단` and `스크린타임`: 9 to 10 of 12 are Screen Time blocking apps (터닝, 잠글시간, 지키자, 락체스트, 진짜로); these are the pillars.
- `공부타이머`, `집중`, `뽀모도로`: mostly study timers (열품타, Forest, 얼티밋 포커스); partly the same expectation.
- `수험생`: mixed with simulation games and exam communities; an experiment.

Held candidates:

- `공부기록`: results are planners and study logs (열품타, 투두메이트, 스터디 로그); the app shows only today's history.
- `숏폼`, `쇼츠`: the app blocks whole apps, not short-form feeds inside an app.
- `폰중독`: the search request failed (HTTP 500); `[TOOL_FAILED]`, kept in the string as unscored.
- Brand and app names (열품타, Forest): App Review Guideline 2.3.7.

Terms to track after release, baseline 2026-11-22: `앱차단` absent, `스크린타임` absent.

## App Review information

Sign-in required: no.
Contact name, email and phone: entered in App Store Connect only, never in this repository.

Notes:

```plaintext
온:공 is a focus timer for students. It uses the Family Controls framework with individual authorization: the person who installs it blocks apps and websites on their own iPhone. It is not a parental control app, and there is no account, server or network access.

How to review (a physical iPhone is needed; Screen Time shields do not appear in Simulator):
1. Open the app and allow Screen Time access in the onboarding.
2. Choose one or more apps or websites to block, then choose a focus length and tap Start.
3. Open a chosen app: the 온:공 shield appears. On iOS 26.5 and later its primary button "온:공 열기" opens 온:공; "닫기" closes the app.
4. In the timer screen, take a break (up to 3 breaks of 3 minutes): the apps are unblocked during the break and blocked again after it.
5. Settings > 매일 제한 blocks a separate selection on chosen weekdays and hours without opening the app.
6. Optional: Settings > Focus > (a Focus) > Focus Filters > 온:공 starts a focus session when that Focus turns on.

Why each extension exists:
- Device Activity Monitor: starts and ends the blocks at the planned times while the app is not running.
- Shield Configuration: draws the 온:공 shield with the blocked app's name.
- Shield Action: answers the shield's two buttons.
- Device Activity Report: shows today's Screen Time usage inside the app; the data never leaves the extension.
- App Intents: runs the Focus filter while the app is not running.
- Widget and Live Activity: show today's focus time and the running session's planned times.

The Screen Time features are free. The app has no in-app purchase in this version.
```
