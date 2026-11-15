# 온:공

공부하는 동안 방해되는 앱과 웹사이트를 Screen Time으로 막고, 정한 시간만큼 집중하도록 돕는 iOS 앱입니다.
FocusStudy는 코드와 프로젝트 이름입니다.

- 집중 시간은 25~50분 사이에서 5분 단위로 정합니다.
- 한 세션에서 최대 3번, 한 번에 3분까지 쉴 수 있습니다.
- 집중 세션과 별도로, 매일 정한 시간대에 앱을 막는 매일 제한을 둘 수 있습니다.
- iOS 집중 모드가 켜질 때 집중 세션이 시작되도록 연결할 수 있습니다.
- 잠금 화면의 Live Activity로 남은 시간을 볼 수 있습니다.
- 집중 기록은 기기 안에만 저장하고, 사용량 보고서는 시스템 확장 안에서만 보여 줍니다.

iOS 17 이상을 지원하며 SwiftUI, SwiftData, Screen Time API(FamilyControls, DeviceActivity, ManagedSettings)를 사용합니다.
외부 의존성과 서버는 없습니다.

## 실행과 검증

`swift test`와 경합 검사에는 macOS 14 이상과 Swift 6.0 도구(Xcode 16 이상)가 필요합니다.
iOS 테스트와 Release 빌드는 CI와 같은 Xcode 26.6과 iOS 26.5 시뮬레이터를 기준으로 확인하며, 이 버전은 [verify.yml](.github/workflows/verify.yml)이 정합니다.
`FocusStudy.xcodeproj`는 `project.yml`에서 XcodeGen으로 생성하므로 직접 수정하지 않습니다([프로젝트 생성 규칙](AGENTS.md#sources-and-project-generation)).
아래 명령은 저장소 루트에서 실행합니다.

```sh
swift test
xcrun swiftc Shared/ControlTypes.swift Shared/SharedControlStore.swift Shared/SessionControl.swift Shared/FocusLength.swift Shared/BreakTiming.swift Shared/EverydaySchedule.swift Shared/RegistrationMarker.swift Tests/Fixtures/ControlRaceHelper.swift -o /tmp/focus-control-race
/tmp/focus-control-race --verify
```

iOS 테스트는 `xcrun simctl list devices available`에서 iPhone의 UUID를 골라 `SIMULATOR_ID`에 넣은 뒤 실행합니다.

```sh
xcodebuild test -project FocusStudy.xcodeproj -scheme FocusStudy -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO
xcodebuild build -project FocusStudy.xcodeproj -scheme FocusStudy -configuration Release -destination 'generic/platform=iOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

| 검사            | 확인하는 것                                                                            |
| --------------- | -------------------------------------------------------------------------------------- |
| `swift test`    | `CoreTests/`, `HistoryTests/`, `ReportTests/`의 세션 제어, SwiftData 기록, 보고서 집계 |
| 경합 검사       | 실제 파일 잠금을 쓰는 두 프로세스에서 지난 세션의 콜백이 새 세션을 바꾸지 못하는지     |
| `FocusSDKTests` | Screen Time adapter, 저장소, 화면 모델                                                 |
| `FocusUITests`  | DEBUG 합성 데이터로 실행한 화면 흐름                                                   |
| Release 빌드    | 개발용 코드를 뺀 App, Monitor, Report, Activity의 기기용 컴파일                        |

경합 검사는 다음 열한 줄을 출력해야 합니다.

```log
PASS: stale A cannot clear B
PASS: stale break 1 cannot touch break 2
PASS: stale everyday revision cannot undo a newer save
PASS: focus off cannot end a manual session
PASS: a callback for the holder's registration returns at once
PASS: a callback for the holder's registration skips the access read
PASS: a callback for another name keeps the bounded retry
PASS: the next lock holder deletes a leftover marker
PASS: a didEnd for the holder's stop returns at once
PASS: a didStart for the holder's stop keeps the bounded retry
PASS: a warning for the holder's stop keeps the bounded retry
```

한 묶음만 실행하려면 test 명령에 `-only-testing:FocusSDKTests` 또는 `-only-testing:FocusUITests`를 붙입니다.
이 검사들은 합성 데이터와 시뮬레이터를 쓰므로 실제 Screen Time 권한, 차단, 콜백 동작을 증명하지 않습니다.
특정 화면이나 진단 경로로 앱을 띄우는 방법은 [개발용 실행 인자](docs/notes/development-launch-arguments.md)에 있습니다.

## 문서와 설정 품질 검사

```sh
trunk check --no-fix
```

Trunk는 Markdown, YAML, GitHub Actions와 영어 철자를 검사합니다.
새 checkout에서 한 번 실행하면 필요한 도구와 Git hook이 준비되며, pre-commit과 pre-push hook은 파일을 고치지 않고 검사만 합니다.
문서는 문장마다 줄을 바꾸고 줄 길이는 제한하지 않습니다.
철자 사전에 단어를 추가할 때는 [.cspell/project-terms.txt](.cspell/project-terms.txt)에 원래 표기대로 넣고 대소문자 구분 없이 정렬하며, 그 단어를 쓰는 변경과 같은 커밋에 포함합니다.

## 실제 기기를 연결하기 전

| 항목      | 값                                                     |
| --------- | ------------------------------------------------------ |
| 개발 Team | `393JTTV68D`                                           |
| Bundle ID | `kr.donminzzi.focusStudy`                              |
| 확장      | `.activity`, `.monitor`, `.report`                     |
| App Group | `group.kr.donminzzi.focusStudy` (App과 Monitor만 사용) |

조정(2026-11-14, #124): Activity 확장도 홈 화면 위젯이 `TodaySnapshot/today.json`을 읽기 위해 이 App Group을 씁니다([홈 화면 위젯 설계](docs/specs/2026-11-13-home-widget-design.md#data-path)).

이 값은 `project.yml`, `Configuration/*-Info.plist`, `Configuration/*.entitlements`에 들어 있습니다.
Apple 계정의 식별자 등록, capability, 프로필은 따로 확인해야 하며, 현재 서명 준비 상태는 [실기기 검증 기록](docs/notes/screen-time-device-matrix.md#서명과-배포)에 있습니다.
실제 앱과 웹사이트를 제한하기 전에는 기기 소유자의 선택과 동의를 받아야 합니다.
실기기 진단 방법은 [개발용 실행 인자](docs/notes/development-launch-arguments.md#실기기-진단)를 따릅니다.

## CI

[verify.yml](.github/workflows/verify.yml)은 PR과 `main` push에서 PR의 실제 head를 checkout하고, 아래 작업을 각각 실행합니다.

- `host`: `swift test`와 경합 검사
- `simulator (FocusSDKTests)`, `simulator (FocusUITests)`: 서명 없이 실행하는 iOS 테스트
- `release`: 서명 없는 기기용 Release 빌드

작업별 제한 시간과 Xcode·runner·시뮬레이터 버전은 workflow에 고정되어 있으며, 지정한 시뮬레이터 runtime이 없으면 검사를 건너뛰지 않고 실패합니다.
UI 테스트가 만든 화면 캡처는 `focus-test-attachments` artifact로 3일 동안 보관합니다.
workflow는 `contents: read` 권한만 쓰고 계정, 인증서, 시크릿을 사용하지 않습니다.

## 문서 안내

| 문서                                                           | 내용                                                   |
| -------------------------------------------------------------- | ------------------------------------------------------ |
| [AGENTS.md](AGENTS.md)                                         | 소스 구조, 생성 파일 관리, 변경별 검증 선택, 문서 목록 |
| [설계](docs/specs/2026-10-26-focus-study-design.md)            | 제품 범위, 사용자 흐름, 데이터 경계, 세션·복구 계약    |
| [구현 기록](docs/implementation-ledger.md)                     | 시간순 결정과 당시 실행 결과                           |
| [검토 기록](docs/notes/independent-review.md)                  | 회귀 문제와 수정 근거                                  |
| [실기기 검증 기록](docs/notes/screen-time-device-matrix.md)    | 환경별 검증 결과, 미검증 항목, 서명 준비 상태          |
| [개발용 실행 인자](docs/notes/development-launch-arguments.md) | 화면 확인용 fixture, Live Activity 확인, 실기기 진단   |
