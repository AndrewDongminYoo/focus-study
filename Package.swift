// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "FocusCore", platforms: [.macOS(.v14), .iOS(.v17)], products: [.library(name: "FocusCore", targets: ["FocusCore"])], targets: [
    .target(name: "FocusCore", path: "Shared"),
    .target(name: "FocusHistory", dependencies: ["FocusCore"], path: "App", exclude: ["AuthorizationService.swift", "BreakSessionView.swift", "CalendarShareCard.swift", "EverydayPlanWriter.swift", "EverydaySettingsModel.swift", "EverydaySettingsView.swift", "FocusActivityRuntime.swift", "FocusFilterEntry.swift", "FocusFilterHandler.swift", "FocusGuideView.swift", "FocusModel.swift", "FocusRuntime.swift", "FocusRuntimeHolder.swift", "FocusServices.swift", "FocusSettings.swift", "FocusSheetStyle.swift", "FocusStudyApp.swift", "FocusStudyFilter.swift", "FocusTheme.swift", "FocusView.swift", "OnboardingView.swift", "PaidAccessSheet.swift", "PaidAccessStore.swift", "PrivacyInfo.xcprivacy", "ProminentLabel.swift", "SelectionEditor.swift", "SelectionFeedback.swift", "SelectionRepository.swift", "SettingsView.swift", "StartupAttempts.swift", "SungongCalendarView.swift", "TodaySnapshotWriter.swift", "UsageReportHost.swift", "WeeklyReviewModel.swift", "WeeklyReviewNotifications.swift", "WeeklyReviewView.swift", "Assets.xcassets", "Debug"], sources: ["CalendarShareRules.swift", "SessionRecord.swift"]),
    .target(name: "FocusReportLogic", path: "Report", exclude: ["FocusReport.swift"], sources: ["UsageSummary.swift"]),
    .testTarget(name: "FocusCoreTests", dependencies: ["FocusCore"], path: "CoreTests"),
    .testTarget(name: "FocusHistoryTests", dependencies: ["FocusHistory", "FocusCore"], path: "HistoryTests"),
    .testTarget(name: "FocusReportLogicTests", dependencies: ["FocusReportLogic"], path: "ReportTests")
], swiftLanguageModes: [.v5])
