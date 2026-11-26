import SwiftUI

/// The share image of the 순공 calendar (docs/specs/2026-11-26-share-image-design.md): the year and the month, a stamp calendar
/// with one stamp on each recorded day, and a small summary line. No day is highlighted, and no day shows its focus time.
/// The sizes are fixed points from the approved mockup, because the image is always drawn at the default text size.
struct CalendarShareCard: View {
    /// The start of the shown local month.
    let month: DateInterval
    /// The start of today; a day after it shows only its dimmed date.
    let today: Date
    /// The starts of the local days of the month with at least one completed session.
    let recordedDays: Set<Date>
    /// The completed focus time of the month.
    let focusDuration: TimeInterval
    let calendar: Calendar

    static let width: CGFloat = 402
    /// Literals of the share image only, from the mockup and the Figma stamp (node 62:2).
    static let stampInk = Color(red: 0xB6 / 255, green: 0x53 / 255, blue: 0x17 / 255)
    static let futureDate = Color(red: 0xBC / 255, green: 0xBA / 255, blue: 0xB5 / 255)
    static let divider = Color(red: 0xDE / 255, green: 0xD8 / 255, blue: 0xCE / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            calendarCard
            Rectangle().fill(Self.divider).frame(height: 1).padding(.top, 14)
            summary.padding(.top, 12)
        }
        .padding(.top, 28).padding(.horizontal, 32).padding(.bottom, 24)
        .frame(width: Self.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(FocusTheme.Screen.canvas))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(calendar.component(.year, from: month.start))").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FocusTheme.Screen.secondaryInk)
                Text(verbatim: "\(calendar.component(.month, from: month.start))월").font(.system(size: 58, weight: .bold)).tracking(-1)
                    .foregroundStyle(FocusTheme.Screen.ink)
            }
            Spacer(minLength: 0)
            // The colon mark: two dots of 11 pt with a gap of 7.
            VStack(spacing: 7) {
                Circle().frame(width: 11, height: 11)
                Circle().frame(width: 11, height: 11)
            }
            // The asset by name: `Color.accentColor` resolves to the system blue inside `ImageRenderer`.
            .foregroundStyle(Color("AccentColor")).padding(.top, 4)
        }
        .padding(.bottom, 22)
    }

    private var calendarCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(CalendarShare.weekdaySymbols(calendar), id: \.self) { symbol in
                    Text(symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(FocusTheme.Screen.secondaryInk).frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 8)
            rowLine
            ForEach(Array(CalendarShare.weeks(month, calendar: calendar).enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day { cell(day) } else { Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity) }
                    }
                }
                .frame(height: 60)
                rowLine
            }
        }
        .padding(.top, 10).padding(.horizontal, 8).padding(.bottom, 6)
        .background(RoundedRectangle(cornerRadius: 16).fill(FocusTheme.Screen.card))
    }
    /// Horizontal lines only, between the weekday row and each week row.
    private var rowLine: some View { Rectangle().fill(FocusTheme.Screen.ink.opacity(0.07)).frame(height: 1) }

    private func cell(_ day: Date) -> some View {
        let number = calendar.component(.day, from: day), future = day > today
        return VStack(spacing: 3) {
            Text(verbatim: "\(number)").font(.system(size: 12)).monospacedDigit().frame(height: 16)
                .foregroundStyle(future ? Self.futureDate : FocusTheme.Screen.ink)
            if !future, recordedDays.contains(day) {
                StampView(variation: CalendarShare.stamp(year: calendar.component(.year, from: day), month: calendar.component(.month, from: day), day: number))
            }
        }
        .padding(.top, 4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(CalendarShare.dayWords(recordedDays.count)).font(.system(size: 12, weight: .semibold)).foregroundStyle(FocusTheme.Screen.ink)
            Text(" " + CalendarShare.timeWords(focusDuration)).font(.system(size: 12, weight: .medium)).foregroundStyle(FocusTheme.Screen.secondaryInk)
            Spacer(minLength: 8)
            Text("온:공").font(.system(size: 11, weight: .medium)).foregroundStyle(FocusTheme.Screen.secondaryInk)
        }
    }

    /// The image of the share button: 402 pt wide, scale 3, the light appearance and the default text size, so it is the same
    /// at every text size and appearance of the device.
    @MainActor static func render(month: DateInterval, today: Date, recordedDays: Set<Date>, focusDuration: TimeInterval, calendar: Calendar) -> UIImage? {
        let renderer = ImageRenderer(content: CalendarShareCard(month: month, today: today, recordedDays: recordedDays, focusDuration: focusDuration, calendar: calendar)
            .environment(\.dynamicTypeSize, .large).environment(\.colorScheme, .light))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// One "순공" stamp of 30 pt, drawn in the 44 × 44 unit box of the Figma stamp (node 62:2).
/// The fractal-noise roughness of the Figma edge has no SwiftUI filter; the under-inked gaps and the paper-grain dots carry the texture.
private struct StampView: View {
    let variation: CalendarShare.Stamp
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 44, y: size.height / 44)
            let center = CGPoint(x: 22, y: 22)
            // The embossed impression: a soft ink shadow below and a white highlight above.
            var ink = context
            ink.addFilter(.shadow(color: CalendarShareCard.stampInk.opacity(0.23), radius: 0.33, x: 0.2, y: 0.25))
            ink.addFilter(.shadow(color: .white.opacity(0.65), radius: 0.1, x: -0.35, y: -0.45))
            ink.stroke(Self.circle(center, 21.05), with: .color(CalendarShareCard.stampInk), lineWidth: 1.9)
            ink.stroke(Self.circle(center, 17.55), with: .color(CalendarShareCard.stampInk.opacity(0.9)), lineWidth: 0.9)
            ink.draw(Text("순공").font(.system(size: 16, weight: .bold)).foregroundColor(CalendarShareCard.stampInk), at: CGPoint(x: 22, y: 22.5), anchor: .center)
            // The paper shows through where the stamp did not ink: three gaps along the outer ring and small grain dots inside.
            let paper = FocusTheme.Screen.card
            for gap in variation.gaps {
                let point = CGPoint(x: 22 + 21 * cos(gap.angle), y: 22 + 21 * sin(gap.angle))
                var along = context
                along.translateBy(x: point.x, y: point.y)
                along.rotate(by: .radians(gap.angle + .pi / 2))
                along.fill(Path(ellipseIn: CGRect(x: -0.9, y: -1.8, width: 1.8, height: 3.6)), with: .color(paper.opacity(0.98)))
            }
            for grain in variation.grains {
                context.fill(Path(ellipseIn: CGRect(x: grain.x - grain.width / 2, y: grain.y - grain.height / 2, width: grain.width, height: grain.height)),
                             with: .color(paper.opacity(0.72)))
            }
        }
        .frame(width: 30, height: 30)
        .scaleEffect(variation.scale).rotationEffect(.degrees(variation.rotation))
        .offset(x: variation.offsetX, y: variation.offsetY).opacity(0.93)
        .accessibilityHidden(true)
    }
    private static func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}
