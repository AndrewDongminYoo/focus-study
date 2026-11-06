import SwiftUI

extension FocusActivityContent {
    var planTitle: String {
        switch phase {
        case .focus: return focusEnd == targetAt ? "집중 종료 예정" : "세션 마감 예정"
        case .waiting: return "앱에서 계속해 주세요"
        case .onBreak: return "쉬는 시간 종료 예정"
        case .breakOver: return "집중 복귀 마감"
        }
    }
    var compactTitle: String {
        switch phase {
        case .focus: return focusEnd == targetAt ? "집중 예정" : "세션 마감"
        case .waiting: return "앱에서"
        case .onBreak: return "휴식 예정"
        case .breakOver: return "복귀 마감"
        }
    }
}

/// Every presentation qualifies the stored phase as a plan. Even a delayed stale redraw
/// cannot turn the countdown into a claim about current shielding or completion.
struct FocusActivityCountdown: View {
    let content: FocusActivityContent
    let isStale: Bool
    var compact = false
    var body: some View {
        if isStale || content.targetAt == nil || (content.targetAt ?? .distantPast) <= Date() {
            Text(compact ? "확인" : "앱에서 확인해 주세요")
                .font(compact ? .caption : .headline).accessibilityIdentifier("activityStale")
        } else if let target = content.targetAt {
            Text(timerInterval: content.checkedAt...max(content.checkedAt, target), countsDown: true, showsHours: false)
                .font(compact ? .system(.caption, design: .rounded, weight: .semibold) : .system(.largeTitle, design: .rounded, weight: .semibold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityLabel("예정 시간까지")
                .accessibilityValue(Text(timerInterval: content.checkedAt...max(content.checkedAt, target), countsDown: true, showsHours: false))
                .accessibilityIdentifier("activityCountdown").accessibilityAddTraits(.updatesFrequently)
        }
    }
}

struct FocusActivityCard: View {
    let content: FocusActivityContent
    let isStale: Bool
    var body: some View {
        let needsConfirmation = isStale || content.targetAt == nil || (content.targetAt ?? .distantPast) <= Date()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label("온:공", systemImage: "timer").font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                Text(content.planTitle).font(.subheadline.weight(.medium)).multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("activityPlanTitle")
            }
            HStack(alignment: .firstTextBaseline) {
                FocusActivityCountdown(content: content, isStale: needsConfirmation)
                Spacer(minLength: 8)
                if let target = content.targetAt {
                    Text(target, style: .time).font(.headline).monospacedDigit()
                        .accessibilityLabel("예정 시각").accessibilityValue(Text(target, style: .time))
                }
            }
            confirmation.font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
                .accessibilityHint("현재 상태는 앱에서 확인해 주세요")
                .accessibilityIdentifier("activityConfirmation")
        }
        .padding(12)
    }
    private var confirmation: Text {
        let checked = Text(content.checkedAt, format: .dateTime.hour().minute().second())
        if content.phase == .breakOver {
            return Text("세션 마감 \(Text(content.deadline, style: .time)) · 마지막 확인 \(checked)")
        }
        return Text("마지막 확인 \(checked)")
    }
}

struct FocusActivityCompactLeading: View {
    let content: FocusActivityContent
    var body: some View {
        Text(content.compactTitle).font(.caption2)
    }
}
