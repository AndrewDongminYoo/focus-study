# Screen Time 검증 기록

2026-10-26 초기 자동 검증 시점에는 실제 개인 앱·웹사이트의 제한을 적용하지 않았다.
모든 자동 테스트는 합성 데이터 또는 앱이 만든 기록만 사용했다.
이후 운영자의 실제 기기 확인 결과는 아래 후속 기록에 구분해 남긴다.

The Live Activity implementation adds an unsigned `.activity` product; earlier three-target signing evidence below does not cover it.
Its [feasibility record](2026-11-06-live-activity-feasibility.md) separates synthetic ActivityKit presentation from pending physical-device and iOS 17 release checks.

## 실행한 검증

아래는 2026-10-26 로컬 실행 당시 기록이며 현재 head를 재검증한 결과가 아니다.
명령과 suite 구성은 [README](../../README.md#실행과-검증)를 따르며, 현재 테스트 수는 새 실행 출력에서 확인한다.

| 환경/명령                                          | 범위                                                                                                                                | 관측 결과                      |
| -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------------ |
| macOS / Xcode 27.1 `swift test`                    | 제어·선택·날짜·시작 복구 32개, SwiftData 5개, 합성 Report 집계 4개                                                                  | 41개 통과, 실패 0개            |
| macOS `focus-control-race --verify`                | 생산 flock 구현을 사용하는 두 별도 프로세스의 새 시작/이전 콜백                                                                     | `PASS: stale A cannot clear B` |
| iPhone 18 Pro Simulator / iOS 27.0                 | SDK 인증 상태·schedule 3개, 선택 저장소 2개, 기록 오류와 세션 제어 분리 2개                                                         | 7개 통과                       |
| 같은 Simulator / DEBUG fixture                     | 거절 안내, 중도 종료 기록, 활성 중 선택 잠금, Picker 취소/저장, 등록 실패, 초기 저장소 실패 후 종료·재시도, 같은 날 보고서 새로고침 | 7개 통과, 실패 0개             |
| 서명 없는 Simulator 및 Release 기기 아키텍처 build | App/Monitor/Report 세 제품 타깃                                                                                                     | `BUILD SUCCEEDED`              |

시뮬레이터 결과를 실제 Screen Time 권한·보고서·차단 적용 증거로 사용하지 않는다. 시스템은 실제 기기에서 지연되거나 다른 동작을 보일 수 있다.

## 실제 기기 인수 검증: 일부 확인

| 시나리오                   | 기대 동작                                                | 상태                                                                                                                                     |
| -------------------------- | -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| 개인 권한 허용/거절        | 허용 후 선택 가능; 거절 시 설정 안내만 제공              | 허용 및 선택 진입은 운영자 확인; 거절은 미검증                                                                                           |
| 실제 앱 차단               | 선택한 앱에 시스템 제한 화면 표시                        | 운영자가 동작 확인; 해제 시점은 미검증                                                                                                   |
| 카테고리 전체 선택 저장    | 포함된 개별 앱·웹사이트를 저장                           | 기존 빌드 실패 제보 후, 수정 빌드 저장 성공을 운영자 확인                                                                                |
| 활성 중 권한 철회          | 관측 시 미사용/중단으로 전환하고 앱 소유 제한 정리       | 미검증                                                                                                                                   |
| 앱 강제 종료/잠금          | 시스템 monitoring 유지 여부와 해제 지연 관측             | 미검증                                                                                                                                   |
| 실제 25분 만료             | 예정 시각과 실제 정리 관측 시각 구분                     | 미검증                                                                                                                                   |
| 앱 재실행/기기 재시작      | preparing/ending/만료 상태 조정, terminal 기록 중복 없음 | 미검증                                                                                                                                   |
| 연속 시작/중복 종료        | 세션 중복 없음; 종료 멱등                                | 미검증                                                                                                                                   |
| 실제 등록 실패             | 활성 표시 없이 이 앱의 store/monitoring 롤백             | 미검증; 순수 제어 및 UI는 주입 실패로 검증                                                                                               |
| 이전 UUID의 지연 콜백      | 새 세션 제한을 해제하지 않음                             | 미검증; 두 프로세스 합성 경합은 통과                                                                                                     |
| 자정/시간대/수동 시각 변경 | 오늘 목록 갱신; 절대 만료 유지; 관측한 시각 변경은 중단  | 미검증; 순수 날짜 로직과 schedule 경계는 통과                                                                                            |
| 50/51개 실제 Picker 선택   | 최대 50개 허용; 51개는 기존 선택 유지                    | 2026-10-27 운영자가 앱·웹사이트 각각 세 항목 확인                                                                                        |
| Safari 일반/비공개 탭      | 선택/미선택 도메인, 동일 도메인의 여러 경로 확인         | iOS 27.0.1에서 일반 탭의 제한 안내·무한 로딩과 종료 후 복구를 운영자 보고; 같은 활성 세션·주소의 개인정보 보호 탭에서는 접속 가능을 확인 |
| Report 표시 및 갱신        | 현재 기기의 오늘 앱/웹 사용량이 확장 안에만 표시됨       | 운영자 스크린샷으로 앱별 사용량 표시 확인; 웹·갱신은 미검증                                                                              |
| 다른 브라우저/WKWebView    | OS·브라우저·기기별 실제 결과를 별도로 기록               | iOS 27.0.1의 Chrome에서 접속 가능을 운영자 보고; 동일 세션 조건·Chrome 버전·WKWebView는 미확인                                           |

실기기 준비 후 각 행에 실제 기기·OS·브라우저 버전, 예정/관측 시각, 통과/실패와 재현 절차를 추가한다. 도메인 이름·앱 선택 토큰·개인 사용량을 파일에 내보내지 않는다.

2026-10-27 운영자는 기존 설치 앱에서 앱과 웹사이트 각각 50개 저장, 51개 저장 거절, 취소 후 기존 50개 유지의 세 항목을 모두 확인했다고 응답했다.
이는 운영자가 보고한 결과이며, 에이전트가 실제 선택 개수를 별도로 캡처하거나 검사한 결과는 아니다.
운영자가 이어서 보고한 현재 iOS 버전은 27.0.1이며, 설치 바이너리의 정확한 커밋은 다시 확인하지 않았다.
브라우저별 차단은 아래 관측과 미확인 조건을 구분하며, 절차는 [Picker·브라우저 검증 계획](../plans/2026-10-27-picker-browser-device-acceptance.md)을 따른다.

같은 날 운영자는 사이트 A가 Chrome에서는 접속되지만 Safari에서는 무한 로딩 상태가 되고, 사이트 B는 Safari에서 제한으로 브라우징할 수 없다는 안내를 표시한다고 보고했다.
사이트명과 실제 주소는 기록하지 않는다.
사이트 B의 제한 안내와 사이트 A의 무한 로딩을 같은 성공 결과로 처리하지 않는다.
운영자는 제한 세션을 종료한 뒤 사이트 A의 로딩 불가도 해소됐다고 확인했다.
이는 세션 상태와 증상의 연관성을 보여주지만, 무한 로딩의 내부 원인이나 모바일 서브도메인과의 관계를 확정하지 않는다.
이어 운영자는 같은 활성 세션에서 일반 탭에 제한이 걸리는 주소를 새 개인정보 보호 탭에 직접 입력하고 새로고침해도 접속된다고 확인했다.
이 환경에서는 개인정보 보호 브라우징을 통한 접속을 막지 못한 것으로 기록한다.
미선택 사이트의 정상 접속과 동일 도메인의 여러 경로 비교는 아직 확인하지 않았다.
브라우저 앱 자체의 선택 여부와 Chrome·Safari를 동일한 활성 세션에서 비교했는지도 추가 확인이 필요하다.
현재 구현은 선택된 웹 도메인 토큰을 `shield.webDomains`에 전달하며, 호스트명이나 리디렉션을 직접 해석하지 않는다.

### Apple 공식 자료 확인: 2026-10-27

[ShieldSettings.webDomains](https://developer.apple.com/documentation/managedsettings/shieldsettings/webdomains-swift.property)는 선택한 도메인에 시스템 제한 화면을 적용하는 API로 설명되어 있다.
확인한 문서에는 개인정보 보호 브라우징을 제한에서 제외한다는 계약이 명시되어 있지 않다.
[STWebpageController.suppressUsageRecording](https://developer.apple.com/documentation/screentime/stwebpagecontroller/suppressusagerecording)은 웹 사용 기록·보고를 중단하는 속성이며, 제한을 해제하는 속성으로 설명되지 않는다.
[WKWebViewConfiguration.showsSystemScreenTimeBlockingView](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/showssystemscreentimeblockingview)는 시스템 제한 화면 표시 여부를 설정하며 기본값은 참이다.
이 자료만으로 Safari 개인정보 보호 탭이나 Chrome의 이번 접속 결과가 의도된 예외인지, OS 또는 브라우저의 결함인지 확정할 수 없다.
따라서 이번 결과를 Apple이 보장하는 정상 동작으로 분류하지 않고, 실기기에서 재현한 제한 공백으로 기록한다.
모바일 서브도메인이 무한 로딩을 유발한다는 가설도 미확인으로 유지한다.

## 서명과 배포

아래 항목은 최초 검증 당시의 상태다.
현재 개발 서명·설치 확인 결과는 [개발 프로비저닝과 설치 완료](#개발-프로비저닝과-설치-완료-2026-10-26)를 따른다.

- 개발 서명: [초기 환경 확인](../specs/2026-10-26-focus-study-design.md#환경-확인과-선행-조건)의 관측은 과거 기록이다.
  실기기 작업 전에 현재 identity와 profile을 다시 확인하며 계정 가입 여부를 추정하지 않는다.
- 개발 Team과 확정된 식별자는 [기기 준비 안내](../../README.md#실제-기기를-연결하기-전)를 따른다.
- 기기 등록·적합한 개발 provisioning profile·Family Controls 개발 capability의 일치는 미확인이다.
- 당시 본체·Monitor·Report의 배포 entitlement는 신청하지 않았다.
  각 App ID의 배포 승인을 개발 빌드 가능 여부와 구분하며 [Apple 신청 안내](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)를 확인한다.
- 이 실기기 검증 단계에서는 계정·인증서·프로필·entitlement 변경이나 실제 제한 적용을 수행하지 않았다.
  GitHub 후속 작업 이력은 아래 PR 기록과 구분한다.

## PR #1 후속 검토

`8b3cd11`의 최초 hosted CI 성공은 당시 기록이며 현재 PR 상태를 뜻하지 않는다.
후속 지적과 수정 근거는 [검토 기록](independent-review.md#github-후속-코드-리뷰), 실행 순서는 [구현 기록](../implementation-ledger.md)에 남긴다.
로컬 후속 결과는 위 표를 기준으로 하고, 새 head의 hosted 결과는 해당 PR checks에서 확인한다.

## 백로그 후속 준비: 2026-10-26

운영자가 개발 Team `393JTTV68D`와 bundle ID `kr.donminzzi.focusStudy`를 선택했다.
확장은 `.monitor`와 `.report`, App Group은 `group.kr.donminzzi.focusStudy`로 소스 설정에 반영했다.
현재 개인 Team의 개발 identity와 연결된 iPhone 16 Pro(iOS 27.0.1, Developer Mode 활성)를 읽기 전용으로 확인했다.
로컬 프로필 검사에서는 이 앱의 Family Controls·App Group을 포함한 개발 프로필을 찾지 못했다.
와일드카드 프로필은 이 capability의 준비 증거로 사용하지 않는다.
이 시점에는 Apple 계정의 식별자 등록과 개발 프로비저닝, 실제 설치·실행·제한 적용을 완료하지 않았다.
후속 서명·설치 결과는 아래에 별도로 기록한다.
이 준비 기록은 위 실기기 인수 항목의 미검증 상태를 변경하지 않는다.

자동 프로비저닝 갱신 없이 수행한 서명 Debug 빌드는 기존 와일드카드 프로필의 Family Controls (Development) 누락과 App/Monitor의 App Groups 누락으로 실패했다.
개발용 App ID와 App Group 등록·연결, 적합한 개발 프로필 생성 또는 갱신이 필요하다.

후속 로컬 자동 검증은 `c25f60c`를 기반으로 한 미커밋 작업 트리에서 수행했다.

| 환경                                 | 검사한 범위                                             | 결과                                           |
| ------------------------------------ | ------------------------------------------------------- | ---------------------------------------------- |
| macOS / `swift test -j 2`            | core 33개, history 5개, report 4개                      | 42개 통과                                      |
| 별도 프로세스 경합 helper            | 생산 파일 잠금과 합성 SDK 경계                          | `PASS: stale A cannot clear B`                 |
| iOS 27.0 Simulator                   | SDK 10개, UI 10개                                       | 20개 통과                                      |
| 같은 Simulator의 최종 대기 fixture   | 보고서 공간 유지, 대기 안내, 0 사용량으로 오인하지 않음 | 대상 UI 테스트 통과, 캡처 확인                 |
| 서명 없는 Release 기기 아키텍처 빌드 | App/Monitor/Report                                      | 빌드 성공, 검사한 DEBUG 진단·fixture 표식 없음 |

이 결과는 실제 설치·권한·차단·콜백 전달·사용 보고서 데이터의 실기기 검증을 대신하지 않는다.

## 개발 프로비저닝과 설치 완료: 2026-10-26

운영자가 개인 Team `393JTTV68D`의 개발 프로필 생성·갱신을 승인한 뒤 `xcodebuild build -allowProvisioningUpdates`로 Debug 서명 빌드를 완료했다.
설치 대상은 `kr.donminzzi.focusStudy` 버전 `0.1`, 빌드 `1`이다.

- App·Monitor·Report의 서명을 `codesign --verify --deep --strict`로 확인했다.
- 세 타깃 모두 Team과 application identifier가 요청한 값과 일치하고 Family Controls 개발 entitlement 및 설치 대상 기기를 포함하는 개발 프로필을 사용한다.
- App과 Monitor의 서명에는 `group.kr.donminzzi.focusStudy`가 포함되며 Report에는 App Group이 없다.
- 서명된 entitlement 검사에서 Family Controls를 제거한 입력이 실패함을 확인한 뒤 실제 세 타깃의 값을 검사했다.
- `devicectl device install app`으로 iPhone 16 Pro에 설치했고, 해당 bundle ID만 조회해 설치된 버전 `0.1`과 빌드 `1`을 다시 확인했다.

기기에는 이 Debug 빌드를 남겼다.
이번 단계에서는 앱을 실행하거나 Screen Time 권한을 요청하거나 실제 앱·웹사이트 제한을 적용하지 않았다.
따라서 위 실기기 인수 시나리오는 계속 미검증이며, 개발 서명 성공은 배포 entitlement 승인이나 App Store 제출을 뜻하지 않는다.

## 운영자 기능 확인과 선택 오류: 2026-10-26

운영자가 설치된 앱을 직접 실행하고 권한 승인, 앱·웹사이트 선택, 실제 앱 차단 동작을 확인했다.
제공한 스크린샷에서는 카테고리의 모든 항목 선택 상태와 보고서의 앱별 사용량 표시를 확인했다.
개인 앱 목록과 사용량은 이 문서에 복사하지 않는다.
카테고리 안의 앱을 모두 선택하면 기존 저장 검증이 거절하는 오류를 제보받았다.
자동 테스트는 합성 토큰으로 저장 경계만 검사한다.
수정 후 실제 Picker 저장 성공은 2026-10-27 운영자가 별도로 확인했다.

수정 후 Simulator에서 SDK 15개와 UI 10개 테스트가 통과했다.
저장소 검사는 합성 토큰 보존, 재로딩, 50/51개 경계와 저장 거절 시 기존 파일 유지를 확인했다.
사용자 문구는 `user-facing-copy`에 따라 간결하게 바꾸고 기존 합니다체를 유지했다.
기존 개발 프로필로 Debug 빌드와 엄격한 서명 검사를 통과한 뒤, 같은 bundle ID로 iPhone에 덮어 설치했다.
설치 후 조회한 버전은 `0.1`, 빌드는 `1`이다.
에이전트는 업데이트한 앱을 실행하지 않았으며, 운영자가 직접 카테고리 전체 선택 저장 성공을 확인했다.

## 권한 중단 기록: 원인 미확인

2026-10-27 운영자는 스크린 타임 권한을 직접 끄지 않았는데 세션 기록에 “접근 철회로 중단”이 표시되었다고 알렸다.
현재 코드는 승인되지 않은 상태를 모두 같은 종료 사유로 기록하며, 화면의 시각은 중단 시각이 아닌 시작 시각이다.
앱 종료나 덮어 설치와의 인과관계는 확인하지 못했다.
운영자 요청에 따라 이번 PR에서는 원인을 미확인으로 남기며 권한 판정과 종료 사유를 변경하지 않는다.

## M2 쉬는 시간과 마감: 미검증

절차는 [M2 설계의 실기기 검증](../specs/2026-11-01-m2-break-pass-design.md#physical-device-verification)을 따른다.
이슈 #8, #9, #10이 해결될 때까지 실행할 수 없으며, 실제 제한 적용은 실행마다 운영자의 명시적 승인이 필요하다.
각 행에 기기, OS 버전, 예정 시각과 관측 시각을 기록한다.
Simulator와 DEBUG fixture 결과는 아래 행의 증거가 아니다.

| 시나리오                         | 기대 동작                                                                   | 상태   |
| -------------------------------- | --------------------------------------------------------------------------- | ------ |
| 쉬는 시간 시작                   | 대기 화면 후 shield가 사라짐; 시작 시각과 해제 시각 기록                    | 미검증 |
| 재차단: 앱 백그라운드, 잠금 해제 | 쉬는 시간 시작 후 3분에서 5분 사이에 shield 복귀                            | 미검증 |
| 재차단: 기기 잠금                | 쉬는 시간 내내 잠금 상태에서도 3분에서 5분 사이에 shield 복귀               | 미검증 |
| 재차단: 앱 강제 종료             | 쉬는 시간 중 강제 종료 후에도 3분에서 5분 사이에 shield 복귀                | 미검증 |
| 재차단 후 다시 집중하지 않음     | 앱 없이 마감에 제한 해제; 기록에 마감 초과 표시                             | 미검증 |
| 재차단 11분 후 다시 집중         | 앱을 백그라운드에 둬도 집중 종료 전 마감에 제한 해제; 기록에 마감 초과 표시 | 미검증 |
| 쉬는 시간 3번                    | 대기 15초, 30초, 60초; 네 번째 쉬는 시간 없음                               | 미검증 |
| 집중 15분 미만 남기고 재개       | focus activity 재등록 성공 여부와 실제 완료 시각                            | 미검증 |
| 쉬는 시간 중 권한 철회           | 종료 사유와 store 상태                                                      | 미검증 |

`intervalWillEndWarning(for:)`의 전달 지연, 과거 `intervalStart`로 15분 미만 남은 focus activity 재등록, 잠금 상태에서 Monitor의 선택 사본 읽기, 끝난 break activity가 `DeviceActivityCenter.activities`에 남는지, 자기 `intervalDidEnd(for:)` 안에서의 재등록, iOS 17 runtime은 모두 미검증이다.

## M3 매일 제한: 미검증

절차는 [M3 설계의 실기기 검증](../specs/2026-11-01-m3-schedule-layer-design.md#physical-device-verification)을 따른다.
이슈 #8, #9, #10이 해결될 때까지 실행할 수 없으며, 실제 제한 적용은 실행마다 운영자의 명시적 승인이 필요하다.
각 행에 기기, OS 버전, 예정 시각과 관측 시각을 기록한다.
Simulator와 DEBUG fixture(`--everyday-fixture blocking`) 결과는 아래 행의 증거가 아니다.

| 시나리오                            | 기대 동작                                                                         | 상태   |
| ----------------------------------- | --------------------------------------------------------------------------------- | ------ |
| 1. 범위 안에서 켜기                 | 매일 제한 선택의 shield가 바로 나타남                                             | 미검증 |
| 2. 풀어 두는 시간, 잠금 해제        | 시작에 shield가 사라지고 끝에 다시 나타남                                         | 미검증 |
| 3. 풀어 두는 시간, 잠금과 강제 종료 | 잠금 상태와 앱 강제 종료 후에도 2와 같은 시각에 바뀜                              | 미검증 |
| 4. 범위 끝과 다음 날 시작           | 범위 끝에 해제; 다음 날 앱 없이 범위 시작에 다시 제한                             | 미검증 |
| 5. 매일 제한 중 집중 세션           | 두 선택이 모두 제한됨; 세션 종료 후 매일 제한 앱은 계속 제한됨                    | 미검증 |
| 6. 풀어 두는 시간 중 집중 세션      | 집중 앱은 계속 제한되고 매일 제한 앱만 풀림                                       | 미검증 |
| 7. 두 제한 중 쉬는 시간             | 두 선택이 모두 풀리고 재차단에 함께 돌아옴; 풀어 두는 시간 끝을 넘는 쉬는 시간도  | 미검증 |
| 8. 제한 중 느슨한 편집              | 끄기, 앱 빼기, 풀어 두는 시간 늘리기는 거절; 앱 추가는 바로 제한                  | 미검증 |
| 9. 각 store에 50개                  | DEBUG 진단으로 두 store에 50개씩 적용; 실제로 제한된 앱 기록                      | 미검증 |
| 10. 범위 중 기기 재시작             | 첫 잠금 해제 전후의 제한 상태                                                     | 미검증 |
| 11. 범위 중 시간대 변경             | 제한 상태와 다음 경계                                                             | 미검증 |
| 12. 제한 중 권한 철회               | store 상태와 `DeviceActivityCenter.activities`                                    | 미검증 |
| 13. 범위 끝 뒤 등록 목록            | 매일 제한 activity가 계속 목록에 남는지                                           | 미검증 |
| 14. 같은 분의 경계                  | 범위와 등교 시간이 같이 시작하고 두 시간이 맞닿을 때 등록 오류, 콜백, shield 상태 | 미검증 |

두 명명된 store의 합집합, 50개 한도가 store별인지 앱별인지, 반복 activity 콜백의 전달 시각, 구간 사이에 activity가 목록에 남는지, 시간대·수동 시각 변경, 재시작 후 첫 잠금 해제 전 `everyday-layer.json` 읽기, 콜백 안의 `startMonitoring`과 `stopMonitoring`, 같은 분 경계의 "too tightly scheduled" 여부, iOS 17 runtime은 모두 미검증이다.

## M4 집중 모드 필터: 미검증

절차는 [M4 설계의 실기기 검증](../specs/2026-11-01-m4-focus-filter-design.md#physical-device-verification)을 따른다.
이슈 #8, #9, #10이 해결될 때까지 실행할 수 없으며, 실제 제한 적용은 실행마다 운영자의 명시적 승인이 필요하다.
긴급·재난 알림을 일부러 발생시키지 않으며 긴급 구조 요청을 시험에 쓰지 않는다.
각 행에 기기, OS 버전, 집중 모드를 바꾼 시각과 관측 시각을 기록한다.
Simulator와 DEBUG fixture(`--focus-filter-refusal`) 결과는 아래 행의 증거가 아니다.

| 시나리오                             | 기대 동작                                                                      | 상태   |
| ------------------------------------ | ------------------------------------------------------------------------------ | ------ |
| 1. 필터 추가                         | 필터 목록에 FocusStudy가 있고 스위치 하나가 꺼진 상태로 나타남                 | 미검증 |
| 2. 앱 강제 종료 후 집중 모드 켜기    | 세션 시작 여부와 시각, 앱이 앞으로 오는지, shield 표시                         | 미검증 |
| 3. 잠금 상태와 예약 집중 모드        | 2와 같은 결과                                                                  | 미검증 |
| 4. 집중 모드 끄기                    | shield가 사라지는 시각; 기록에 "집중 종료"                                     | 미검증 |
| 5. 집중 모드를 켜 둔 채 종료 후 반복 | 필터 편집과 재시작의 `perform()` 호출 기록(DEBUG 호출 기록); 두 번째 세션 없음 | 미검증 |
| 6. 직접 시작한 세션 중 켜고 끄기     | 세션이 계속됨; 설정에 `busy` 거절 표시                                         | 미검증 |
| 7. 제한한 앱의 알림                  | 집중 모드에서 허용했을 때와 허용하지 않았을 때 알림 표시 여부                  | 미검증 |
| 8. 허용한 사람                       | 메시지와 카카오톡의 전화·메시지; 허용하지 않은 사람의 반복 전화                | 미검증 |
| 9. 허용한 앱과 시간 민감 알림        | 허용한 앱의 알림; 시간 민감 알림 설정을 켰을 때와 껐을 때                      | 미검증 |
| 10. 긴급                             | 긴급 우회 연락처의 전화; 기기의 긴급 알림 설정 기록(바꾸지 않음)               | 미검증 |
| 11. 권한 철회 후 켜기                | 설정에 `access` 거절 표시                                                      | 미검증 |
| 12. 집중 모드 전환과 빠른 끄고 켜기  | 호출 순서와 최종 상태                                                          | 미검증 |
| 13. `current` 읽기                   | 집중 모드가 꺼졌을 때와 켜졌을 때의 값이나 오류(DEBUG 진단)                    | 미검증 |
| 14. 첫 잠금 해제 전 예약 집중 모드   | `perform()` 실행 여부와 저장된 거절                                            | 미검증 |

제한한 앱의 알림 표시, 백그라운드 `perform()`의 실행·지연·반복과 빠른 호출 순서, 백그라운드에서 `DeviceActivityCenter` 등록과 `ManagedSettingsStore` 쓰기, 메신저별 허용한 사람, 긴급 알림 종류별 동작, Settings의 필터 표시, 꺼진 상태의 `current`, 집중 모드 직접 전환 시 값, 첫 잠금 해제 전 `perform()`, iOS 17 runtime은 모두 미검증이다.

## Start latency sample: 2026-11-05

On the iPhone 16 Pro with iOS 27.0.1 (`24A446`), the first measured accepted `FocusModel.start()` call in the installed diagnostic Debug build took 2,522.737 ms.
The timer started normally, and a subsequent break was confirmed on the phone.
This is one successful real-path sample, not a percentile, tap-to-render duration, or shield-delivery measurement.
See the [measurement record](2026-11-05-start-latency.md) for build identity and boundaries.
The new early-return operation and dedicated break screen remain unverified on a physical device.

## Start latency phases: 2026-11-10

On the same iPhone 16 Pro and iOS 27.0.1 (`24A446`), a signed Debug build from `fdf5b57` launched with `--screen-time-diagnostics` measured six accepted starts.
The focus activity registration took 2,313.355 to 2,323.773 ms and the focus shield write 41.537 to 42.445 ms; the start totals were 2,389.948 to 2,403.707 ms, with the first and repeated starts alike.
Every start reached a running session and was ended before the next one.
See the [measurement record](2026-11-05-start-latency.md#physical-device-phases-measured-on-2026-11-10) for the per-start table, the everyday registrations at launch, and the limits.

## Registration marker: 2026-11-10

On the same iPhone 16 Pro and iOS 27.0.1 (`24A446`), a signed Debug build from `2aba43c` (#105) launched with `--screen-time-diagnostics` measured every registration inside a lock section at 0.670 to 97.359 ms, three starts at 75.301 to 89.651 ms, four break requests at 37.212 to 62.784 ms, four automatic break starts at 98.570 to 108.688 ms, and a resume after the break end at 68.710 ms.
Two resumes with an early return took 2,426.931 and 2,429.035 ms; the wait sits at the stop of the break activity, which #107 takes up.
The break re-block about 3 minutes after the break start was confirmed outside the app.
A session end at its focus end and an everyday window end re-applying the everyday shield remain unverified with this build.
See the [measurement record](2026-11-05-start-latency.md#registration-marker-measured-on-2026-11-10) for the tables and the limits.

## 쉬는 시간 전환 지연 제보: 2026-11-08

iPhone 16 Pro, iOS 27.0.1 (`24A446`)에 `e3e9116`에서 만든 서명된 Debug 빌드를 설치해 직접 사용한 결과다.

- Live Activity와 Dynamic Island는 대체로 잘 동작했다.
- 집중 모드 필터("집중 모드 연결")가 iPhone 설정에 나타나는 것을 확인했다.
- `쉬는 시간 갖기`를 누르면 화면이 아무 변화 없이 잠시 멈췄다가 대기 화면("N초 뒤에 쉬는 시간이 시작돼요"와 진행 막대)이 나타났다.
  `다시 집중하기`도 같았다.
  멈춘 사이에 버튼을 다시 누르는 것도 막아 달라는 요청이 있었다.

쉬는 시간 전환의 기기 시간은 아직 재지 않았다.
이 기록은 위 세 가지 관찰만 남기며, 위 표의 다른 시나리오를 확인한 것으로 바꾸지 않는다.

## Access state: 2026-11-11

On the same iPhone 16 Pro with iOS 27.0.1, a signed Debug build from `fecb739` (#117) launched with `--screen-time-diagnostics` ran the [access-state design's device steps](../specs/2026-11-11-access-state-design.md#physical-device-verification) from 16:29 to 18:01 +09:00.
The history rows show the session start time, not the end time.

| Step                                                        | Result                                                                                                                                                                               |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 2 and 3. Break re-block with the app in the background      | Passed four times, twice after the app was not running for 5 minutes; the app logged nothing at the break ends, so the Monitor re-blocked                                            |
| 4. Everyday range end with no session                       | Passed: the everyday apps unlocked at 18:00, and the app on return logged no `register_everyday` and no `stop_everyday`                                                              |
| 5. Cold launch with access on                               | Passed twice: four `register_everyday` lines and no `stop_everyday` before them; the `checking` line did not appear                                                                  |
| 6. Cold launch after a revocation                           | The screen stayed in `checking` and never reached `denied`; a tap on start ran the recovery request, access was granted, and only then the session started                           |
| 7. Revocation during a break with the app in the background | Failed twice: a blocked app opened at once, and both sessions ended as `.recoveryInterrupted` ("중단된 세션 정리"); the Live Activity disappeared in one run and stayed in the other |

On iOS 27.0.1 a revocation in Settings reads `.notDetermined`, not `.denied`, in a running app process and in a cold launch, so step 7 cannot pass with the current design; #118 takes it up, and #115 stays open.
Reconciliation (2026-11-13, #118): the access-state design now accepts this result of step 7, a session that ends as `.recoveryInterrupted` after a revocation that reads `.notDetermined`, in [A real revocation](../specs/2026-11-11-access-state-design.md#a-real-revocation) and in the acceptance lines of its [physical-device verification](../specs/2026-11-11-access-state-design.md#physical-device-verification).
Every focus registration that overwrote a registered focus activity took 289.9 to 300.3 ms or 508.3 to 510.1 ms, while the first registration of a session took 19.6 and 36.7 ms; #119 takes it up.
The per-step evidence is in the #115 comments of 2026-11-11.

## 개인정보 경계와 배포 entitlement 검토: 2026-11-13

이슈 #17의 검토 결과다.
코드 항목은 `76d5058`의 소스를 읽어 확인했고, 실행하거나 기기에서 관찰한 결과가 아니다.
entitlement 신청이나 스토어 제출은 이 검토에 포함하지 않았다.

### Report 확장의 데이터 반출 경로

| 경로                | 결과                                                                                                                                                               |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| App Group           | 없음. `Configuration/Report.entitlements`에는 `com.apple.developer.family-controls`만 있고 `com.apple.security.application-groups`가 없다.                         |
| SwiftData           | 없음. `Report/`의 두 파일은 SwiftData를 import하지 않는다. `ModelContainer`는 `App/FocusRuntime.swift`와 DEBUG fixture에만 있고 `cloudKitDatabase: .none`을 쓴다.  |
| 파일·`UserDefaults` | 없음. `Report/`에는 `FileManager`, `UserDefaults`, `containerURL`, 파일 쓰기 호출이 없다.                                                                          |
| 로그                | 없음. `Report/`에는 `NSLog`, `print`, `os_log`, `Logger` 호출이 없다.                                                                                              |
| 네트워크            | 없음. `App`, `Shared`, `Integration`, `Monitor`, `Report`, `Presentation`, `Activity` 어디에도 `URLSession`이나 `URLRequest`가 없다.                               |
| 화면                | `FocusReportScene`이 사용 시간과 앱·웹 토큰을 `UsageSummaryView`로 그리는 것이 유일한 출력이다. 이 값은 확장의 화면 안에서만 쓰이고 앱 프로세스로 전달되지 않는다. |

### 선택 토큰의 저장 위치

| 파일                                   | 위치                                                          | 읽는 타깃    |
| -------------------------------------- | ------------------------------------------------------------- | ------------ |
| `selection.json` (집중 선택)           | 앱 컨테이너의 Application Support `PrivateSelection/`         | App          |
| 세션별 쉬는 시간 선택 사본             | App Group `group.kr.donminzzi.focusStudy`의 `SessionControl/` | App, Monitor |
| `everyday-layer.json` (매일 제한 선택) | 같은 App Group 디렉터리                                       | App, Monitor |

세 파일 모두 `.completeFileProtectionUntilFirstUserAuthentication`으로 쓴다.
`control.json`과 `registration-marker.json`에는 토큰이 없다.
Report와 Activity 확장은 App Group entitlement가 없어 이 파일들을 읽지 못한다.
토큰이 기기 밖으로 나가는 경로는 찾지 못했다: 네트워크 호출이 없고, 앱의 `NSLog` 호출은 모두 `#if DEBUG` 안의 진단 줄이다.
그중 `SCREEN_TIME_TIMING`, `SCREEN_TIME_PROBE`, `START_LATENCY`, `BREAK_LATENCY`, `END_LATENCY`는 작업 이름, 시간, 오류 설명만 기록한다.
`LIVE_ACTIVITY_PROBE`가 받는 메시지의 내용은 이 검토에서 줄 단위로 확인하지 않았다.

### 배포 entitlement 상태

2026-11-13 기준이다.

| App ID                                        | Family Controls 배포 entitlement | 근거                                                                                             |
| --------------------------------------------- | -------------------------------- | ------------------------------------------------------------------------------------------------ |
| App (`kr.donminzzi.focusStudy`)               | 미신청                           | 2026-11-13에 신청한 적이 없음을 확인했다.                                                        |
| Monitor                                       | 미신청                           | 위와 같다.                                                                                       |
| Report                                        | 미신청                           | 위와 같다.                                                                                       |
| Activity (`kr.donminzzi.focusStudy.activity`) | 해당 없음                        | `project.yml`의 `FocusActivity` 타깃에는 entitlements 파일이 없고 Family Controls를 쓰지 않는다. |

개발 빌드는 가능하다: 세 타깃의 Family Controls 개발 entitlement와 개발 프로필로 서명한 Debug 빌드를 2026-10-26부터 실기기에 설치해 왔다([개발 프로비저닝과 설치 완료](#개발-프로비저닝과-설치-완료-2026-10-26)).
이것은 배포 승인이 아니다: App Store나 TestFlight 배포에는 App, Monitor, Report 각 App ID의 배포 entitlement 승인이 따로 필요하며, 신청 절차는 [Apple 신청 안내](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)를 따른다.
