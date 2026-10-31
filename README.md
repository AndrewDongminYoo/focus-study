# FocusStudy (임시 이름)

학생이 자신의 앱·웹사이트 사용을 돌아보고 25분 집중 시간을 정하는 iOS 17+ SwiftUI/SwiftData 앱입니다. 정식 제품명은 미정입니다.

Xcode 프로젝트는 `FocusStudy.xcodeproj`입니다.
[GitHub 저장소](https://github.com/AndrewDongminYoo/focus-study)의 CI 설정은 [verify.yml](.github/workflows/verify.yml)에서 관리합니다.

## 실행과 검증

개발 환경의 과거 확인 결과는 [설계의 환경 확인](docs/specs/2026-10-26-focus-study-design.md#환경-확인과-선행-조건)에 기록되어 있습니다.
프로젝트 생성과 소스 구성 변경은 [AGENTS.md](AGENTS.md#sources-and-project-generation)를 따릅니다.
아래 명령은 저장소 루트에서 실행합니다.

```sh
swift test
xcrun swiftc Shared/ControlTypes.swift Shared/SharedControlStore.swift Shared/SessionControl.swift Tests/Fixtures/ControlRaceHelper.swift -o /tmp/focus-control-race
/tmp/focus-control-race --verify
xcodebuild build -project FocusStudy.xcodeproj -scheme FocusStudy -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

`xcrun simctl list devices available`에서 사용 가능한 iPhone UUID를 확인하고 `SIMULATOR_ID`에 설정한 뒤 실행합니다.

```sh
xcodebuild test -project FocusStudy.xcodeproj -scheme FocusStudy -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO
xcodebuild build -project FocusStudy.xcodeproj -scheme FocusStudy -configuration Release -destination 'generic/platform=iOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

| 검증                   | 범위와 한계                                                                                                                 |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `swift test`           | `CoreTests/`, `HistoryTests/`, `ReportTests/`의 제어 로직, SwiftData 기록, 합성 보고서 집계를 검사합니다.                   |
| 경합 helper            | 실제 파일 잠금과 합성 monitoring/shield를 사용하는 두 프로세스를 검사하며 `PASS: stale A cannot clear B`를 출력해야 합니다. |
| iOS scheme             | `FocusSDKTests`와 `FocusUITests`에서 SDK adapter/repository/model 및 DEBUG 합성 UI를 검사합니다.                            |
| unsigned Release build | fixture를 제외한 App/Monitor/Report의 기기 아키텍처 컴파일을 검사합니다.                                                    |

SDK 또는 UI만 확인할 때는 test 명령에 `-only-testing:FocusSDKTests` 또는 `-only-testing:FocusUITests`를 추가합니다.
이 검증은 실제 Screen Time 권한·차단·콜백 동작의 증거가 아닙니다.

화면만 확인하려면 Debug scheme의 Launch Arguments에 `--ui-testing approved --selected`를 넣습니다. 권한 거절 화면은 `--ui-testing denied --selected`, 등록 실패 화면은 `--ui-testing registration-failure --selected`입니다. 이 경로는 메모리 SwiftData와 고유 임시 제어 파일을 사용하고 Release에는 fixture 구현이 포함되지 않습니다. 실제 Screen Time API 지원의 증거가 아닙니다. `--ui-testing startup-failure --selected`는 합성 세션이 진행 중일 때 초기 저장소가 한 번 실패하는 복구 화면을 확인합니다.
`--ui-testing expiring`은 만료 3초 전의 합성 세션으로 시작해 25분 완료 화면을 확인하고, `--ui-testing not-requested --selected`는 권한을 요청하기 전의 첫 화면을 확인합니다.

### 보고서 상태와 실기기 진단

보고서 합성 UI는 `--ui-testing report-waiting`, `--ui-testing report-empty`, `--ui-testing report-zero`와 `--selected`로 확인합니다.
대기 상태는 보고서 콘텐츠가 아직 없는 호스트이며, 빈 데이터와 실제 0은 확장이 사용하는 `UsageSummarySection`을 같은 방식으로 렌더링합니다.
기본 fixture의 콘텐츠 재생성 검사는 그대로 유지합니다.

실기기 진단은 Debug 빌드의 별도 실행 인자 `--screen-time-diagnostics`로 활성화합니다.
`--ui-testing`과 함께 사용하지 않으며 합성 fixture와 달리 실제 권한·선택·monitoring 경로를 사용합니다.
설치 허용은 실제 앱·웹 제한 적용의 동의를 대신하지 않습니다.

1. 동의받은 선택과 정상 권한을 준비한 후 `다음 등록 후 실패 주입`을 누르고 세션을 시작합니다.
   실제 monitoring 등록이 성공한 직후 한 번 오류를 던져 세션 엔진의 stop/clear 롤백을 확인합니다.
   실제 SDK가 먼저 실패하면 그 오류를 유지하고 주입은 소비합니다.
2. 세션 A가 활성일 때 `현재 세션 콜백 저장`을 누릅니다.
   A를 종료하고 B를 시작한 뒤 `이전 세션 콜백 전달`을 눌러 B가 유지되는지 확인합니다.
   같은 활성 세션에는 저장한 콜백을 재전달할 수 없습니다.
3. 관측 결과는 실기기 검증표에 기록합니다.
   이 경로는 shared callback engine을 직접 호출하므로 OS 확장 콜백의 실제 전달 지연을 증명하지 않습니다.

진단은 기본 실행과 Release 빌드에 표시되지 않으며, 토큰·도메인·사용량을 기록하거나 내보내지 않습니다.

## 문서와 설정 품질 검사

[Trunk 설정](.trunk/trunk.yaml)은 Markdown, YAML, GitHub Actions와 영어 철자를 검사합니다.
Swift 동작 검증은 위 테스트 명령을 사용합니다.

```sh
trunk check --no-fix
```

초기 설정 전체를 다시 확인할 때만 `trunk check --all --no-fix`를 사용합니다.
새 checkout에서는 `trunk check`를 실행해 설정된 도구와 Git hook을 준비합니다.
pre-commit은 staged 파일, pre-push는 push할 커밋을 검사하며 파일을 자동 수정하지 않습니다.
문장별 줄바꿈을 유지하고 줄 길이는 강제하지 않습니다.
문서 형식 규칙은 `.trunk/configs/`, 철자 검사 범위와 사전은 루트 [cspell.config.yaml](cspell.config.yaml)에서 관리합니다.
Swift와 Darwin 파일 연산, CI의 Python 코드에는 기본 제공 사전을 적용합니다.
추가 용어는 [.cspell/project-terms.txt](.cspell/project-terms.txt)에 원문 표기를 유지하고 대소문자 구분 없이 정렬합니다.
Xcode 프로젝트와 숨김 설정 파일도 검사하며, 한국어 맞춤법 검사를 대신하지 않습니다.
사전과 설정은 같은 커밋에 포함해야 합니다.

## 실제 기기를 연결하기 전

운영자가 선택한 개발 Team은 `393JTTV68D`이며 bundle ID는 `kr.donminzzi.focusStudy`, 확장은 `.monitor`와 `.report`입니다.
App Group은 `group.kr.donminzzi.focusStudy`입니다.
`project.yml`, `Configuration/*-Info.plist`, `Configuration/*.entitlements`가 이 값을 사용하며, Apple 계정의 식별자 등록·capability·프로필 적합성은 별도로 확인해야 합니다.
App과 Monitor만 같은 App Group을 사용하며 Report에는 App Group entitlement가 없습니다.

개발 서명과 실제 기기 준비 상태는 [검증 기록](docs/notes/screen-time-device-matrix.md#서명과-배포)을 확인하세요.
실제 앱·웹사이트에 제한을 적용하기 전에는 기기 소유자의 선택과 동의를 받아야 합니다.

## 문서 안내

| 문서                                                 | 관리하는 내용                                        |
| ---------------------------------------------------- | ---------------------------------------------------- |
| [AGENTS.md](AGENTS.md)                               | 소스 구조, 생성 파일 관리, 변경별 검증 선택          |
| [설계](docs/specs/2026-10-26-focus-study-design.md)  | 제품 범위, 사용자 흐름, 데이터 경계, 세션·복구 계약  |
| [계획](docs/plans/2026-10-26-focus-study.md)         | 초기 작업 분해와 현재 구현의 대응 관계               |
| [구현 기록](docs/implementation-ledger.md)           | 시간순 결정과 당시 실행 결과                         |
| [검토 기록](docs/notes/independent-review.md)        | 회귀 문제와 수정 근거                                |
| [검증 기록](docs/notes/screen-time-device-matrix.md) | 환경별 검증 결과, 실기기 미검증 항목, 서명 준비 상태 |

## 공개 PR의 CI

`.github/workflows/verify.yml`은 PR의 실제 head를 checkout하고 SwiftPM 테스트, 두 프로세스 경쟁 검증, 서명 없는 SDK/mock UI 테스트와 기기용 Release 빌드를 실행합니다. `contents: read` 권한만 사용하며 계정·인증서·시크릿·entitlement를 구성하지 않습니다.

runner·Xcode·Simulator 버전은 workflow에 명시된 값을 기준으로 합니다.
지정한 runtime이 없으면 검증을 건너뛰지 않고 실패합니다.
로컬 결과와 hosted CI 결과는 각각의 실행 증거로 구분하며, 이전 성공 기록을 현재 head의 결과로 사용하지 않습니다.
