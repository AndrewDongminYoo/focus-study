# FocusStudy (임시 이름)

학생이 자신의 앱·웹사이트 사용을 돌아보고 25분 집중 시간을 정하는 iOS 17+ SwiftUI/SwiftData 앱입니다. 정식 제품명은 미정입니다.

프로젝트: `/Volumes/dongminyu/Development/01_personal/focus-study/FocusStudy.xcodeproj`  
로컬 브랜치: `feature/focus-study`. GitHub remote, CI, push, 배포는 구성하지 않았습니다.

## 실행과 검증

Xcode 27.1(27A9275), iOS SDK 27.1로 개발했습니다. 외부 패키지 의존성은 없습니다. `project.yml`을 변경하면 설치된 XcodeGen으로 `xcodegen generate`를 실행합니다. 생성된 Xcode 프로젝트도 로컬 저장소에 포함합니다.

```sh
swift test
xcrun swiftc Shared/ControlTypes.swift Shared/SharedControlStore.swift Shared/SessionControl.swift Tests/Fixtures/ControlRaceHelper.swift -o /tmp/focus-control-race
/tmp/focus-control-race --verify
xcodebuild build -project FocusStudy.xcodeproj -scheme FocusStudy -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
xcodebuild test -project FocusStudy.xcodeproj -scheme FocusStudy -destination 'platform=iOS Simulator,id=88F93347-37E2-4EE9-9C1C-86E89C6896AE' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO
```

Simulator UUID는 이 Mac의 iPhone 18 Pro/iOS 27.0입니다. 다른 환경에서는 `xcrun simctl list devices available` 결과로 바꿉니다. SwiftPM은 macOS에서 순수 제어 로직, SwiftData 기록, 합성 보고서 집계를 실행합니다. iOS scheme은 SDK adapter/repository 테스트와 DEBUG 전용 합성 UI 테스트를 실행합니다. 테스트 fixture에서는 FamilyControls 인증 요청, DeviceActivity monitoring 등록, ManagedSettings 제한을 호출하지 않습니다.

화면만 확인하려면 Debug scheme의 Launch Arguments에 `--ui-testing approved --selected`를 넣습니다. 권한 거절 화면은 `--ui-testing denied --selected`, 등록 실패 화면은 `--ui-testing registration-failure --selected`입니다. 이 경로는 메모리 SwiftData와 고유 임시 제어 파일을 사용하고 Release에는 fixture 구현이 포함되지 않습니다. 실제 Screen Time API 지원의 증거가 아닙니다. `--ui-testing startup-failure --selected`는 합성 세션이 진행 중일 때 초기 저장소가 한 번 실패하는 복구 화면을 확인합니다.

## 실제 기기를 연결하기 전

현재 bundle ID `example.focusstudy.local`, `.monitor`, `.report`와 App Group `group.example.focusstudy.local`은 컴파일용 placeholder입니다. 실제로 등록된 식별자로 오인하지 마세요. 이름과 Team을 결정한 다음 `project.yml`, `Configuration/*-Info.plist`, `Configuration/*.entitlements`의 값을 일치시켜야 합니다. App과 Monitor만 같은 App Group을 사용하며 Report에는 App Group entitlement가 없습니다.

이 Mac의 읽기 전용 확인에서 유효한 코드 서명 identity는 0개였습니다. 계정 설정, 인증서/프로필 생성, Family Controls entitlement 신청은 수행하지 않았습니다. 개발 서명 및 실제 기기 준비가 필요합니다. `-allowProvisioningUpdates`를 사용하지 않았습니다. 배포는 별도 단계이며 본체·Monitor·Report의 Family Controls 배포 entitlement를 각 App ID별로 심사받아야 합니다.

실제 앱·웹사이트에 제한을 적용하기 전에는 기기 소유자의 선택과 동의를 받아야 합니다. Safari 우선 실제 기기 검증표는 [검증 기록](docs/qa/screen-time-device-matrix.md)을 참고하세요. iOS 17은 deployment target으로 컴파일했지만 해당 OS에서의 런타임 검증은 하지 못했습니다.

## 동작과 데이터 경계

- 개별 앱·웹사이트 토큰을 각각 50개까지 선택합니다. 빈 선택, 카테고리, 한도 초과는 저장·시작 전에 거절합니다. 현재 세션 중 선택을 바꾸지 않습니다.
- 25분 고정 세션과 중도 종료를 제공하며 일시정지는 없습니다. 시간은 절대 만료 시각에서 다시 계산합니다. 잠금·종료·콜백 지연 때문에 초 단위 자동 해제를 보장하지 않습니다.
- 하나의 명명된 ManagedSettings store만 사용합니다. UUID를 포함한 monitoring 이름과 App Group의 프로세스 간 잠금으로 이전 콜백과 새 세션을 구분합니다. 실패 시 제한을 롤백하고 활성으로 표시하지 않습니다.
- 선택·기록 저장소 초기화가 실패해도 제어 상태를 먼저 조정하고 안전한 종료·재시도를 제공합니다.
- App Group은 세션 ID·시각·단계·종료 사유 등 제어 데이터만 보관합니다. 선택 토큰은 본체 내부 파일에 저장하고 사용량은 Report 확장의 메모리와 화면에만 둡니다. SwiftData에는 앱이 만든 세션 기록만 저장합니다.
- 웹사이트는 선택된 도메인의 shield를 사용합니다. 임의 URL 입력, 경로별 차단, 모든 브라우저 우회 방지는 제공하지 않습니다. Safari 비공개 브라우징에 영향을 주는 `blockedByFilter`는 사용하지 않습니다.
- 기록된 시간은 실제 공부나 연속 차단 성공의 증거가 아닙니다. 사용 보고서가 늦거나 비어 있다고 사용량을 0으로 단정하지 않습니다.

설계와 실행 판단은 [설계](docs/superpowers/specs/2026-10-26-focus-study-design.md), [계획](docs/superpowers/plans/2026-10-26-focus-study.md), [구현 기록](docs/implementation-ledger.md)에 남겼습니다.
