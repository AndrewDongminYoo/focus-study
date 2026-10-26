# FocusStudy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 학생이 선택한 앱·웹사이트의 사용을 25분 동안 제한하고 오늘의 세션과 사용 보고서를 살펴보게 한다.

**Architecture:** SwiftUI 본체가 인증·선택·SwiftData 기록을 소유한다. App과 Monitor는 잠금으로 보호된 최소 메타데이터 및 하나의 명명된 store를 공유하고, Report는 격리된 사용량 UI만 제공한다.

**Tech Stack:** iOS 17+, SwiftUI, SwiftData, FamilyControls, ManagedSettings, DeviceActivity, XCTest, Darwin flock.

**Spec:** [설계 문서](../specs/2026-10-26-focus-study-design.md)

## Global Constraints

- iOS 17 이상 SwiftUI + SwiftData를 사용한다.
- 일시정지는 제공하지 않는다. 권한 거절 시 설정 안내만 한다.
- 앱 본체와 Monitor 및 Report 확장의 3개 제품 타깃을 사용하고 기본 시스템 shield를 사용한다. 테스트 번들은 제품 타깃 수에 포함하지 않는다.
- 보호자 관리, Android, 계정, 서버, AI, 카페, 리워드는 제외한다.
- 사용 보고서 민감 데이터를 앱 저장소로 내보내지 않는다.
- 정식 앱 이름은 미정이며 FocusStudy는 임시 식별자이다.
- 문서 전용 제한은 후속 구현 승인으로 해제되었다. 로컬 프로젝트·저장소·feature 브랜치와 의미 단위 커밋은 허용한다. push·계정 변경·entitlement 신청은 하지 않는다.

## Review Focus

1. 잠금 경쟁과 이전 콜백: 이전 ID가 새 store를 지우지 않아야 한다(Task 2).
2. 중간 실패·프로세스 종료: preparing/ending을 복구하고 잘못된 활성 표시를 막아야 한다(Task 2).
3. 선택 경계: 0/50/51개, 카테고리·취소·세션 중 편집을 정확히 처리해야 한다(Task 1, 3).
4. 날짜·시간대·권한 변경: 시간과 오늘 기록을 재계산하고 철회 시 중단해야 한다(Task 2, 3).
5. 사용량 없음·저장 실패: 0 사용으로 단정하거나 terminal 기록을 잃지 않아야 한다(Task 3, 4).

## 파일 구조와 공통 실행 규칙

아래는 계획 당시 파일 분해이며, 승인된 프로젝트 루트를 기준으로 한다. 실행 시 인터페이스·파일 배치 수정은 `docs/implementation-ledger.md`에 기록했다.

```text
App/FocusStudyApp.swift                    # SwiftData 컨테이너와 화면 진입
App/AuthorizationService.swift             # 개인 인증 adapter
App/SelectionRepository.swift              # 앱 내부 토큰 저장과 검증
App/SessionCoordinator.swift               # 시작/종료와 표시 상태
App/SessionRecord.swift                    # SwiftData 모델 및 terminal 반영
App/FocusView.swift                        # 선택, 세션, 오늘 기록
App/UsageReportHost.swift                  # Report context/filter
Shared/ControlTypes.swift                  # Foundation만 사용하는 제어 값 타입
Shared/SessionControl.swift                # 종료 판정과 프로토콜
Shared/SharedControlStore.swift            # App Group flock/원자 쓰기
Shared/ScreenTimeAdapters.swift            # 명명된 store와 monitoring adapter
Monitor/FocusMonitor.swift                 # 콜백에서 ID 기반 조정
Report/FocusReport.swift                   # extension와 scene
Report/UsageSummary.swift                  # 확장 내부 집계·뷰
Tests/SelectionTests.swift
Tests/SessionControlTests.swift
Tests/SharedControlStoreTests.swift
Tests/SessionCoordinatorTests.swift
Tests/SessionRecordTests.swift
Tests/UsageSummaryTests.swift
Tests/Fixtures/ControlRaceHelper.swift     # macOS에서 실행하는 잠금 검증 도구
UITests/FocusFlowTests.swift
docs/qa/screen-time-device-matrix.md
```

실행 승인 뒤 Xcode 프로젝트명·공유 scheme을 확정하고 환경 변수 `PROJECT`(실제 .xcodeproj 절대 경로), `SCHEME`, `SIM_ID`(사용 가능한 simulator UUID), `DEVICE_ID`(등록된 실기기 UUID)를 설정한다. `xcrun simctl list devices available`로 SIM_ID를 고른다. 제품 타깃 셋 외에 App용 unit/UI test 번들과 Report 소스만 연결한 별도 unit test 번들을 둔다. 아래 `Tests`/`UITests`/`ReportTests`는 그 테스트 번들의 확정할 이름이며 확정 시 명령도 함께 바꾼다.

공통 unit 명령(U): `xcodebuild test -project "$PROJECT" -scheme "$SCHEME" -destination "platform=iOS Simulator,id=$SIM_ID" -only-testing:Tests`

각 Task의 RED 단계는 해당 테스트를 추가한 다음 U에 `-only-testing:Tests/해당클래스`만 지정해 실행한다(U의 기존 only-testing은 대체한다). 기대 결과는 명시한 assertion 실패 또는 구현 전 symbol 부재이며 서명·destination 오류는 RED 증거가 아니다. GREEN 단계에서는 같은 명령이 `TEST SUCCEEDED`, 실패 0건이어야 한다. 구현 승인 후에도 저장소가 없다면 임의 생성하지 않는다. Task 끝의 로컬 커밋은 기존 저장소가 있거나 생성 승인이 있을 때만 수행하고 push하지 않는다.

## Task 1: 선택과 인증의 실행 가능한 기반

**Files:** Create `App/FocusStudyApp.swift`, `App/AuthorizationService.swift`, `App/SelectionRepository.swift`, `Tests/SelectionTests.swift`; 구현 승인 후 확정 경로의 Xcode 프로젝트와 세 타깃 설정.

**Interfaces:** `AuthorizationService.requestIndividual() async throws`; `status: AuthorizationStatus`. `SelectionRepository.load() throws -> FamilyActivitySelection`, `save(_ selection: FamilyActivitySelection) throws`. `SelectionValidator.validate(appCount: Int, webCount: Int, categoryCount: Int) throws`는 empty/tooManyApps/tooManyWebsites/categoriesUnsupported를 반환하는 오류를 정의한다. SDK 토큰을 임의 생성하지 않고 validator는 개수로 테스트한다.

- [ ] RED: `SelectionTests`에 (0,0,0) 거절, (1,0,0)/(0,1,0)/(50,50,0) 허용, 51개 각각 거절, 카테고리 1개 거절을 작성하고 실행한다.
- [ ] 구현: 확정된 이름/경로에 본체와 Monitor/Report 타깃을 만들고 iOS 17 최소 버전·공유 scheme·테스트 번들을 설정한다. 선택은 앱 Application Support 내부 Codable 파일로 저장하며 실패 시 기존 파일을 유지한다. 개인 인증 adapter를 연결한다.
- [ ] GREEN: 같은 테스트를 통과시킨다. `xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO`에서 `BUILD SUCCEEDED`를 확인한다. 이는 Screen Time 동작 증거가 아니다.
- [ ] 검증: 세 제품 타깃의 Family Controls 설정을 검토한다. App Group은 App/Monitor만 공유하고 Report에는 부여하지 않는다. 계정/프로필 변경이 필요하면 별도 승인 절차로 남긴다.
- [ ] 커밋: 생성된 프로젝트·Task 1 파일만 stage하고 `git commit -m "feat: add authorization and private selection storage"`를 실행한다.

## Task 2: 경쟁과 실패에 안전한 세션 제어

**Files:** Create `Shared/ControlTypes.swift`, `Shared/SessionControl.swift`, `Shared/SharedControlStore.swift`, `Shared/ScreenTimeAdapters.swift`, `App/SessionCoordinator.swift`, `Monitor/FocusMonitor.swift`, `Tests/SessionControlTests.swift`, `Tests/SharedControlStoreTests.swift`, `Tests/SessionCoordinatorTests.swift`, `Tests/Fixtures/ControlRaceHelper.swift`.

**Interfaces:**

- `ControlEnvelope: Codable`는 설계의 current/terminal 한 건과 schemaVersion을 담는다. `ControlSession`은 UUID, activityName, startedAt, expiresAt, phase, optional reason/observedAt을 갖는다. `EndReason`은 expired/earlyExit/authorizationRevoked/startFailed/recoveryInterrupted/clockChanged를 정의한다.
- `ControlStore.withExclusiveAccess<T>(_ body: (inout ControlEnvelope) throws -> T) throws -> T`는 잠금·재읽기·원자 저장 전체를 보장한다. 구현체 `SharedControlStore.init(directory: URL)`는 App/Monitor가 해석한 App Group URL을 주입받는다. 이 파일과 ControlTypes는 Foundation/Darwin만 사용해 macOS 검증 도구에서도 컴파일한다. 내부 동기 side effect는 actor 밖에서도 같은 잠금을 사용한다.
- `MonitoringClient.register(id: UUID, start: Date, end: Date) throws`, `isRegistered(id: UUID) -> Bool`, `stop(id: UUID)`; `ShieldClient.apply(_ selection: FamilyActivitySelection)`, `matches(_ selection: FamilyActivitySelection) -> Bool`, `clear()`를 정의한다. 각각 실제 SDK와 가짜 구현을 제공한다.
- `SessionCoordinator.start(selection: FamilyActivitySelection, now: Date) throws -> ControlSession`, `finish(id: UUID, reason: EndReason, now: Date) throws`, `reconcile(now: Date, authorization: AuthorizationStatus, clockChanged: Bool) throws -> ControlEnvelope`를 제공한다. `@MainActor` coordinator의 메서드는 동기 작업을 짧게 수행한다. 앱/Monitor 공용 종료 로직은 `SessionControl`의 동기 `reconcile`/`finish`에 두어 같은 잠금 계약을 사용한다.
- `SessionControl.handleCallback(activityName: String, now: Date, authorization: AuthorizationStatus) throws`는 ID와 만료 검증 후 정리한다. 날짜·권한은 주입하여 테스트한다. 공유 store 이름은 `focusSession`이다.

- [ ] RED: `SessionControlTests`에 1,500초 만료, 이른 콜백 무동작, A 종료 후 B 시작 뒤 A 콜백 무동작, 같은 종료 2회 무동작, 권한 철회/clockChanged 중단을 작성하고 실행한다.
- [ ] RED: `SessionCoordinatorTests`에 등록 throw 시 stop/clear 및 inactive, 등록 목록 불일치·shield readback 불일치·active 저장 실패 시 롤백, preparing/ending 복구, double start 거절을 작성한다. `SharedControlStoreTests`에는 잠금 timeout·손상 파일·원자 교체 실패를 추가한다. 가짜 저장 오류를 단계별 주입하며 오류 직후 active 표시가 없음을 assert한다.
- [ ] 구현: 설계의 시작/종료 순서를 그대로 연결한다. `flock` 획득부터 read/ID 비교/store 변경/파일 교체까지 같은 임계 구역에 둔다. 저장·정리 실패는 재시도 가능한 오류로 전달한다. 25분 비반복 날짜 구성요소 schedule을 만들고 monitoring을 UUID별로 중지한다. Monitor는 저장된 선택을 요구하지 않으며 늦은 start에서 shield를 재적용하지 않는다.
- [ ] GREEN: 위 세 클래스 테스트를 통과시킨다. `xcrun swiftc Shared/ControlTypes.swift Shared/SharedControlStore.swift Tests/Fixtures/ControlRaceHelper.swift -o /tmp/focus-control-race` 뒤 `/tmp/focus-control-race --verify`를 실행한다. helper는 자신의 worker 프로세스 둘을 실행해 같은 임시 디렉터리에 A 종료와 B 시작을 교차 요청하고, 잠금 안의 ID 재검사와 합성 clear/apply 로그 순서를 assert한다. 기대 출력은 `PASS: stale A cannot clear B`, exit 0이다. 이는 실제 store가 아닌 프로세스 간 잠금의 증거이며 실제 Monitor 경로는 Task 5에서 확인한다. helper는 배포 제품 타깃에 포함하지 않는다.
- [ ] 검증: 잠금 내부 `await` 부재, default store 사용 부재, 다른 activity 일괄 stop 부재를 검토한다. 중간 crash 각 지점의 재시작 결과를 테스트 표로 남긴다.
- [ ] 커밋: Task 2 파일을 stage하고 `git commit -m "feat: coordinate focus sessions across app and monitor"`를 실행한다.

## Task 3: 오늘 기록과 SwiftUI 흐름

**Files:** Create `App/SessionRecord.swift`, `App/FocusView.swift`, `Tests/SessionRecordTests.swift`, `UITests/FocusFlowTests.swift`; Modify `App/FocusStudyApp.swift`, `App/SessionCoordinator.swift`.

**Interfaces:** `@Model SessionRecord`는 설계의 UUID 고유 키와 시각/사유만 가진다. `SessionHistory.importTerminal(_ session: ControlSession) throws`는 upsert 후 성공한 UUID만 공유 terminal에서 확인 처리한다. `records(on date: Date, calendar: Calendar) throws -> [SessionRecord]`는 시작일 기준이다. `remainingSeconds(expiresAt: Date, now: Date) -> Int`는 0...1500으로 제한한다. 시작은 이전 terminal import 성공 후에만 호출한다.

- [ ] RED: `SessionRecordTests`에 terminal 재수입 시 1건, SwiftData save 실패 시 공유 terminal 유지, 자정·DST·시간대 변경의 오늘 필터, 남은 시간 1500/0 경계 및 재시작 시 재계산을 작성하고 실행한다.
- [ ] RED: `FocusFlowTests`에 권한 거절 후 설정 안내와 disabled start/report, Picker 취소 시 기존 선택 유지, active 중 편집 불가, 중도 종료 후 편집 가능을 가짜 adapter로 작성한다. UI test 명령은 U의 filter를 `-only-testing:UITests/FocusFlowTests`로 대체한다.
- [ ] 구현: 시작 준비·활성·오류·미사용 상태를 화면에 연결한다. Timer/TimelineView는 전경 표시 갱신에만 사용한다. `scenePhase.active`와 날짜/시간대/시계 변경 관측에서 reconcile·terminal import·오늘 쿼리를 수행한다. 실패를 숨기거나 완료로 세지 않는다.
- [ ] GREEN: Task 3 unit/UI 테스트에서 `TEST SUCCEEDED`를 확인한다. SwiftData는 in-memory container와 저장 실패 adapter로 검증한다.
- [ ] 커밋: Task 3 변경을 stage하고 `git commit -m "feat: show focus session flow and daily history"`를 실행한다.

## Task 4: 격리된 사용 보고서

**Files:** Create `App/UsageReportHost.swift`, `Report/FocusReport.swift`, `Report/UsageSummary.swift`, `Tests/UsageSummaryTests.swift`; Modify `App/FocusView.swift`.

**Interfaces:** `DeviceActivityReport.Context.focusToday`를 양쪽에 동일 문자열로 정의한다. `UsageReportHost`는 현재 기기·현재 Calendar의 오늘 구간 filter를 만든다. `FocusReportScene.makeConfiguration(representing: DeviceActivityResults<DeviceActivityData>) async -> UsageSummary`는 현재 SDK 시그니처를 사용한다. `UsageSummary`는 확장 내부 메모리 값이며 `summarize(durations: [TimeInterval]) -> TimeInterval`를 순수 함수로 분리한다. synthetic duration만 테스트에 사용한다.

- [ ] RED: Report 전용 테스트 번들 `ReportTests/UsageSummaryTests`에 빈 입력의 빈 상태, 합성 60+120초의 180초 합계, 로딩과 빈 상태 구분을 작성한다. U의 filter를 `-only-testing:ReportTests/UsageSummaryTests`로 바꿔 실패를 확인한다.
- [ ] 구현: Report extension/scene과 SwiftUI 목록을 작성한다. 시스템 데이터는 async 순회하고 앱 이름·사이트·사용량은 Report 메모리와 화면에만 둔다. 본체는 데이터 회신용 callback/파일/URL scheme을 제공하지 않는다.
- [ ] GREEN: 같은 Report 테스트와 simulator build를 통과시킨다. 실기기 보고서의 표시·갱신 지연은 Task 5에서 확인한다.
- [ ] 검증: Report 소스에 App Group, SwiftData, 파일 쓰기, 데이터 로그, 네트워크 호출이 없는지 검토한다. `rg -n 'UserDefaults|FileManager|ModelContext|URLSession|print\(|Logger' Report`는 결과 없음이 기대값이며, 이것만으로 완전한 보안 검토를 대신하지 않는다.
- [ ] 커밋: Task 4 파일을 stage하고 `git commit -m "feat: render private device activity report"`를 실행한다.

## Task 5: 실기기 인수 검증

**Files:** Create `docs/qa/screen-time-device-matrix.md`; 실패 시 해당 소스/테스트만 수정한다.

**Interfaces:** 앞선 Task의 공개 인터페이스를 그대로 사용한다. 검증표는 기기·OS·브라우저 버전, 시나리오, 기대/실제, 해제 지연, 통과/실패/미검증을 기록한다. 도메인 이름·개인 사용량은 증거 파일에 포함하지 않는다.

- [ ] 선행 확인: 승인된 Team/App Group/bundle ID와 세 타깃 개발 서명을 확인한다. `security find-identity -v -p codesigning`의 0건 상태가 해소되지 않으면 실기기 빌드 단계는 blocker로 기록한다. 배포 심사를 개발 테스트의 대체 증거로 쓰지 않는다.
- [ ] 전체 검증: U와 UI/Report 테스트를 한 번씩 통과시킨다. 실기기 명령은 `xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -destination "platform=iOS,id=$DEVICE_ID"`이며 기대값은 `BUILD SUCCEEDED`이다. `-allowProvisioningUpdates`로 계정 설정을 자동 변경하지 않는다. 설치·실행은 승인된 개발 서명으로 Xcode에서 수행한다.
- [ ] 실기기 세션 검증: 거절/철회, 강제 종료, 잠금, 실제 25분 만료, 재실행과 기기 재시작, 자정·시간대·시계 변경, 연속 시작·중복 종료를 수행한다. 예정/관측 해제 시각을 구분한다. 실패는 먼저 재현 테스트 RED를 추가한 뒤 수정하고 GREEN을 확인한다.
- [ ] 실패/경쟁 검증: DEBUG 전용 주입으로 register throw와 이전 UUID 지연 콜백을 전달하고 롤백 및 현재 세션 유지 여부를 확인한다. 이는 실제 OS 실패/지연 발생의 증거와 구분한다. 주입 기능은 Release에 포함하지 않는다.
- [ ] 웹 검증: Safari 일반/비공개 탭에서 선택/미선택 사이트와 동일 도메인의 다른 경로를 확인한다. 합성 50/51 검증과 실제 Picker 선택 결과를 분리한다. 다른 브라우저/WKWebView는 OS별 별도 표에 실제 결과만 기록한다. 전체 우회 방지나 경로별 차단을 완료 조건으로 만들지 않는다.
- [ ] 개인정보/배포 검토: Report 경계와 앱 내부 토큰 저장을 재검토한다. App/Monitor/Report 각각의 배포 entitlement 심사 상태를 미신청/심사 중/승인으로 분리해 기록하며 이 Task가 신청을 승인하지는 않는다.
- [ ] 커밋: 검증표와 검증 중 수정 파일만 stage하고 `git commit -m "test: document on-device screen time validation"`을 실행한다.

## 자체 검토와 인계

2026-10-26 문서 자체 검토를 완료했다. 선택·인증은 Task 1/3, ID·동시성·롤백·멱등·만료는 Task 2, 오늘 기록·시간 변경은 Task 3, 민감 데이터 경계는 Task 4, 필수 실기기 항목과 서명·배포 구분은 Task 5에 대응한다. Review Focus 5개 모두 해당 RED 단계나 실기기 검증에 연결했다. 공개 타입과 메서드 이름을 대조했고, 보고서 테스트는 App 테스트와 분리했다.

계획 작성 당시에는 환경 읽기와 두 문서 작성만 수행했다. 이후의 로컬 순차 구현 승인을 반영한 현재 상태는 아래 실행 결과와 구현 기록을 따른다. push·계정 변경·entitlement 신청·실기기 검증은 수행하지 않았다.


## 구현 승인 후 경로 전제 (2026-10-26)

로컬 순차 구현과 새 프로젝트·로컬 버전 관리 초기화가 승인되었다. 기존의 이번 턴 문서만 작성한다는 제한은 이 승인으로 해제되었다. FocusStudy는 여전히 임시 제품명이며 bundle ID와 App Group ID는 로컬 컴파일용 placeholder를 사용한다. 계정·서명 설정 변경, entitlement 신청, GitHub 생성·push·배포는 승인 범위 밖이다.


## 실행 결과 추적

Task 1~4의 로컬 구현을 완료하고 Task 5의 자동 검증을 수행했다. 실제 기기 인수 항목은 미실행이다. 순차 구현 뒤 독립 전체 검토 한 번을 수행했으며, 두 Important 복구 문제를 새 실패 테스트로 재현한 뒤 한 번의 수정 단계에서 처리했다. 실행 명령과 최종 결과는 README, `docs/implementation-ledger.md`, `docs/qa/screen-time-device-matrix.md`를 기준으로 한다. 원래 계획의 명령 U는 실제 구현에서 macOS SwiftPM 테스트와 iOS `FocusSDKTests`/`FocusUITests`로 나뉘었다.
