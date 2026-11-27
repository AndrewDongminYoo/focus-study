import SwiftUI
import WidgetKit

/// The small home screen widget: a dial plate with today's completed focus time on the knob and the count below it.
/// It does no I/O: the provider, or the app's DEBUG preview, gives it the state.
/// It shows only completed records of today, never a session state, a time of day or a restriction state; the lamps are lit when today has a completed session.
/// Geometry is in the 170 pt units of the Figma frames and scales with the widget's size; text keeps its Dynamic Type style.
struct TodayWidgetView: View {
    /// The fixed numbers of the widget gallery and the DEBUG preview; never read from the snapshot.
    static let sample = TodayWidgetState.numbers(count: 3, focusSeconds: 4500)
    let state: TodayWidgetState
    /// Only for the DEBUG preview, which cannot enter the accented mode: draws the flat look of that mode.
    var drawsFlat = false
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    @Environment(\.colorScheme) private var colorScheme
    /// The accented and vibrant modes give each group one color, so the view draws them flat: no gradient and no shadow.
    private var flat: Bool { drawsFlat || renderingMode != .fullColor }
    private var palette: TodayDialPalette { colorScheme == .dark ? .dark : .light }
    private var lit: Bool { if case .numbers = state { return true } else { return false } }
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                dial(side / 170)
                texts(side / 170)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        // The dial has a fixed size: above xxLarge the time would end in an ellipsis that reads as another number ("1…").
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("todayWidget")
        .containerBackground(for: .widget) { TodayWidgetBackground(drawsFlat: flat) }
    }
    private func style(_ full: some ShapeStyle, flat opacity: Double) -> AnyShapeStyle {
        flat ? AnyShapeStyle(Color.white.opacity(opacity)) : AnyShapeStyle(full)
    }
    private func gradient(_ stops: [Gradient.Stop]) -> LinearGradient { LinearGradient(stops: stops, startPoint: .topLeading, endPoint: .bottomTrailing) }
    private func shadow(_ color: Color) -> Color { flat ? .clear : color }
    @ViewBuilder private func dial(_ s: CGFloat) -> some View {
        let p = palette, center = CGPoint(x: 85 * s, y: 85 * s)
        ForEach(0..<12, id: \.self) { index in
            let major = index % 3 == 0
            Capsule().fill(style(p.tick.shadow(.inner(color: p.tickInner, radius: 0.25 * s, y: 0.5 * s)), flat: 0.5))
                .frame(width: (major ? 1.8 : 1.2) * s, height: (major ? 5 : 3.5) * s)
                .shadow(color: shadow(p.tickLift), radius: 0.3 * s, x: 0.6 * s, y: 0.7 * s)
                .offset(y: -59.5 * s).rotationEffect(.degrees(Double(index) * 30)).position(center)
        }
        Circle().fill(style(gradient(p.groove).shadow(.inner(color: p.grooveInner, radius: 1.5 * s, x: s, y: 2 * s)), flat: 0.08))
            .shadow(color: shadow(p.grooveLip), radius: 0.5 * s, y: s)
            .frame(width: 110 * s, height: 110 * s).position(center)
        Circle().fill(style(p.plate, flat: 0.12)).overlay(Circle().fill(style(gradient(p.plateSheen), flat: 0)))
            .shadow(color: shadow(p.plateDrop), radius: 3.5 * s, x: 2 * s, y: 7 * s)
            .shadow(color: shadow(p.plateLift), radius: 1.5 * s, x: -2 * s, y: -2 * s)
            .frame(width: 105 * s, height: 105 * s).position(center)
        RoundedRectangle(cornerRadius: 1.5 * s).fill(style(gradient(p.indexWell).shadow(.inner(color: p.indexInner, radius: 0.5 * s, y: s)), flat: 0.25))
            .frame(width: 3 * s, height: 14 * s).position(x: 85 * s, y: 45 * s)
        lamp(TodayDialPalette.marker, glow: TodayDialPalette.markerGlow, blur: 3, s: s, cornerRadius: 0.9)
            .frame(width: 1.8 * s, height: 12.4 * s).position(x: 85 * s, y: 45 * s)
        Circle().fill(style(gradient(p.bevel), flat: 0.1))
            .shadow(color: shadow(p.bevelDrop), radius: 3 * s, x: 3 * s, y: 8 * s)
            .shadow(color: shadow(p.bevelLift), radius: 1.5 * s, x: -2 * s, y: -2 * s)
            .frame(width: 64 * s, height: 64 * s).position(x: 85 * s, y: 90 * s)
        Circle().fill(style(p.knob.shadow(.inner(color: p.knobInnerLight, radius: 0.5 * s, y: s)).shadow(.inner(color: p.knobInnerDark, radius: 0.5 * s, y: -s)), flat: 0.16))
            .overlay(Circle().fill(style(gradient(p.knobSheen), flat: 0)))
            .frame(width: 62 * s, height: 62 * s).position(center)
        Circle().strokeBorder(style(gradient(p.edge), flat: 0.3), lineWidth: 0.5 * s)
            .frame(width: 60 * s, height: 60 * s).position(center)
        Circle().fill(style(gradient(p.socket).shadow(.inner(color: p.socketInner, radius: s, y: s)), flat: 0.35))
            .frame(width: 10 * s, height: 10 * s).position(x: 150 * s, y: 17 * s)
        Group {
            if lit { lamp(TodayDialPalette.lamp, glow: TodayDialPalette.lampGlow, blur: 5, s: s, cornerRadius: 3) }
            else { Circle().fill(style(gradient(p.lampOff), flat: 0.3)) }
        }
        .frame(width: 6 * s, height: 6 * s).position(x: 150 * s, y: 17 * s)
        ForEach([19.5, 150.5], id: \.self) { x in
            RoundedRectangle(cornerRadius: 2 * s).fill(style(gradient(p.well).shadow(.inner(color: p.wellInner, radius: 0.5 * s, y: s)), flat: 0.25))
                .frame(width: 11 * s, height: 4 * s).position(x: x * s, y: 155 * s)
            Group {
                if lit { lamp(TodayDialPalette.bar, glow: TodayDialPalette.barGlow, blur: 3, s: s, cornerRadius: 1) }
                else { RoundedRectangle(cornerRadius: s).fill(style(gradient(p.barOff), flat: 0.3)) }
            }
            .frame(width: 9 * s, height: 2 * s).position(x: x * s, y: 155 * s)
        }
    }
    /// A lit part: amber with a glow in full color; in the flat modes it joins the accent group.
    private func lamp(_ stops: [Gradient.Stop], glow: Color, blur: CGFloat, s: CGFloat, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius * s)
            .fill(flat ? AnyShapeStyle(TodayDialPalette.flatAccent) : AnyShapeStyle(gradient(stops)))
            .shadow(color: shadow(glow), radius: blur / 2 * s)
            .widgetAccentable()
    }
    @ViewBuilder private func texts(_ s: CGFloat) -> some View {
        // Outside the plate the text stands on the widget background, which StandBy removes; there it needs the light ink.
        let outside: Color = flat ? .white : showsBackground ? palette.ink : TodayDialPalette.dark.ink
        Text("오늘 집중").font(.caption2.weight(.medium)).foregroundStyle(outside).fitted()
            .frame(width: 120 * s, alignment: .leading).position(x: 74 * s, y: 17 * s)
        Group {
            switch state {
            case .numbers(_, let seconds):
                VStack(spacing: 0) {
                    ForEach(Array(TodaySnapshot.durationLines(seconds).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.subheadline.bold()).monospacedDigit().fitted()
                    }
                }
                .foregroundStyle(flat ? TodayDialPalette.flatAccent : palette.ink)
                .widgetAccentable()
            case .empty, .check:
                Text("온:공").font(.callout.bold()).foregroundStyle(flat ? .white : palette.ink).fitted()
            }
        }
        .frame(width: 52 * s).position(x: 85 * s, y: 85 * s)
        Group {
            switch state {
            case .numbers(let count, _): Text("\(count)회").font(.caption.bold()).monospacedDigit()
            case .empty: Text("앱에서 시작해 보세요").font(.caption2.weight(.medium))
            case .check: Text("앱에서 확인해 주세요").font(.caption2.weight(.medium))
            }
        }
        .foregroundStyle(outside).fitted()
        .frame(width: 110 * s).position(x: 85 * s, y: 155 * s)
    }
    private var accessibilityText: String {
        switch state {
        case .numbers(let count, let seconds): return "오늘 집중 \(TodaySnapshot.durationText(seconds)), \(count)회"
        case .empty: return "오늘 집중, 앱에서 시작해 보세요"
        case .check: return "오늘 집중, 앱에서 확인해 주세요"
        }
    }
}

private extension View {
    /// One line that shrinks to 70% for large text and then ends with an ellipsis, so long text never wraps or overflows the dial.
    func fitted() -> some View { lineLimit(1).minimumScaleFactor(0.7).truncationMode(.tail) }
}

/// The widget's background plate. The system removes it in the accented mode and in StandBy; the DEBUG preview draws it behind the view.
struct TodayWidgetBackground: View {
    var drawsFlat = false
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let p: TodayDialPalette = colorScheme == .dark ? .dark : .light
        if drawsFlat {
            ContainerRelativeShape().fill(Color.white.opacity(0.14))
        } else {
            ContainerRelativeShape().fill(p.base.shadow(.inner(color: p.frameInnerLight, radius: 0.5, y: 1)).shadow(.inner(color: p.frameInnerDark, radius: 1, y: -1)))
                .overlay(ContainerRelativeShape().fill(LinearGradient(stops: p.frameSheen, startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
    }
}

/// The dial colors of one appearance: light from Figma frames 76:663 and 76:664, dark from the approved proposal on the screen redesign's dark tokens.
/// The extension has no asset catalog, so the values are in code. The home widget spec's amendment of 2026-11-27 lists them.
struct TodayDialPalette {
    let base, ink: Color, frameSheen: [Gradient.Stop], frameInnerLight, frameInnerDark: Color
    let groove: [Gradient.Stop], grooveInner, grooveLip: Color
    let plate: Color, plateSheen: [Gradient.Stop], plateDrop, plateLift: Color
    let tick, tickInner, tickLift: Color
    let indexWell: [Gradient.Stop], indexInner: Color, well: [Gradient.Stop], wellInner: Color
    let bevel: [Gradient.Stop], bevelDrop, bevelLift: Color
    let knob: Color, knobSheen: [Gradient.Stop], knobInnerLight, knobInnerDark: Color, edge: [Gradient.Stop]
    let socket: [Gradient.Stop], socketInner: Color, lampOff, barOff: [Gradient.Stop]

    static let light = TodayDialPalette(
        base: Color(hex: 0xDED8CE), ink: Color(hex: 0x202C46),
        frameSheen: stops((0xFFFFFF, 0.15, 0), (0xFFFFFF, 0, 0.5), (0x746D5B, 0.12, 1)), frameInnerLight: Color(hex: 0xFFFFFF, 0.5), frameInnerDark: Color(hex: 0x79715E, 0.14),
        groove: stops((0xAFA99A, 1, 0), (0xCEC8BA, 1, 0.38), (0xEEEADD, 1, 1)), grooveInner: Color(hex: 0x6A6352, 0.26), grooveLip: Color(hex: 0xFFFFFF, 0.45),
        plate: Color(hex: 0xDED8CE), plateSheen: stops((0xFFFFFF, 0.28, 0), (0xFFFFFF, 0.02, 0.55), (0x6E685B, 0.1, 1)),
        plateDrop: Color(hex: 0x635C4B, 0.25), plateLift: Color(hex: 0xFFFFFF, 0.5),
        tick: Color(hex: 0xBCBAB5), tickInner: Color(hex: 0x716A59, 0.18), tickLift: Color(hex: 0xFFFFFF, 0.6),
        indexWell: stops((0xB6A16B, 1, 0), (0xF4E7AC, 1, 1)), indexInner: Color(hex: 0x8F7942, 0.3),
        well: stops((0x9F8955, 1, 0), (0xF2E3AD, 1, 1)), wellInner: Color(hex: 0x6D5F3D, 0.35),
        bevel: stops((0xECE7D8, 1, 0), (0xB5AF9F, 1, 0.6), (0x8E8879, 1, 1)), bevelDrop: Color(hex: 0x554E3E, 0.33), bevelLift: Color(hex: 0xFFFFFF, 0.35),
        knob: Color(hex: 0xDED8CE), knobSheen: stops((0xFFFFFF, 0.34, 0), (0xFFFFFF, 0.08, 0.62), (0x7C7462, 0.06, 1)),
        knobInnerLight: Color(hex: 0xFFFFFF, 0.8), knobInnerDark: Color(hex: 0x6B6351, 0.16),
        edge: stops((0xFFFFFF, 0.7, 0), (0xFFFFFF, 0.08, 0.55), (0x817865, 0.2, 1)),
        socket: stops((0x9E8C58, 1, 0), (0xF7EDC7, 1, 1)), socketInner: Color(hex: 0x5B4C28, 0.4),
        lampOff: stops((0xC9C1A8, 1, 0), (0x9A927B, 1, 1)), barOff: stops((0xADA58E, 1, 0), (0xC2BAA5, 1, 1)))

    static let dark = TodayDialPalette(
        base: Color(hex: 0x202C46), ink: Color(hex: 0xFFF4E2),
        frameSheen: stops((0xFFFFFF, 0.07, 0), (0xFFFFFF, 0, 0.5), (0x05080F, 0.25, 1)), frameInnerLight: Color(hex: 0xFFFFFF, 0.08), frameInnerDark: Color(hex: 0x000000, 0.3),
        groove: stops((0x121A2D, 1, 0), (0x1A2339, 1, 0.38), (0x2E3A57, 1, 1)), grooveInner: Color(hex: 0x05080F, 0.5), grooveLip: Color(hex: 0xFFFFFF, 0.06),
        plate: Color(hex: 0x222E49), plateSheen: stops((0xFFFFFF, 0.08, 0), (0xFFFFFF, 0, 0.55), (0x000000, 0.15, 1)),
        plateDrop: Color(hex: 0x05080F, 0.45), plateLift: Color(hex: 0xFFFFFF, 0.05),
        tick: Color(hex: 0x48536C), tickInner: Color(hex: 0x000000, 0.3), tickLift: Color(hex: 0xFFFFFF, 0.06),
        indexWell: stops((0x1A2339, 1, 0), (0x3A4766, 1, 1)), indexInner: Color(hex: 0x8F7942, 0.3),
        well: stops((0x1A2339, 1, 0), (0x3A4766, 1, 1)), wellInner: Color(hex: 0x6D5F3D, 0.35),
        bevel: stops((0x3A4766, 1, 0), (0x1B243A, 1, 0.6), (0x10172A, 1, 1)), bevelDrop: Color(hex: 0x04070E, 0.5), bevelLift: Color(hex: 0xFFFFFF, 0.05),
        knob: Color(hex: 0x27334E), knobSheen: stops((0xFFFFFF, 0.1, 0), (0xFFFFFF, 0.02, 0.62), (0x000000, 0.1, 1)),
        knobInnerLight: Color(hex: 0xFFFFFF, 0.12), knobInnerDark: Color(hex: 0x000000, 0.25),
        edge: stops((0xFFFFFF, 0.25, 0), (0xFFFFFF, 0.03, 0.55), (0x000000, 0.3, 1)),
        socket: stops((0x2A3550, 1, 0), (0x56617C, 1, 1)), socketInner: Color(hex: 0x5B4C28, 0.4),
        lampOff: stops((0x4A5570, 1, 0), (0x2C3650, 1, 1)), barOff: stops((0x33405C, 1, 0), (0x45516C, 1, 1)))

    /// The lit parts are the same in both appearances.
    static let lamp = stops((0xFFF7AB, 1, 0), (0xFFD940, 1, 0.4), (0xD59400, 1, 1)), lampGlow = Color(hex: 0xFFC52A, 0.65)
    static let marker = stops((0xFFF7B3, 1, 0), (0xFFCE27, 1, 0.4), (0xE4A900, 1, 1)), markerGlow = Color(hex: 0xFFD23B, 0.45)
    static let bar = stops((0xFFF39A, 1, 0), (0xFFD02D, 1, 0.5), (0xD99C00, 1, 1)), barGlow = Color(hex: 0xFFCC22, 0.4)
    /// The accent group's color in the flat look; the accented mode replaces it with the person's tint.
    static let flatAccent = Color(hex: 0xF4A64A)

    private static func stops(_ values: (UInt32, Double, CGFloat)...) -> [Gradient.Stop] {
        values.map { Gradient.Stop(color: Color(hex: $0.0, $0.1), location: $0.2) }
    }
}

private extension Color {
    init(hex: UInt32, _ opacity: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}
