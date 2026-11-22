import UIKit

/// The layout of the custom shield (docs/specs/2026-11-20-custom-shield-design.md, contract item 1) and the copy of the shield name and open button design (docs/specs/2026-11-21-shield-name-and-open-button-design.md, contract items 1, 2 and 4).
/// The extension cannot read the app's asset catalog, so the colors are the hex values of the navy room; `FocusSDKTests` compares them with the app's color sets.
/// Nothing here depends on time or on stored data; the only per-item value is the name that the system passes to the configuration call.
enum ShieldContent {
    /// What a configuration call shields.
    enum Item {
        case application
        case website
    }

    static let closeButton = "닫기"
    /// A no-break space keeps the label on one line where it fits; the primary button has a fixed height, and at the largest accessibility text size with Display Zoom iOS 27.0.1 still wraps it to two clipped lines (issue #201), so accessibility sizes use `openButtonShort`.
    static let openButton = "온:공\u{00A0}열기"
    /// The open button at an accessibility text size (amendment of 2026-11-22 in the shield name and open button design); the shield has no button height or line-break property.
    static let openButtonShort = "열기"

    /// The open button label for the text size; `accessibilityText` is true only for an accessibility content size category.
    static func openButton(accessibilityText: Bool) -> String {
        accessibilityText ? openButtonShort : openButton
    }

    /// "{name}, 지금은 쉬어요" needs no particle after the name, whose last syllable cannot be read from a Latin name; with no name, a text for the kind of item.
    static func title(name: String?, item: Item) -> String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return "\(name), 지금은 쉬어요"
        }
        switch item {
        case .application: return "지금은 쉬는 앱이에요"
        case .website: return "지금은 쉬는 사이트예요"
        }
    }

    /// The shield has no spacing or alignment property: the leading line break separates the subtitle from the title.
    /// Without the open button, a second line sends the person to the app.
    static func subtitle(opensApp: Bool) -> String {
        opensApp ? "\n온:공이 잠시 막고 있어요." : "\n온:공이 잠시 막고 있어요.\n언제 풀리는지는 온:공에서 볼 수 있어요."
    }

    /// `FocusNavy`, `FocusCream` and `FocusAmber`; the same values in the light and the dark appearance.
    static let navy = UIColor(red: 0x1E / 255, green: 0x27 / 255, blue: 0x44 / 255, alpha: 1)
    static let cream = UIColor(red: 0xFF / 255, green: 0xF4 / 255, blue: 0xE2 / 255, alpha: 1)
    static let amber = UIColor(red: 0xF4 / 255, green: 0xA6 / 255, blue: 0x4A / 255, alpha: 1)
    /// Cream in light mode and navy in dark mode, the opposite of the label that iOS draws for each appearance.
    static let buttonBackground = UIColor { $0.userInterfaceStyle == .dark ? navy : cream }
    /// The title, the subtitle and the button label: navy on the light background of light mode, cream on the dark one.
    static let text = UIColor { $0.userInterfaceStyle == .dark ? cream : navy }

    /// The height of the mark image in points; the width follows the mark's 78.2 by 179.4 bounds.
    static let markHeight: CGFloat = 72
    /// Transparent space under the mark, the only way to separate the icon from the title.
    static let markBottomInset: CGFloat = 20
    /// The mark's height as a share of the tile's side, as in the app icon (717 of 1024 px).
    static let markTileShare: CGFloat = 0.7

    /// The colon mark of the navy focus room design ("Colon mark geometry"): a ring with an even-odd hole over an amber dot, on a transparent background.
    /// The canvas is rounded up to whole pixels, and the mark is centered in it above `bottomInset`.
    /// With `tile`, the mark sits on a navy rounded square like the app icon: the shield uses one icon image for both appearances, and the tile carries the mark on a light background.
    static func colonMark(height: CGFloat = markHeight, bottomInset: CGFloat = markBottomInset, tile: Bool = true, scale: CGFloat = 3) -> UIImage {
        let unit = height / 179.4
        let mark = CGSize(width: 78.2 * unit, height: height)
        let side = tile ? (height / markTileShare * scale).rounded(.up) / scale : 0
        let canvas = CGSize(width: max(side, (mark.width * scale).rounded(.up) / scale),
                            height: max(side, (mark.height * scale).rounded(.up) / scale) + bottomInset)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            if tile {
                navy.setFill()
                UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), cornerRadius: side * 0.22).fill()
            }
            let left = (canvas.width - mark.width) / 2, top = (canvas.height - bottomInset - mark.height) / 2
            let radius = 39.1 * unit, hole = 17 * unit
            let ring = UIBezierPath(ovalIn: CGRect(x: left, y: top, width: 2 * radius, height: 2 * radius))
            ring.append(UIBezierPath(ovalIn: CGRect(x: left + radius - hole, y: top + radius - hole, width: 2 * hole, height: 2 * hole)))
            ring.usesEvenOddFillRule = true
            cream.setFill()
            ring.fill()
            amber.setFill()
            UIBezierPath(ovalIn: CGRect(x: left, y: top + (140.3 - 39.1) * unit, width: 2 * radius, height: 2 * radius)).fill()
        }
    }
}
