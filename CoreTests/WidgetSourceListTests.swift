import XCTest

/// The widget extension's boundary (home widget spec "Privacy boundary that changes"): the `FocusActivity` sources of `project.yml` and the imports of those files.
/// This is the check for the control file, the lock file and the history store, whose short names a search of the built extension cannot see.
final class WidgetSourceListTests: XCTestCase {
    private static let approved = [
        "Widget", "Activity/FocusActivityAttributes.swift", "Activity/FocusActivityViews.swift",
        "Shared/FocusActivityContent.swift", "Shared/TodaySnapshot.swift",
    ]
    private static let forbiddenImports = ["FamilyControls", "ManagedSettings", "DeviceActivity", "SwiftData"]
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// The `sources` entries of `FocusActivity`; a source with options would appear as `path:` and fail the comparison.
    private func activitySources() throws -> [String] {
        let lines = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8).components(separatedBy: "\n")
        let target = try XCTUnwrap(lines.firstIndex(of: "  FocusActivity:"))
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
    func testActivitySourcesAreTheApprovedList() throws {
        XCTAssertEqual(try activitySources(), Self.approved.map { "- \($0)" })
    }
    func testActivitySourcesImportNoScreenTimeFrameworkOrSwiftData() throws {
        let manager = FileManager.default
        let widget = try manager.contentsOfDirectory(atPath: root.appendingPathComponent("Widget").path).filter { $0.hasSuffix(".swift") }.map { "Widget/\($0)" }
        let files = widget + Self.approved.filter { $0.hasSuffix(".swift") }
        XCTAssertTrue(widget.contains("Widget/TodayWidget.swift"))
        for file in files {
            let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            for framework in Self.forbiddenImports {
                XCTAssertFalse(text.contains("import \(framework)"), "\(file) imports \(framework)")
            }
        }
        let snapshot = try String(contentsOf: root.appendingPathComponent("Shared/TodaySnapshot.swift"), encoding: .utf8)
        XCTAssertEqual(snapshot.components(separatedBy: "\n").filter { $0.hasPrefix("import ") }, ["import Foundation"])
    }
}
