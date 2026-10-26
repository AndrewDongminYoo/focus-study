# 독립 전체 검토

검토 범위: `4b6f0dc..afbee63`. 구현자가 아닌 독립 검토자 한 명이 읽기 전용으로 전체 변경을 검토했다. 단계별 검토자나 추가 검토자를 만들지 않았다. 검토자는 파일·Git·계정·제한을 변경하지 않았으며 실기기 동작을 검증했다고 주장하지 않았다.

## 발견 사항과 처리

1. Important: 종료 정리 뒤 ending/terminal 저장이 모두 실패하거나 읽기가 잠시 실패하면, 이전 active 메타데이터를 나중에 그대로 신뢰하는 문제가 있었다. `testFailedCleanupWritesCannotRestoreActiveAfterEngineRestart`, `testTransientReadFailureStopsOwnedMonitoringAndCannotRestoreActiveAfterRestart`에서 실제 assertion 실패를 확인했다. 등록 부재를 중단으로 조정하고 읽기 실패 시 이 앱 namespace의 등록도 정리하도록 수정했다. 기존 ending이 저장된 경우 종료 사유와 관측 시각을 유지한다.
2. Important: 선택·SwiftData 초기화 오류가 제어 복구와 중도 종료를 막았다. `StartupRecoveryTests` 두 개와 `testStartupStorageFailureAllowsSafeEndAndRetry`를 실패시킨 뒤, 제어 runtime을 저장소 초기화에서 분리하고 오류 화면에 종료·재시도를 연결했다. terminal은 history 저장 성공 전까지 유지한다.

Critical 또는 Minor 발견 사항은 없었다. 추가 검토는 요청하지 않고 한 번의 TDD 수정 단계와 전체 suite로 처리한다. 최종 통과 결과는 구현 기록에 남긴다.

## 검토로 확인하지 못한 항목

실제 기기 권한·shield 적용·콜백 시점·Report 갱신, iOS 17 런타임과 DeviceActivity의 calendar 구성요소 해석은 실제 런타임 증거가 필요하다. 이 한계를 기능 실패로 단정하거나 검증 완료로 표시하지 않는다. 별도 추측성 calendar 결함은 제기하지 않았다.

## 수정 후 결과

한 번의 수정 단계 후 단위 테스트 41개, iOS Simulator SDK/UI 테스트 11개가 모두 통과했다. 두 프로세스 경쟁 검증과 서명 없는 Release 빌드도 통과했다. 저장소 복구가 만료 후에 발생하는 경우도 동일 회귀 테스트에 포함해 일반 완료로 오인하지 않도록 검증했다. 재검토자를 추가하지 않았으며 실제 기기 검증은 여전히 남아 있다.
