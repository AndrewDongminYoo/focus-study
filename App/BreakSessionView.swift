import SwiftUI

/// The stored phase owns this screen, so dismissing a presentation cannot hide a paused session.
struct BreakSessionView: View {
    let model: FocusModel
    let onEnd: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 54
    private var isWaiting: Bool { model.current?.phase == .waiting }
    private var isOnBreak: Bool { model.current?.phase == .onBreak }
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)
            VStack(spacing: 24) {
                Text(isWaiting ? "쉬기 전에 잠시 기다려요" : isOnBreak ? "쉬는 시간" : "다시 집중할 시간")
                    .font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                if let seconds = model.breakRemaining {
                    countdown(seconds, label: "쉬는 시간 \(seconds / 60)분 \(seconds % 60)초 남음", identifier: "breakCountdown")
                        .foregroundStyle(.tint)
                } else if let seconds = model.waitRemaining {
                    countdown(seconds, label: "대기 시간 \(seconds)초 남음", identifier: "breakWaitCountdown")
                } else {
                    Image(systemName: "checkmark.circle").font(.system(size: countdownSize, weight: .light)).foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
                Text(isWaiting ? "기다리는 동안에는 계속 제한해요." : isOnBreak
                     ? "제한을 잠시 풀었어요. 쉬는 시간이 끝나면 다시 제한해요."
                     : "쉬는 시간이 끝나서 다시 제한했어요.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer(minLength: 48)
            VStack(spacing: 20) {
                if isWaiting {
                    breakWait
                    Text("다른 앱으로 나가면 집중으로 돌아가요. 이번 쉬는 시간을 쓰면 \(model.breaksLeft - 1)번 남아요.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).accessibilityIdentifier("breaksLeft")
                    Button("집중으로 돌아가기") { model.cancelWait() }.frame(minHeight: 44).accessibilityIdentifier("breakWaitCancel")
                } else {
                    Button("다시 집중하기") { model.resume() }
                        .buttonStyle(.borderedProminent).controlSize(.large).modifier(ProminentLabel()).accessibilityIdentifier("resume")
                    if !isOnBreak {
                        Text(deadlineNotice).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .monospacedDigit().accessibilityIdentifier("deadlineNotice")
                    }
                }
                Button("집중 종료", role: .destructive, action: onEnd).frame(minHeight: 44).accessibilityIdentifier("end")
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red).accessibilityIdentifier("startError")
                    Button("다시 확인하기") { model.refresh() }.accessibilityIdentifier("retry")
                }
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 24)
        .accessibilityElement(children: .contain).accessibilityIdentifier("breakScreen")
    }
    private func countdown(_ seconds: Int, label: String, identifier: String) -> some View {
        Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
            .font(.system(size: countdownSize, weight: .light, design: .rounded)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.5).contentTransition(.numericText(countsDown: true))
            .animation(reduceMotion ? nil : .default, value: seconds)
            .accessibilityLabel(label).accessibilityIdentifier(identifier).accessibilityAddTraits(.updatesFrequently)
    }
    private var breakWait: some View {
        let progress = model.waitProgress ?? 0, left = model.waitRemaining ?? 0
        return Text("\(left)초 뒤에 쉬는 시간이 시작돼요").font(.headline).monospacedDigit()
            .padding(.vertical, 16).padding(.horizontal, 20).frame(maxWidth: .infinity)
            .background(alignment: .leading) {
                GeometryReader { proxy in Capsule().fill(Color.accentColor.opacity(0.3)).frame(width: proxy.size.width * progress) }
            }
            .background(Capsule().fill(Color.secondary.opacity(0.12))).clipShape(Capsule())
            .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
            .accessibilityElement(children: .ignore).accessibilityLabel("쉬는 시간 준비 중").accessibilityValue("\(left)초 남음")
            .accessibilityIdentifier("breakWait")
    }
    private var deadlineNotice: String {
        let left = model.resumeRemaining ?? 0
        return left > 0 ? "\(left / 60)분 \(left % 60)초 안에 다시 집중하면 이 세션을 마칠 수 있어요."
            : "이제는 다시 집중해도 시간 안에 마칠 수 없어서 이 세션은 집중 시간으로 기록되지 않아요."
    }
}
