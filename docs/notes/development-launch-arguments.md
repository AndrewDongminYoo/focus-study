# 개발용 실행 인자

Debug 빌드의 scheme 설정에서 Launch Arguments에 넣어 특정 화면이나 진단 경로로 앱을 실행합니다.
아래 인자를 처리하는 코드는 모두 `#if DEBUG` 안에 있으므로 Release 빌드에는 포함되지 않습니다.

## 화면 확인 (`--ui-testing`)

`--ui-testing` 모드는 메모리 안의 SwiftData와 실행마다 새로 만드는 임시 제어 파일을 사용합니다.
실제 권한을 요청하거나 monitoring을 등록하거나 제한을 적용하지 않으므로, 이 모드의 결과는 실제 Screen Time 동작의 증거가 아닙니다.
`--ui-testing onboarding`을 제외한 모드는 온보딩을 마친 사용자로 시작합니다.

| 인자                                           | 확인하는 화면                                                                                                                |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `--ui-testing approved --selected`             | 권한을 받고 제한할 앱을 고른 기본 화면                                                                                       |
| `--ui-testing denied --selected`               | 권한을 거절한 화면                                                                                                           |
| `--ui-testing registration-failure --selected` | monitoring 등록에 실패한 화면                                                                                                |
| `--ui-testing startup-failure --selected`      | 세션이 진행 중일 때 저장소가 처음 한 번 실패하는 복구 화면                                                                   |
| `--ui-testing onboarding`                      | 설정을 마치지 않은 새 사용자의 온보딩                                                                                        |
| `--ui-testing expiring`                        | 앱을 띄울 때 만료 3초 전의 세션을 만들어 완료 화면을 보여 줍니다. 완료를 닫고 다시 시작한 세션은 설정한 길이만큼 진행됩니다. |
| `--ui-testing ending-soon`                     | 시작 버튼을 누르면 집중 종료 10초 전부터 세션을 시작합니다.                                                                  |
| `--ui-testing history`                         | 오늘 날짜에 25분·50분 완료, 집중 종료, 마감 초과 기록을 넣은 기록 화면입니다. 자정 직후에도 기록은 오늘에 속합니다.          |
| `--ui-testing report-waiting --selected`       | 보고서 콘텐츠가 아직 오지 않은 대기 상태                                                                                     |
| `--ui-testing report-empty --selected`         | 보고서 데이터가 없는 상태                                                                                                    |
| `--ui-testing report-zero --selected`          | 실제 사용량이 0인 상태입니다. 빈 데이터와 실제 0은 보고서 확장이 쓰는 `UsageSummarySection`으로 그립니다.                    |

모드와 함께 쓰는 인자는 다음과 같습니다.

| 인자                            | 동작                                                                                                                                                   |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `--length <분>`                 | 집중 시간 설정을 지정합니다(25~50분, 5분 단위).                                                                                                        |
| `--solid-controls`              | 불투명한 버튼 대체 스타일을 보여 줍니다. 시스템의 투명도 설정은 바꾸지 않습니다.                                                                       |
| `--start-delay <초>`            | 합성 monitoring 등록을 최대 3초 늦춰 시작 진행 표시를 확인합니다. 실제 Screen Time 지연을 재현하지는 않습니다.                                         |
| `--break-timing short`          | 쉬는 시간 대기를 1·2·4초, 쉬는 시간을 3초, 마감 여유를 5초, 대기 유예를 2초로 줄입니다. 집중 시간은 줄이지 않습니다.                                   |
| `--everyday-fixture blocking`   | 실행 5분 전(5분 단위)에 시작해 2시간 동안 이어지는 합성 매일 제한을 합성 앱 1개와 함께 저장합니다. 범위가 자정에 닿지 않도록 고정 시간대로 계산합니다. |
| `--focus-filter-refusal <사유>` | 마지막 집중 모드 시작 거절을 저장해 설정의 집중 모드 안내에서 보여 줍니다. 사유는 `access`, `selection`, `busy`, `history`, `error` 중 하나입니다.     |

`--ui-testing ending-soon`과 `--break-timing short`를 함께 쓰면, 쉬는 시간을 가진 뒤 다시 집중하지 않은 세션이 시작 버튼을 누르고 약 19초 뒤에 마감에 닿습니다.

## Live Activity 확인

Live Activity는 마지막으로 확인한 집중·휴식·복귀 계획을 보여 줄 뿐이며, 실제로 차단되었는지는 확인하지 않습니다.
출시 조건과 관측된 한계는 [결정 문서](../specs/2026-11-06-live-activity-decision.md)와 [가능성 검토 기록](2026-11-06-live-activity-feasibility.md)에 있습니다.

일반 `--ui-testing` 모드는 ActivityKit 요청을 보내지 않습니다.

- `--activity-preview <모드>`는 Activity를 요청하지 않고 공용 view만 그립니다. 모드는 `focus`, `break`, `return`, `waiting`, `stale`, `deadline`, `late`이며, 라이트·다크 모드와 큰 글씨를 확인할 때 씁니다. 시스템의 갱신이나 백그라운드 전달은 확인하지 못합니다.
- `--ui-testing approved --selected --live-activity-probe <UUID>`는 합성 Screen Time 데이터로 실제 ActivityKit 표시를 확인합니다. 실제 monitoring이나 제한은 켜지 않습니다. 다만 probe는 자기 임시 제어 파일에 없는 세션의 Activity를 모두 끝내므로, 같은 기기에 실제 세션의 Live Activity가 떠 있으면 그 세션을 먼저 마친 뒤 실행합니다.
- 같은 UUID로 다시 실행하면 같은 임시 제어 디렉터리와 UserDefaults를 쓰므로, 닫은 Activity가 다시 생기지 않는지 확인할 수 있습니다. 독립된 실행에는 새 UUID를 씁니다.
- probe 실행에서는 표시 작업이 `LIVE_ACTIVITY_PROBE`로 시작하는 콘솔 로그로 남습니다.
- 휴식 경계는 `--break-timing short`로, 집중 종료는 `--ui-testing ending-soon`으로 앞당길 수 있습니다.

## 실기기 진단

`--screen-time-diagnostics`는 Debug 빌드에서만 동작하며, 합성 데이터 대신 실제 권한·선택·monitoring 경로를 사용합니다.
`--ui-testing`과 함께 쓰지 않습니다.
앱 설치를 허락받은 것은 실제 앱·웹사이트 제한에 대한 동의가 아니므로, 기기 소유자의 동의를 따로 받아야 합니다.
진단 화면은 기본 실행과 Release 빌드에 나타나지 않으며, 토큰·도메인·사용량을 기록하거나 내보내지 않습니다.

시작 조건을 통과한 `집중 시작하기` 탭은 처리에 걸린 시간을 Xcode 콘솔에 `START_LATENCY total_ms=...` 로그로 남깁니다.
시작 진행 표시를 그리기 위한 프레임 대기는 이 시간에 포함되지 않습니다.
첫 시작과 이후 시작의 값을 기기·OS·빌드, 성공 여부와 함께 기록하고, 합성 측정값과 구분합니다.
측정 범위와 결과는 [시작 지연 기록](2026-11-05-start-latency.md)에 있습니다.

진단 절차는 다음과 같습니다.

1. 동의받은 선택과 정상 권한을 준비한 뒤 `다음 등록 후 실패 주입`을 누르고 세션을 시작합니다.
   실제 monitoring 등록이 성공한 직후 오류를 한 번 던져서 세션 엔진이 등록을 되돌리는지 확인합니다.
   실제 SDK가 먼저 실패하면 그 오류를 그대로 두고 주입은 사용한 것으로 처리합니다.
2. 세션 A가 진행 중일 때 타이머 화면의 설정 버튼을 열고 `현재 세션 콜백 저장`을 누릅니다.
   진단 실행에서는 세션 중에도 설정 버튼이 남아 있습니다.
   A를 종료하고 B를 시작한 뒤 `이전 세션 콜백 전달`을 눌러 B가 유지되는지 확인합니다.
   저장한 콜백은 같은 세션에 다시 전달할 수 없습니다.
3. 관측 결과를 [실기기 검증 기록](screen-time-device-matrix.md)에 남깁니다.
   이 절차는 공용 콜백 엔진을 직접 호출하므로, OS가 확장에 콜백을 전달하는 실제 지연은 증명하지 않습니다.
