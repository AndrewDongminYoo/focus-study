import SwiftUI

/// Shared rendering only; the host supplies synthetic values in DEBUG fixtures.
struct UsageSummarySection: View {
    let total: TimeInterval?
    var body: some View {
        Section("이 기기의 오늘 사용 시간") {
            if let total {
                Text(Duration.seconds(total).formatted(.units(allowed: [.hours, .minutes], width: .wide)))
                    .font(.title).accessibilityIdentifier("reportTotal")
            } else {
                Text("아직 보고서 데이터를 표시할 수 없습니다. 잠시 후 다시 확인해 주세요.")
                    .foregroundStyle(.secondary).accessibilityIdentifier("reportUnavailable")
            }
        }
    }
}
