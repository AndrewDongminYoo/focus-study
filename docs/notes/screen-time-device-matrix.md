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

## Monitor timing: 2026-11-14

On the same iPhone 16 Pro with iOS 27.0.1 (`24A446`), a signed Debug build from `87f1103` launched with `--screen-time-diagnostics` ran the [Monitor timing design's device steps](../specs/2026-11-13-monitor-timing-design.md#physical-device-verification) from 14:47 to 15:22 +09:00.
The lines were read from `log collect` archives with the predicate of [Reading the lines](../specs/2026-11-13-monitor-timing-design.md#reading-the-lines).

| Step                                         | Result                                                                                                                                                                                                                                                                                                |
| -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2. Lines arrive                              | Passed: the session start at 14:47:31 gave a `didStart activity=focus` callback that found the lock busy, skipped on the registration marker and ended after 3.2 ms                                                                                                                                   |
| 3. Break re-block with the app in background | Passed twice (14:51:44, 15:08:16): the `willEndWarning activity=break` section took the lock at attempt 0 and held it for 59.3 and 65.9 ms (`apply_shield` 32.3 to 33.1 ms, `apply_everyday` 12.4 to 13.3 ms, `stop_break` 3.9 to 9.2 ms); the `didEnd` of the same second skipped on the stop marker |
| 4. Focus overwrites with the app in front    | The four focus callbacks right after a re-registration took 228.7 to 251.9 ms, of which the access read was 226.8 to 250.9 ms and the lock wait 0.6 to 1.4 ms; every other access read took 0.02 to 1.6 ms; the app's `SCREEN_TIME_TIMING op=register` lines were not in the archives                 |
| 5. Launch without the argument               | Passed: after the relaunch at 15:21:15 the Monitor ran until 15:21:44 and wrote no `MONITOR_TIMING` line; the last line, at 15:21:07, came from the session end before the relaunch                                                                                                                   |

Every access read in the Monitor returned `unknown`; only a `denied` read ends a session ([access-state design](../specs/2026-11-11-access-state-design.md#what-each-state-does)), and every session of the run continued.
`log collect` for an attached device needs root (`Must be root to collect logs from attached device`), and in zsh `log` is a shell builtin, so the command is `sudo /usr/bin/log collect …`.
The section hold time is measured for the break re-block section only; the other Monitor sections stay unmeasured.

## Focus overwrite wait: 2026-11-14

On the same iPhone 16 Pro with iOS 27.0.1, a signed Debug build from `ae5faf7` (#141, app timing lines through `Logger`) launched with `--screen-time-diagnostics` ran one session from 19:42:25 to 19:45:26 +09:00 with three break requests, three break starts and three resumes with the app in front.
The app and the Monitor lines came from one `log collect` archive.

| App call                          | App time       | Monitor callbacks in the same second                                                  |
| --------------------------------- | -------------- | ------------------------------------------------------------------------------------- |
| Session start, `register`         | 36.3 ms        | one `didStart activity=focus`, 0.5 ms                                                 |
| Break request, `register`         | 294.8–296.1 ms | `didEnd activity=focus` 0.3–0.5 ms, then `didStart activity=focus` 250.8–252.4 ms     |
| Break start, `register`           | 507.8–511.4 ms | `didEnd activity=focus` 228.5–229.8 ms, then `didStart activity=focus` 245.7–247.7 ms |
| Resume, `stop_break`              | 245.8–247.8 ms | `didEnd activity=break` 234.8–237.6 ms                                                |
| Resume, `register` after the stop | 506.4–509.3 ms | `didEnd activity=focus` 205.9–207.6 ms, then `didStart activity=focus` 246.3–246.7 ms |

Every slow callback spent 204.1 to 251.0 ms in its access read, waited 0.9 to 1.6 ms for a busy lock, and skipped on the registration or stop marker; the first callback of each call read access in 0.02 to 0.1 ms.
So the app's `startMonitoring` and `stopMonitoring` calls return only after the Monitor callbacks that they cause have returned, and each later callback waits about 0.25 s for the main queue in `ScreenTimeAccess.current()` before it skips.
The resumes took 1,114.1 to 1,115.5 ms in total (`BREAK_LATENCY action=resume`), above the 1,000 ms acceptance of #115; the break requests took 324.4 to 328.8 ms and the break starts 604.6 to 609.8 ms.
This is the source of the wait of #119.

## Focus overwrite wait after the early check: 2026-11-15

On the same iPhone 16 Pro with iOS 27.0.1, a signed Debug build from `62a1955` (#144, the busy probe before the access read) launched with `--screen-time-diagnostics` ran one session from 09:48:52 to 09:51:14 +09:00 with three break requests, three break starts and three resumes with the app in front.

| App call                          | 2026-11-14     | 2026-11-15     |
| --------------------------------- | -------------- | -------------- |
| Break request, `register`         | 294.8–296.1 ms | 41.7–43.4 ms   |
| Break start, `register`           | 507.8–511.4 ms | 24.8–25.3 ms   |
| Resume, `stop_break`              | 245.8–247.8 ms | 2.4–3.0 ms     |
| Resume, `register` after the stop | 506.4–509.3 ms | 17.9–26.3 ms   |
| Resume, `BREAK_LATENCY` total     | 1,114–1,116 ms | 105.2–120.3 ms |

Every one of the 31 Monitor callbacks found the lock busy at the probe (`attempt=probe`), skipped on the holder's marker with no `access` line, and took 0.13 to 1.25 ms.
The session start registration, which overwrites nothing, took 133.4 ms.
Every focus overwrite is below 100 ms, which is the done-when of #119.

## Streak and home screen widget: 2026-11-14

On the same iPhone 16 Pro with iOS 27.0.1 (`24A446`) and the same signed Debug build from `87f1103`, after the Monitor timing run.
The build was signed with `-allowProvisioningUpdates`, approved for that one build on 2026-11-14, because the development profile did not include the App Groups capability for `kr.donminzzi.focusStudy.activity`. It was installed over the existing app, and the history store kept its records from 2026-10-26.

| Check                                                                                   | Result                                                                                                                                                |
| --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| [Widget](../specs/2026-11-13-home-widget-design.md#physical-device-verification) step 1 | The added small widget showed the Empty view ("앱에서 시작해 보세요") while today had no completed session; the gallery preview was not recorded      |
| Widget step 2: a session completed with the app in front                                | Passed: after the completion at 15:50 the widget showed "25분 · 1회", the numbers of the app's today summary; the time to the change was not recorded |
| Widget step 3: a session completed with the app in the background and the device locked | Passed: after the unlock the widget still showed "25분 · 1회"; after the app was opened and closed it showed "50분 · 2회"                             |
| [Streak](../specs/2026-11-13-streak-design.md) in the history sheet                     | Passed: "오늘 집중 25분 · 1회" and "연속 집중 1일"; today's two early exits are listed and not counted                                                |
| Streak against the store                                                                | A copy of the store read with `sqlite3` has one `expired` record, today's, and no record on 2026-11-13, so 1 is the expected number                   |

The history store is `Library/Application Support/default.store` in the App Group container `group.kr.donminzzi.focusStudy`, read with `devicectl device info files --domain-type appGroupDataContainer`; `devicectl device copy from` with the same domain copied it.
Widget steps 5 to 7 (a Focus start, a restart, and the looks) remain unverified.
During step 3, just after the switch to dark mode, the Live Activity on the Lock Screen appeared to show a light background for a moment, a screenshot taken then was white, and the card then turned dark. The observation is uncertain, the cause was not checked, and it is not recorded as a failure.

Around midnight from 2026-11-14 to 2026-11-15, with the app not opened:

- Widget step 4: the widget, which showed "50분 · 2회" on 2026-11-14, showed the Empty view ("오늘 집중", "앱에서 시작해 보세요") around midnight and still showed it later. No number of the earlier day was seen; the exact minute of the change was not recorded, so the 00:00, 00:01 and 00:05 readings of the plan are not separately recorded.
- Usage report (#14), date change: opened just after midnight, the report showed the new day, with 온:공 at 0분; the "no data" notice did not appear, because the report had a row. The notice for missing or late data remains unverified on the device.

## Usage report: closed on 2026-11-15 (#14)

On the iPhone 16 Pro with iOS 27.0.1 and the signed Debug builds of `87f1103` and `ae5faf7`, the usage report was opened on 2026-11-14 and again just after midnight on 2026-11-15.

| Item of #14                     | Result                                                                                                                                                                                                                                                                                    |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Today's report on the device    | Verified: it showed at once, inside the extension, with no visible wait                                                                                                                                                                                                                   |
| Date change                     | Verified: after midnight the report showed the new day                                                                                                                                                                                                                                    |
| Reload on the same day          | Verified on 2026-11-15: the reload button left the area blank for a moment while the extension drew the recreated content (`.id(refreshID)` in `App/UsageReportHost.swift`), and the notice below it stayed; closing and reopening the screen showed the earlier content without a redraw |
| Notice for missing or late data | Not seen on the device and accepted as unverified there: the report lists 온:공 itself from 0분 on, so a day with no row is rare; `testReportWaitingDoesNotClaimZeroUsage` and `testEmptyReportShowsUnavailableInsteadOfZero` cover both notices in the simulator fixture                 |

No usage value, app name or domain is recorded here.
Decided on 2026-11-15: #14 closes with this record, and the notice for missing or late data stays covered by the simulator fixtures only.

## Injected registration failure, earlier callback and repeated taps: 2026-11-15 (#16, #11)

On the same iPhone 16 Pro with iOS 27.0.1, a signed Debug build from `62a1955` launched with `--screen-time-diagnostics` at 13:53 +09:00.
The history rows come from a copy of the device store read with `sqlite3`; the timing lines come from one `log collect` archive.

| Step                                                                            | Result                                                                                                                                                                                                                                 |
| ------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "다음 등록 후 실패 주입", then start (#16)                                      | Passed: an error notice, no timer screen, and the selected apps stayed open; the app logged `register` (94.1 ms) and then `stop` (11.6 ms) in the same second with no `apply_shield`, and the history row is `startFailed` at 13:53:32 |
| Session A, "현재 세션 콜백 저장", end A; session B, "이전 세션 콜백 전달" (#16) | Passed: A ran 13:54:08–13:54:29, B started at 13:54:36 and kept its restrictions until it was ended by hand at 13:55:05, with no `stop` between; both rows are `earlyExit`, and the sheet shows them under the same start minute       |
| Start tapped twice quickly, end and its confirmation tapped twice quickly (#11) | Passed: one `register` at 13:55:46, one `stop` at 13:55:53, and one `earlyExit` row                                                                                                                                                    |

The registration failure is injected by the DEBUG path of #15, not a failure that the system produced; no natural registration failure or late callback of an earlier session was observed on the device, so those stay unverified.
The replay of the earlier callback runs the engine in the app process, so it has no Monitor line.

## Picker selection limit: 2026-11-15 (#13)

On the same device and build, with no session and with an everyday layer that already had apps selected, the focus selection was edited with individual apps only, no category and no website.

| Step                                                                        | Result                                                                                                                               |
| --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| 50 focus apps that, with the everyday apps, made more than 50 apps together | Refused with "집중 시간과 매일 제한을 합쳐 앱은 50개까지 고를 수 있어요.", as the union rule of `SelectionValidator.unionLimit` says |
| 50 apps together, two of them shared with the everyday selection            | Saved                                                                                                                                |
| One more app, 51 together                                                   | Refused, and the saved selection stayed as it was                                                                                    |

The limit for websites and the per-category counting were not checked on the device. Safari and other browsers remain open in #13.

## Focus filter, force-quit, real expiry and web blocking: 2026-11-15 (#55, #11, #13, widget)

On the same device and build, from 14:11 to about 15:05 +09:00, with the Work Focus.
Focus changes come from `donotdisturbd` (category `AppFocusConfiguration`) in `log collect` archives; session times come from a copy of the device store.
The app was reopened from the Home Screen at about 14:30, which removed the timing flag, so later steps have no app or Monitor timing lines.

| Step                                                      | Result                                                                                                                                                                                                                 |
| --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| M4 step 1: the filter in Settings > Focus > Work          | Listed as 온:공 with the filter switch "집중 시간" (its description below it) and one option, "집중 시작"; both were turned on                                                                                         |
| M4 steps 2 and 3: Focus on with the app not in front      | Failed: at 14:12:58 and 14:15:13 the system logged `No extension for action in app; background update unavailable`, `perform()` did not run, no session started and no refusal was stored; #152 takes it up            |
| Focus on with the app in front                            | A session started at once (14:24:35, and again at 14:34:30)                                                                                                                                                            |
| Force-quit during the session, then lock and unlock (#11) | Passed: the Live Activity kept counting, every app of the focus selection stayed shielded, and the reopened app showed the running session                                                                             |
| Safari (#13), with youtube.com in the focus selection     | Passed: youtube.com and every path under it were blocked in normal and private tabs; apple.com, not selected, opened                                                                                                   |
| Other browsers (#13)                                      | Not blocked: youtube.com opened in Chrome and in Firefox for iOS; this is recorded as a limit of the web domain shield in those browsers                                                                               |
| Notifications (M4 step 7, partial)                        | A shielded app showed no notification; an app allowed in the Work Focus delivered its notifications silently                                                                                                           |
| Real 25-minute expiry with the app not running (#11)      | Passed: the session that started at 14:34:30 had its planned end at 14:59:30; the Monitor ended it with `observedAt` 14:59:33 and the apps opened at about 15:00; the row `expired` appeared when the app was opened   |
| Focus off at 15:01:18 with the app not running            | No `perform()` call, as above                                                                                                                                                                                          |
| Widget and Live Activity before the app ran               | The widget kept the Empty view and the Live Activity kept its confirmation state; after the app was opened, the widget showed the completed session, the Live Activity ended, and the history sheet showed "25분 완료" |
| Widget step 7: looks                                      | Passed in dark mode, the tinted Home Screen, the largest text size and StandBy                                                                                                                                         |

#13 closes with the Picker record above and this record: Safari blocks the selected domain and its paths in both tab types, and Chrome and Firefox do not block it on this device and OS.
Widget step 5 (a Focus start with the app closed) cannot run until #152 is resolved.

## Focus changes with the app in front, `current`, and access: 2026-11-15 (#55, #11)

On the same device and build, relaunched with `--screen-time-diagnostics` at 15:08:38 +09:00, every Focus change made from Control Center with the app in front.
Focus changes come from `donotdisturbd` in a `log collect` archive; session rows come from a copy of the device store.

| Step                                                             | Result                                                                                                                                                                                                                                                                                                      |
| ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| M4 step 6: a session from the start button, then Work on and off | Passed: the session started at 15:09:14 kept running through Work on (15:09:19) and off (15:09:30) and was ended by hand at 15:09:53                                                                                                                                                                        |
| M4 step 12: direct switches and quick changes                    | Each switch from Work to Personal Time or Do Not Disturb, and each Work off, ended the session at once; each switch back to Work started a new one (sessions 15:10:00–15:10:13, 15:10:32–15:10:56, 15:11:01–15:11:30, 15:11:40–15:12:35, 15:13:21–15:13:44); every one of them is `earlyExit` ("집중 종료") |
| M4 step 13: `current` from the diagnostics                       | `off` with the Focus off and `on` with Work on                                                                                                                                                                                                                                                              |
| M4 step 11: Work on with access revoked in Settings (15:14:53)   | Passed: no session started; the timer screen kept "스크린 타임 권한을 확인하고 있어요. 시작하면 다시 확인해요." and the Focus filter diagnostics showed the refusal `access`                                                                                                                                |
| #11: deny, then allow                                            | A tap on start showed the system request; after a denial an error notice showed for a moment and the screen went back to the checking line; a second request that was allowed started a session                                                                                                             |

The denial does not leave its notice on screen, because a denial on iOS 27 reads `.notDetermined`; #38 takes up the notice and the settings path.
Unchecked in M4: steps 5, 8, 9, 10 and 14, and step 7 beyond the partial record above.

## Restart with a running session: 2026-11-15 (#11, widget, #55)

On the same device and build, a session was started from the app at about 15:57:53 +09:00, a one-time Work Focus schedule was set for 16:05 to 17:00, and the device restarted (`=== system boot` at 16:00:24, first unlock at 16:01:14 by `analytics_send_first_unlock`, both from one `log collect` archive).
An earlier boot at 15:55:53 (first unlock 15:56:21) is in the same archive.

| Check                                        | Result                                                                                                                                                                                                                                    |
| -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Shield through the restart (#11)             | Passed: after the unlock every app of the focus selection was still shielded                                                                                                                                                              |
| Live Activity before the first unlock        | Not shown on the Lock Screen                                                                                                                                                                                                              |
| Widget step 6                                | After the unlock the widget showed "25분 · 1회", the completed session of the day                                                                                                                                                         |
| App after the restart (#11)                  | Failed: a `FocusStudy` process started at 16:00:40, before the first unlock; opening the app at about 16:10 showed "앱 데이터를 확인해 주세요"; "다시 확인하기" restored the running session with about 12 minutes left; #155 takes it up |
| M4 step 14: a Focus schedule after a restart | Inconclusive: the Work schedule did not turn the Focus on at 16:05, before or after the unlock, and the schedule still showed as never triggered; with the app not in front the filter would not run anyway (#152)                        |

The earlier boot shows the cause of the failure: its pre-unlock process logged `Failed to fetch authorization status: ... Code=257` for `Authorizations.plist`.

#11 closes with the records of 2026-11-15: allow, deny and revoke; force-quit and lock; a real 25-minute expiry with its planned and observed times; a relaunch and a restart; repeated start and end taps with one record each.
The preparing and ending states were not forced on the device, and their recovery stays covered by the host and simulator tests only.
Reconciliation (2026-11-15): the store copy of round 6 shows that the restarted session started at 15:59:12, not at about 15:57:53 as written above, and that it expired normally: planned end 16:24:12, `observedAt` 16:24:15, reason `expired`.

## Time zone and manual clock changes: 2026-11-15 (#12)

On the same device and build, with "자동으로 설정" turned off in Settings > General > Date & Time; session rows come from a copy of the device store.

| Step                                                                                       | Result                                                                                                                                                                                                 |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| A session from 16:35:01 (planned end 17:00:01), time zone to Singapore, then back to Seoul | Passed: the session kept running, the remaining time neither grew nor shrank, and the planned end stayed 17:00:01; it was ended by hand at 16:39:11 (`earlyExit`)                                      |
| The end time shown during the Singapore time zone                                          | Still "5:00" in Seoul time. The timer screen shows only the remaining time, so this is most likely the Live Activity, which keeps its rendered time until the app sends an update; not checked further |
| A session from 16:39:35, then the clock set 10 minutes ahead by hand                       | Passed: the Live Activity countdown dropped at once, and the app showed the session ended as `clockChanged` ("시각 변경으로 중단") at 16:50:26 device time                                             |

The session across local midnight is recorded in its own section below.
The date and time settings were set back to automatic after these checks (reported on 2026-11-15).

## Restart after the pre-unlock fix: 2026-11-15 (#155)

On the same iPhone 16 Pro with iOS 27.0.1, a signed Debug build from `8794caa` (#158) was installed over the existing app at 18:15 +09:00 and opened from the Home Screen, with no diagnostics argument; a session was started and the device restarted.
From one `log collect` archive: `=== system boot` at 18:18:22, a `FocusStudy` process (pid 247) at 18:18:36 with no user action, `Failed to fetch authorization status: ... Code=257` for `Authorizations.plist` in that process at 18:18:38, and the first unlock (`analytics_send_first_unlock`) at 18:20:20.
After the unlock the app opened on the running session with no "앱 데이터를 확인해 주세요" screen, in the same process that had started before the unlock.
This is the condition of the failure recorded above (a launch before the first unlock that cannot read protected files), and it no longer shows the failure screen, which is the done-when of #155.

## Session across local midnight: 2026-11-15 to 2026-11-16 (#12)

On the same iPhone 16 Pro with iOS 27.0.1 and the signed Debug build from `8794caa`, with the date and time set to automatic in the Seoul time zone, a 25-minute session was started before midnight and left to run without a break.
Session times come from a copy of the device store taken at 00:07 on 2026-11-16; the other results were observed on the device.

| Check                             | Result                                                                                                                                            |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Expiry across midnight            | Passed: started 2026-11-15 23:42:03, planned end 2026-11-16 00:07:03, `observedAt` 00:07:05, reason `expired`; every restricted app was unblocked |
| Today's history after midnight    | Passed: the sheet on 2026-11-16 showed no session, because a session belongs to the local day of its start                                        |
| Home screen widget after midnight | Passed: Empty, since 2026-11-16 has no completed session; the widget was not checked before midnight                                              |
| Streak after midnight             | Passed: "연속 집중 2일"; the store has completed sessions on 2026-11-14 and 2026-11-15 and none on 2026-11-16, so the run ends yesterday          |

With the time zone and clock checks above, this covers the done-when of #12.

## Focus filter extension: first run 2026-11-16, stopped (#152)

The device steps of the [extension design](../specs/2026-11-16-focus-filter-extension-design.md#physical-device-verification).
On the iPhone 16 Pro with iOS 27.0.1, a signed Debug build of `aa1b47e` (#166) was installed over the existing app at 19:08 +09:00 with `devicectl device install app`; `-allowProvisioningUpdates` created the development profile of `kr.donminzzi.focusStudy.intents`, approved for this build, and the signed extension carries only the App Group and `com.apple.developer.family-controls`.
The app was opened once and closed; then, with the app not running, the Work Focus with the filter option on was turned on at 19:13:48 and off at 19:14:14.
The results below come from one `log collect` archive; the values on screen were not reported.

| Step                                                                                    | Result                                                                                                                                                                                                                                        |
| --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. Which process runs each call, with the app running and closed                        | App closed: the extension ran both calls (`donotdisturbd`: `Failed to find process state for application bundle; will use extension if available`, then `Executing prepared action on kr.donminzzi.focusStudy.intents`). App running: not run |
| 2. App closed, Focus on: a session starts and the selection is shielded                 | The extension set `shield.applications` and `shield.webDomains` at 19:13:49; the store is in the container `kr.donminzzi.focusStudy.intents` (see below). The shield on screen was not reported                                               |
| 3. App closed, Focus off before the base length: `.earlyExit`                           | The extension cleared its `focusSession` store at 19:14:14. The end reason was not read: the record waits for the app's next import, and `SessionControl/` cannot be copied from the device                                                   |
| 4. Focus on past the base length: a rollover, restrictions stay                         | Unverified                                                                                                                                                                                                                                    |
| 5. Focus off after a rollover: `.expired` with the focused time, streak and widget      | Unverified                                                                                                                                                                                                                                    |
| 6. A break inside an open session, then Focus off during the break                      | Unverified                                                                                                                                                                                                                                    |
| 7. "집중 종료" during an open session, then Focus off and on starts a new session       | Unverified                                                                                                                                                                                                                                    |
| 8. Focus on before the first unlock after a restart                                     | Unverified                                                                                                                                                                                                                                    |
| 9. Live Activity: none while closed, appears on open, counts up past the base length    | Unverified                                                                                                                                                                                                                                    |
| 10. Migration over the current build keeps the selection and a 40-minute length         | Unverified                                                                                                                                                                                                                                    |
| 11. Call order: Focus on, then open the app and turn the Focus off within a second      | Unverified                                                                                                                                                                                                                                    |
| Whether an ended focus interval stays registered, so a lost rollover is not interrupted | Unverified                                                                                                                                                                                                                                    |

Finding that stopped the run: ManagedSettings keeps one store per container.
The app writes `focusSession` and `everydayLayer` in the container `kr.donminzzi.focusStudy`, and the extension wrote and cleared `focusSession` in the container `kr.donminzzi.focusStudy.intents`; the same store name is a different store.
So an end that the app or the Monitor runs for a session that the extension started (`집중 종료`, a break, a timed end) clears only its own container and leaves the extension's shield on.
`[UNCERTAIN]` Whether the DeviceActivity registration of the extension is visible to the app and reaches the app's Monitor. One sign that it does: `runningboardd` logged a `launch request for xpcservice<kr.donminzzi.focusStudy.monitor>` at 19:13:48.954, after `Invoking FocusStudyFilter.perform()` at 48.887 (the registration comes first in the start steps) and before the shield writes at 49.058. The Monitor logs nothing without its DEBUG timing flag, so the archive does not show which callback ran. If it is not visible, opening the app ends that session as `.recoveryInterrupted`, and the next Focus off finds no running session, so nothing clears the extension's shield.
That path was not run on purpose. The filter was removed from the Focus on the device the same evening, and nothing in the archive shows a shield left in either container: the extension wrote nothing to `everydayLayer` and cleared its `focusSession`.
The design needs an amendment so that only processes of the app container apply and clear shields (#152).

Probe the same evening, with a DEBUG build of `aa1b47e` plus a probe commit on the local branch `probe/152-extension-monitor`, which is not pushed, installed over the app and launched with `--screen-time-diagnostics --filter-probe on`.
While the probe flag exists, a Focus filter call in either process registers or stops a 16-minute `probe.<UUID>` interval only, and the Monitor logs a probe callback without running the engine; no session and no shield.
The filter was added to the Work Focus again and the app was closed; the Focus was turned on at 20:06:23 and off at 20:07:35.

| Check                                                                   | Result                                                                                                                                                            |
| ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Which process ran the calls                                             | The extension, both times (`will use extension if available`)                                                                                                     |
| Does the app's Monitor receive an interval that the extension registers | Yes: `FocusMonitor` logged `FILTER_PROBE monitor didStart probe.5DEF5A4D-…` at 20:06:24.114, and `didEnd` at 20:07:35.806 when the extension stopped the interval |
| Does the extension see its own interval                                 | Yes: `visible=1` right after the registration                                                                                                                     |

So an interval that the extension registers belongs to the app, and the first candidate of the amendment (the extension stores the session and registers the interval, and the Monitor applies the shield) has the callbacks it needs.
A manual session that the app's start button began at 20:06:03 (`START_LATENCY`) ran during the probe; it shielded in the app's container, the probe did not touch it, and it was ended in the app.
After the probe the filter was removed from the Focus and the app was launched with `--filter-probe off`; the flag file is outside the part of the App Group that `devicectl` lists, so its removal was not checked.

## Focus filter extension after the shield amendment: 2026-11-17, stopped (#152)

The device steps of the [shield amendment](../specs/2026-11-16-extension-shield-amendment.md#physical-device-verification).
On the iPhone 16 Pro with iOS 27.0.1, a signed Debug build of `388472f` (#169) was installed over the existing app at 10:26:58 +09:00 with `devicectl device install app`, with the existing development profiles and no `-allowProvisioningUpdates`.
With the app not running, the Work Focus with the filter option on was turned on at 10:28:00 and off at 10:28:59; a second run with the Monitor's timing flag (the app launched once with `--screen-time-diagnostics` at 10:38:09) turned it on at 10:39:00 and toggled it until 10:42:06.
The results come from two `log collect` archives and from what was reported on screen.

| Step                                                       | Result                                                                                                                                                                    |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 6. The renamed option and a filter added before the rename | Passed: the option reads "자동으로 집중 시작" and kept its value over the install                                                                                         |
| 1. App closed, Focus on: the Monitor applies the shield    | Failed: the selected apps stayed open; only the everyday layer's apps were blocked. No process wrote a ManagedSettings store (no `with container` line in either archive) |
| 2. App closed, Focus off: the Monitor lifts the shield     | Nothing to lift, because step 1 applied nothing; the everyday layer stayed as it was                                                                                      |
| 3. to 5.                                                   | Not run                                                                                                                                                                   |

Finding that stopped the run: the Monitor's callback never gets the lock while the extension's section is running, and that section does not end until the callback returns.
In the timed run, the extension registered `focus.058E4111-…` at 10:39:00.089 inside its start section; `UsageTrackingAgent` notified the Monitor at 00.101, and the Monitor's `didStart` found the lock busy on the probe and on attempts 0 to 5 (`marker=none` each time) and ended at 02.454 with `result=lock_timeout` after 2281 ms.
The extension logged nothing after the registration and finished `perform()` at 02.473, 19 ms after the Monitor gave up.
Every call that started or stopped a running interval took about 2.3 s (on at 10:39:00, 10:40:23 and 10:41:32; off at 10:41:04 and 10:42:06), and the one off call that had no interval to stop (10:40:20) took 8 ms.
The amendment's gap table accepts a lost `intervalDidStart` or `intervalDidEnd` as a rare case (rows 2 and 4), but with the extension holding the lock it happens on every start and every end, so the extension can neither shield a session nor, once one is shielded, lift it.

Probe the same morning, with a DEBUG build of `388472f` plus a probe commit on the local branch `probe/152-extension-lock-wait`, which is not pushed, installed over the app at 10:46:27.
In the extension only, the probe logs the duration of every DeviceActivity call and registers each interval to start 5 s later than the engine asks.
With the app closed, the Work Focus was turned on at 10:49:02 and off at 10:49:49; the app was opened afterwards.

| Check                                      | Result                                                                                                                                                                                                                |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A registration whose interval starts later | `register` took 32 ms and the whole on call 65 ms; `UsageTrackingAgent` notified the Monitor at 10:49:09.600, and the Monitor took the lock and set `shield.applications` and `shield.webDomains` at 09.755 to 09.770 |
| Shield on screen after that start          | The selected apps were blocked                                                                                                                                                                                        |
| A stop of a running interval               | `stop` took 2277 ms: the agent notified the Monitor of the end at 10:49:49.811, during the call, and the call returned at 52.085; the whole off call took 2297 ms                                                     |
| Shield on screen after that end            | The selected apps stayed blocked                                                                                                                                                                                      |
| The app's repair of that shield            | Opening the app lifted the block                                                                                                                                                                                      |

So `startMonitoring` of an interval that starts now and `stopMonitoring` of a running interval return only after the Monitor's callback for it returns, and a callback that waits for the caller's lock always loses; an interval that starts later returns at once.
The Monitor logged its stores as in the container `kr.donminzzi.focusStudy.monitor`, unlike the app's `kr.donminzzi.focusStudy`, but the app's repair lifted the shield that the Monitor applied, so the Monitor and the app write the same `focusSession` store.
The amendment needs a revision so that no extension section starts or stops an interval whose callback is due at once (#152).

Second probe the same afternoon, with a second probe commit on the same local branch installed over the app at 13:35:04: the extension keeps the 5 s delayed start and records each focus stop, then makes it after the call has released the lock.
With the app closed, the Work Focus was turned on and off twice; the app was not opened.

| Call      | 13:39:34 to 13:40:00                                                                                     | 13:41:13 to 13:41:45                                                                                     |
| --------- | -------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| On        | 113 ms (`register` 38 ms); the Monitor set the shield at 13:39:40.042, and the selection was blocked     | 52 ms (`register` 31 ms); the Monitor set the shield at 13:41:19.914, and the selection was blocked      |
| Off       | 41 ms; the deferred `stop` took 29 ms, and the Monitor cleared `focusSession` at 13:40:00.379, inside it | 36 ms; the deferred `stop` took 24 ms, and the Monitor cleared `focusSession` at 13:41:45.543, inside it |
| On screen | The block lifted without opening the app                                                                 | The block lifted without opening the app                                                                 |

The [lock-order amendment](../specs/2026-11-17-extension-lock-order-amendment.md) builds on these two changes.
The second probe build stays on the device until the next install.

## Focus filter extension after the lock-order amendment: 2026-11-17 (#152)

The device steps of the [lock-order amendment](../specs/2026-11-17-extension-lock-order-amendment.md#physical-device-verification), then the remaining steps of the shield amendment and of the extension design.
On the iPhone 16 Pro with iOS 27.0.1, a signed Debug build of `0dc3d2f` (#172) was installed over the second probe build with `devicectl device install app`, with the existing development profiles; the results come from five `log collect` archives and from what was reported on screen.

| Step                                                                          | Result                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Lock order 1. App closed, Focus on: shielded within about 10 s                | Passed: the extension's call ran from 20:05:33.363 to 33.437 (74 ms); the Monitor's `intervalDidStart` set the shield at 20:05:40.856, and the selected apps were blocked within 10 s                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Lock order 2. App closed, Focus off: lifted without opening the app           | Passed: the call ran from 20:06:09.729 to 09.757 (28 ms); the Monitor's `intervalDidEnd` cleared `focusSession` at 09.755, inside the call, and the block lifted at once                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| Lock order 3. The everyday layer keeps its state                              | Passed on screen: only the focus selection changed in both calls                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Shield amendment 3. Focus on, then open the app; `집중 종료` lifts the shield | Passed: the call took 45 ms and the Monitor set the shield at 20:07:00.071; the app opened 10 s after the Focus with the timer running at 24:50, and `집중 종료` cleared `focusSession` in the app at 20:07:15.039, after which the Monitor logged `did end` at 15.048                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Shield amendment 4. A break in a filter-started session                       | Partly run on 2026-11-18: the app was still running in the background, so `donotdisturbd` ran both calls in the app (`Application is running; will use`), and the app, not the Monitor, shielded the session at 09:43:44.987. The break started at 09:44:17 and the app cleared `focusSession`; with the app closed, the Monitor's `intervalWillEndWarning` of `break.1` set the shield again at 09:47:19.255, and the selected apps were blocked without opening the app. Focus off at 09:48:58 ran in the app and cleared the shield. Second run the same morning, with the app swiped away before each call: the extension ran Focus on at 09:59:41 (65 ms), and the Monitor shielded the session at 09:59:48.239; the break started in the app at 10:00:17, the app was swiped away again, and the Monitor's break warning set the shield again at 10:03:19.803; the extension ran Focus off at 10:03:46 (23 ms), and the Monitor cleared `focusSession` at 10:03:46.079, inside the call. Passed |
| Extension design 4 and 5. A rollover, then Focus off                          | Failed on 2026-11-18, the session ended as "중단된 세션 정리" (`.recoveryInterrupted`) and was not counted; see below                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |

Finding of the rollover run: a registration made inside `intervalDidEnd` of the same one-shot activity is deleted after the callback.
With the app swiped away, the extension ran Focus on at 10:25:14 (205 ms) with a 25-minute length, and the Monitor shielded the session at 10:25:22.068.
At 10:50:17.177 `UsageTrackingAgent` delivered `did end`; inside the Monitor's callback the rollover registered `focus.FDC4006D-…` again from 10:25:14 to 11:15:15 (10:50:17.195 to .225), and the agent then delivered `did end` and `did start` for the new schedule (10:50:17.226 and .229).
At 10:50:17.236 the agent logged `Deleting budget for one-shot activity: focus.FDC4006D-…`, so the interval that the rollover had just registered was removed; the shield stayed on, because the ManagedSettings store is separate.
At 10:52:59 `donotdisturbd` ran Focus off in the app process, not in the extension; the app's startup reconcile found no registration and ended the session as `.recoveryInterrupted` at 10:52:59.428, before `perform()` began at 59.588. `[UNCERTAIN]` Why the call went to the app; the result would be the same in the extension, which applies the same missing-registration rule.
So the rollover of the extension design (#163) never keeps its interval on a device, and the same holds for the "Callback with nothing due" re-registration in `intervalDidEnd`; this answers the open row above ("whether an ended focus interval stays registered") with no.

Probe the same day, with a probe commit on the local branch `probe/152-rollover-warning`, which is not pushed, installed over the app at 10:58:36: every focus registration carries a 1-minute warning, the Monitor runs the rollover in the focus activity's `intervalWillEndWarning`, and the extension starts 20-minute sessions.
With the app swiped away, the extension ran Focus on at 11:42:22, and the Monitor shielded the session at 11:42:29.203; the Focus stayed on until 12:22:37, so two rollovers were due.

| Time     | Event                                                                                                                                                                                                 |
| -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 12:01:25 | The first warning reached the Monitor (`will end`), which registered the interval again with the end 12:22:23; the agent delivered `did end` and `did start` for the new schedule and deleted nothing |
| 12:21:25 | The agent raised the second warning alarm (`isWarning: 1`) for the new schedule, but delivered no `will end` to the Monitor                                                                           |
| 12:22:25 | `did end` reached the Monitor, its rollover registered the interval again inside `intervalDidEnd`, and the agent logged `Deleting budget for one-shot activity` at 12:22:25.454                       |
| 12:22:37 | Focus off ran in the app process, and the app's startup reconcile ended the session as `.recoveryInterrupted`                                                                                         |

So a re-registration before the end keeps the interval, but the agent delivers no second warning for a schedule registered again under the same name. `[UNCERTAIN]` Why; the agent reused the same budget object (`p361044`) for both schedules.
A rollover that registers the same name again cannot be repeated on a device, so the rollover needs a design without periodic re-registration (#152).

## Focus filter extension after the single-interval amendment: 2026-11-19 (#152)

The device steps of the [single-interval amendment](../specs/2026-11-18-single-interval-rollover-amendment.md#physical-device-verification), with the real base length of 25 minutes.
On the iPhone 16 Pro with iOS 27.0.1, a signed Debug build of `9d685f5` (#176) was installed over the probe build with `devicectl device install app` at 00:48:19, with the existing development profiles and with no session open; the results come from one `log collect` archive (00:10 to 01:20) and from what was reported on screen.
A first Focus on at 00:49:52 ran in the extension, and a Focus off at 00:51:13 ran in the app, which was open; the run below started with the next Focus on.

| Time         | Event                                                                                                                                                                     |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 00:51:20     | With the app swiped away, the extension ran Focus on; the selected apps were blocked                                                                                      |
| 00:51:27.786 | `UsageTrackingAgent` delivered `did start` for `focus.9B4C2B51-…`, the one interval of the session, 5 s after the call plus about 2 s                                     |
| 01:16:20     | The base length was reached: no callback came, the shield stayed, and the Live Activity card showed "집중 모드를 끌 때까지" with the count-up instead of the confirmation |
| 01:17:58     | A break request in the app overwrote the interval with the `waiting` end (`did end` and `did start` of the replaced schedule)                                             |
| 01:18:13     | The break started: `break.1` `did start`, and the interval was overwritten with the deadline                                                                              |
| 01:19:18     | "다시 집중하기" ended the break early: `break.1` `did end`, and the interval was overwritten with the bound end again; the session continued                              |
| 01:19:34     | The extension ran Focus off; the deferred stop delivered `did end` at 01:19:34.751, and the block lifted                                                                  |

The session ended as completed, and history showed it with its focused time; the archive holds no `Deleting budget for one-shot activity` line for the session.
So the interval registered at the start kept its budget through the first chunk end and through three overwrites from the app, which is the point where the rollover of #163 lost its interval on 2026-11-18.
Not run: the second chunk end at 50 minutes, where the code path is the same as at the first (no callback and no registration), and the bound end of about one week, which the host tests cover.

## Declined access request: 2026-11-19 (#38)

On the iPhone 16 Pro with iOS 27.0.1, a signed Debug build of `1bf7a11` (#178) was installed over the app with `devicectl device install app` at 11:13:39, with the existing development profiles; the result is what was reported on screen.

| Step                                                                           | Result                                                                                                                                                                                  |
| ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Screen Time access turned off in Settings › Apps › 온:공, then "집중 시작하기" | The system request appeared                                                                                                                                                             |
| "허용 안 함" in the system request                                             | Passed: "스크린 타임 권한이 꺼져 있어요" with both settings paths, "설정 열기" and "다시 확인하기" stayed on screen; before #178 the notice went back to "확인하고 있어요" (2026-11-15) |
| Access turned on again in Settings, back in the app, "다시 확인하기"           | Passed: the guidance left                                                                                                                                                               |

The guidance stays only in `declined`, which only `FamilyControlsError.authorizationCanceled` reaches, so an individual decline throws that error on iOS 27.0.1.

## Home screen widget, remaining steps: 2026-11-19 (#124)

The remaining steps of the [widget design](../specs/2026-11-13-home-widget-design.md#physical-device-verification), on the iPhone 16 Pro with iOS 27.0.1 and the signed Debug build of `1bf7a11` that was installed for #38; `origin/main` at `d43bffa` differs from it only in a comment and in docs, so nothing was installed.
The small widget was on the Home Screen and in Today View.
Results come from what was reported on screen, from two `log collect` archives (`donotdisturbd`, `runningboardd`, boot and first unlock) and from copies of the history store taken before and after the run.
Before the run, today had one completed session (00:51:20, 26.9 minutes), and the widget showed "27분 · 1회".

| Step                                                                                 | Result                                                                                                                                                                                                                                                |
| ------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. Gallery preview                                                                   | Passed: "1시간 15분 · 3회", the fixed sample (`TodayWidgetView.sample`, 3 sessions and 4500 s)                                                                                                                                                        |
| 2. A session completed with the app in front                                         | Passed: started 17:28:09, `expired` at 17:53:09; on the Home Screen right after the completion the widget already showed "52분 · 2회"                                                                                                                 |
| 5. Focus on with the app swiped away                                                 | The app process (pid 11215) ended at 17:54:08; the Focus on call at 17:54:18 ran in the extension (`will use extension if available`, `Executing prepared action on kr.donminzzi.focusStudy.intents`), and the selected apps were blocked within 10 s |
| 5. A background launch of the app during the session                                 | At 17:56:22 `dasd` launched the app in the background (pid 11276, `role: Background`), and the process went to `running-suspended`                                                                                                                    |
| 5. Focus off at 18:20:43, past the base length                                       | The call ran in that suspended app process (`Executing prepared action on kr.donminzzi.focusStudy`, 0.68 s); the session ended as `expired` with 26.41 minutes, and the widget changed to "1시간 18분 · 3회" at once, without the app in front        |
| 5. Focus on at 18:28:34 and off at 18:29:09                                          | Both calls ran in the app process; the session ended as `earlyExit` ("집중 종료" in the history sheet) and the widget kept "1시간 18분 · 3회"                                                                                                         |
| 5. The app opened afterwards                                                         | No change: "1시간 18분 · 3회"                                                                                                                                                                                                                         |
| 6. Restart: boot at 18:32:12, first unlock at 18:33:08, Today View before the unlock | The widget showed "1시간 18분 · 3회", the correct numbers, and not the placeholder that the plan expected; after the unlock the Home Screen widget showed the same                                                                                    |

The three completed sessions of the store copy (26.9, 25.0 and 26.41 minutes) add up to 78.3 minutes, the "1시간 18분 · 3회" of the widget.
So the extension did not write the snapshot (decision 26 of the extension design), and the widget changed without the app in front only because the system had launched the app in the background and the Focus off call ran in that process.
Which process gets a Focus call is the system's choice; this run does not show a widget change after a call that ran in the extension, because no session ended in the extension.
`[UNCERTAIN]` Why `dasd` launched the app at 17:56:22. The same route may explain the Focus off of 2026-11-18 that ran in the app after the app was swiped away, but that archive was not checked for a `dasd` launch.
`[UNCERTAIN]` Whether the view before the first unlock was a render that WidgetKit kept from before the restart or a new read of the snapshot. It showed no wrong number, which is the acceptance of step 6.
Not recorded: the time from a completion to the changed number in step 2, beyond "already changed" when the Home Screen appeared.

## M4 remaining steps: 2026-11-19 (#55)

The steps of the [M4 design](../specs/2026-11-01-m4-focus-filter-design.md#physical-device-verification) that were still open after #152, on the same iPhone 16 Pro with iOS 27.0.1 and the signed Debug build of `1bf7a11`, with the Work Focus; nothing was installed.
Steps 7 to 10 (notifications, allowed people and apps, Time Sensitive, emergency) are out of scope since 2026-11-19, because iOS filters notifications by the Focus's own settings, which the app neither reads nor changes; steps 1, 2, 4, 6 and 11 to 13 have their records above.
The app was launched with `--screen-time-diagnostics` at 21:34:45 and 21:43:30 for the DEBUG call log. Results come from that log (times in UTC on screen, written here as +09:00), from what was reported on screen, from one `log collect` archive (`donotdisturbd` category `AppFocusConfiguration`, boots and first unlocks) and from a copy of the history store.

| Step                                                                              | Result                                                                                                                                                                                                                                                                                       |
| --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 5. Focus on with the app in front, then "집중 종료"                               | The call ran in the app (`on started` 21:36:23); the session ended as `earlyExit` at 21:36:55                                                                                                                                                                                                |
| 5. The filter option turned off and on with the Focus on                          | Three off calls at 21:37:24 (`off done`, no session), then an on call at 21:37:27 that started a new session (`on started`) and two `on repeated` calls at 21:37:27 and 28 that started nothing; the design treats the option off as a Focus off, so the second session follows its rules    |
| 5. The filter screen opened and closed without a change                           | No call; only `check on` lines (21:39:32, 21:40:19) from the app's activation check                                                                                                                                                                                                          |
| 5. Restart with the Focus on: boot 21:42:06, first unlock 21:42:31                | No call (`from and to mode are the same`); the session of 21:37:27 kept running with no second one, and the call log had only `check on` lines after the relaunch; Focus off at 21:46:10 ended it as `earlyExit`                                                                             |
| 3. Device locked, Focus on from Control Center at 21:46:44                        | Passed: the call ran in the extension, and after the unlock the selected apps were blocked; Focus off at 21:48:47 in the extension                                                                                                                                                           |
| 3. A daily Work schedule 21:53–22:08 starting while the device is locked          | Passed: the call ran in the extension at 21:53:02, and after the unlock the selected apps were blocked; Focus off at 21:55:44                                                                                                                                                                |
| 14. Schedule 22:00–22:15, restart before it: boot 21:57:17, first unlock 22:01:26 | At 22:00:02 the Focus turned on and `donotdisturbd` logged `Ignoring request to coordinate app configurations; device has not unlocked since boot.`; no `perform()` ran and nothing was shielded                                                                                             |
| 14. After the first unlock                                                        | At 22:02:03 `Handling first launch/unlock: current=com.apple.focus.work` applied the filters of every app of the Focus; the call of 온:공 ran at 22:02:13 in the app, which was opened from the Home Screen at 22:01:56, and started a session at 22:02:15 with no tap; no refusal was shown |

The history store copy has five sessions after 21:30, all `earlyExit`: 21:36:22, 21:37:27, 21:46:44, 21:53:02 and 22:02:15, the last one ended by the Focus off at 22:03:57.
So a Focus that turns on before the first unlock leaves the selection open until about 40 s after the unlock, when the system handles the first unlock; the app gets no call before that and cannot shorten the delay.
`[UNCERTAIN]` Whether the call after the first unlock would run in the extension when the app is not opened; here the app had been opened 7 s before the system handled the first unlock.
`[UNCERTAIN]` What sent the off call at 21:50:36, which `donotdisturbd` logged after `Handling first launch/unlock: current=(null)` at 21:50:34, while the schedule was being set up with the Focus off; it found no session.

## Custom shield: run on 2026-11-20 and 2026-11-21 (#187)

The checks of the [custom shield design](../specs/2026-11-20-custom-shield-design.md#verification-plan) for the `FocusShield` extension.
A simulator cannot show a shield, so `ShieldConfigurationTests` checks only the configuration that the extension returns; it is not evidence for the rows below.
On 2026-11-20 the iOS 26.5 simulator (Xcode 26.6, ad-hoc signed Debug build) showed the Screen Time access alert and the "Allow with Passcode" sheet, then asked for the iPhone passcode; the simulator has none, an empty entry left access denied, and so no shield could be applied there.
On 2026-11-20, the signed Debug build of `a6f2a78` was installed on an iPhone 16 Pro with iOS 27.0.1 and a Shield development profile that included Family Controls and the test device.
An attempt to check the largest text size through the everyday store diagnostic stopped when the app picker and its settings sheet closed before an app could be selected.
The same diagnostic closed at the original text size and UIKit logged repeated attempts to present a sheet while another sheet was already being presented.
The diagnostic applied no restriction, so the largest text size check remains unverified.
At 21:38:06 the same day, a signed Debug build of `a6f2a78` with the picker sheet moved from the diagnostics section to `SettingsView` was installed over the app with `devicectl device install app`, with the existing development profiles, and launched with `--screen-time-diagnostics`.
The app picker stayed open, one app was selected and applied to the `everydayLayer` store, and the shield was captured on screen at the default text size (21:44) and at two larger sizes (21:45), the larger of which is the largest size.
Pixels read from the captures: the background is `#232529`, not the navy `#1E2744`, which matches the SDK description of `backgroundColor` as the color used in the background blur effect; the title and the subtitle are cream; the "닫기" label is near white (`#FEF9F1` at the lightest) on the cream button (`#FDF4E4`), not the configured navy, so it is close to unreadable at every size.
Tapping "닫기" closed the shielded app, with no action extension.
The restriction was then removed and the text size restored.
A second build (installed at 21:50:19) made the button navy with a cream label: the label was drawn `#DCDDE0` on the navy button (`#202742`), so iOS 27.0.1 does not use the configured label color, and the label was readable at the default text size.
A third build (installed at 21:54:06) added a line break before the subtitle and between its two sentences, and 20 pt of transparent space under the 72 pt mark; at the default text size (22:07) both line breaks showed, and the mark was drawn about 0.78 times as tall as before, close to 72 / 92, so iOS fits the icon image into a fixed box.
This layout was approved on screen. At the largest text size (22:08) the title wrapped to two lines, the subtitle to five, and "닫기" nearly filled the button height; nothing was clipped, and the mark was drawn smaller again.

On 2026-11-21, the light and dark check ran on signed Debug builds of the `fix/shield-light-appearance` branch, each installed over the app with `devicectl device install app`; every install also cleared the selection that the everyday store diagnostic had applied, so it was applied again after each one.
On the merged `dab7689` layout (captured 06:46), the light appearance drew a light blur background (`#E9EBF0`) on which the cream title, subtitle and ring could not be read, and a dark gray label on the navy button; the dark appearance matched the 2026-11-20 captures.
A dark blur style (installed 06:48:22, captured 06:51) kept the light appearance as dark as the dark one, and the label was drawn light on the cream button that the light appearance resolved; it was rejected.
With no blur style and the text and the button following the appearance (installed 06:53:48), the text read in both appearances, but the dark appearance drew the light variant (navy ring) of the registered `UIImageAsset`, and the light appearance drew a light label on the cream button because the label still had a cream color.
The approved build (installed 07:00:02, captured 07:00) has navy text, a navy label and a cream button in the light appearance, cream text and a navy button in the dark appearance, where iOS draws the label white, and the mark on a navy rounded square in the proportion of the app icon.
With the approved build at the largest text size (07:03), both appearances showed the tile, a two-line title, a five-line subtitle and "닫기" without clipping.
No smaller iPhone was available, so Display Zoom (Larger Text) stood in for a small screen: at the largest text size, with a focus session shielding the app (captured about 07:08, within 15 s of the session start), both appearances still fit without clipping; Display Zoom does not reproduce the shorter height of an iPhone SE.
For the two layers at once, a second focus session was started at about 07:20; at 07:21:13 the app was relaunched with `--screen-time-diagnostics` during that session, the session stayed open, and the everyday store diagnostic applied an app that the session already shielded: the same shield showed (captured with 23:44 left). Ending the session early lifted both shields, which matches the lock section that ends a session converging the everyday store to the stored everyday file; no log was read to confirm it. Both sessions of this run were ended early.
At 07:27 the everyday store diagnostic applied `example.com` alone, and Safari showed the same shield for that domain; iOS centered the content and put "닫기" right under the subtitle instead of at the bottom, and the copy still says "앱" for a website. Only Safari was checked.
Each run applies real restrictions and needs its own approval; record the device, the OS version and the build in each row.

| Check                                                    | Expected                                                               | Status                                                                                              |
| -------------------------------------------------------- | ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| 1. Light and dark appearance                             | The text, the mark and the button can be read in both                  | Passed on 2026-11-21 with the approved build                                                        |
| 2. Largest text size                                     | The title, the subtitle and "닫기" are not clipped                     | Passed on 2026-11-21 with the approved build; the first 2026-11-20 build failed (unreadable "닫기") |
| 3. Small screen                                          | The mark, the text and the button fit                                  | Passed on 2026-11-21 with Display Zoom as a stand-in; no small device                               |
| 4. App shield and Safari web-domain shield               | The same configuration; other browsers are not claimed                 | Passed on 2026-11-21 with the approved build (Safari only)                                          |
| 5. "닫기" without an action extension                    | Record what it does; if it does not close the app, stop for a decision | Passed                                                                                              |
| 6. Focus and everyday layers shield the same app at once | The same shield shows                                                  | Passed on 2026-11-21 with the approved build                                                        |

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
조정(2026-11-14, #124): Activity 확장은 이제 홈 화면 위젯을 위해 App Group entitlement(`Configuration/Activity.entitlements`)를 가진다. 시스템은 확장 프로세스에 컨테이너 전체를 열어 주므로 경계는 타깃의 코드다: 위젯 코드는 `TodaySnapshot/today.json`만 읽고, 제어 파일·선택 파일·등록 표시·기록 저장소를 열 수 있는 파일은 컴파일하지 않는다(`CoreTests/WidgetSourceListTests.swift`, [홈 화면 위젯 설계](../specs/2026-11-13-home-widget-design.md#data-path)). Report는 그대로 App Group entitlement가 없다. 기록 저장소의 위치는 아직 관측하지 못했다: 서명하지 않은 시뮬레이터 Debug 빌드는 entitlement가 없어(`codesign -d --entitlements -`가 빈 결과) `simctl get_app_container … groups`가 아무 그룹도 보여 주지 않았고, 실제 런타임은 App Group 디렉터리를 얻지 못해 저장소를 만들지 않았다. 서명한 기기 빌드에서 관측한다.
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

조정(2026-11-20, #187): Shield 확장(`kr.donminzzi.focusStudy.shield`)이 추가되었다. 이 확장은 Family Controls를 쓰므로 배포 entitlement가 따로 필요하며, 아직 신청하지 않았다. #17의 검토는 이 App ID를 다루지 않는다.

조정(2026-11-14, #124): Activity 행의 근거 중 entitlements 파일이 없다는 부분은 바뀌었다. `Configuration/Activity.entitlements`는 App Group만 담고 Family Controls는 쓰지 않으므로 배포 entitlement는 여전히 해당 없음이다. 이 App ID의 App Groups capability와 프로필 변경은 아직 하지 않았다.

개발 빌드는 가능하다: 세 타깃의 Family Controls 개발 entitlement와 개발 프로필로 서명한 Debug 빌드를 2026-10-26부터 실기기에 설치해 왔다([개발 프로비저닝과 설치 완료](#개발-프로비저닝과-설치-완료-2026-10-26)).
이것은 배포 승인이 아니다: App Store나 TestFlight 배포에는 App, Monitor, Report 각 App ID의 배포 entitlement 승인이 따로 필요하며, 신청 절차는 [Apple 신청 안내](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)를 따른다.
