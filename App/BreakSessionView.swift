import SwiftUI

/// The stored phase owns this screen, so dismissing a presentation cannot hide a paused session.
struct BreakSessionView: View {
    let model: FocusModel
    let onEnd: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 54
    @AccessibilityFocusState private var phaseHeadingFocused: Bool
    private var isWaiting: Bool { model.current?.phase == .waiting }
    private var isOnBreak: Bool { model.current?.phase == .onBreak }
    private var isPending: Bool { model.pendingBreak != nil }
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)
            VStack(spacing: FocusTheme.Layout.sectionSpacing) {
                Text(isWaiting ? "쉬기 전에 잠시 기다려요" : isOnBreak ? "쉬는 시간" : "다시 집중할 시간")
                    .font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader).accessibilityFocused($phaseHeadingFocused)
                if let seconds = model.breakRemaining {
                    countdown(seconds, label: "쉬는 시간 \(seconds / 60)분 \(seconds % 60)초 남음", identifier: "breakCountdown")
                        .foregroundStyle(FocusTheme.Palette.accent)
                } else if let seconds = model.waitRemaining {
                    countdown(seconds, label: "대기 시간 \(seconds)초 남음", identifier: "breakWaitCountdown")
                } else {
                    Image(systemName: "checkmark.circle").font(.system(size: countdownSize, weight: .light)).foregroundStyle(FocusTheme.Palette.accent)
                        .accessibilityHidden(true)
                }
                Text(isWaiting ? "기다리는 동안에는 계속 제한해요." : isOnBreak
                     ? "제한을 잠시 풀었어요. 쉬는 시간이 끝나면 다시 제한해요."
                     : "쉬는 시간이 끝나서 다시 제한했어요.")
                    .font(.subheadline).foregroundStyle(FocusTheme.Palette.secondaryText).multilineTextAlignment(.center)
            }
            Spacer(minLength: 48)
            VStack(spacing: FocusTheme.Layout.controlSpacing) {
                if isWaiting {
                    // Returning from the wait, or the automatic start at its end, replaces the progress bar until the transition runs.
                    if let pending = model.pendingBreak {
                        BreakFeedback(model: model, pending: pending).frame(minHeight: FocusTheme.Layout.minimumTapTarget)
                    } else {
                        breakWait
                    }
                    Text("다른 앱으로 나가면 집중으로 돌아가요. 이번 쉬는 시간을 쓰면 \(model.breaksLeft - 1)번 남아요.")
                        .font(.footnote).foregroundStyle(FocusTheme.Palette.secondaryText).multilineTextAlignment(.center).accessibilityIdentifier("breaksLeft")
                    Button("집중으로 돌아가기") { model.requestBreakAction(.cancelWait) }.frame(minHeight: FocusTheme.Layout.minimumTapTarget)
                        .disabled(isPending).accessibilityIdentifier("breakWaitCancel")
                } else {
                    Button("다시 집중하기") { model.requestBreakAction(.resume) }
                        .modifier(FocusPrimaryAction()).controlSize(.large).modifier(ProminentLabel()).disabled(isPending).accessibilityIdentifier("resume")
                    if let pending = model.pendingBreak {
                        BreakFeedback(model: model, pending: pending).frame(minHeight: FocusTheme.Layout.minimumTapTarget)
                    }
                    if !isOnBreak {
                        Text(deadlineNotice).font(.footnote).foregroundStyle(FocusTheme.Palette.secondaryText).multilineTextAlignment(.center)
                            .monospacedDigit().accessibilityIdentifier("deadlineNotice")
                    }
                }
                Button("집중 종료", role: .destructive, action: onEnd).frame(minHeight: FocusTheme.Layout.minimumTapTarget)
                    .disabled(isPending).accessibilityIdentifier("end")
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(FocusTheme.Palette.error).accessibilityIdentifier("startError")
                    Button("다시 확인하기") { model.refresh() }.accessibilityIdentifier("retry")
                }
            }
        }
        .padding(.horizontal, FocusTheme.Layout.screenInset).padding(.bottom, FocusTheme.Layout.sectionSpacing)
        .accessibilityElement(children: .contain).accessibilityIdentifier("breakScreen")
        .onChange(of: model.current?.phase, initial: true) { _, _ in phaseHeadingFocused = true }
        .sensoryFeedback(.selection, trigger: isOnBreak)
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
            .padding(.vertical, FocusTheme.Layout.controlSpacing).padding(.horizontal, FocusTheme.Layout.screenInset).frame(maxWidth: .infinity)
            .background(alignment: .leading) {
                GeometryReader { proxy in Capsule().fill(FocusTheme.Palette.progressFill).frame(width: proxy.size.width * progress) }
            }
            .background(Capsule().fill(FocusTheme.Palette.progressTrack)).clipShape(Capsule())
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
