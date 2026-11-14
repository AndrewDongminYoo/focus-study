// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "FocusCore", platforms: [.macOS(.v14), .iOS(.v17)], products: [.library(name: "FocusCore", targets: ["FocusCore"])], targets: [
    .target(name: "FocusCore", path: "Shared"),
    .target(name: "FocusHistory", dependencies: ["FocusCore"], path: "App", exclude: ["AuthorizationService.swift", "BreakSessionView.swift", "EverydaySettingsModel.swift", "EverydaySettingsView.swift", "FocusActivityRuntime.swift", "FocusFilterHandler.swift", "FocusGuideView.swift", "FocusModel.swift", "FocusRuntime.swift", "FocusRuntimeHolder.swift", "FocusSettings.swift", "FocusSheetStyle.swift", "FocusStudyApp.swift", "FocusStudyFilter.swift", "FocusTheme.swift", "FocusView.swift", "OnboardingView.swift", "PrivacyInfo.xcprivacy", "ProminentLabel.swift", "SelectionEditor.swift", "SelectionFeedback.swift", "SelectionRepository.swift", "SettingsView.swift", "TodayHistoryView.swift", "TodaySnapshotWriter.swift", "UsageReportHost.swift", "Assets.xcassets", "Debug"], sources: ["SessionRecord.swift"]),
    .target(name: "FocusReportLogic", path: "Report", exclude: ["FocusReport.swift"], sources: ["UsageSummary.swift"]),
    .testTarget(name: "FocusCoreTests", dependencies: ["FocusCore"], path: "CoreTests"),
    .testTarget(name: "FocusHistoryTests", dependencies: ["FocusHistory", "FocusCore"], path: "HistoryTests"),
    .testTarget(name: "FocusReportLogicTests", dependencies: ["FocusReportLogic"], path: "ReportTests")
], swiftLanguageModes: [.v5])
