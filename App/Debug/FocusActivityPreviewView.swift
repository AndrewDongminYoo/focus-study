#if DEBUG
import SwiftUI

/// Synthetic view input only: no authorization, monitoring, shields or ActivityKit request.
struct FocusActivityPreviewView: View {
    let mode: String
    @State private var content: FocusActivityContent
    init(mode: String) {
        self.mode = mode
        let now = Date()
        var checkedAt = now.addingTimeInterval(-10)
        var session = ControlSession(startedAt: now.addingTimeInterval(-1320))
        session.phase = .active
        switch mode {
        case "break":
            session.phase = .onBreak; session.pausedAt = now.addingTimeInterval(-25)
            session.breakEndsAt = now.addingTimeInterval(170); session.deadlineCredit = 195
        case "return":
            session.phase = .breakOver; session.pausedAt = now.addingTimeInterval(-205)
            session.breakEndsAt = now.addingTimeInterval(-10); session.deadlineCredit = 195
        case "waiting":
            session.phase = .waiting; session.pausedAt = checkedAt; session.waitEndsAt = now.addingTimeInterval(5)
        case "stale":
            session.phase = .onBreak; session.pausedAt = now.addingTimeInterval(-225)
            session.breakEndsAt = now.addingTimeInterval(-30); session.deadlineCredit = 195
            checkedAt = now.addingTimeInterval(-40)
        case "deadline":
            session = ControlSession(startedAt: now.addingTimeInterval(-1800)); session.phase = .active; session.pausedSeconds = 900
        case "late":
            session = ControlSession(startedAt: now.addingTimeInterval(-2000)); session.phase = .breakOver
            session.pausedAt = now.addingTimeInterval(-800); session.breakEndsAt = now.addingTimeInterval(-605); session.deadlineCredit = 195
        default: break
        }
        guard let projected = FocusActivityProjection.make(session: session, now: checkedAt, timing: .standard) else {
            preconditionFailure("Invalid activity preview fixture")
        }
        _content = State(initialValue: projected.content)
    }
    private var isStale: Bool { mode == "stale" || mode == "late" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Live Activity 미리보기").font(.headline).accessibilityIdentifier("activityPreviewReady")
                Text("잠금 화면").font(.caption)
                FocusActivityCard(content: content, isStale: isStale)
                    .background(.background, in: RoundedRectangle(cornerRadius: 20))
                Text("Dynamic Island · 확장").font(.caption)
                FocusActivityCard(content: content, isStale: isStale).environment(\.colorScheme, .dark)
                    .background(.black, in: RoundedRectangle(cornerRadius: 20))
                Text("Dynamic Island · 간결").font(.caption)
                HStack {
                    FocusActivityCompactLeading(content: content)
                    Spacer()
                    FocusActivityCountdown(content: content, isStale: isStale, compact: true)
                }.environment(\.colorScheme, .dark).padding().background(.black, in: Capsule())
                Text("Dynamic Island · 최소").font(.caption)
                Image(systemName: isStale ? "clock.badge.exclamationmark" : "timer").foregroundStyle(.white).padding()
                    .background(.black, in: Circle())
            }.padding()
        }.background(Color(uiColor: .systemGroupedBackground))
    }
}
#endif
