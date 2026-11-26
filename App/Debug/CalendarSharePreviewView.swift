#if DEBUG
import SwiftUI

/// `--calendar-share-preview <mode>`: the exported share image of the 순공 calendar with synthetic values, for the approval captures.
/// It reads no history. Every mode uses a fixed today (2026-11-24), the Asia/Seoul time zone and Sunday as the first weekday,
/// so the captures do not change with the run date.
/// - `current`: November 2026 up to today, 20 recorded days and 35 hours, as in the mockup.
/// - `four`: February 2026, a past month of four rows.
/// - `six`: August 2026, a past month of six rows.
/// - `one`: October 2026, one recorded day of 40 minutes.
struct CalendarSharePreviewView: View {
    let mode: String
    var body: some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.firstWeekday = 1
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24))!
        let (month, days, minutes) = Self.sample(mode)
        let start = calendar.date(from: DateComponents(year: 2026, month: month, day: 1))!
        let interval = SessionMonth.interval(containing: start, calendar: calendar)
        let recorded = Set(days.map { calendar.date(from: DateComponents(year: 2026, month: month, day: $0))! })
        return ZStack {
            FocusTheme.Screen.canvas.ignoresSafeArea()
            if let image = CalendarShareCard.render(month: interval, today: today, recordedDays: recorded, focusDuration: TimeInterval(minutes * 60), calendar: calendar) {
                Image(uiImage: image).resizable().scaledToFit().padding(FocusTheme.Layout.screenInset).accessibilityIdentifier("calendarShareImage")
            }
        }
    }
    private static func sample(_ mode: String) -> (month: Int, days: [Int], minutes: Int) {
        switch mode {
        case "four": (2, [2, 3, 5, 6, 9, 10, 11, 16, 17, 19, 23, 24, 26], 1_310)
        case "six": (8, [1, 3, 4, 5, 10, 11, 12, 13, 17, 18, 20, 24, 25, 27, 31], 1_620)
        case "one": (10, [15], 40)
        default: (11, [1, 2, 3, 5, 6, 7, 9, 10, 11, 12, 14, 15, 16, 17, 19, 20, 21, 22, 23, 24], 2_100)
        }
    }
}
#endif
