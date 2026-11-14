import SwiftUI
import WidgetKit

/// The extension's widgets: the Live Activity and the home screen widget.
@main struct FocusWidgets: WidgetBundle {
    var body: some Widget {
        FocusActivityWidget()
        TodayFocusWidget()
    }
}
