import SwiftUI
import WidgetKit

/// The small home screen widget. It does no I/O: the provider, or the app's DEBUG preview, gives it the state.
/// It shows only completed records of today, never a session state, a time of day or a restriction state.
struct TodayWidgetView: View {
    /// The fixed numbers of the widget gallery and the DEBUG preview; never read from the snapshot.
    static let sample = TodayWidgetState.numbers(count: 3, focusSeconds: 4500)
    /// The values of `App/Assets.xcassets/AccentColor`. The extension has no asset catalog, so it cannot load that color by name.
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0xF4 / 255, green: 0xA6 / 255, blue: 0x4A / 255, alpha: 1)
            : UIColor(red: 0xA8 / 255, green: 0x5F / 255, blue: 0x10 / 255, alpha: 1)
    })
    let state: TodayWidgetState
    @Environment(\.widgetRenderingMode) private var renderingMode
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("오늘 집중").font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.5)
            Spacer(minLength: 0)
            switch state {
            case .numbers(let count, let seconds):
                // Full color uses the accent; the accented mode puts only the time in the accent group; the vibrant mode depends on no color.
                Text(TodaySnapshot.durationText(seconds))
                    .font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(renderingMode == .fullColor ? Self.accent : Color.primary)
                    .widgetAccentable()
                Text("\(count)회").font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            case .empty:
                Text("앱에서 시작해 보세요").font(.subheadline.weight(.medium)).minimumScaleFactor(0.5)
            case .check:
                Text("앱에서 확인해 주세요").font(.subheadline.weight(.medium)).minimumScaleFactor(0.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("todayWidget")
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }
    private var accessibilityText: String {
        switch state {
        case .numbers(let count, let seconds): return "오늘 집중 \(TodaySnapshot.durationText(seconds)), \(count)회"
        case .empty: return "오늘 집중, 앱에서 시작해 보세요"
        case .check: return "오늘 집중, 앱에서 확인해 주세요"
        }
    }
}
