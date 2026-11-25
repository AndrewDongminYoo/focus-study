import Foundation
import UIKit
import UserNotifications

/// The review notification through `UNUserNotificationCenter`: the app's only notification code, in the app target only.
struct SystemReviewNotificationCenter: ReviewNotificationScheduling {
    nonisolated static let identifier = "weeklyReview"
    /// `weeklyReview` for the first request of a plan, `weeklyReview.1` and on for the others.
    nonisolated static func identifier(_ index: Int) -> String { index == 0 ? identifier : "\(identifier).\(index)" }
    private var center: UNUserNotificationCenter { .current() }
    func permission() async -> ReviewPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .authorized
        }
    }
    func requestPermission() async { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
    /// The text is fixed when the request is added, so it holds no numbers.
    func replace(with plan: ReviewNotificationPlan, calendar: Calendar) async -> Bool {
        center.removePendingNotificationRequests(withIdentifiers: (0..<WeeklyReview.pendingDates).map(Self.identifier))
        // A single notification carries its time zone, so it fires at the absolute time that the plan checked against the trial end,
        // also after the device moves to another time zone; the repeating one follows the local time on purpose.
        func once(_ date: Date) -> UNCalendarNotificationTrigger {
            UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.timeZone, .year, .month, .day, .hour, .minute], from: date), repeats: false)
        }
        func repeating(_ weekday: Int, _ minute: Int) -> UNCalendarNotificationTrigger {
            UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: minute / 60, minute: minute % 60, weekday: weekday), repeats: true)
        }
        let triggers: [UNCalendarNotificationTrigger]
        switch plan {
        case .none: return true
        case .once(let date): triggers = [once(date)]
        case let .repeating(weekday, minute): triggers = [repeating(weekday, minute)]
        case let .onceThenRepeating(date, weekday, minute): triggers = [once(date), repeating(weekday, minute)]
        case .dates(let dates): triggers = dates.map(once)
        }
        let content = UNMutableNotificationContent()
        content.body = "이번 주 회고가 준비됐어요"
        content.sound = .default
        do {
            for (index, trigger) in triggers.enumerated() {
                try await center.add(UNNotificationRequest(identifier: Self.identifier(index), content: content, trigger: trigger))
            }
            return true
        } catch {
            return false
        }
    }
}

/// The delegate of `UNUserNotificationCenter`, set at launch so that a tap that launches the app is not lost.
/// It holds a tap until the app's runtime is ready to open the review.
final class ReviewNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReviewNotificationDelegate()
    @MainActor private var pending: Date?
    @MainActor private var handler: ((Date) -> Void)?
    /// Takes a tap that arrived before the handler.
    @MainActor func setHandler(_ handler: @escaping (Date) -> Void) {
        self.handler = handler
        if let pending { self.pending = nil; handler(pending) }
    }
    @MainActor private func receive(_ date: Date) {
        if let handler { handler(date) } else { pending = date }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let date = response.notification.date
        if response.notification.request.identifier.hasPrefix(SystemReviewNotificationCenter.identifier) {
            Task { @MainActor in self.receive(date) }
        }
        completionHandler()
    }
    /// While the app is in the foreground, the notification still shows as a banner.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

/// Sets the notification delegate before the first scene, so a cold launch from a notification tap reaches it.
final class FocusAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if DEBUG
        // UI test fixtures never touch the notification center.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return true }
        #endif
        UNUserNotificationCenter.current().delegate = ReviewNotificationDelegate.shared
        return true
    }
}
