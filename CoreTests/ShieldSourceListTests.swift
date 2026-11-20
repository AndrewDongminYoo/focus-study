import XCTest

/// The shield extension's boundary (custom shield design, contract item 5 and "Targets and entitlements"): it compiles only `Shield/`, reads no data, and its entitlements hold only Family Controls.
final class ShieldSourceListTests: XCTestCase {
    private static let allowedImports: Set<String> = ["ManagedSettings", "ManagedSettingsUI", "UIKit"]
    /// Calls that would read stored data: the App Group, files, defaults, the history store or the selection.
    private static let forbiddenText = ["containerURL", "FileManager", "UserDefaults", "ModelContainer", "FamilyActivitySelection", "SharedControlStore", "Bundle.main.object"]
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// The `sources` entries of `FocusShield`; a source with options would appear as `path:` and fail the comparison.
    private func shieldSources() throws -> [String] {
        let lines = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8).components(separatedBy: "\n")
        let target = try XCTUnwrap(lines.firstIndex(of: "  FocusShield:"))
        var sources: [String] = [], inSources = false
        for line in lines[(target + 1)...] {
            if !line.hasPrefix("    ") && !line.isEmpty { break }
            if line == "    sources:" { inSources = true; continue }
            guard inSources else { continue }
            if line.hasPrefix("      ") { sources.append(line.trimmingCharacters(in: .whitespaces)); continue }
            break
        }
        return sources
    }

    func testShieldSourcesAreOnlyTheShieldDirectory() throws {
        XCTAssertEqual(try shieldSources(), ["- Shield"])
    }

    func testShieldSourcesReadNoData() throws {
        let directory = root.appendingPathComponent("Shield")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".swift") }
        XCTAssertEqual(Set(files), ["FocusShieldConfiguration.swift", "ShieldContent.swift"])
        for file in files {
            let text = try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
            let imports = text.components(separatedBy: "\n").filter { $0.hasPrefix("import ") }.map { String($0.dropFirst("import ".count)) }
            XCTAssertTrue(Set(imports).isSubset(of: Self.allowedImports), "\(file) imports \(imports)")
            for name in Self.forbiddenText {
                XCTAssertFalse(text.contains(name), "\(file) contains \(name)")
            }
        }
    }

    func testShieldEntitlementsHoldOnlyFamilyControls() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("Configuration/Shield.entitlements"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(Set(plist.keys), ["com.apple.developer.family-controls"])
        XCTAssertEqual(plist["com.apple.developer.family-controls"] as? Bool, true)
    }

    func testShieldInfoNamesTheConfigurationExtensionPoint() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("Configuration/Shield-Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let extensionInfo = try XCTUnwrap(plist["NSExtension"] as? [String: Any])
        XCTAssertEqual(extensionInfo["NSExtensionPointIdentifier"] as? String, "com.apple.ManagedSettingsUI.shield-configuration-service")
        XCTAssertEqual(extensionInfo["NSExtensionPrincipalClass"] as? String, "$(PRODUCT_MODULE_NAME).FocusShieldConfiguration")
        XCTAssertNil(plist["FocusAppGroupIdentifier"])
    }
}
