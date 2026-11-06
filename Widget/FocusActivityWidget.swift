import ActivityKit
import SwiftUI
import WidgetKit

@main struct FocusActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            FocusActivityCard(content: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color(uiColor: .systemBackground))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    FocusActivityCard(content: context.state, isStale: context.isStale)
                }
            } compactLeading: {
                FocusActivityCompactLeading(content: context.state)
            } compactTrailing: {
                FocusActivityCountdown(content: context.state, isStale: context.isStale, compact: true)
            } minimal: {
                if context.isStale {
                    Image(systemName: "clock.badge.exclamationmark").accessibilityLabel("온:공에서 확인해 주세요")
                } else {
                    Image(systemName: "timer").accessibilityLabel("온:공 예정 시간 · 앱에서 확인해 주세요")
                }
            }
            .keylineTint(.accentColor)
        }
    }
}
