import SwiftUI
import WidgetKit

/// The extension's widgets: the Live Activity and the two home screen widgets.
@main struct FocusWidgets: WidgetBundle {
    var body: some Widget {
        FocusActivityWidget()
        TodayFocusWidget()
        EverydayPlanWidget()
    }
}
