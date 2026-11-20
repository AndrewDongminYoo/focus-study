import UIKit

/// The one static layout of the custom shield (docs/specs/2026-11-20-custom-shield-design.md, contract item 1).
/// The extension cannot read the app's asset catalog, so the colors are the hex values of the navy room; `FocusSDKTests` compares them with the app's color sets.
/// Nothing here depends on time, on the shielded item or on stored data (contract items 4 and 5).
enum ShieldContent {
    static let title = "지금은 쉬는 앱이에요"
    /// The shield has no spacing or alignment property: the leading line break separates the subtitle from the title, and the second one keeps each sentence on its own line.
    static let subtitle = "\n온:공이 이 앱을 잠시 막고 있어요.\n언제 풀리는지는 온:공에서 볼 수 있어요."
    static let primaryButton = "닫기"

    /// `FocusNavy`, `FocusCream` and `FocusAmber`; the same values in the light and the dark appearance.
    static let navy = UIColor(red: 0x1E / 255, green: 0x27 / 255, blue: 0x44 / 255, alpha: 1)
    static let cream = UIColor(red: 0xFF / 255, green: 0xF4 / 255, blue: 0xE2 / 255, alpha: 1)
    static let amber = UIColor(red: 0xF4 / 255, green: 0xA6 / 255, blue: 0x4A / 255, alpha: 1)

    /// The height of the mark image in points; the width follows the mark's 78.2 by 179.4 bounds.
    static let markHeight: CGFloat = 72
    /// Transparent space under the mark, the only way to separate the icon from the title.
    static let markBottomInset: CGFloat = 20

    /// The colon mark of the navy focus room design ("Colon mark geometry"): a cream ring with an even-odd hole over an amber dot, on a transparent background.
    /// The canvas is rounded up to whole pixels, and the mark is centered in it above `bottomInset`.
    static func colonMark(height: CGFloat = markHeight, bottomInset: CGFloat = markBottomInset, scale: CGFloat = 3) -> UIImage {
        let unit = height / 179.4
        let mark = CGSize(width: 78.2 * unit, height: height)
        let canvas = CGSize(width: (mark.width * scale).rounded(.up) / scale, height: (mark.height * scale).rounded(.up) / scale + bottomInset)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
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
