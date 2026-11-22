import ManagedSettings
import ManagedSettingsUI
import UIKit
import XCTest

/// The custom shield of docs/specs/2026-11-20-custom-shield-design.md, read from the extension's sources compiled into this test bundle.
/// A simulator cannot show a shield, so this checks the configuration that the extension returns, not what iOS draws.
final class ShieldConfigurationTests: XCTestCase {
    /// Contract item 1: the shield's colors are the navy room's color sets of the app, in the light and the dark appearance.
    func testShieldColorsAreTheAppColorSets() throws {
        for (name, color) in [("FocusNavy", ShieldContent.navy), ("FocusCream", ShieldContent.cream), ("FocusAmber", ShieldContent.amber)] {
            let named = try XCTUnwrap(UIColor(named: name, in: Bundle(for: ShieldConfigurationTests.self), compatibleWith: nil), name)
            for style in [UIUserInterfaceStyle.light, .dark] {
                let traits = UITraitCollection(userInterfaceStyle: style)
                XCTAssertEqual(try srgb(color.resolvedColor(with: traits)), try srgb(named.resolvedColor(with: traits)), "\(name), style \(style.rawValue)")
            }
        }
    }

    /// Custom shield contract item 1: the system blur tinted navy, the mark on a navy tile, and text and a button that follow the appearance: navy text and a cream button in light mode, cream text and a navy button in dark mode.
    func testShieldLayoutIsTheApprovedOne() throws {
        let shield = FocusShieldConfiguration.shield(name: "Instagram", item: .application, opensApp: true, contentSize: .large)
        XCTAssertNil(shield.backgroundBlurStyle)
        XCTAssertEqual(try srgb(XCTUnwrap(shield.backgroundColor)), try srgb(ShieldContent.navy))
        let light = UITraitCollection(userInterfaceStyle: .light), dark = UITraitCollection(userInterfaceStyle: .dark)
        for color in [shield.title?.color, shield.subtitle?.color, shield.primaryButtonLabel?.color, shield.secondaryButtonLabel?.color] {
            let text = try XCTUnwrap(color)
            XCTAssertEqual(try srgb(text.resolvedColor(with: light)), try srgb(ShieldContent.navy))
            XCTAssertEqual(try srgb(text.resolvedColor(with: dark)), try srgb(ShieldContent.cream))
        }
        let button = try XCTUnwrap(shield.primaryButtonBackgroundColor)
        XCTAssertEqual(try srgb(button.resolvedColor(with: light)), try srgb(ShieldContent.cream))
        XCTAssertEqual(try srgb(button.resolvedColor(with: dark)), try srgb(ShieldContent.navy))
        let icon = try XCTUnwrap(shield.icon)
        let side = (ShieldContent.markHeight / ShieldContent.markTileShare * 3).rounded(.up) / 3
        XCTAssertEqual(icon.scale, 3)
        XCTAssertEqual(icon.size.width, side, accuracy: 0.01)
        XCTAssertEqual(icon.size.height, side + ShieldContent.markBottomInset, accuracy: 0.01)
    }

    /// Name design, contract item 1: the name in the title, trimmed, and a text for each kind of item without one.
    func testTitleNamesTheItemOrFallsBack() {
        XCTAssertEqual(ShieldContent.title(name: "Instagram", item: .application), "Instagram, 지금은 쉬어요")
        XCTAssertEqual(ShieldContent.title(name: "  유튜브 \n", item: .application), "유튜브, 지금은 쉬어요")
        XCTAssertEqual(ShieldContent.title(name: "youtube.com", item: .website), "youtube.com, 지금은 쉬어요")
        for blank in [nil, "", "  \n"] as [String?] {
            XCTAssertEqual(ShieldContent.title(name: blank, item: .application), "지금은 쉬는 앱이에요")
            XCTAssertEqual(ShieldContent.title(name: blank, item: .website), "지금은 쉬는 사이트예요")
        }
    }

    /// Name design, contract items 2 and 4: with the open button, "온:공 열기" leads, "닫기" follows and the subtitle is one line; without it, "닫기" alone and a second line.
    func testButtonsAndSubtitleFollowTheOpenButton() {
        let opens = FocusShieldConfiguration.shield(name: nil, item: .application, opensApp: true, contentSize: .large)
        XCTAssertEqual(opens.primaryButtonLabel?.text, "온:공\u{00A0}열기")
        XCTAssertEqual(opens.secondaryButtonLabel?.text, "닫기")
        XCTAssertEqual(opens.subtitle?.text, "\n온:공이 잠시 막고 있어요.")
        let closes = FocusShieldConfiguration.shield(name: nil, item: .application, opensApp: false, contentSize: .large)
        XCTAssertEqual(closes.primaryButtonLabel?.text, "닫기")
        XCTAssertNil(closes.secondaryButtonLabel)
        XCTAssertEqual(closes.subtitle?.text, "\n온:공이 잠시 막고 있어요.\n언제 풀리는지는 온:공에서 볼 수 있어요.")
    }

    /// Amendment of 2026-11-22 (issue #201): at an accessibility text size the open button is "열기", which fits the fixed-height button on one line.
    func testOpenButtonLabelFollowsAccessibilityText() {
        XCTAssertEqual(ShieldContent.openButton(accessibilityText: false), "온:공\u{00A0}열기")
        XCTAssertEqual(ShieldContent.openButton(accessibilityText: true), "열기")
    }

    /// Amendment of 2026-11-22: only an accessibility category shortens the open button; an unknown category keeps it, and "닫기" never changes.
    func testShieldShortensTheOpenButtonOnlyAtAccessibilitySizes() {
        let large = FocusShieldConfiguration.shield(name: nil, item: .application, opensApp: true, contentSize: .accessibilityExtraExtraExtraLarge)
        XCTAssertEqual(large.primaryButtonLabel?.text, "열기")
        XCTAssertEqual(large.secondaryButtonLabel?.text, "닫기")
        for category in [UIContentSizeCategory.large, .extraExtraExtraLarge, .unspecified] {
            let shield = FocusShieldConfiguration.shield(name: nil, item: .website, opensApp: true, contentSize: category)
            XCTAssertEqual(shield.primaryButtonLabel?.text, "온:공\u{00A0}열기", "\(category.rawValue)")
            XCTAssertEqual(shield.secondaryButtonLabel?.text, "닫기", "\(category.rawValue)")
        }
        let closes = FocusShieldConfiguration.shield(name: nil, item: .application, opensApp: false, contentSize: .accessibilityExtraExtraExtraLarge)
        XCTAssertEqual(closes.primaryButtonLabel?.text, "닫기")
        XCTAssertNil(closes.secondaryButtonLabel)
    }

    /// The data source calls: an application gets the application fallback, because `localizedDisplayName` is nil outside the extension, and a website gets its domain.
    /// The two category calls need an `ActivityCategory`, which has no public initializer without a token; they build the same shield by source.
    func testCallsUseTheirItemAndOneIcon() {
        let source = FocusShieldConfiguration()
        let application = source.configuration(shielding: Application(bundleIdentifier: "com.example.app"))
        let webDomain = source.configuration(shielding: WebDomain(domain: "example.com"))
        XCTAssertEqual(application.title?.text, "지금은 쉬는 앱이에요")
        XCTAssertEqual(webDomain.title?.text, "example.com, 지금은 쉬어요")
        for shield in [application, webDomain] {
            let open = ShieldContent.openButton(accessibilityText: FocusShieldConfiguration.contentSize.isAccessibilityCategory)
            XCTAssertEqual(shield.primaryButtonLabel?.text, FocusShieldConfiguration.opensApp ? open : "닫기")
            XCTAssertTrue(shield.icon === FocusShieldConfiguration.icon)
        }
    }

    /// Name design, contract item 5: on iOS 26.5 and later the primary button opens the app and the secondary button closes; below, both close.
    func testActionResponses() {
        if #available(iOS 26.5, *) {
            XCTAssertEqual(FocusShieldAction.response(for: .primaryButtonPressed), .openParentalControlsApp)
        } else {
            XCTAssertEqual(FocusShieldAction.response(for: .primaryButtonPressed), .close)
        }
        XCTAssertEqual(FocusShieldAction.response(for: .secondaryButtonPressed), .close)
    }

    /// The mark's geometry (navy focus room design, "Colon mark geometry"): cream ring, transparent hole, amber dot, transparent corners.
    func testColonMarkPixels() throws {
        // At scale 1 the 78.2 by 179.4 mark sits centered in a 79 by 180 pixel canvas.
        let image = ShieldContent.colonMark(height: 179.4, bottomInset: 0, tile: false, scale: 1)
        XCTAssertEqual(image.size, CGSize(width: 79, height: 180))
        let pixels = try rgbaPixels(image)
        let cream = RGBA(red: 0xFF, green: 0xF4, blue: 0xE2, alpha: 255), amber = RGBA(red: 0xF4, green: 0xA6, blue: 0x4A, alpha: 255)
        XCTAssertEqual(pixels.at(x: 39, y: 11), cream, "ring above the hole")
        XCTAssertEqual(pixels.at(x: 39, y: 39).alpha, 0, "hole")
        XCTAssertEqual(pixels.at(x: 39, y: 140), amber, "dot")
        XCTAssertEqual(pixels.at(x: 1, y: 1).alpha, 0, "corner")
        XCTAssertEqual(pixels.at(x: 39, y: 89).alpha, 0, "gap between the ring and the dot")
        // A bottom inset adds only transparent rows under the mark.
        let inset = try rgbaPixels(ShieldContent.colonMark(height: 179.4, bottomInset: 20, tile: false, scale: 1))
        XCTAssertEqual(inset.at(x: 39, y: 140), amber, "dot stays in place")
        XCTAssertEqual(inset.at(x: 39, y: 190).alpha, 0, "inset under the dot")
        // The tile: a 257 pixel navy rounded square (179.4 / 0.7, rounded up) with the mark centered, and the inset under it.
        let tiled = ShieldContent.colonMark(height: 179.4, bottomInset: 20, tile: true, scale: 1)
        XCTAssertEqual(tiled.size, CGSize(width: 257, height: 277))
        let tile = try rgbaPixels(tiled)
        let navy = RGBA(red: 0x1E, green: 0x27, blue: 0x44, alpha: 255)
        XCTAssertEqual(tile.at(x: 1, y: 1).alpha, 0, "rounded tile corner")
        XCTAssertEqual(tile.at(x: 5, y: 128), navy, "tile beside the mark")
        XCTAssertEqual(tile.at(x: 128, y: 50), cream, "ring above the hole")
        XCTAssertEqual(tile.at(x: 128, y: 179), amber, "dot")
        XCTAssertEqual(tile.at(x: 128, y: 267).alpha, 0, "inset under the tile")
        // The shield's own icon, kept for review; the shield itself is drawn by iOS on a device only.
        let attachment = XCTAttachment(image: ShieldContent.colonMark())
        attachment.name = "shield-colon-mark"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private struct RGBA: Equatable { var red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 }

    private struct Pixels {
        var width: Int, bytes: [UInt8]
        func at(x: Int, y: Int) -> RGBA {
            let offset = (y * width + x) * 4
            return RGBA(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2], alpha: bytes[offset + 3])
        }
    }

    /// Unpremultiplied would need another context; every sampled pixel is opaque or fully transparent, so premultiplied values are exact.
    private func rgbaPixels(_ image: UIImage) throws -> Pixels {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(drawn)
        return Pixels(width: width, bytes: bytes)
    }

    private func srgb(_ color: UIColor) throws -> [Int] {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let values = try XCTUnwrap(color.cgColor.converted(to: space, intent: .defaultIntent, options: nil)?.components)
        return values.map { Int(($0 * 255).rounded()) }
    }
}
