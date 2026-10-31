// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "FocusCore", platforms: [.macOS(.v14), .iOS(.v17)], products: [.library(name: "FocusCore", targets: ["FocusCore"])], targets: [
    .target(name: "FocusCore", path: "Shared"),
    .target(name: "FocusHistory", dependencies: ["FocusCore"], path: "App", exclude: ["AuthorizationService.swift", "FocusModel.swift", "FocusRuntime.swift", "FocusStudyApp.swift", "FocusView.swift", "PrivacyInfo.xcprivacy", "SelectionEditor.swift", "SelectionFeedback.swift", "SelectionRepository.swift", "UsageReportHost.swift", "Debug"], sources: ["SessionRecord.swift"]),
    .target(name: "FocusReportLogic", path: "Report", exclude: ["FocusReport.swift"], sources: ["UsageSummary.swift"]),
    .testTarget(name: "FocusCoreTests", dependencies: ["FocusCore"], path: "CoreTests"),
    .testTarget(name: "FocusHistoryTests", dependencies: ["FocusHistory", "FocusCore"], path: "HistoryTests"),
    .testTarget(name: "FocusReportLogicTests", dependencies: ["FocusReportLogic"], path: "ReportTests")
], swiftLanguageModes: [.v5])
