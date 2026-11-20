import UIKit
import XCTest

/// The navy room colors of docs/specs/2026-11-20-navy-focus-room-design.md, read from the app's asset catalog compiled into this test bundle.
final class FocusRoomPaletteTests: XCTestCase {
    func testRoomColorsAreTheApprovedValuesInEveryAppearance() throws {
        XCTAssertEqual(try color("FocusNavy"), RGBA(red: 0x1E, green: 0x27, blue: 0x44, alpha: 1))
        XCTAssertEqual(try color("FocusCream"), RGBA(red: 0xFF, green: 0xF4, blue: 0xE2, alpha: 1))
        XCTAssertEqual(try color("FocusCreamSecondary"), RGBA(red: 0xFF, green: 0xF4, blue: 0xE2, alpha: 0.62))
        XCTAssertEqual(try color("FocusAmber"), RGBA(red: 0xF4, green: 0xA6, blue: 0x4A, alpha: 1))
    }

    func testRoomTextContrastOnNavy() throws {
        let navy = try color("FocusNavy")
        let cream = try contrast(color("FocusCream"), on: navy)
        let secondary = try contrast(color("FocusCreamSecondary"), on: navy)
        let amber = try contrast(color("FocusAmber"), on: navy)
        // The decision of 2026-11-20 measured about 13.5:1 and 7.28:1.
        XCTAssertEqual(cream, 13.5, accuracy: 0.05)
        XCTAssertEqual(amber, 7.28, accuracy: 0.05)
        XCTAssertEqual(secondary, 6.1, accuracy: 0.05)
        XCTAssertGreaterThanOrEqual(secondary, 4.5)
        XCTAssertLessThan(secondary, cream)
    }

    /// The room forces the dark appearance, so the end action reads the dark `ErrorText`, with the default and the increased contrast.
    func testEndActionTextContrastOnNavy() throws {
        let navy = try color("FocusNavy")
        let named = try XCTUnwrap(UIColor(named: "ErrorText", in: Bundle(for: FocusRoomPaletteTests.self), compatibleWith: nil))
        for level in [UIAccessibilityContrast.normal, .high] {
            let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: .dark), UITraitCollection(accessibilityContrast: level)])
            let text = try components(named.resolvedColor(with: traits), "ErrorText", file: #filePath, line: #line)
            XCTAssertGreaterThanOrEqual(contrast(text, on: navy), 4.5, "ErrorText with contrast level \(level.rawValue)")
        }
    }

    func testContrastIsOneForEqualColorsAndTwentyOneForBlackOnWhite() {
        let white = RGBA(red: 255, green: 255, blue: 255, alpha: 1), black = RGBA(red: 0, green: 0, blue: 0, alpha: 1)
        XCTAssertEqual(contrast(white, on: white), 1, accuracy: 0.001)
        XCTAssertEqual(contrast(black, on: white), 21, accuracy: 0.001)
        // A transparent color composites to its background.
        XCTAssertEqual(contrast(RGBA(red: 0, green: 0, blue: 0, alpha: 0), on: white), 1, accuracy: 0.001)
    }

    /// Channels on the 0...255 scale; equality allows the rounding of the compiled catalog.
    private struct RGBA: Equatable {
        var red: Double, green: Double, blue: Double, alpha: Double
        static func == (lhs: RGBA, rhs: RGBA) -> Bool {
            abs(lhs.red - rhs.red) < 0.5 && abs(lhs.green - rhs.green) < 0.5 && abs(lhs.blue - rhs.blue) < 0.5 && abs(lhs.alpha - rhs.alpha) < 0.0005
        }
    }

    /// The color must resolve to the same value in the light and the dark appearance, so that both read the same navy room.
    private func color(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> RGBA {
        let bundle = Bundle(for: FocusRoomPaletteTests.self)
        let named = try XCTUnwrap(UIColor(named: name, in: bundle, compatibleWith: nil), "\(name) is missing from the compiled asset catalog", file: file, line: line)
        let light = try components(named.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)), name, file: file, line: line)
        let dark = try components(named.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)), name, file: file, line: line)
        XCTAssertEqual(light, dark, "\(name) has appearance variants", file: file, line: line)
        return light
    }

    private func components(_ color: UIColor, _ name: String, file: StaticString, line: UInt) throws -> RGBA {
        let srgb = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let converted = try XCTUnwrap(color.cgColor.converted(to: srgb, intent: .defaultIntent, options: nil), "\(name) does not convert to sRGB", file: file, line: line)
        let values = try XCTUnwrap(converted.components, file: file, line: line)
        guard values.count == 4 else {
            XCTFail("\(name) has \(values.count) components, not RGBA", file: file, line: line)
            return RGBA(red: -1, green: -1, blue: -1, alpha: -1)
        }
        return RGBA(red: Double(values[0]) * 255, green: Double(values[1]) * 255, blue: Double(values[2]) * 255, alpha: Double(values[3]))
    }

    /// WCAG 2 contrast ratio; a translucent foreground is composited over the background in sRGB first.
    private func contrast(_ foreground: RGBA, on background: RGBA) -> Double {
        func blend(_ top: Double, _ bottom: Double) -> Double { top * foreground.alpha + bottom * (1 - foreground.alpha) }
        let shown = RGBA(red: blend(foreground.red, background.red), green: blend(foreground.green, background.green), blue: blend(foreground.blue, background.blue), alpha: 1)
        let lighter = max(luminance(shown), luminance(background)), darker = min(luminance(shown), luminance(background))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func luminance(_ color: RGBA) -> Double {
        func linear(_ channel: Double) -> Double {
            let value = channel / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }
}
