import SwiftUI

/// The 순공 calendar sheet, opened from the idle screen's "오늘의 집중" card (docs/specs/2026-11-25-sungong-calendar-design.md and its amendment of 2026-11-25).
/// With paid access `locked`, one card replaces the month card and the grid, and the selected-day card stays fixed on today.
struct SungongCalendarView: View {
    let model: FocusModel
    @Environment(\.dismiss) private var dismiss
    /// `nil` only in a preview without a runtime; the review entry is then absent.
    @Environment(WeeklyReviewModel.self) private var review: WeeklyReviewModel?
    /// `nil` only in a preview without a runtime; the locked card's button then does nothing.
    @Environment(PaidAccessStore.self) private var paidAccess: PaidAccessStore?
    /// The paywall of the locked card shows over this sheet, so the month, the selected day and the scroll position stay as they are
    /// in every outcome (docs/specs/2026-11-26-paywall-design.md, contract item 7). It holds no start request.
    @State private var showsPaywall = false
    @ScaledMetric(relativeTo: .title2) private var arrowSize: CGFloat = 23
    @ScaledMetric(relativeTo: .subheadline) private var cellHeight: CGFloat = 48
    private var calendar: Calendar { .current }
    private var locked: Bool { model.services.paidAccess() == .locked }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FocusTheme.Layout.relatedSpacing) {
                    header
                    // A history failure from any read, also the month read, shows the error in place of the cards, and never an empty month.
                    if let error = model.errorMessage {
                        errorCard(error)
                    } else if let state = model.sungong, let records = state.records, let values = state.values {
                        if locked {
                            lockedCard
                        } else {
                            monthCard(state, values)
                            gridCard(state, values)
                        }
                        dayCard(state, records: records, values: values)
                        if !locked, let review { reviewEntry(review) }
                    }
                    notes
                    reportLink
                }
                .padding(.horizontal, FocusTheme.Layout.screenInset).padding(.bottom, FocusTheme.Layout.sectionSpacing)
            }
            .background(FocusTheme.Screen.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .modifier(FocusEditorSheet())
        .onAppear { model.openCalendar() }
        .onDisappear { model.closeCalendar() }
        // Access that turns `locked` while the sheet is open fixes the selected day on today.
        .onChange(of: locked) { _, locked in if locked { model.showCalendarToday() } }
        .sheet(isPresented: $showsPaywall) { if let paidAccess { PaidAccessSheet(store: paidAccess) } }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: FocusTheme.Layout.detailSpacing) {
            // A hidden copy of "닫기" on the left keeps the title centered at every text size, and the title shrinks on one line instead of running into "닫기".
            HStack(spacing: FocusTheme.Layout.detailSpacing) {
                closeLabel.hidden().accessibilityHidden(true)
                Text("순공시간").font(.title2.bold()).foregroundStyle(FocusTheme.Screen.ink).accessibilityAddTraits(.isHeader)
                    .lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: .infinity)
                Button { dismiss() } label: { closeLabel }
                    .buttonStyle(.plain).accessibilityIdentifier("historyDone")
            }
            Text("공부한 시간만, 하루하루 모아봐요.").font(.subheadline).foregroundStyle(FocusTheme.Screen.secondaryInk).multilineTextAlignment(.center)
        }
        .padding(.top, FocusTheme.Layout.relatedSpacing).padding(.bottom, FocusTheme.Layout.inlineSpacing)
    }

    private var closeLabel: some View {
        Text("닫기").font(.subheadline.weight(.medium)).foregroundStyle(FocusTheme.Screen.accentText).fixedSize()
            .frame(minWidth: FocusTheme.Layout.minimumTapTarget, minHeight: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
    }

    private func errorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: FocusTheme.Layout.relatedSpacing) {
            Text(error).font(.subheadline).foregroundStyle(FocusTheme.Screen.secondaryInk).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("historyError")
            Button("다시 확인하기") { model.refresh() }.font(.subheadline.weight(.semibold)).foregroundStyle(FocusTheme.Screen.accentText)
                .frame(minHeight: FocusTheme.Layout.minimumTapTarget).accessibilityIdentifier("historyRetry")
        }
        .modifier(FocusCard())
    }

    // MARK: Month card and grid

    private func monthCard(_ state: SungongCalendar, _ values: SessionMonth) -> some View {
        HStack(alignment: .top, spacing: FocusTheme.Layout.controlSpacing) {
            VStack(alignment: .leading, spacing: FocusTheme.Layout.detailSpacing) {
                Text("\(monthNumber(state.month.start))월 누적 순공시간").font(.footnote).foregroundStyle(FocusTheme.Screen.secondaryInk)
                Text(SessionMonth.totalText(values.focusDuration)).font(.title.weight(.semibold)).monospacedDigit().foregroundStyle(FocusTheme.Screen.ink)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("calendarMonthTotal")
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: FocusTheme.Layout.detailSpacing) {
                Text("기록한 날").font(.footnote).foregroundStyle(FocusTheme.Screen.secondaryInk)
                Text("\(values.recordedDays)일").font(.headline).monospacedDigit().foregroundStyle(FocusTheme.Screen.ink)
                    .accessibilityIdentifier("calendarRecordedDays")
                streakLine
            }
            .multilineTextAlignment(.trailing)
        }
        .modifier(FocusCard())
    }
    /// The display-only streak (docs/specs/2026-11-13-streak-design.md); absent while it is unavailable.
    @ViewBuilder private var streakLine: some View {
        if let streak = model.streak {
            Text("연속 집중 \(streak)일").font(.footnote).monospacedDigit().foregroundStyle(FocusTheme.Screen.secondaryInk)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("historyStreak")
        }
    }

    private func monthTitle(_ state: SungongCalendar) -> some View {
        Text(verbatim: "\(calendar.component(.year, from: state.month.start))년 \(monthNumber(state.month.start))월").font(.title3.bold())
            .foregroundStyle(FocusTheme.Screen.ink).fixedSize().accessibilityAddTraits(.isHeader).accessibilityIdentifier("calendarMonth")
    }
    private func monthControls(_ state: SungongCalendar, todaySelected: Bool, nextMonth: Date) -> some View {
        HStack(spacing: FocusTheme.Layout.detailSpacing) {
            monthButton("‹", label: "이전 달", identifier: "calendarPrevious", enabled: true) { model.showCalendarMonth(-1) }
            Button { model.showCalendarToday() } label: {
                Text("오늘").font(.subheadline.weight(.semibold))
                    .foregroundStyle(todaySelected ? FocusTheme.Screen.secondaryInk : FocusTheme.Screen.accentText)
                    .frame(minWidth: FocusTheme.Layout.minimumTapTarget, minHeight: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(todaySelected).accessibilityIdentifier("calendarToday")
            monthButton("›", label: "다음 달", identifier: "calendarNext", enabled: nextMonth <= state.today) { model.showCalendarMonth(1) }
        }
        .fixedSize()
    }

    private func gridCard(_ state: SungongCalendar, _ values: SessionMonth) -> some View {
        let todaySelected = state.isTodaysMonth && state.selectedDay == state.today
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: state.month.start) ?? state.month.end
        return VStack(spacing: FocusTheme.Layout.relatedSpacing) {
            // The controls move under the title when both do not fit on one line, so "2026년" never breaks inside the number.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: FocusTheme.Layout.detailSpacing) {
                    monthTitle(state)
                    Spacer(minLength: FocusTheme.Layout.inlineSpacing)
                    monthControls(state, todaySelected: todaySelected, nextMonth: nextMonth)
                }
                VStack(alignment: .leading, spacing: FocusTheme.Layout.detailSpacing) {
                    monthTitle(state)
                    HStack { Spacer(minLength: 0); monthControls(state, todaySelected: todaySelected, nextMonth: nextMonth) }
                }
            }
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol).font(.footnote.weight(.medium)).foregroundStyle(FocusTheme.Screen.secondaryInk).frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            VStack(spacing: FocusTheme.Layout.detailSpacing) {
                ForEach(Array(weeks(state.month).enumerated()), id: \.offset) { _, week in
                    HStack(spacing: FocusTheme.Layout.detailSpacing) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            if let day { dayCell(day, state: state, values: values) } else { Color.clear.frame(maxWidth: .infinity, minHeight: cellHeight).accessibilityHidden(true) }
                        }
                    }
                }
            }
        }
        .modifier(FocusCard())
    }
    private func monthButton(_ glyph: String, label: String, identifier: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph).font(.system(size: arrowSize)).foregroundStyle(enabled ? FocusTheme.Screen.accentText : FocusTheme.Screen.secondaryInk)
                .frame(minWidth: FocusTheme.Layout.minimumTapTarget, minHeight: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).accessibilityLabel(label).accessibilityIdentifier(identifier)
    }
    private func dayCell(_ day: Date, state: SungongCalendar, values: SessionMonth) -> some View {
        let selected = day == state.selectedDay, future = day > state.today
        let duration = values.day(day, calendar: calendar).focusDuration, recorded = duration > 0
        let number = calendar.component(.day, from: day)
        let ink = selected ? FocusTheme.Palette.onAccent : future ? FocusTheme.Screen.secondaryInk : FocusTheme.Screen.ink
        let valueInk = selected ? FocusTheme.Palette.onAccent : recorded ? FocusTheme.Screen.accentText : FocusTheme.Screen.secondaryInk
        return Button { model.selectCalendarDay(day) } label: {
            VStack(spacing: 2) {
                Text(verbatim: "\(number)").font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(ink)
                Text(verbatim: future ? " " : recorded ? SessionMonth.cellText(duration) : "—").font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(valueInk)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: cellHeight).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? FocusTheme.Palette.accent : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(future)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(future ? dayName(day) : "\(dayName(day)), \(recorded ? SessionMonth.totalText(duration) : "기록 없음")")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("calendarDay-\(number)")
    }

    // MARK: Locked card

    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: FocusTheme.Layout.relatedSpacing) {
            Text("구매하면 순공 캘린더를 볼 수 있어요").font(.headline).foregroundStyle(FocusTheme.Screen.ink).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("calendarLocked")
            Button("구매하기") { if paidAccess != nil { showsPaywall = true } }
                .buttonStyle(FocusFillButtonStyle(fill: FocusTheme.Palette.accent, label: FocusTheme.Palette.onAccent))
                .accessibilityIdentifier("calendarPurchase")
        }
        .modifier(FocusCard())
    }

    // MARK: Selected-day card

    private func dayCard(_ state: SungongCalendar, records: [SessionRecord], values: SessionMonth) -> some View {
        let day = locked ? state.today : state.selectedDay
        let rows = records.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
        let totals = values.day(day, calendar: calendar)
        return VStack(alignment: .leading, spacing: FocusTheme.Layout.inlineSpacing) {
            // "11월 24일 화요일", as in the Figma frames; the numeric `month(.defaultDigits)` style gave "11. 24. 화요일".
            Text(verbatim: "\(monthNumber(day))월 \(calendar.component(.day, from: day))일 \(day.formatted(Date.FormatStyle().weekday(.wide).locale(Locale(identifier: "ko_KR"))))")
                .font(.headline).foregroundStyle(FocusTheme.Screen.ink).accessibilityIdentifier("historyDate")
            Text(SessionMonth.totalText(totals.focusDuration)).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(FocusTheme.Screen.ink)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("historySummary")
            Text("집중 세션 \(totals.completedCount)회").font(.footnote).monospacedDigit().foregroundStyle(FocusTheme.Screen.secondaryInk)
                .accessibilityIdentifier("historyCount")
            if locked { streakLine }
            if rows.isEmpty {
                Text(day == state.today ? "아직 기록이 없어요." : "기록이 없어요.").font(.subheadline).foregroundStyle(FocusTheme.Screen.secondaryInk)
                    .padding(.top, FocusTheme.Layout.detailSpacing)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows, id: \.id) { record in
                        Divider()
                        sessionRow(record)
                    }
                }
                .padding(.top, FocusTheme.Layout.detailSpacing)
            }
        }
        .modifier(FocusCard())
    }
    /// A completed session shows its stored span and minutes; any other shows its start time and its end reason, and no minutes.
    private func sessionRow(_ record: SessionRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: FocusTheme.Layout.inlineSpacing) {
            if record.counts {
                Text(verbatim: "\(clock(record.startedAt))–\(clock(record.endedAt))").font(.caption).monospacedDigit().foregroundStyle(FocusTheme.Screen.secondaryInk)
                Spacer(minLength: FocusTheme.Layout.inlineSpacing)
                Text("\(Int(record.focusDuration) / 60)분").font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(FocusTheme.Screen.ink)
                    .accessibilityIdentifier("completedSession")
            } else {
                Text(verbatim: clock(record.startedAt)).font(.caption).monospacedDigit().foregroundStyle(FocusTheme.Screen.secondaryInk)
                Spacer(minLength: FocusTheme.Layout.inlineSpacing)
                Text(reasonText(record.reason)).font(.subheadline).foregroundStyle(FocusTheme.Screen.secondaryInk).multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, FocusTheme.Layout.inlineSpacing)
    }

    // MARK: Weekly review entry

    /// The review of the current period (docs/specs/2026-11-25-weekly-review-design.md, contract item 5); absent with access `locked`.
    /// The idle screen replaces this sheet with the review sheet.
    private func reviewEntry(_ review: WeeklyReviewModel) -> some View {
        Button { review.requestOpenCurrent() } label: {
            HStack {
                Label("이번 주 돌아보기", systemImage: "text.book.closed").foregroundStyle(FocusTheme.Screen.ink)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(FocusTheme.Screen.secondaryInk)
            }
            .font(.subheadline.weight(.medium)).frame(minHeight: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
            .modifier(FocusCard())
        }
        .buttonStyle(.plain).accessibilityIdentifier("calendarReview")
    }

    // MARK: Note and usage report

    private var notes: some View {
        VStack(spacing: FocusTheme.Layout.detailSpacing) {
            Text("공부한 집중 세션의 기록을 합산해요.")
            Text("휴식 시간과 일반 스크린타임은 포함하지 않아요.")
        }
        .font(.caption).foregroundStyle(FocusTheme.Screen.secondaryInk).multilineTextAlignment(.center).frame(maxWidth: .infinity)
        .padding(.top, FocusTheme.Layout.inlineSpacing)
    }
    private var reportLink: some View {
        VStack(alignment: .leading, spacing: FocusTheme.Layout.inlineSpacing) {
            NavigationLink {
                #if DEBUG
                if model.services.isFixture { FixtureUsageReportHost() }
                else { UsageReportHost() }
                #else
                UsageReportHost()
                #endif
            } label: {
                HStack {
                    Label("오늘의 사용 보고서", systemImage: "chart.bar").foregroundStyle(FocusTheme.Screen.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(FocusTheme.Screen.secondaryInk)
                }
                .font(.subheadline.weight(.medium)).frame(minHeight: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
                .modifier(FocusCard())
            }
            .buttonStyle(.plain).accessibilityIdentifier("report")
            Text("집중 기록과 별도로 기기 사용 시간을 볼 수 있어요.").font(.footnote).foregroundStyle(FocusTheme.Screen.secondaryInk)
                .padding(.horizontal, 16)
        }
        .padding(.top, FocusTheme.Layout.inlineSpacing)
    }

    // MARK: Calendar arithmetic and text

    /// The weeks of the month as rows of seven, with `nil` before the first day and after the last.
    private func weeks(_ month: DateInterval) -> [[Date?]] {
        let count = calendar.range(of: .day, in: .month, for: month.start)?.count ?? 30
        let lead = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for offset in 0..<count { cells.append(calendar.date(byAdding: .day, value: offset, to: month.start).map { calendar.startOfDay(for: $0) }) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }
    private var weekdaySymbols: [String] {
        let symbols = ["일", "월", "화", "수", "목", "금", "토"], first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
    private func monthNumber(_ date: Date) -> Int { calendar.component(.month, from: date) }
    private func dayName(_ day: Date) -> String { "\(monthNumber(day))월 \(calendar.component(.day, from: day))일" }
    /// The stored clock time in 24-hour "HH:mm", such as "09:00".
    private func clock(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
    private func reasonText(_ reason: EndReason) -> String {
        switch reason {
        case .expired: "완료"
        case .earlyExit: "집중 종료"
        case .authorizationRevoked: "접근 철회로 중단"
        case .startFailed: "시작 실패"
        case .clockChanged: "시각 변경으로 중단"
        case .recoveryInterrupted: "중단된 세션 정리"
        case .deadlineMissed: "시간 초과로 집중에서 제외"
        }
    }
}
