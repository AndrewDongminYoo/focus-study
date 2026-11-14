#if DEBUG
import SwiftUI

/// Draws the production home screen widget view for one synthetic state: no file read, no App Group access and no WidgetKit request.
/// The frame is not the system's small size, and it shows neither the accented mode nor the removed background.
struct TodayWidgetPreviewView: View {
    let mode: String
    private var state: TodayWidgetState {
        switch mode {
        case "empty": return .empty
        case "check": return .check
        default: return TodayWidgetView.sample
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("홈 화면 위젯 미리보기").font(.headline).accessibilityIdentifier("widgetPreviewReady")
                Text("작은 위젯").font(.caption)
                // The system adds content margins around a widget's view; the padding stands in for them.
                TodayWidgetView(state: state).padding(16).frame(width: 170, height: 170)
                    .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 22))
                    // In dark mode the widget background and the page are both black, so the outline shows the widget's edge.
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(uiColor: .separator)))
            }.padding()
        }.background(Color(uiColor: .systemGroupedBackground))
    }
}
#endif
