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

    /// The tokens of the idle, break and timer screens (docs/specs/2026-11-23-screen-redesign-design.md). The room forces the dark
    /// appearance, so it reads the dark values of the cards, pills and chips.
    enum Screen {
        static let canvas = Color("FocusCanvas")
        static let card = Color("FocusCard")
        static let pill = Color("FocusPill")
        static let chip = Color("FocusChip")
        static let creamFill = Color("FocusCreamFill")
        static let ink = Color("FocusInk")
        static let secondaryInk = Color("FocusSecondaryInk")
        static let accentText = Color("AccentText")
        static let inset: CGFloat = 24
        static let cornerRadius: CGFloat = 16
        static let buttonHeight: CGFloat = 51
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

/// The shared layout of the idle, break and timer screens: a header row, a two-line title, the dial, the lines below it and the action area.
struct FocusScreenLayout<Header: View, Title: View, Dial: View, Notes: View, Actions: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var title: Title
    @ViewBuilder var dial: Dial
    @ViewBuilder var notes: Notes
    @ViewBuilder var actions: Actions
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: FocusTheme.Layout.inlineSpacing) { header }.frame(minHeight: FocusTheme.Layout.minimumTapTarget)
            // The spacers take the free height; the text keeps its full height instead of truncating to one line.
            title.font(.title.bold()).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(.top, FocusTheme.Layout.inlineSpacing)
            Spacer(minLength: FocusTheme.Layout.sectionSpacing)
            dial
            VStack(spacing: FocusTheme.Layout.relatedSpacing) { notes }.multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.top, FocusTheme.Layout.inlineSpacing)
            Spacer(minLength: FocusTheme.Layout.sectionSpacing)
            VStack(spacing: 11) { actions }.fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, FocusTheme.Screen.inset).padding(.bottom, FocusTheme.Layout.inlineSpacing)
    }
}

/// The dial sizes of the spec, in points: the frame, the band radius and the inner circle radius, where the dot sits.
private enum FocusDialGeometry {
    static let size: CGFloat = 276, band: CGFloat = 136.7, inner: CGFloat = 110.7
}

/// The 60-tick dial of the redesign. The drawn ring is hidden from VoiceOver; the content keeps its own elements.
/// At the accessibility text sizes the ring is not drawn and the content shows as a column.
struct FocusDial<Content: View>: View {
    /// Turns of the dot from 12 o'clock. Values above 1 keep turning, so a new lap does not animate backwards.
    var turns: Double
    /// The inner disc in the dark appearance: the screen background.
    var background: Color
    var animatesDot: Bool
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private typealias Geometry = FocusDialGeometry

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: FocusTheme.Layout.inlineSpacing) { content }
        } else {
            ZStack {
                ring.accessibilityHidden(true)
                Circle().fill(scheme == .dark ? FocusTheme.Room.marker : FocusTheme.Palette.accent).frame(width: 6.7, height: 6.7)
                    .offset(y: -Geometry.inner).rotationEffect(.degrees(turns * 360))
                    .animation(animatesDot ? .linear(duration: 1) : nil, value: turns).accessibilityHidden(true)
                VStack(spacing: 7) { content }.frame(maxWidth: 2 * Geometry.inner - 32)
            }
            .frame(width: Geometry.size, height: Geometry.size)
        }
    }

    private var ring: some View {
        let dark = scheme == .dark
        let band = Color(hex: dark ? 0x232F4A : 0xF1E6D9), disc = dark ? background : Color(hex: 0xFBF8F2)
        let stroke = Color(hex: dark ? 0x435069 : 0xDFC7AF), minor = Color(hex: dark ? 0x48536C : 0xD7BDA5), major = Color(hex: dark ? 0xB7C0D4 : 0xB96326)
        return Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func circle(_ radius: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
            }
            context.fill(circle(Geometry.band), with: .color(band))
            context.fill(circle(Geometry.inner), with: .color(disc))
            context.stroke(circle(Geometry.inner), with: .color(stroke), lineWidth: 0.7)
            for tick in 0..<60 {
                let isMajor = tick % 5 == 0, angle = Double(tick) / 60 * 2 * .pi
                func point(_ radius: CGFloat) -> CGPoint { CGPoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle)) }
                var line = Path()
                line.move(to: point(isMajor ? 119.3 : 123.3)); line.addLine(to: point(128.7))
                context.stroke(line, with: .color(isMajor ? major : minor), style: StrokeStyle(lineWidth: isMajor ? 1.7 : 1, lineCap: .round))
            }
        }
    }
}

/// A capsule with an optional dot and a short text, for the status pill and the remaining-breaks chip.
struct FocusCapsuleLabel: View {
    let text: String
    var dot: Color?
    let textColor: Color
    let fill: Color
    var body: some View {
        HStack(spacing: 6) {
            if let dot { Circle().fill(dot).frame(width: 6, height: 6).accessibilityHidden(true) }
            Text(text).font(.footnote.weight(.medium)).foregroundStyle(textColor)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Capsule().fill(fill))
    }
}

/// A card on the canvas or in the room.
struct FocusCard: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.horizontal, 16).padding(.vertical, 13).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: FocusTheme.Screen.cornerRadius).fill(FocusTheme.Screen.card))
    }
}

/// A full-width filled button of the redesign; a disabled one fades.
struct FocusFillButtonStyle: ButtonStyle {
    let fill: Color
    let label: Color
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(label).multilineTextAlignment(.center)
            .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: FocusTheme.Screen.buttonHeight)
            .background(RoundedRectangle(cornerRadius: FocusTheme.Screen.cornerRadius).fill(fill))
            .contentShape(RoundedRectangle(cornerRadius: FocusTheme.Screen.cornerRadius))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

/// "집중 종료" as a text button in `ErrorText`, on the timer and the break screens.
struct FocusEndButton: View {
    let action: () -> Void
    var body: some View {
        Button(role: .destructive, action: action) {
            Text("집중 종료").font(.subheadline).foregroundStyle(FocusTheme.Palette.error).frame(maxWidth: .infinity, minHeight: 45).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier("end")
    }
}

private extension Color {
    /// An sRGB color from a 24-bit hex value such as `0xF1E6D9`, for the dial colors that have no token.
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
