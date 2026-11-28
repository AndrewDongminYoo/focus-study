#if DEBUG
import SwiftUI

/// Draws the production everyday plan widget view for one fixed plan at a fixed time of Wednesday 2026-11-25:
/// no file read, no App Group access and no WidgetKit request. The flat widget only approximates the accented mode.
struct EverydayPlanWidgetPreviewView: View {
    let mode: String
    private var display: EverydayPlanDisplay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        func at(_ hour: Int, _ minute: Int = 0) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: hour, minute: minute)) ?? Date() }
        var plan = EverydayPlan.sample
        switch mode {
        case "none": return EverydayPlanFile(plan: nil, needsCheck: false).display(at: at(14, 20), calendar: calendar)
        case "check": return EverydayPlanFile(plan: plan, needsCheck: true).display(at: at(14, 20), calendar: calendar)
        case "off": plan.enabled = false
        case "day-off": plan.weekdays = [1, 7]
        case "off-today": plan.offDay = EverydayPlan.dayKey(of: at(12), calendar: calendar)
        case "before": return EverydayPlanFile(plan: plan, needsCheck: false).display(at: at(7), calendar: calendar)
        case "unblocked": return EverydayPlanFile(plan: plan, needsCheck: false).display(at: at(12, 30), calendar: calendar)
        case "after": return EverydayPlanFile(plan: plan, needsCheck: false).display(at: at(19), calendar: calendar)
        default: break
        }
        return EverydayPlanFile(plan: plan, needsCheck: false).display(at: at(14, 20), calendar: calendar)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("제한 계획 위젯 미리보기").font(.headline).accessibilityIdentifier("planWidgetPreviewReady")
                // The background is drawn here because `containerBackground` draws nothing in an app; 364 × 170 shrinks to fit a narrower screen.
                EverydayPlanWidgetView(display: display).aspectRatio(364 / 170, contentMode: .fit).frame(maxWidth: 364)
                    .background { TodayWidgetBackground() }
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                Text("강조 모드 근사(평면)").font(.caption)
                EverydayPlanWidgetView(display: display, drawsFlat: true).aspectRatio(364 / 170, contentMode: .fit).frame(maxWidth: 364)
                    .background { TodayWidgetBackground(drawsFlat: true) }
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .padding(3)
                    .background(LinearGradient(colors: [Color(red: 0.15, green: 0.2, blue: 0.3), Color(red: 0.24, green: 0.2, blue: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
                    .accessibilityHidden(true)
            }.padding()
        }.background(Color(uiColor: .systemGroupedBackground))
    }
}
#endif
