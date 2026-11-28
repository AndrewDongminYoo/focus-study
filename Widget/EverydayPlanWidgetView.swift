import SwiftUI
import WidgetKit

/// The everyday plan widget: today's range as a timeline of restricted and unblocked spans, where now is in them, and the next change.
/// It shows the stored plan as planned times only, never a session state, an applied restriction, a token, a name or usage.
/// It does no I/O: the provider, or the app's DEBUG preview, gives it the display.
/// Geometry is in the units of Figma frame 93:602 (364 × 170) and scales with the widget's size; text keeps its Dynamic Type style.
struct EverydayPlanWidgetView: View {
    /// The fixed plan at 14:20 of today, for the widget gallery and the placeholder; never read from the file.
    static func sample(calendar: Calendar) -> EverydayPlanDisplay {
        let date = calendar.date(bySettingHour: 14, minute: 20, second: 0, of: Date()) ?? Date()
        return EverydayPlanFile(plan: .sample, needsCheck: false).display(at: date, calendar: calendar)
    }
    let display: EverydayPlanDisplay
    /// Only for the DEBUG preview, which cannot enter the accented mode: draws the flat look of that mode.
    var drawsFlat = false
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme
    /// The accented and vibrant modes give each group one color, so the view draws them flat: no gradient and no shadow.
    private var flat: Bool { drawsFlat || renderingMode != .fullColor }
    private var dark: Bool { colorScheme == .dark }
    private var palette: TodayDialPalette { dark ? .dark : .light }
    private var ink: Color { flat ? .white : palette.ink }
    private var secondary: Color { flat ? .white.opacity(0.7) : palette.secondaryInk }
    private var accentText: Color { flat ? TodayDialPalette.flatAccent : dark ? Self.rgb(0xF4A64A) : Self.rgb(0xAE5519) }
    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width / 364, proxy.size.height / 170)
            ZStack {
                header(s)
                timeline(s)
                switch display.state {
                case .today(let today): blocks(today, s)
                default:
                    Text(display.state.line ?? "").font(.headline.bold()).foregroundStyle(ink).planFitted()
                        .frame(width: 328 * s, alignment: .leading).position(x: 182 * s, y: 118 * s)
                }
            }
            .frame(width: 364 * s, height: 170 * s)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(display.accessibilityText)
        .accessibilityIdentifier("everydayPlanWidget")
        .containerBackground(for: .widget) { TodayWidgetBackground(drawsFlat: flat) }
    }
    @ViewBuilder private func header(_ s: CGFloat) -> some View {
        Text(EverydayPlanDisplay.title).font(.caption.bold()).foregroundStyle(ink).planFitted()
            .frame(width: 200 * s, alignment: .leading).position(x: 118 * s, y: 22 * s)
        if let weekdays = display.weekdays {
            Text(weekdays).font(.caption2.weight(.medium)).foregroundStyle(secondary).planFitted()
                .frame(width: 130 * s, alignment: .trailing).position(x: 283 * s, y: 21 * s)
        }
    }
    @ViewBuilder private func timeline(_ s: CGFloat) -> some View {
        let p = palette
        RoundedRectangle(cornerRadius: 6 * s)
            .fill(flat ? AnyShapeStyle(Color.white.opacity(0.08)) : AnyShapeStyle(LinearGradient(stops: p.groove, startPoint: .top, endPoint: .bottom)
                .shadow(.inner(color: p.grooveInner, radius: 1.5 * s, x: s, y: 2 * s))))
            .shadow(color: flat ? .clear : p.grooveLip, radius: 0.5 * s, y: s)
            .frame(width: 332 * s, height: 21 * s).position(x: 182 * s, y: 61.5 * s)
        if case .today(let today) = display.state {
            let length = CGFloat(today.rangeEnd - today.rangeStart)
            let x = { (minute: Int) in (18 + CGFloat(minute - today.rangeStart) / length * 328) * s }
            Text(EverydayPlanFile.time(today.rangeStart)).font(.caption2.weight(.medium)).monospacedDigit().foregroundStyle(secondary).planFitted()
                .frame(width: 80 * s, alignment: .leading).position(x: 56 * s, y: 41 * s)
            Text(EverydayPlanFile.time(today.rangeEnd)).font(.caption2.weight(.medium)).monospacedDigit().foregroundStyle(secondary).planFitted()
                .frame(width: 80 * s, alignment: .trailing).position(x: 308 * s, y: 41 * s)
            ForEach(Array(today.spans.enumerated()), id: \.offset) { index, span in
                // 1.4 apart, less around a span too short to give up the whole gap.
                let full = x(span.end) - x(span.start)
                let insets = EverydayPlanSpan.edgeInsets(width: full, leading: index > 0, trailing: index + 1 < today.spans.count, gap: 1.4 * s)
                let lead = insets.leading, width = max(full - insets.leading - insets.trailing, 0)
                spanShape(restricted: span.restricted, s: s)
                    .frame(width: width, height: 17 * s).position(x: x(span.start) + lead + width / 2, y: 61.5 * s)
            }
            if today.nowIsInsideRange {
                ForEach([45.5, 77.5], id: \.self) { y in
                    Capsule().fill(flat ? AnyShapeStyle(TodayDialPalette.flatAccent) : AnyShapeStyle(p.tick.shadow(.inner(color: p.tickInner, radius: 0.25 * s, y: 0.5 * s))))
                        .shadow(color: flat ? .clear : p.tickLift, radius: 0.3 * s, x: 0.6 * s, y: 0.7 * s)
                        .widgetAccentable()
                        .frame(width: 1.8 * s, height: 5 * s).position(x: x(today.now), y: y * s)
                }
            }
        }
    }
    @ViewBuilder private func spanShape(restricted: Bool, s: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3 * s)
        if flat {
            if restricted { shape.fill(TodayDialPalette.flatAccent).widgetAccentable() } else { shape.fill(Color.white.opacity(0.35)) }
        } else {
            let base = restricted ? (dark ? Self.rgb(0xF4A64A) : Self.rgb(0xB65317)) : (dark ? Self.rgb(0xFFF4E2, 0.2) : Color.white.opacity(0.72))
            shape.fill(base).overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0)], startPoint: .top, endPoint: .center)))
        }
    }
    @ViewBuilder private func blocks(_ today: EverydayPlanToday, _ s: CGFloat) -> some View {
        Rectangle().fill(flat ? Color.white.opacity(0.2) : palette.ink.opacity(0.08))
            .frame(width: 1 * s, height: 46 * s).position(x: 182.5 * s, y: 121 * s)
        block(today.left, leading: 18, s: s)
        block(today.right, leading: 198, s: s)
    }
    /// Three lines at the tops 96, 112 and 137 of the frame.
    @ViewBuilder private func block(_ block: EverydayPlanBlock, leading: CGFloat, s: CGFloat) -> some View {
        let width: CGFloat = 150, x = (leading + width / 2) * s
        Text(block.label).font(.caption2).monospacedDigit().foregroundStyle(secondary).planFitted()
            .frame(width: width * s, alignment: .leading).position(x: x, y: 103 * s)
        Group {
            if block.accent { Text(block.value).foregroundStyle(accentText).widgetAccentable() } else { Text(block.value).foregroundStyle(ink) }
        }
        .font(.headline.bold()).monospacedDigit().planFitted()
        .frame(width: width * s, alignment: .leading).position(x: x, y: 124 * s)
        if let detail = block.detail {
            Text(detail).font(.caption2).monospacedDigit().foregroundStyle(secondary).planFitted()
                .frame(width: width * s, alignment: .leading).position(x: x, y: 144 * s)
        }
    }
    private static func rgb(_ hex: UInt32, _ opacity: Double = 1) -> Color {
        Color(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

private extension View {
    /// One line that shrinks to 70% for large text and then ends with an ellipsis.
    func planFitted() -> some View { lineLimit(1).minimumScaleFactor(0.7).truncationMode(.tail) }
}
