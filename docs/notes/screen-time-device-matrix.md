# Screen Time 검증 기록

2026-10-26. 실제 개인 앱·웹사이트의 제한을 적용하지 않았다. 모든 자동 테스트는 합성 데이터 또는 앱이 만든 기록만 사용했다.

## 실행한 검증

아래는 2026-10-26 로컬 실행 당시 기록이며 현재 head를 재검증한 결과가 아니다.
명령과 suite 구성은 [README](../../README.md#실행과-검증)를 따르며, 현재 테스트 수는 새 실행 출력에서 확인한다.

| 환경/명령 | 범위 | 관측 결과 |
| --- | --- | --- |
| macOS / Xcode 27.1 `swift test` | 제어·선택·날짜·시작 복구 32개, SwiftData 5개, 합성 Report 집계 4개 | 41개 통과, 실패 0개 |
| macOS `focus-control-race --verify` | 생산 flock 구현을 사용하는 두 별도 프로세스의 새 시작/이전 콜백 | `PASS: stale A cannot clear B` |
| iPhone 18 Pro Simulator / iOS 27.0 | SDK 인증 상태·schedule 3개, 선택 저장소 2개, 기록 오류와 세션 제어 분리 2개 | 7개 통과 |
| 같은 Simulator / DEBUG fixture | 거절 안내, 중도 종료 기록, 활성 중 선택 잠금, Picker 취소/저장, 등록 실패, 초기 저장소 실패 후 종료·재시도, 같은 날 보고서 새로고침 | 7개 통과, 실패 0개 |
| 서명 없는 Simulator 및 Release 기기 아키텍처 build | App/Monitor/Report 세 제품 타깃 | `BUILD SUCCEEDED` |

시뮬레이터 결과를 실제 Screen Time 권한·보고서·차단 적용 증거로 사용하지 않는다. 시스템은 실제 기기에서 지연되거나 다른 동작을 보일 수 있다.

## 실제 기기 인수 검증: 모두 미실행

| 시나리오 | 기대 동작 | 상태 |
| --- | --- | --- |
| 개인 권한 허용/거절 | 허용 후 선택 가능; 거절 시 설정 안내만 제공 | 미검증 |
| 활성 중 권한 철회 | 관측 시 미사용/중단으로 전환하고 앱 소유 제한 정리 | 미검증 |
| 앱 강제 종료/잠금 | 시스템 monitoring 유지 여부와 해제 지연 관측 | 미검증 |
| 실제 25분 만료 | 예정 시각과 실제 정리 관측 시각 구분 | 미검증 |
| 앱 재실행/기기 재시작 | preparing/ending/만료 상태 조정, terminal 기록 중복 없음 | 미검증 |
| 연속 시작/중복 종료 | 세션 중복 없음; 종료 멱등 | 미검증 |
| 실제 등록 실패 | 활성 표시 없이 이 앱의 store/monitoring 롤백 | 미검증; 순수 제어 및 UI는 주입 실패로 검증 |
| 이전 UUID의 지연 콜백 | 새 세션 제한을 해제하지 않음 | 미검증; 두 프로세스 합성 경합은 통과 |
| 자정/시간대/수동 시각 변경 | 오늘 목록 갱신; 절대 만료 유지; 관측한 시각 변경은 중단 | 미검증; 순수 날짜 로직과 schedule 경계는 통과 |
| 50/51개 실제 Picker 선택 | 최대 50개 허용; 51개는 기존 선택 유지 | 미검증; 합성 개수 검증은 통과 |
| Safari 일반/비공개 탭 | 선택/미선택 도메인, 동일 도메인의 여러 경로 확인 | 미검증 |
| Report 표시 및 갱신 | 현재 기기의 오늘 앱/웹 사용량이 확장 안에만 표시됨 | 미검증 |
| 다른 브라우저/WKWebView | OS·브라우저·기기별 실제 결과를 별도로 기록 | 미검증; 지원 보장 없음 |

실기기 준비 후 각 행에 실제 기기·OS·브라우저 버전, 예정/관측 시각, 통과/실패와 재현 절차를 추가한다. 도메인 이름·앱 선택 토큰·개인 사용량을 파일에 내보내지 않는다.

## 서명과 배포

- 개발 서명: [초기 환경 확인](../specs/2026-10-26-focus-study-design.md#환경-확인과-선행-조건)의 관측은 과거 기록이다.
  실기기 작업 전에 현재 identity와 profile을 다시 확인하며 계정 가입 여부를 추정하지 않는다.
- 식별자 placeholder와 변경 대상은 [기기 준비 안내](../../README.md#실제-기기를-연결하기-전)를 따른다.
- 기기 등록·적합한 개발 provisioning profile·Family Controls 개발 capability의 일치는 미확인이다.
- 당시 본체·Monitor·Report의 배포 entitlement는 신청하지 않았다.
  각 App ID의 배포 승인을 개발 빌드 가능 여부와 구분하며 [Apple 신청 안내](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)를 확인한다.
- 이 실기기 검증 단계에서는 계정·인증서·프로필·entitlement 변경이나 실제 제한 적용을 수행하지 않았다.
  GitHub 후속 작업 이력은 아래 PR 기록과 구분한다.

## PR #1 후속 검토

`8b3cd11`의 최초 hosted CI 성공은 당시 기록이며 현재 PR 상태를 뜻하지 않는다.
후속 지적과 수정 근거는 [검토 기록](independent-review.md#github-후속-코드-리뷰), 실행 순서는 [구현 기록](../implementation-ledger.md)에 남긴다.
로컬 후속 결과는 위 표를 기준으로 하고, 새 head의 hosted 결과는 해당 PR checks에서 확인한다.
