import SwiftUI

/// Gives an enabled prominent label the on-accent color, which keeps contrast on the dark-mode accent fill.
/// A disabled button keeps the system's disabled label, so apply this before `.disabled(...)` in the modifier chain.
struct ProminentLabel: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        if isEnabled {
            content.foregroundStyle(FocusTheme.Palette.onAccent)
        } else {
            content
        }
    }
}
