# FocusStudy Implementation Plan

> 초기 구현의 작업 분해 기록입니다.
> 체크박스는 당시 계획이며 현재 미완료 작업 목록이나 새 실행 승인이 아닙니다.
> 현재 파일·인터페이스는 소스에 맞춰 정정했으며, 실행 결과는 [구현 기록](../implementation-ledger.md), 남은 실기기 검증은 [검증표](../notes/screen-time-device-matrix.md)를 따릅니다.

**Goal:** 학생이 선택한 앱·웹사이트의 사용을 25분 동안 제한하고 오늘의 세션과 사용 보고서를 살펴보게 한다.

제품 범위와 동작 계약은 [설계](../specs/2026-10-26-focus-study-design.md), 작업 규칙과 소스 구조는 [AGENTS.md](../../AGENTS.md)를 기준으로 합니다.

## Review Focus

1. 잠금 경쟁과 이전 콜백: 이전 ID가 새 store를 지우지 않아야 한다(Task 2).
2. 중간 실패·프로세스 종료: preparing/ending을 복구하고 잘못된 활성 표시를 막아야 한다(Task 2).
3. 선택 경계: 0/50/51개, 카테고리·취소·세션 중 편집을 정확히 처리해야 한다(Task 1, 3).
4. 날짜·시간대·권한 변경: 시간과 오늘 기록을 재계산하고 철회 시 중단해야 한다(Task 2, 3).
5. 사용량 없음·저장 실패: 0 사용으로 단정하거나 terminal 기록을 잃지 않아야 한다(Task 3, 4).

## 파일 구조와 공통 실행 규칙

현재 파일 구성은 [소스 구조](../../AGENTS.md#architecture-and-ownership), 실행 명령과 테스트 타깃은 [README](../../README.md#실행과-검증)에서 관리합니다.
아래 인터페이스 링크는 구현된 선언을 가리키며, 초기 제안과 달라진 이유는 [구현 기록](../implementation-ledger.md)에 남아 있습니다.

## Task 1: 선택과 인증의 실행 가능한 기반

**Files:** Create `App/FocusStudyApp.swift`, `App/AuthorizationService.swift`, `App/SelectionRepository.swift`, `CoreTests/SelectionTests.swift`; 구현 승인 후 확정 경로의 Xcode 프로젝트와 세 타깃 설정.

**Interfaces:** [AuthorizationProviding / AuthorizationService](../../App/AuthorizationService.swift), [SelectionStoring / SelectionRepository](../../App/SelectionRepository.swift), [SelectionValidator](../../Shared/SelectionValidator.swift)를 따릅니다.
인증 요청은 오류를 내부에서 처리하고 `AccessStatus`를 노출하며, 선택 파일은 throwing initializer에서 읽습니다.

- [ ] RED: `SelectionTests`에 (0,0,0) 거절, (1,0,0)/(0,1,0)/(50,50,0) 허용, 51개 각각 거절, 저장 정책의 카테고리 1개 거절을 작성하고 실행한다.
      Picker의 카테고리 전체 선택은 개별 토큰으로 변환한 뒤 같은 개수 제한을 적용한다.
- [ ] 구현: 확정된 이름/경로에 본체와 Monitor/Report 타깃을 만들고 iOS 17 최소 버전·공유 scheme·테스트 번들을 설정한다. 선택은 앱 Application Support 내부 Codable 파일로 저장하며 실패 시 기존 파일을 유지한다. 개인 인증 adapter를 연결한다.
- [ ] GREEN: 해당 host/SDK 테스트와 README의 unsigned Simulator build를 통과시킨다.
- [ ] 검증: 세 제품 타깃의 Family Controls 설정을 검토한다. App Group은 App/Monitor만 공유하고 Report에는 부여하지 않는다. 계정/프로필 변경이 필요하면 별도 승인 절차로 남긴다.
- [ ] 커밋: 생성된 프로젝트·Task 1 파일만 stage하고 `git commit -m "feat: add authorization and private selection storage"`를 실행한다.

## Task 2: 경쟁과 실패에 안전한 세션 제어

**Files:** Create `Shared/ControlTypes.swift`, `Shared/SessionControl.swift`, `Shared/SharedControlStore.swift`, `Integration/ScreenTimeAdapters.swift`, `App/FocusModel.swift`, `Monitor/FocusMonitor.swift`, `CoreTests/SessionControlTests.swift`, `CoreTests/SharedControlStoreTests.swift`, `SDKTests/FocusModelTests.swift`, `Tests/Fixtures/ControlRaceHelper.swift`.

**Interfaces:** [ControlStore / LockedControl 및 SDK 경계 프로토콜](../../Shared/ControlTypes.swift), [SessionControl](../../Shared/SessionControl.swift), [SharedControlStore](../../Shared/SharedControlStore.swift)를 따릅니다.
잠금 콜백은 `LockedControl`의 명시적인 load/save를 사용하며, 선택 적용과 일치 검사는 start의 클로저로 전달합니다.
UI 조정은 [FocusModel](../../App/FocusModel.swift), 시작 복구는 [FocusRuntime](../../App/FocusRuntime.swift)과 [StartupRecovery](../../Shared/StartupRecovery.swift)가 담당합니다.

- [ ] RED: `SessionControlTests`에 1,500초 만료, 이른 콜백 무동작, A 종료 후 B 시작 뒤 A 콜백 무동작, 같은 종료 2회 무동작, 권한 철회/clockChanged 중단을 작성하고 실행한다.
- [ ] RED: `SessionControlTests`에 등록 throw 시 stop/clear 및 inactive, 등록 목록 불일치·shield readback 불일치·active 저장 실패 시 롤백, preparing/ending 복구, double start 거절을 작성한다. `SharedControlStoreTests`에는 잠금 timeout·손상 파일을 검사한다.
      실제 파일 교체 실패는 `SharedControlStoreTests.testAtomicReplacementFailurePreservesFileAndAllowsRetry`에서 변경 불가 파일을 사용해 재현하며 기존 바이트 보존, 잠금 해제와 재시도를 검사한다.
      제어 단계별 저장 실패는 `SessionControlTests`의 가짜 저장소에서 주입한다.
      가짜 저장 오류를 단계별 주입하며 오류 직후 active 표시가 없음을 assert한다.
- [ ] 구현: 설계의 시작/종료 순서를 그대로 연결한다. `flock` 획득부터 read/ID 비교/store 변경/파일 교체까지 같은 임계 구역에 둔다. 저장·정리 실패는 재시도 가능한 오류로 전달한다. 25분 비반복 날짜 구성요소 schedule을 만들고 monitoring을 UUID별로 중지한다. Monitor는 저장된 선택을 요구하지 않으며 늦은 start에서 shield를 재적용하지 않는다.
- [ ] GREEN: 제어·저장소 테스트와 README의 두 프로세스 경합 검증을 실행한다.
      helper는 합성 shield와 실제 파일 잠금을 사용하며 실기기 증거를 대신하지 않는다.
- [ ] 검증: 잠금 내부 `await` 부재, default store 사용 부재, 다른 activity 일괄 stop 부재를 검토한다. 중간 crash 각 지점의 재시작 결과를 테스트 표로 남긴다.
- [ ] 커밋: Task 2 파일을 stage하고 `git commit -m "feat: coordinate focus sessions across app and monitor"`를 실행한다.

## Task 3: 오늘 기록과 SwiftUI 흐름

**Files:** Create `App/SessionRecord.swift`, `App/FocusView.swift`, `HistoryTests/SessionRecordTests.swift`, `UITests/FocusFlowTests.swift`; Modify `App/FocusStudyApp.swift`, `App/FocusModel.swift`.

**Interfaces:** [SessionRecord / SessionHistory](../../App/SessionRecord.swift)와 [TimeRules](../../Shared/TimeRules.swift)를 따릅니다.
기록 반영·날짜·만료 계약은 설계에서 관리합니다.

- [ ] RED: `SessionRecordTests`에 terminal 재수입 시 1건, SwiftData save 실패 시 공유 terminal 유지, 자정·DST·시간대 변경의 오늘 필터, 남은 시간 1500/0 경계 및 재시작 시 재계산을 작성하고 실행한다.
- [ ] RED: `FocusFlowTests`에 권한 거절 후 설정 안내와 disabled start/report, Picker 취소 시 기존 선택 유지, active 중 편집 불가, 중도 종료 후 편집 가능을 가짜 adapter로 작성한다.
      UI 테스트는 README의 `FocusUITests` 타깃을 사용한다.
- [ ] 구현: 시작 준비·활성·오류·미사용 상태를 화면에 연결한다. Timer/TimelineView는 전경 표시 갱신에만 사용한다. `scenePhase.active`와 날짜/시간대/시계 변경 관측에서 reconcile·terminal import·오늘 쿼리를 수행한다. 실패를 숨기거나 완료로 세지 않는다.
- [ ] GREEN: README의 host 테스트와 iOS UI 테스트가 각각 성공하는지 확인한다.
      SwiftData는 in-memory container와 저장 실패 adapter로 검증한다.
- [ ] 커밋: Task 3 변경을 stage하고 `git commit -m "feat: show focus session flow and daily history"`를 실행한다.

## Task 4: 격리된 사용 보고서

**Files:** Create `App/UsageReportHost.swift`, `Report/FocusReport.swift`, `Report/UsageSummary.swift`, `ReportTests/UsageSummaryTests.swift`; Modify `App/FocusView.swift`.

**Interfaces:** [UsageReportHost / UsageReportContainer](../../App/UsageReportHost.swift), [FocusReportScene / ReportConfiguration](../../Report/FocusReport.swift), [UsageSummary](../../Report/UsageSummary.swift)를 따릅니다.
호스트와 확장은 `focus.today` 컨텍스트를 사용하며, 집계 결과는 optional total과 토큰별 행을 포함하는 확장 내부 구성으로 전달합니다.

- [ ] RED: SwiftPM의 `FocusReportLogicTests` 타깃에 속한 `UsageSummaryTests`에 빈 입력의 빈 상태, 합성 60+120초의 180초 합계, 로딩과 빈 상태 구분을 작성한다.
      README의 host 테스트 명령으로 확인한다.
      `UsageSummaryTests`는 데이터 없음과 실제 0을 구분한다.
      대기 안내와 빈 데이터·실제 0의 화면은 `FocusFlowTests`에서 실제 `UsageSummarySection` 및 보고서 호스트와 연결된 합성 fixture로 검사한다.
      실제 시스템 로딩 신호를 추정하거나 보고서 데이터를 본체로 전달하지 않는다.
- [ ] 구현: Report extension/scene과 SwiftUI 목록을 작성한다. 시스템 데이터는 async 순회하고 앱 이름·사이트·사용량은 Report 메모리와 화면에만 둔다. 본체는 데이터 회신용 callback/파일/URL scheme을 제공하지 않는다.
- [ ] GREEN: 같은 Report 테스트와 simulator build를 통과시킨다. 실기기 보고서의 표시·갱신 지연은 Task 5에서 확인한다.
- [ ] 검증: Report 소스에 App Group, SwiftData, 파일 쓰기, 데이터 로그, 네트워크 호출이 없는지 검토한다. `rg -n 'UserDefaults|FileManager|ModelContext|URLSession|print\(|Logger' Report`는 결과 없음이 기대값이며, 이것만으로 완전한 보안 검토를 대신하지 않는다.
- [ ] 커밋: Task 4 파일을 stage하고 `git commit -m "feat: render private device activity report"`를 실행한다.

## Task 5: 실기기 인수 검증

**Files:** Create `docs/notes/screen-time-device-matrix.md`; 실패 시 해당 소스/테스트만 수정한다.

**Interfaces:** 앞선 Task의 구현을 사용합니다.
시나리오와 증거 기록 형식은 [실기기 검증표](../notes/screen-time-device-matrix.md)에서 관리합니다.

- [ ] 선행 확인: 승인된 Team/App Group/bundle ID와 세 타깃 개발 서명을 확인한다. `security find-identity -v -p codesigning`의 0건 상태가 해소되지 않으면 실기기 빌드 단계는 blocker로 기록한다. 배포 심사를 개발 테스트의 대체 증거로 쓰지 않는다.
- [ ] 전체 검증: README의 자동 검증을 실행하고, 승인된 서명과 기기로 실기기 인수를 진행한다.
      자동 provisioning 변경이나 설치 권한을 이 계획에서 추론하지 않는다.
- [ ] 실기기 세션 검증: 거절/철회, 강제 종료, 잠금, 실제 25분 만료, 재실행과 기기 재시작, 자정·시간대·시계 변경, 연속 시작·중복 종료를 수행한다. 예정/관측 해제 시각을 구분한다. 실패는 먼저 재현 테스트 RED를 추가한 뒤 수정하고 GREEN을 확인한다.
- [ ] 실패/경쟁 검증: DEBUG 전용 주입으로 register throw와 이전 UUID 지연 콜백을 전달하고 롤백 및 현재 세션 유지 여부를 확인한다. 이는 실제 OS 실패/지연 발생의 증거와 구분한다. 주입 기능은 Release에 포함하지 않는다.
- [ ] 웹 검증: Safari 일반/비공개 탭에서 선택/미선택 사이트와 동일 도메인의 다른 경로를 확인한다. 합성 50/51 검증과 실제 Picker 선택 결과를 분리한다. 다른 브라우저/WKWebView는 OS별 별도 표에 실제 결과만 기록한다. 전체 우회 방지나 경로별 차단을 완료 조건으로 만들지 않는다.
- [ ] 개인정보/배포 검토: Report 경계와 앱 내부 토큰 저장을 재검토한다. App/Monitor/Report 각각의 배포 entitlement 심사 상태를 미신청/심사 중/승인으로 분리해 기록하며 이 Task가 신청을 승인하지는 않는다.
- [ ] 커밋: 검증표와 검증 중 수정 파일만 stage하고 `git commit -m "test: document on-device screen time validation"`을 실행한다.

## 실행 결과 추적

초기 구현과 후속 수정의 결정·실행 결과는 [구현 기록](../implementation-ledger.md)에 보존합니다.
과거 로컬 구현 승인은 새 커밋·push·서명 변경·실기기 작업을 승인하지 않습니다.
현재 검증 상태와 미실행 항목은 [검증 기록](../notes/screen-time-device-matrix.md)을 확인합니다.
