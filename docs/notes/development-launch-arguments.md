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
| `--ui-testing checking --selected`             | 권한 값을 아직 확인하지 못한 화면입니다. 시작 버튼을 누르면 권한을 요청하고, 승인된 뒤에 시작합니다.                         |
| `--ui-testing registration-failure --selected` | monitoring 등록에 실패한 화면                                                                                                |
| `--ui-testing startup-failure --selected`      | 세션이 진행 중일 때 저장소가 처음 한 번 실패하는 복구 화면                                                                   |
| `--ui-testing onboarding`                      | 설정을 마치지 않은 새 사용자의 온보딩                                                                                        |
| `--ui-testing expiring`                        | 앱을 띄울 때 만료 3초 전의 세션을 만들어 완료 화면을 보여 줍니다. 완료를 닫고 다시 시작한 세션은 설정한 길이만큼 진행됩니다. |
| `--ui-testing ending-soon`                     | 시작 버튼을 누르면 집중 종료 10초 전부터 세션을 시작합니다.                                                                  |
| `--ui-testing history`                         | 오늘 날짜에 25분·50분 완료, 집중 종료, 마감 초과 기록을 넣은 기록 화면입니다. 자정 직후에도 기록은 오늘에 속합니다.          |
| `--ui-testing history-failure --selected`      | 오늘의 기록을 읽을 때마다 실패합니다. 다시 확인해도 기록 오류가 남고, 타이머 화면에서는 시작할 수 없습니다.                  |
| `--ui-testing report-waiting --selected`       | 보고서 콘텐츠가 아직 오지 않은 대기 상태                                                                                     |
| `--ui-testing report-empty --selected`         | 보고서 데이터가 없는 상태                                                                                                    |
| `--ui-testing report-zero --selected`          | 실제 사용량이 0인 상태입니다. 빈 데이터와 실제 0은 보고서 확장이 쓰는 `UsageSummarySection`으로 그립니다.                    |

모드와 함께 쓰는 인자는 다음과 같습니다.

| 인자                            | 동작                                                                                                                                                   |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `--length <분>`                 | 집중 시간 설정을 지정합니다(25~50분, 5분 단위).                                                                                                        |
| `--solid-controls`              | 불투명한 버튼 대체 스타일을 보여 줍니다. 시스템의 투명도 설정은 바꾸지 않습니다.                                                                       |
| `--start-delay <초>`            | 합성 monitoring 등록을 최대 3초 늦춰 시작 진행 표시를 확인합니다. 실제 Screen Time 지연을 재현하지는 않습니다.                                         |
| `--break-delay <초>`            | 쉬는 시간 진행 표시를 최대 5초 띄운 뒤 전환합니다. 메인 스레드를 막지 않으므로 실제 기기의 멈춤은 재현하지 않습니다.                                   |
| `--break-timing short`          | 쉬는 시간 대기를 1·2·4초, 쉬는 시간을 3초, 마감 여유를 15초로 줄입니다. 대기 유예와 집중 시간은 줄이지 않습니다.                                       |
| `--everyday-fixture blocking`   | 실행 5분 전(5분 단위)에 시작해 2시간 동안 이어지는 합성 매일 제한을 합성 앱 1개와 함께 저장합니다. 범위가 자정에 닿지 않도록 고정 시간대로 계산합니다. |
| `--everyday-fixture preview`    | 08:00~18:00 범위에 점심 12:00~13:00을 풀어 두는 켜진 매일 제한을 합성 앱 1개와 함께 저장합니다. 고정 시간대에서 실행 시각은 12:00~12:30입니다.         |
| `--everyday-fixture off`        | `preview`와 같은 일정을 꺼진 상태로 저장합니다.                                                                                                        |
| `--everyday-off-wait <초>`      | 매일 제한 `오늘만 끄기`의 30초 대기를 1~30초로 줄입니다. 대기가 끝난 뒤의 유예는 바꾸지 않습니다. 합성 매일 제한에만 적용됩니다.                       |
| `--focus-filter-refusal <사유>` | 마지막 집중 모드 시작 거절을 저장해 설정의 집중 모드 안내에서 보여 줍니다. 사유는 `access`, `selection`, `busy`, `history`, `error` 중 하나입니다.     |

`--ui-testing ending-soon`과 `--break-timing short`를 함께 쓰면, 쉬는 시간을 가진 뒤 다시 집중하지 않은 세션이 시작 버튼을 누르고 약 29초 뒤에 마감에 닿습니다.

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

받아들여진 쉬는 시간 전환도 같은 방식으로 `BREAK_LATENCY action=<request|cancelWait|startBreak|resume> total_ms=...` 로그를 남깁니다.
`request`는 `쉬는 시간 갖기`, `cancelWait`는 `집중으로 돌아가기`나 앱을 떠날 때의 대기 취소, `startBreak`는 대기가 끝난 뒤의 자동 시작, `resume`은 `다시 집중하기`입니다.
진행 표시를 그리기 위한 프레임 대기와 거절된 탭은 이 시간에 포함되지 않습니다.

세션 종료 탭은 그 탭부터 종료 엔진 호출이 돌아올 때까지의 시간을 `END_LATENCY total_ms=...` 로그로 남깁니다.
그 뒤의 화면 갱신, 프레임 대기와 화면 애니메이션은 이 시간에 포함되지 않고, 진행 중인 세션이 없는 탭은 로그를 남기지 않습니다.

같은 실행에서 Screen Time 작업은 하나마다 `SCREEN_TIME_TIMING op=<register|register_break|register_everyday|stop|stop_break|stop_everyday|apply_shield> ms=...` 로그를 남깁니다.
`register`는 집중 세션, `register_break`는 쉬는 시간, `register_everyday`는 매일 제한의 `DeviceActivityCenter` 등록이고, `apply_shield`는 시작할 때의 집중 제한 적용입니다.
`stop`은 집중 세션과 그 쉬는 시간 활동 전체, `stop_break`는 쉬는 시간 하나, `stop_everyday`는 매일 제한 활동 하나의 `DeviceActivityCenter` 등록 해제입니다.
`apply_shield`는 시작에서만 남지만, 등록과 해제 줄은 시작 밖에서도 남습니다.
쉬는 시간 전환은 `register_break`와 함께 집중 세션을 다시 `register`하고, 콜백 처리, 상태 맞추기(reconcile)와 정리(cleanup)도 집중 세션을 다시 `register`할 수 있으며, 매일 제한 수렴은 잠금 구간마다 `register_everyday`를 남길 수 있습니다.
그래서 줄 이름만으로는 어느 작업에서 나온 줄인지 알 수 없습니다.
가장 가까운 `START_LATENCY` 줄에 바로 묶지 말고, 그 시작과 그 줄 사이에 쉬는 시간 전환이나 상태 맞추기 같은 다른 작업이 없었는지 함께 확인합니다.
등록 실패를 주입한 시작에서도 실제 등록 시간이 먼저 기록됩니다.
시작이나 쉬는 시간 전환 중에 남은 이 로그는 그 `START_LATENCY`나 `BREAK_LATENCY` 구간 안에 있으므로, total에는 로그를 남기는 시간도 포함됩니다.

`등록 시간 비교`는 저장되거나 등록된 세션이 없을 때만 동작하며, 지금을 포함하는 20분 구간(`current`)과 2분 뒤에 시작하는 20분 구간(`future`)을 번갈아 세 번씩 실제 `DeviceActivityCenter`에 등록하고 바로 멈춥니다.
등록마다 `SCREEN_TIME_PROBE interval=<current|future> n=<1..3> ms=...` 로그를 남기고, 등록이 실패하면 같은 줄에 `failed`와 `error=`를 붙입니다.
활동 이름은 `probe.<current|future>.<n>`이라 세션·쉬는 시간·매일 제한 활동으로 읽히지 않고, 버튼 동작 자체는 세션 파일과 제한을 바꾸지 않습니다.
다만 iOS가 `probe.*` 활동의 Monitor 콜백을 전달하면, 그 콜백도 다른 콜백처럼 잠금 구간 끝에서 매일 제한 store와 활동을 저장된 매일 제한 파일에 맞춥니다.
그래서 `매일 제한 store에 선택 적용(합집합 검사 없음)`의 결과는 이 버튼을 누르기 전에 기록합니다.
여섯 번의 등록과 일곱 번의 정지가 메인 스레드에서 이어지므로 끝날 때까지 화면이 멈추며, 끝나면 여섯 값이 진단 메시지에 나타납니다.
모든 등록이 측정된 집중 등록(약 2.32초)만큼 걸린다면 등록만 약 14초이며, 이는 추정이고 정지 시간은 잰 적이 없습니다.

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

## Monitor 콜백 시간 측정

Monitor 확장은 실행 인자를 받지 못하므로, 앱이 App Group의 `SessionControl/monitor-timing.json` 파일로 확장의 시간 측정을 켭니다.
설계와 줄의 뜻은 [Monitor timing 설계](../specs/2026-11-13-monitor-timing-design.md)에 있고, 이 기능은 Debug 빌드에만 들어 있습니다.

- 앱을 `--screen-time-diagnostics`와 함께 실행하면 실행할 때마다 이 파일을 새로 씁니다. 파일에는 `schemaVersion`과 쓴 시각 `writtenAt`만 들어 있습니다.
- 인자 없이 실제 런타임으로 실행하면 파일을 지웁니다. 실행 인자가 없는 집중 모드 필터의 백그라운드 실행도 여기에 해당하므로, 그 뒤에는 인자와 함께 다시 실행해야 측정이 켜집니다.
- `--ui-testing` 실행은 이 파일을 쓰지도, 읽지도, 지우지도 않습니다.
- 쓰기나 삭제가 실패해도 앱은 그대로 실행됩니다. 쓴 지 24시간이 지난 파일과 미래 시각의 파일은 꺼진 것으로 읽습니다.

파일이 유효하면 Monitor 콜백 하나가 아래 줄을 통합 로그(subsystem `kr.donminzzi.focusStudy.monitor`, category `timing`, notice 수준)에 남깁니다.
Xcode 콘솔의 앱 로그(`SCREEN_TIME_TIMING` 등)는 그대로입니다.

```plaintext
MONITOR_TIMING cb=<n> kind=<kind> activity=<activity> step=begin flag_ms=<ms>
MONITOR_TIMING cb=<n> kind=<kind> activity=<activity> step=access ms=<ms> state=<approved|denied|unknown>
MONITOR_TIMING cb=<n> kind=<kind> activity=<activity> step=lock attempt=<0-5> wait_ms=<ms> result=<acquired|busy>
MONITOR_TIMING cb=<n> kind=<kind> activity=<activity> step=marker ms=<ms> marker=<none|register|stop> result=<skip|continue>
MONITOR_TIMING cb=<n> kind=<kind> activity=<activity> step=call op=<op> ms=<ms>
MONITOR_TIMING cb=<n> kind=<kind> activity=<activity> step=section hold_ms=<ms>
MONITOR_TIMING cb=<n> kind=<kind> activity=<activity> step=end total_ms=<ms> result=<ran|skipped|lock_timeout|error>
```

- `cb`는 그 확장 프로세스에서 측정한 콜백의 번호이고, 로그 도구가 보여 주는 프로세스 id와 함께 한 콜백의 줄을 묶습니다.
- `kind`는 `didStart`, `didEnd`, `willEndWarning` 중 하나이고, `activity`는 `focus`, `break`, `everyday`, `other` 중 하나입니다. 활동 이름, UUID, 토큰, 앱 이름, 도메인은 어느 줄에도 없습니다.
- `op`는 `register`, `register_break`, `register_everyday`, `stop`, `stop_break`, `stop_everyday`, `apply_shield`, `clear_shield`, `apply_everyday`, `clear_everyday` 중 하나입니다.
- `hold_ms`는 잠금 구간 본문이 걸린 시간입니다. 잠금을 잡은 시도의 `lock`, `call`, `section` 줄은 잠금을 푼 뒤에 한꺼번에 남으므로, 로그를 남기는 시간은 `hold_ms`에 들어가지 않습니다.
- 잠금 구간 안에서 프로세스가 끝난 콜백은 `begin`만 있고 `end`가 없습니다. 반대로 `end`가 없다는 것만으로는 어느 단계였는지 알 수 없습니다. 접근 상태 읽기, 잠금 대기, 재시도 사이의 0.25초 대기 중에 끝나도 `end`가 없으므로, 마지막으로 남은 줄로 단계를 좁힙니다.

기기를 Mac에 연결한 상태에서 실행이 끝난 뒤에 줄을 읽습니다.

```bash
log collect --device-udid <UDID> --last 30m --output monitor-timing.logarchive
log show --archive monitor-timing.logarchive --predicate 'subsystem == "kr.donminzzi.focusStudy.monitor" && category == "timing"'
```

Mac의 `log stream`은 Mac 자신의 로그만 읽으므로 기기의 줄을 볼 수 없습니다.
Mac의 Console 앱에서 기기를 고르고 같은 subsystem과 category로 걸러 실시간으로 볼 수 있는지는 아직 확인하지 않았습니다.
`log collect`가 이 기기와 iOS 버전에서 동작하는지도 실기기에서 확인한 적이 없으며, 확인 절차는 설계 문서의 [실기기 검증](../specs/2026-11-13-monitor-timing-design.md#physical-device-verification)에 있습니다.
`.logarchive`는 저장소에 넣지 않습니다.
