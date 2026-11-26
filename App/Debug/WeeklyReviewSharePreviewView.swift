#if DEBUG
import SwiftUI

/// `--review-share-preview`: the exported share image of the weekly review with synthetic values, for the approval captures.
/// It reads no history, and its sessions are the spec's example: two days and five sessions in a first period of three days, opened on day 3.
struct WeeklyReviewSharePreviewView: View {
    private let calendar = Calendar.current
    var body: some View {
        let today = ReviewDay(Date(), calendar: calendar), period = ReviewPeriod(first: today.adding(-2, calendar: calendar), last: today)
        // Three sessions two days before today and two the day before: "이틀에 걸쳐 5번".
        let entries = [(-2, 9), (-2, 14), (-2, 20), (-1, 8), (-1, 19)].map { offset, hour in
            ReviewEntry(startedAt: today.adding(offset, calendar: calendar).start(in: calendar).addingTimeInterval(TimeInterval(hour * 3600)), focusDuration: 1500)
        }
        let summary = ReviewSummary(entries: entries, period: period, today: today, calendar: calendar)
        ZStack {
            FocusTheme.Screen.canvas.ignoresSafeArea()
            if let image = WeeklyReviewShareCard.render(period: period, sentence: WeeklyReview.sentence(summary, inProgress: true), summary: summary, calendar: calendar) {
                Image(uiImage: image).resizable().scaledToFit().padding(FocusTheme.Layout.screenInset).accessibilityIdentifier("reviewShareImage")
            }
        }
    }
}
#endif
