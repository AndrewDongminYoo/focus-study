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

    /// The navy room of an active session and the completion card (docs/specs/2026-11-20-navy-focus-room-design.md); the same values in both appearances.
    enum Room {
        static let background = Color("FocusNavy")
        static let text = Color("FocusCream")
        static let secondaryText = Color("FocusCreamSecondary")
        static let marker = Color("FocusAmber")
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
    var tint = FocusTheme.Palette.primaryText
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if #available(iOS 26, *), !FocusTheme.prefersSolidControls(reduceTransparency: reduceTransparency, contrast: contrast) {
            content
                .buttonStyle(.glass)
                .tint(tint)
        } else {
            content
                .buttonStyle(.bordered)
                .tint(tint)
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

/// The colon mark of the app icon v5 without its background: a cream ring over an amber dot, in the bounds of the two shapes (78.2 by 179.4 units).
struct ColonMark: View {
    var height: CGFloat
    var body: some View {
        let unit = height / 179.4
        Canvas { context, _ in
            let radius = 39.1 * unit, hole = 17 * unit, center = 39.1 * unit
            var ring = Path(ellipseIn: CGRect(x: 0, y: 0, width: 2 * radius, height: 2 * radius))
            ring.addEllipse(in: CGRect(x: center - hole, y: center - hole, width: 2 * hole, height: 2 * hole))
            context.fill(ring, with: .color(FocusTheme.Room.text), style: FillStyle(eoFill: true))
            context.fill(Path(ellipseIn: CGRect(x: 0, y: (140.3 - 39.1) * unit, width: 2 * radius, height: 2 * radius)), with: .color(FocusTheme.Room.marker))
        }
        .frame(width: 78.2 * unit, height: height)
        .accessibilityHidden(true)
    }
}
