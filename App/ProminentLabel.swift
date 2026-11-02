import SwiftUI

/// Gives an enabled `.borderedProminent` label the `AccentLabel` color, which keeps contrast on the dark-mode accent fill.
/// A disabled button keeps the system's disabled label, so apply this before `.disabled(...)` in the modifier chain.
struct ProminentLabel: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        if isEnabled {
            content.foregroundStyle(Color("AccentLabel"))
        } else {
            content
        }
    }
}
