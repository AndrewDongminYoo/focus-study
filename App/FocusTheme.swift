import SwiftUI
import UIKit

enum FocusTheme {
    enum Palette {
        static let primaryText = Color(uiColor: .label)
        static let secondaryText = Color(uiColor: .secondaryLabel)
        static let accent = Color.accentColor
        static let onAccent = Color("AccentLabel")
        static let error = Color("ErrorText")
        static let surface = Color(uiColor: .systemBackground)
        static let groupedSurface = Color(uiColor: .systemGroupedBackground)
        static let progressTrack = Color(uiColor: .quaternarySystemFill)
        static let progressFill = accent.opacity(0.24)
    }

    enum Layout {
        // Spacing roles derived from the Mirae screen layouts; native controls retain their own geometry.
        static let detailSpacing: CGFloat = 4
        static let inlineSpacing: CGFloat = 8
        static let relatedSpacing: CGFloat = 12
        static let controlSpacing: CGFloat = 16
        static let screenInset: CGFloat = 20
        static let sectionSpacing: CGFloat = 24
        static let minimumTapTarget: CGFloat = 44
        static let compactConfirmationHeight: CGFloat = 320
    }

    static func prefersSolidControls(reduceTransparency: Bool, contrast: ColorSchemeContrast) -> Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing"), arguments.contains("--solid-controls") { return true }
        #endif
        return reduceTransparency || contrast == .increased
    }
}

struct FocusPrimaryAction: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if #available(iOS 26, *), !FocusTheme.prefersSolidControls(reduceTransparency: reduceTransparency, contrast: contrast) {
            content
                .buttonStyle(.glassProminent)
                .tint(FocusTheme.Palette.accent)
        } else {
            content
                .buttonStyle(.borderedProminent)
                .tint(FocusTheme.Palette.accent)
        }
    }
}

struct FocusSecondaryAction: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if #available(iOS 26, *), !FocusTheme.prefersSolidControls(reduceTransparency: reduceTransparency, contrast: contrast) {
            content
                .buttonStyle(.glass)
                .tint(FocusTheme.Palette.primaryText)
        } else {
            content
                .buttonStyle(.bordered)
                .tint(FocusTheme.Palette.primaryText)
        }
    }
}

struct FocusGlassGroup: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if #available(iOS 26, *), !FocusTheme.prefersSolidControls(reduceTransparency: reduceTransparency, contrast: contrast) {
            GlassEffectContainer(spacing: FocusTheme.Layout.inlineSpacing) {
                content
            }
        } else {
            content
        }
    }
}
