# FocusStudy 설계

작성일: 2026-10-26. 상태: 승인된 범위의 설계 문서이며 구현은 시작하지 않았다.
**정식 앱 이름과 프로젝트 경로는 미정이다. FocusStudy는 문서의 임시 식별자일 뿐이다.** 아래 소스 경로와 타깃 이름도 구현 시 확정할 상대 경로 제안이다.

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

인증 후 FamilyActivityPicker로 앱·웹사이트를 고른다. 첫 범위는 개별 토큰만 저장하며 카테고리 선택은 저장 전에 거절하고 개별 항목을 고르도록 안내한다. 빈 선택은 시작할 수 없다. 취소하면 이전 선택을 유지한다. 웹사이트와 앱 토큰을 각각 최대 50개로 검증한다. 초과 시 임의로 잘라 저장하지 않고 기존 선택을 유지한다. Picker가 보여줄 수 있는 사이트 목록과 토큰 표현은 시스템에 따른다. 임의 URL 입력 기능은 없다.

홈에는 선택한 항목, 25분 시작 버튼, 오늘의 기록, 사용 보고서 진입을 둔다. 시작 준비 중에는 재진입을 막는다. 활성 상태에서는 남은 시간과 중도 종료 버튼을 제공하고 선택 편집을 잠근다. 종료 후 선택을 바꿀 수 있다. 오늘 기록에는 시작 시각, 기록된 경과 시간, 만료/중도 종료/중단 상태를 표시한다. 완료 기록은 공부나 차단 성공의 인증서가 아니다.

사용 보고서는 현재 기기의 오늘 사용량을 Report 확장의 SwiftUI 안에서 보여준다. 본체는 `DeviceActivityReport.Context`와 오늘의 `DeviceActivityFilter`만 전달한다. 지연·빈 데이터에는 보고서 데이터를 기다리거나 표시할 수 없다는 안내를 제공하고, 0 사용량이나 권한 거절로 단정하지 않는다. 기록 화면의 세션 시간과 시스템 사용량은 별개이다.

## 웹사이트 차단 계약

`FamilyActivitySelection.webDomainTokens`를 명명된 store의 `shield.webDomains`에 그대로 적용한다. 사이트/도메인 단위이며 URL 경로별 차단과 모든 브라우저 우회 방지를 보장하지 않는다. 50개 한도는 저장과 시작 양쪽에서 검증한다. Safari를 먼저 실기기로 확인하고 다른 브라우저 및 WKWebView는 OS 버전별 실제 결과를 별도 기록한다. 미검증 조합을 지원한다고 표시하지 않는다. [FamilyActivityPicker](https://developer.apple.com/documentation/familycontrols/familyactivitypicker), [웹 도메인 shield 한도](https://developer.apple.com/documentation/managedsettings/shieldsettings/webdomains-swift.property), [앱 shield 한도](https://developer.apple.com/documentation/managedsettings/shieldsettings/applications-swift.property)

수동 `WebDomain(domain:)`와 `webContent.blockedByFilter`는 첫 범위에서 제외한다. 필터 정책은 Safari 비공개 브라우징을 비활성화하는 부작용이 있다. 선택 토큰을 통한 shield와 이 필터를 혼용하지 않는다. [Apple 필터 문서](https://developer.apple.com/documentation/managedsettings/webcontentsettings/blockedbyfilter-swift.property)

## 타깃과 데이터 경계

| 위치 | 책임과 저장 범위 |
| --- | --- |
| App | 인증, Picker, 세션 시작·종료, SwiftData 기록, Report 호스트를 담당한다. 선택 토큰은 앱 내부 파일에만 저장한다. |
| Monitor | 현재 세션의 만료·권한 상태를 조정하고 같은 명명된 store를 해제한다. 선택 토큰이나 SwiftData에 접근하지 않는다. |
| Report | 사용량을 집계·렌더링한다. 사용량·앱 이름·사이트·토큰을 App Group, SwiftData, 파일, 로그, 네트워크로 내보내지 않는다. App Group 접근 권한도 주지 않는다. |
| Shared 소스(App/Monitor만) | 제어 메타데이터와 프로세스 간 잠금, 종료 판정, 명명된 store 식별자를 공유한다. 별도 프레임워크 제품 타깃을 추가하지 않는다. |

App과 Monitor는 하나의 `ManagedSettingsStore(named: .focusSession)`만 사용한다. 이 store의 `clearAllSettings()`만 호출하며 기본 store나 다른 앱의 제한을 변경하지 않는다. 명명된 store는 앱과 확장 사이에서 시스템이 공유한다. 개인 인증은 사용자가 철회할 수 있으며 앱 삭제 방지를 제공하지 않는다. [WWDC22 Screen Time API](https://developer.apple.com/videos/play/wwdc2022/110336/)

App Group에는 버전, 세션 UUID, UUID를 포함한 activity 이름, 시작/만료 시각, 단계(`preparing/active/ending/terminal`), 종료 사유·관측 시각만 둔다. 마지막 terminal 항목은 본체 기록 반영 확인 전까지 유지한다. 다음 시작 전에 이를 반영하므로 다중 기록 큐는 필요 없다. 토큰, 사용량, 사이트 이름은 공유하지 않는다. SwiftData `SessionRecord`는 UUID를 고유 키로 하고 시작/예정 만료/종료 시각, 종료 사유만 저장한다. 저장 오류가 나면 terminal 확인 처리를 하지 않고 재시도하며, 중복 반영하지 않는다.

## 세션 상태와 원자성

세션 시간은 1,500초이다. `expiresAt = startedAt + 1500`으로 정하고 표시 때마다 `max(0, min(1500, expiresAt - now))`를 계산한다. 백그라운드 루프·타이머 tick 횟수로 시간을 누적하지 않는다. 날짜와 시간대 변경 시 오늘 구간은 현재 Calendar의 시작일부터 다음 날 시작까지로 다시 계산하고, 세션은 시작일 기준으로 목록에 배치한다. 시간대 변경만으로 절대 만료 시각을 바꾸지 않는다. 수동 시계 변경은 표시와 만료 판단에 영향을 줄 수 있으므로 변경을 관측하면 중단 처리한다. 프로세스 종료 중 발생한 시계 조작까지 탐지한다고 주장하지 않는다.

앱 actor만으로는 확장과의 경쟁을 막을 수 없다. App Group의 고정 lock 파일에 `flock`을 사용하고, 잠금 내부에서 메타데이터를 다시 읽은 후 ID 비교, store 변경, 원자적 파일 교체를 수행한다. 잠금을 잡고 `await`하거나 UI를 기다리지 않는다. 잠금 획득 실패·손상 데이터·파일 보호로 읽기 불가 시 시작을 거절하고 활성이라고 표시하지 않는다. 공유 저장은 JSON 원자 교체를 사용하고 UserDefaults의 읽기-쓰기 조합을 원자 연산으로 취급하지 않는다. 잠금 대기는 짧은 제한을 두고 실패를 재시도 가능한 오류로 전달한다.

1. 시작 전에 권한, 선택 개수, 이전 terminal의 SwiftData 반영, 기존 세션 부재를 확인한다. 인증 요청은 잠금 밖에서 수행한다.
2. 잠금 안에서 UUID와 `preparing` 메타데이터를 기록한다. `DeviceActivityName("focus.<UUID>")`와 시작/만료 날짜 구성요소를 사용해 비반복 25분 모니터를 등록한다. `startMonitoring`은 동기 throwing API이다. 초·날짜·시간대를 포함하는 schedule 생성과 자정 경계를 실기기로 검증한다.
3. 등록 성공 후 고정된 선택의 앱·웹 토큰을 store에 적용한다. 등록 목록의 이름, 설정값의 일치, 권한 유지와 메타데이터 쓰기 성공을 확인하고 `active`를 기록한다. 이것은 설정 요청의 성공 조건이며 실제 차단 적용 증거는 아니다. 잠금 해제 후 최신 상태를 재조회해 활성 UI를 표시한다.
4. 어느 단계든 실패하면 해당 UUID의 monitoring을 중지하고 이 앱 store만 해제한다. 기록을 중단으로 남기고 오류를 표시한다. 롤백 도중 저장 오류가 나도 해제와 중지부터 시도하고, 다음 조정에서 재시도한다. 시작 실패를 완료 세션으로 세지 않는다.
5. 종료는 ID 일치 확인 후 `ending`을 먼저 기록하고 store 해제, 해당 monitoring 중지, terminal 기록을 순서대로 수행한다. 반복 호출은 같은 결과를 내며 다른 세션에는 영향을 주지 않는다. `ending`에서 죽은 프로세스는 다음 조정에서 정리를 완료한다.
6. Monitor의 `intervalDidEnd(for:)`는 activity에서 UUID를 얻어 잠금 안에서 현재 ID와 만료 시각을 함께 비교한다. 이전 UUID, 파싱 불가 이름, 이른 콜백은 새 세션을 해제하지 않는다. `intervalDidStart`도 만료/불완전 상태 조정만 수행하며 shield를 재적용하지 않는다. 콜백에서 본체 actor나 비동기 작업의 완료를 기다리지 않는다.

앱 활성화·재시작과 Monitor 진입 시 상태를 조정한다. 권한 철회는 즉시 관측 가능한 시점에 중단/미사용으로 전환하고 store와 monitoring을 정리한다. 만료한 active는 만료 처리하고, 잔존 preparing은 중단 처리하며, ending은 정리를 재시도한다. 읽을 수 없는 메타데이터에서는 새 시작을 막고 가능한 범위에서 이 앱 store를 해제한다. 기기가 잠기거나 앱이 종료되면 콜백이 지연될 수 있어 초 단위 자동 해제를 보장하지 않는다. 만료 기록은 예정 시각과 실제 정리 관측 시각을 구분한다.

## 환경 확인과 선행 조건

2026-10-26 할당 작업 공간은 비어 있었고 저장소·프로젝트·로컬 `.agents` 및 상위 개발 경로의 AGENTS.md는 없었다. 사용자 홈 `.agents/skills/fluent-korean/SKILL.md`와 제공된 `writing-plans`, `verification-before-completion` 지침을 읽었다.

| 읽기 전용 명령/대상 | 관측 결과와 해석 |
| --- | --- |
| `xcode-select -p` | `/Applications/Xcode.app/Contents/Developer` |
| `xcodebuild -version` | Xcode 27.1, Build 27A9275 |
| `xcodebuild -showsdks` | iOS 27.1 및 Simulator iOS 27.1 SDK가 있다. iOS 17 런타임·실기기 보유는 미확인이다. 캐시/FSEvents 경고가 있었지만 목록 조회는 성공했다. |
| 설치 SDK의 `.swiftinterface` | `webDomainTokens`, `shield.webDomains: Set<WebDomainToken>?`, throwing `startMonitoring`, `DeviceActivityResults<DeviceActivityData>`를 받는 async `makeConfiguration`을 확인했다. WWDC의 오래된 배열 기반 예제를 그대로 복사하지 않는다. |
| `security find-identity -v -p codesigning` | `0 valid identities found`. 현재 조회에서 유효한 서명 identity가 보이지 않는다. 계정 미가입이나 인증서 부재로 단정하지 않는다. |
| 기존 provisioning profile 디렉터리 | 프로필 파일은 존재한다. 새 앱 ID가 미정이므로 적합성·Family Controls 권한·기기 등록은 미검증이다. 내용을 내보내거나 계정을 변경하지 않았다. |

컴파일 전제는 확인했지만 세 타깃의 개발 서명과 실제 기기의 Screen Time 동작은 아직 blocker이다. 정식 이름, 프로젝트 절대 경로, bundle ID 3개, Team, App Group ID를 구현 전에 확정한다. 계정 설정과 entitlement 신청은 별도 승인 범위이다. Family Controls 배포 entitlement는 본체와 두 확장 각각의 App ID에 대해 별도 심사가 필요하며 개발 빌드 가능 여부와 구분한다. [Apple entitlement 신청 안내](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement), [Family Controls 구성](https://developer.apple.com/documentation/xcode/configuring-family-controls)

## 완료 기준과 검증 경계

순수 로직·가짜 adapter 테스트는 경계값, 롤백, 중복 종료, 경쟁 순서를 증명한다. 시뮬레이터는 UI와 SwiftData 검증에만 사용하며 실제 Screen Time 적용 증거로 사용하지 않는다. 실제 기기에서 iOS 17과 지원 대상 최신 OS를 우선 확인한다. 대상 기기/OS가 없으면 미검증으로 남긴다.

필수 실기기 항목은 권한 거절/철회, 앱 강제 종료, 잠금, 25분 만료와 지연 시간, 재시작, 연속 시작, 등록 실패, 이전 세션 지연 콜백, 날짜/시간대 변경이다. Safari에서 선택 사이트와 미선택 사이트, 동일 도메인의 다른 경로, 일반/비공개 탭을 확인한다. 50/51개 한도는 합성 검증과 가능한 실제 Picker 선택을 구분한다. 다른 브라우저/WKWebView는 OS·브라우저 버전별 탐색 검증으로 별도 기록한다. Report의 민감 데이터 외부 쓰기 부재도 코드 검토한다. 아직 이 검증은 실행하지 않았다.


## 구현 승인 후 경로 전제 (2026-10-26)

로컬 순차 구현과 새 프로젝트·로컬 버전 관리 초기화가 승인되었다. 프로젝트 루트는 `/Volumes/dongminyu/Development/01_personal/focus-study`이다. 기존의 이번 턴 문서만 작성한다는 제한은 이 승인으로 해제되었다. FocusStudy는 여전히 임시 제품명이며 bundle ID와 App Group ID는 로컬 컴파일용 placeholder를 사용한다. 계정·서명 설정 변경, entitlement 신청, GitHub 생성·push·배포는 승인 범위 밖이다.
