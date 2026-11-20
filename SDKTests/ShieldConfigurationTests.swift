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

    /// Contract item 1: navy background without blur, the mark, cream title and subtitle, "닫기" and no secondary button.
    func testShieldLayoutIsTheApprovedOne() throws {
        let shield = FocusShieldConfiguration.shield
        XCTAssertNil(shield.backgroundBlurStyle)
        XCTAssertEqual(try srgb(XCTUnwrap(shield.backgroundColor)), try srgb(ShieldContent.navy))
        XCTAssertEqual(shield.title?.text, "지금은 쉬는 앱이에요")
        XCTAssertEqual(shield.subtitle?.text, "\n온:공이 이 앱을 잠시 막고 있어요.\n언제 풀리는지는 온:공에서 볼 수 있어요.")
        XCTAssertEqual(try srgb(XCTUnwrap(shield.title?.color)), try srgb(ShieldContent.cream))
        XCTAssertEqual(try srgb(XCTUnwrap(shield.subtitle?.color)), try srgb(ShieldContent.cream))
        XCTAssertEqual(shield.primaryButtonLabel?.text, "닫기")
        XCTAssertNil(shield.secondaryButtonLabel)
        let icon = try XCTUnwrap(shield.icon)
        XCTAssertEqual(icon.scale, 3)
        XCTAssertEqual(icon.size.height, ShieldContent.markHeight + ShieldContent.markBottomInset, accuracy: 0.01)
        XCTAssertEqual(icon.size.width, 78.2 / 179.4 * ShieldContent.markHeight, accuracy: 1.0 / 3)
    }

    /// Contract item 2: the application and the web domain calls return the same configuration.
    /// The two category calls need an `ActivityCategory`, which has no public initializer without a token; they return the same `shield` by source.
    func testApplicationAndWebDomainCallsReturnTheSameShield() {
        let source = FocusShieldConfiguration()
        let application = source.configuration(shielding: Application(bundleIdentifier: "com.example.app"))
        let webDomain = source.configuration(shielding: WebDomain(domain: "example.com"))
        for shield in [application, webDomain] {
            XCTAssertEqual(shield.title?.text, ShieldContent.title)
            XCTAssertEqual(shield.subtitle?.text, ShieldContent.subtitle)
            XCTAssertEqual(shield.primaryButtonLabel?.text, ShieldContent.primaryButton)
            XCTAssertTrue(shield.icon === FocusShieldConfiguration.shield.icon)
        }
    }

    /// The mark's geometry (navy focus room design, "Colon mark geometry"): cream ring, transparent hole, amber dot, transparent corners.
    func testColonMarkPixels() throws {
        // At scale 1 the 78.2 by 179.4 mark sits centered in a 79 by 180 pixel canvas.
        let image = ShieldContent.colonMark(height: 179.4, bottomInset: 0, scale: 1)
        XCTAssertEqual(image.size, CGSize(width: 79, height: 180))
        let pixels = try rgbaPixels(image)
        let cream = RGBA(red: 0xFF, green: 0xF4, blue: 0xE2, alpha: 255), amber = RGBA(red: 0xF4, green: 0xA6, blue: 0x4A, alpha: 255)
        XCTAssertEqual(pixels.at(x: 39, y: 11), cream, "ring above the hole")
        XCTAssertEqual(pixels.at(x: 39, y: 39).alpha, 0, "hole")
        XCTAssertEqual(pixels.at(x: 39, y: 140), amber, "dot")
        XCTAssertEqual(pixels.at(x: 1, y: 1).alpha, 0, "corner")
        XCTAssertEqual(pixels.at(x: 39, y: 89).alpha, 0, "gap between the ring and the dot")
        // A bottom inset adds only transparent rows under the mark.
        let inset = try rgbaPixels(ShieldContent.colonMark(height: 179.4, bottomInset: 20, scale: 1))
        XCTAssertEqual(inset.at(x: 39, y: 140), amber, "dot stays in place")
        XCTAssertEqual(inset.at(x: 39, y: 190).alpha, 0, "inset under the dot")
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
