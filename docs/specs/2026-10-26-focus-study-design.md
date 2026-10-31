# FocusStudy 설계

작성일: 2026-10-26. 상태: 승인된 범위의 로컬 구현을 진행했으며 실제 기기 인수 검증이 남아 있다.
**정식 앱 이름은 미정이다. FocusStudy는 임시 식별자이다.**

## 목적과 범위

학생이 자신의 주의 분산을 돌아보고 25분 동안 집중하도록 돕는다. SwiftUI와 Apple 네이티브 API 학습을 함께 목표로 한다. 실제 공부 여부, 연속 차단, 부정행위 방지를 증명하지 않는다.

- iOS 17 이상 SwiftUI + SwiftData를 사용한다.
- 개인 FamilyControls 인증, 사용자 선택 앱과 웹사이트, DeviceActivityReport 안의 사용 보고서, 25분 고정 세션과 중도 종료, 오늘의 세션 기록을 제공한다.
- 일시정지는 제공하지 않는다. 권한 거절 시 설정 안내만 한다.
- 앱 본체와 Monitor 및 Report 확장의 3개 제품 타깃을 사용하고 기본 시스템 shield를 사용한다. 테스트 번들은 제품 타깃 수에 포함하지 않는다.
- 보호자 관리, Android, 계정, 서버, AI, 카페, 리워드는 제외한다.
- 사용 보고서 민감 데이터를 앱 저장소로 내보내지 않는다.

## 사용자 흐름

첫 화면은 목적과 권한 이유를 설명하고 사용자의 동작으로 `.individual` 인증을 요청한다. 거절 또는 오류 뒤에는 시작과 보고서를 비활성화하고 설정에서 Screen Time 접근을 확인하는 안내만 보여준다. 미승인 상태를 대체 타이머 기능으로 우회하지 않는다. 설정 이동은 지원되는 앱 설정 URL만 사용하며 비공개 Screen Time deep link를 만들지 않는다.

인증 후 FamilyActivityPicker로 앱·웹사이트를 고른다. Picker는 `includeEntireCategory: true`로 열어 카테고리 안의 앱·웹사이트도 개별 토큰으로 받는다.
선택 화면에는 현재 편집 중인 앱과 웹사이트 개수를 각각 표시한다.
저장할 때 카테고리 토큰을 제외하고 선택 당시의 개별 토큰만 저장한다.
개별 토큰을 포함하지 않는 모드의 카테고리 입력은 누락을 막기 위해 거절한다. 빈 선택은 시작할 수 없다. 취소하면 이전 선택을 유지한다. 웹사이트와 앱 토큰을 각각 최대 50개로 검증한다. 초과 시 임의로 잘라 저장하지 않고 기존 선택을 유지한다. Picker가 보여줄 수 있는 사이트 목록과 토큰 표현은 시스템에 따른다. 임의 URL 입력 기능은 없다.

홈에는 선택한 항목, 25분 시작 버튼, 오늘의 기록, 사용 보고서 진입을 둔다. 시작 준비 중에는 재진입을 막는다. 활성 상태에서는 남은 시간과 중도 종료 버튼을 제공하고 선택 편집을 잠근다. 종료 후 선택을 바꿀 수 있다. 오늘 기록에는 시작 시각, 기록된 경과 시간, 만료/중도 종료/중단 상태를 표시한다. 완료 기록은 공부나 차단 성공의 인증서가 아니다.

사용 보고서는 현재 기기의 오늘 사용량을 Report 확장의 SwiftUI 안에서 보여준다. 본체는 `DeviceActivityReport.Context`와 오늘의 `DeviceActivityFilter`만 전달한다. 지연·빈 데이터에는 보고서 데이터를 기다리거나 표시할 수 없다는 안내를 제공하고, 0 사용량이나 권한 거절로 단정하지 않는다. 기록 화면의 세션 시간과 시스템 사용량은 별개이다.

## 웹사이트 차단 계약

`FamilyActivitySelection.webDomainTokens`를 명명된 store의 `shield.webDomains`에 그대로 적용한다. 사이트/도메인 단위이며 URL 경로별 차단과 모든 브라우저 우회 방지를 보장하지 않는다. 50개 한도는 저장과 시작 양쪽에서 검증한다. Safari를 먼저 실기기로 확인하고 다른 브라우저 및 WKWebView는 OS 버전별 실제 결과를 별도 기록한다. 미검증 조합을 지원한다고 표시하지 않는다. [FamilyActivityPicker](https://developer.apple.com/documentation/familycontrols/familyactivitypicker), [웹 도메인 shield 한도](https://developer.apple.com/documentation/managedsettings/shieldsettings/webdomains-swift.property), [앱 shield 한도](https://developer.apple.com/documentation/managedsettings/shieldsettings/applications-swift.property)

수동 `WebDomain(domain:)`와 `webContent.blockedByFilter`는 첫 범위에서 제외한다. 필터 정책은 Safari 비공개 브라우징을 비활성화하는 부작용이 있다. 선택 토큰을 통한 shield와 이 필터를 혼용하지 않는다. [Apple 필터 문서](https://developer.apple.com/documentation/managedsettings/webcontentsettings/blockedbyfilter-swift.property)

## 타깃과 데이터 경계

| 위치                       | 책임과 저장 범위                                                                                                                                        |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| App                        | 인증, Picker, 세션 시작·종료, SwiftData 기록, Report 호스트를 담당한다. 선택 토큰은 앱 내부 파일에만 저장한다.                                          |
| Monitor                    | 현재 세션의 만료·권한 상태를 조정하고 같은 명명된 store를 해제한다. 선택 토큰이나 SwiftData에 접근하지 않는다.                                          |
| Report                     | 사용량을 집계·렌더링한다. 사용량·앱 이름·사이트·토큰을 App Group, SwiftData, 파일, 로그, 네트워크로 내보내지 않는다. App Group 접근 권한도 주지 않는다. |
| Shared 소스(App/Monitor만) | 제어 메타데이터와 프로세스 간 잠금, 종료 판정, 명명된 store 식별자를 공유한다. 별도 프레임워크 제품 타깃을 추가하지 않는다.                             |

App과 Monitor는 하나의 `ManagedSettingsStore(named: ManagedSettingsStore.Name("focusSession"))`만 사용한다.
이 store의 `clearAllSettings()`만 호출하며 기본 store나 다른 앱의 제한을 변경하지 않는다.
명명된 store는 앱과 확장 사이에서 시스템이 공유한다.
개인 인증은 사용자가 철회할 수 있으며 앱 삭제 방지를 제공하지 않는다. [WWDC22 Screen Time API](https://developer.apple.com/videos/play/wwdc2022/110336/)

App Group에는 `ControlEnvelope.schemaVersion`과 선택적인 `session`을 저장한다.
세션에는 UUID, 시작/만료 시각, 단계(`preparing/active/ending/terminal`), 종료 사유·관측 시각을 둔다.
`activityName`은 UUID에서 계산하며 JSON 필드로 저장하지 않는다.
마지막 terminal 항목은 본체 기록 반영 확인 전까지 유지한다.
다음 시작 전에 이를 반영하므로 다중 기록 큐는 필요 없다.
토큰, 사용량, 사이트 이름은 공유하지 않는다.
SwiftData `SessionRecord`는 UUID를 고유 키로 하고 시작/예정 만료/기록 종료/관측 시각과 종료 사유를 저장한다.
저장 오류가 나면 terminal 확인 처리를 하지 않고 재시도하며, 중복 반영하지 않는다.

## 세션 상태와 원자성

세션 시간은 1,500초이다. `expiresAt = startedAt + 1500`으로 정하고 표시 때마다 `Int(ceil(max(0, min(1500, expiresAt.timeIntervalSince(now)))))`를 계산한다.
백그라운드 루프·타이머 tick 횟수로 시간을 누적하지 않는다.
날짜와 시간대 변경 시 오늘 구간은 현재 Calendar의 시작일부터 다음 날 시작까지로 다시 계산하고, 세션은 시작일 기준으로 목록에 배치한다.
시간대 변경만으로 절대 만료 시각을 바꾸지 않는다.
수동 시계 변경은 표시와 만료 판단에 영향을 줄 수 있으므로 변경을 관측하면 중단 처리한다.
프로세스 종료 중 발생한 시계 조작까지 탐지한다고 주장하지 않는다.

앱 actor만으로는 확장과의 경쟁을 막을 수 없다. App Group의 고정 lock 파일에 `flock`을 사용하고, 잠금 내부에서 메타데이터를 다시 읽은 후 ID 비교, store 변경, 원자적 파일 교체를 수행한다. 잠금을 잡고 `await`하거나 UI를 기다리지 않는다. 잠금 획득 실패·손상 데이터·파일 보호로 읽기 불가 시 시작을 거절하고 활성이라고 표시하지 않는다. 공유 저장은 JSON 원자 교체를 사용하고 UserDefaults의 읽기-쓰기 조합을 원자 연산으로 취급하지 않는다. 잠금 대기는 짧은 제한을 두고 실패를 재시도 가능한 오류로 전달한다.

1. 시작 전에 권한, 선택 개수, 이전 terminal의 SwiftData 반영, 기존 세션 부재를 확인한다. 인증 요청은 잠금 밖에서 수행한다.
2. 잠금 안에서 UUID와 `preparing` 메타데이터를 기록한다. `DeviceActivityName("focus.<UUID>")`와 시작/만료 날짜 구성요소를 사용해 비반복 25분 모니터를 등록한다. `startMonitoring`은 동기 throwing API이다. 초·날짜·시간대를 포함하는 schedule 생성과 자정 경계를 실기기로 검증한다.
3. 등록 성공 후 고정된 선택의 앱·웹 토큰을 store에 적용한다. 등록 목록의 이름, 설정값의 일치, 권한 유지와 메타데이터 쓰기 성공을 확인하고 `active`를 기록한다. 이것은 설정 요청의 성공 조건이며 실제 차단 적용 증거는 아니다. 잠금 해제 후 최신 상태를 재조회해 활성 UI를 표시한다.
4. 어느 단계든 실패하면 해당 UUID의 monitoring을 중지하고 이 앱 store만 해제한다. 기록을 중단으로 남기고 오류를 표시한다. 롤백 도중 저장 오류가 나도 해제와 중지부터 시도하고, 다음 조정에서 재시도한다. 시작 실패를 완료 세션으로 세지 않는다.
5. 종료는 ID 일치 확인 후 `ending`을 먼저 기록하고 store 해제, 해당 monitoring 중지, terminal 기록을 순서대로 수행한다. 반복 호출은 같은 결과를 내며 다른 세션에는 영향을 주지 않는다. `ending`에서 죽은 프로세스는 다음 조정에서 정리를 완료한다.
6. Monitor의 `intervalDidEnd(for:)`는 activity 이름을 `SessionControl.handleCallback`에 전달한다.
   잠금 안에서 현재 세션의 계산된 이름과 비교한 뒤 권한·단계·등록 상태·만료를 조정한다.
   이름이 일치하지 않는 콜백은 현재 세션을 변경하지 않는다.
   정상 권한과 등록을 유지한 active 세션은 이른 콜백만으로 만료되지 않는다. `intervalDidStart`도 만료/불완전 상태 조정만 수행하며 shield를 재적용하지 않는다.
   콜백에서 본체 actor나 비동기 작업의 완료를 기다리지 않는다.

앱 활성화·재시작과 Monitor 진입 시 상태를 조정한다.
권한 철회는 즉시 관측 가능한 시점에 중단/미사용으로 전환하고 store와 monitoring을 정리한다.
등록이 유지된 active가 만료하면 만료 처리하고, 등록이 사라진 active와 잔존 preparing은 중단 처리하며, ending은 정리를 재시도한다.
읽을 수 없는 메타데이터에서는 새 시작을 막고 가능한 범위에서 이 앱 store를 해제한다.
기기가 잠기거나 앱이 종료되면 콜백이 지연될 수 있어 초 단위 자동 해제를 보장하지 않는다.
만료 기록은 예정 시각과 실제 정리 관측 시각을 구분한다.

## 환경 확인과 선행 조건

아래 표는 2026-10-26 초기 설계 당시의 환경 확인 이력이며 현재 설치·서명 상태를 보장하지 않는다.

| 읽기 전용 명령/대상                        | 관측 결과와 해석                                                                                                                                                                                                                          |
| ------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `xcode-select -p`                          | `/Applications/Xcode.app/Contents/Developer`                                                                                                                                                                                              |
| `xcodebuild -version`                      | Xcode 27.1, Build 27A9275                                                                                                                                                                                                                 |
| `xcodebuild -showsdks`                     | iOS 27.1 및 Simulator iOS 27.1 SDK가 있다. iOS 17 런타임·실기기 보유는 미확인이다. 캐시/FSEvents 경고가 있었지만 목록 조회는 성공했다.                                                                                                    |
| 설치 SDK의 `.swiftinterface`               | `webDomainTokens`, `shield.webDomains: Set<WebDomainToken>?`, throwing `startMonitoring`, `DeviceActivityResults<DeviceActivityData>`를 받는 async `makeConfiguration`을 확인했다. WWDC의 오래된 배열 기반 예제를 그대로 복사하지 않는다. |
| `security find-identity -v -p codesigning` | `0 valid identities found`. 현재 조회에서 유효한 서명 identity가 보이지 않는다. 계정 미가입이나 인증서 부재로 단정하지 않는다.                                                                                                            |
| 기존 provisioning profile 디렉터리         | 프로필 파일은 존재한다. 새 앱 ID가 미정이므로 적합성·Family Controls 권한·기기 등록은 미검증이다. 내용을 내보내거나 계정을 변경하지 않았다.                                                                                               |

실기기 준비와 서명 상태는 [검증 기록](../notes/screen-time-device-matrix.md#서명과-배포)에서 관리한다.
개발 서명과 배포 entitlement는 별도로 확인한다.
참고: [Apple entitlement 신청 안내](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement), [Family Controls 구성](https://developer.apple.com/documentation/xcode/configuring-family-controls).

## 완료 기준과 검증 경계

자동 검증의 명령과 증명 범위는 [README](../../README.md#실행과-검증)를 따른다.
실기기 시나리오와 미검증 상태는 [검증표](../notes/screen-time-device-matrix.md)에서 관리한다.
실제 기기에서 iOS 17과 지원 대상 최신 OS를 확인하며, 대상 기기·OS가 없으면 미검증으로 남긴다.

## 구현 후 복구 계약 보완

독립 전체 검토를 반영해, 제어 상태를 읽지 못하면 잠금 안에서 이 앱의 명명된 store와 `focus.<UUID>` namespace의 등록만 정리한다. 이후 읽기가 회복되어도 등록이 사라진 active 메타데이터를 활성으로 신뢰하지 않고 중단으로 조정한다. 다른 namespace의 monitoring을 중지하지 않으며 제한을 복구 목적으로 재적용하지 않는다. 종료 원인·시각은 ending 기록이 저장된 경우 유지한다. ending과 terminal 저장이 모두 실패한 뒤 재시작하면 잃어버린 원인을 추정하지 않고 복구 중단으로 기록한다.

시작 시 세션 제어 복구를 선택 토큰과 SwiftData 초기화보다 먼저 수행한다. 선택·기록 저장소가 열리지 않아도 제어 경로를 유지하며 오류 화면에서 안전한 현재 세션 종료와 재시도를 제공한다. 기록 저장소가 정상화되기 전에는 terminal을 확인 처리하지 않는다.

기록 조회 실패는 확인된 활성 제어 상태를 무효화하지 않으며 중도 종료를 계속 제공한다.
제어 상태 읽기 실패는 활성 표시를 유지하지 않는다.
같은 날 보고서를 다시 불러올 때도 `UsageReportContainer`의 콘텐츠 ID를 바꿔 하위 뷰를 새로 만든다.
회귀 근거는 [검토 기록](../notes/independent-review.md)에 남긴다.

## M1 조정: 2026-10-31

[M1 설계](2026-10-31-m1-launch-flow-design.md)와 그 설계를 구현한 코드가 세션 길이와 실행 흐름에 대한 기준이다.
이 절보다 앞에 있는 "25분 고정 세션", "25분 시작 버튼", "비반복 25분 모니터", 홈 화면 구성에 관한 문장은 2026-10-26 당시의 결정으로 남겨 두며, 현재 동작을 설명하지 않는다.
세션 길이는 개인 설정에서 25분부터 50분까지 5분 단위로 정하고, 각 세션은 시작할 때의 길이를 `expiresAt`에 저장한다.
설정을 마치지 않은 사용자는 온보딩(소개, 스크린 타임 권한, 제한할 앱 고르기, 집중 시간)을 먼저 거치고, 설정을 마친 사용자는 전체 화면 타이머에서 시작한다.
권한을 거절했거나 나중에 끈 사용자에게는 시스템 권한 요청을 다시 띄우지 않고 설정 앱에서 켜는 방법을 안내한다.
일시정지 없음, 계정·서버 없음, 기본 시스템 shield 사용 같은 나머지 범위 결정은 바뀌지 않았다.
