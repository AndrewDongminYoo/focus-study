import SwiftUI

/// The stored phase owns this screen, so dismissing a presentation cannot hide a paused session.
/// Layout and texts: docs/specs/2026-11-23-screen-redesign-design.md, "Break screen".
struct BreakSessionView: View {
    let model: FocusModel
    let onEnd: () -> Void
    /// DEBUG device diagnostics only: the settings sheet stays reachable during a break.
    var onSettings: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 57
    @AccessibilityFocusState private var phaseHeadingFocused: Bool
    private var isWaiting: Bool { model.current?.phase == .waiting }
    private var isOnBreak: Bool { model.current?.phase == .onBreak }
    private var isPending: Bool { model.pendingBreak != nil }
    var body: some View {
        FocusScreenLayout {
            Text("잠깐의 쉼").font(.subheadline.weight(.medium)).foregroundStyle(FocusTheme.Screen.secondaryInk)
            Spacer()
            FocusCapsuleLabel(text: isWaiting ? "휴식 전환 대기" : isOnBreak ? "쉬는 시간" : "다시 집중할 시간",
                              textColor: FocusTheme.Screen.accentText, fill: FocusTheme.Screen.pill)
            if let onSettings {
                Button(action: onSettings) {
                    Image(systemName: "gearshape").frame(width: FocusTheme.Layout.minimumTapTarget, height: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(FocusTheme.Screen.ink).accessibilityLabel("설정").accessibilityIdentifier("settingsButton")
            }
        } title: {
            Text(isWaiting ? "쉬기 전에,\n잠시만 기다려요" : isOnBreak ? "제한을 잠시\n풀어 두었어요" : "쉬는 시간이\n끝났어요")
                .foregroundStyle(FocusTheme.Screen.ink).accessibilityAddTraits(.isHeader).accessibilityFocused($phaseHeadingFocused)
        } dial: {
            FocusDial(turns: turns, background: FocusTheme.Screen.canvas, animatesDot: !reduceMotion) {
                Text(isWaiting ? "쉬는 시간까지" : isOnBreak ? "남은 쉬는 시간" : "쉬는 시간 끝")
                    .font(.subheadline).foregroundStyle(FocusTheme.Screen.secondaryInk).lineLimit(1).minimumScaleFactor(0.5)
                if let seconds = model.breakRemaining {
                    countdown(seconds).accessibilityLabel("쉬는 시간 \(seconds / 60)분 \(seconds % 60)초 남음").accessibilityIdentifier("breakCountdown")
                } else if let seconds = model.waitRemaining {
                    countdown(seconds).accessibilityLabel("대기 시간 \(seconds)초 남음").accessibilityIdentifier("breakWaitCountdown")
                } else {
                    countdown(0).accessibilityHidden(true)
                }
                Text(isWaiting ? "\(model.waitRemaining ?? 0)초 후 휴식 시작" : isOnBreak ? "끝나면 다시 제한해요" : "다시 제한했어요")
                    .font(.footnote.weight(.medium)).foregroundStyle(FocusTheme.Screen.accentText).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            }
            // A new phase starts a new dial, so the dot moves to its new place without turning back over the ring.
            .id(model.current?.phase)
        } notes: {
            if isWaiting { Text("기다리는 동안에는 계속 제한해요.").font(.subheadline).foregroundStyle(FocusTheme.Screen.secondaryInk) }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(FocusTheme.Palette.error).accessibilityIdentifier("startError")
                Button("다시 확인하기") { model.refresh() }.accessibilityIdentifier("retry")
            }
        } actions: {
            if isWaiting {
                waitCard
                Button("집중으로 돌아가기") { model.requestBreakAction(.cancelWait) }
                    .buttonStyle(primaryStyle).disabled(isPending).accessibilityIdentifier("breakWaitCancel")
            } else {
                if !isOnBreak {
                    Text(deadlineNotice).font(.subheadline).foregroundStyle(FocusTheme.Screen.ink).monospacedDigit()
                        .modifier(FocusCard()).accessibilityIdentifier("deadlineNotice")
                }
                Button("다시 집중하기") { model.requestBreakAction(.resume) }
                    .buttonStyle(primaryStyle).disabled(isPending).accessibilityIdentifier("resume")
                if let pending = model.pendingBreak {
                    BreakFeedback(model: model, pending: pending, textColor: FocusTheme.Screen.secondaryInk).frame(minHeight: FocusTheme.Layout.minimumTapTarget)
                }
            }
            FocusEndButton(action: onEnd).disabled(isPending)
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("breakScreen")
        .onChange(of: model.current?.phase, initial: true) { _, _ in phaseHeadingFocused = true }
        .sensoryFeedback(.selection, trigger: isOnBreak)
    }
    /// Returning from the wait, or the automatic start at its end, replaces the first line with the feedback until the transition runs.
    private var waitCard: some View {
        let left = model.waitRemaining ?? 0
        return VStack(alignment: .leading, spacing: FocusTheme.Layout.relatedSpacing) {
            if let pending = model.pendingBreak {
                BreakFeedback(model: model, pending: pending, textColor: FocusTheme.Screen.secondaryInk).frame(maxWidth: .infinity, minHeight: FocusTheme.Layout.minimumTapTarget)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("지금").font(.footnote.weight(.bold)).foregroundStyle(FocusTheme.Screen.accentText)
                    Spacer(minLength: FocusTheme.Layout.inlineSpacing)
                    Text("\(left)초 대기 → 쉬는 시간 시작").font(.subheadline.weight(.medium)).foregroundStyle(FocusTheme.Screen.ink).monospacedDigit()
                }
                .accessibilityElement(children: .ignore).accessibilityLabel("쉬는 시간 준비 중").accessibilityValue("\(left)초 남음")
                .accessibilityIdentifier("breakWait")
            }
            // One text, so that the two lines read as the one sentence that VoiceOver and the UI tests read.
            (Text("다른 앱으로 나가면 집중으로 돌아가요.\n").foregroundStyle(FocusTheme.Screen.secondaryInk)
                + Text("이번 쉬는 시간을 쓰면 \(model.breaksLeft - 1)번 남아요.").fontWeight(.medium).foregroundStyle(FocusTheme.Screen.accentText))
                .font(.subheadline).lineSpacing(6)
                .accessibilityLabel("다른 앱으로 나가면 집중으로 돌아가요. 이번 쉬는 시간을 쓰면 \(model.breaksLeft - 1)번 남아요.").accessibilityIdentifier("breaksLeft")
        }
        .modifier(FocusCard())
    }
    /// Navy with a cream label in the light appearance; the cream fill with a navy label in the dark appearance.
    private var primaryStyle: FocusFillButtonStyle {
        scheme == .dark ? FocusFillButtonStyle(fill: FocusTheme.Screen.creamFill, label: FocusTheme.Room.background)
            : FocusFillButtonStyle(fill: FocusTheme.Room.background, label: FocusTheme.Room.text)
    }
    /// The wait share, the break share, or a full turn after the break (spec "Dial").
    private var turns: Double {
        if let progress = model.waitProgress { return progress }
        if let left = model.breakRemaining {
            let length = max(1, model.services.engine.timing.breakLength)
            return min(1, max(0, (length - Double(left)) / length))
        }
        return 1
    }
    private func countdown(_ seconds: Int) -> some View {
        Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
            .font(.system(size: countdownSize, weight: .medium)).monospacedDigit().foregroundStyle(FocusTheme.Screen.ink)
            .lineLimit(1).minimumScaleFactor(0.5).contentTransition(.numericText(countsDown: true))
            .animation(reduceMotion ? nil : .default, value: seconds)
            .accessibilityAddTraits(.updatesFrequently)
    }
    private var deadlineNotice: String {
        let left = model.resumeRemaining ?? 0
        return left > 0 ? "\(left / 60)분 \(left % 60)초 안에 다시 집중하면 이 세션을 마칠 수 있어요."
            : "이제는 다시 집중해도 시간 안에 마칠 수 없어서 이 세션은 집중 시간으로 기록되지 않아요."
    }
}
