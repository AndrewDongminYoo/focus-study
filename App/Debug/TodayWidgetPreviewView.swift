#if DEBUG
import SwiftUI

/// Draws the production home screen widget view for one synthetic state: no file read, no App Group access and no WidgetKit request.
/// The frame is not the system's small size on every device. The second widget forces the flat look of the accented mode,
/// which only approximates that mode: the system's tint and its removal of the background are not reproduced.
struct TodayWidgetPreviewView: View {
    let mode: String
    private var state: TodayWidgetState {
        switch mode {
        case "empty": return .empty
        case "check": return .check
        // The longest time of one day, for the ellipsis at large text sizes.
        case "long": return .numbers(count: 12, focusSeconds: 86_340)
        default: return TodayWidgetView.sample
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("홈 화면 위젯 미리보기").font(.headline).accessibilityIdentifier("widgetPreviewReady")
                Text("작은 위젯").font(.caption)
                // The widget draws edge to edge (`contentMarginsDisabled`), and its background is drawn here because `containerBackground` draws nothing in an app.
                // Outside a widget `widgetFamily` reads `systemMedium`, so each preview names its family.
                TodayWidgetView(state: state, family: .systemSmall).frame(width: 170, height: 170)
                    .background { TodayWidgetBackground() }
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                Text("중간 위젯").font(.caption)
                // 364 × 170, shrunk to fit a narrower screen; the view scales itself to the size it gets.
                TodayWidgetView(state: state, family: .systemMedium).aspectRatio(364 / 170, contentMode: .fit).frame(maxWidth: 364)
                    .background { TodayWidgetBackground() }
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                Text("강조 모드 근사(평면)").font(.caption)
                VStack(alignment: .leading, spacing: 12) {
                    TodayWidgetView(state: state, drawsFlat: true, family: .systemSmall).frame(width: 170, height: 170)
                        .background { TodayWidgetBackground(drawsFlat: true) }
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                    TodayWidgetView(state: state, drawsFlat: true, family: .systemMedium).aspectRatio(364 / 170, contentMode: .fit).frame(maxWidth: 364)
                        .background { TodayWidgetBackground(drawsFlat: true) }
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                }
                .padding(3)
                .background(LinearGradient(colors: [Color(red: 0.15, green: 0.2, blue: 0.3), Color(red: 0.24, green: 0.2, blue: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
                .accessibilityHidden(true)
            }.padding()
        }.background(Color(uiColor: .systemGroupedBackground))
    }
}
#endif
