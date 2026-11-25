import SwiftUI
import UIKit

/// The weekly review sheet (docs/specs/2026-11-25-weekly-review-design.md): form A as one scrolling sheet, form B as pages while the trial grants access.
struct WeeklyReviewView: View {
    let model: FocusModel
    let review: WeeklyReviewModel
    let day: ReviewDay
    /// The request that opened this sheet; closing it clears only this request, never a newer one from a notification tap.
    let requestID: UUID
    let form: ReviewForm
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var pageIndex = 0
    @State private var shareImage: UIImage?
    @State private var saveMessage: String?
    @State private var saver = PhotoSaver()
    private var calendar: Calendar { .current }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, FocusTheme.Layout.screenInset)
            if review.loadFailed {
                ScrollView { errorCard.padding(.horizontal, FocusTheme.Layout.screenInset) }
            } else if let page = review.page {
                switch form {
                case .sheet: sheetForm(page)
                case .pages: pagesForm(page)
                }
            } else {
                Spacer()
            }
        }
        .background(FocusTheme.Screen.canvas.ignoresSafeArea())
        .modifier(FocusEditorSheet())
        .onAppear { review.load(day: day) { [model] interval in try model.completedSessions(in: interval) } }
        .onDisappear { review.close(request: requestID) }
        .onChange(of: review.page?.summary) { _, _ in renderShareImage() }
        // The sentence loses "지금까지" after the period's last day although the day totals stay the same.
        .onChange(of: review.page?.sentence) { _, _ in renderShareImage() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: FocusTheme.Layout.detailSpacing) {
            // Save and share sit next to the close control.
            HStack(spacing: FocusTheme.Layout.detailSpacing) {
                Spacer(minLength: 0)
                iconButton("square.and.arrow.down", label: "사진에 저장하기", identifier: "reviewSave") { save() }
                if let shareImage {
                    let image = Image(uiImage: shareImage)
                    ShareLink(item: image, preview: SharePreview("이번 주 회고", image: image)) { iconLabel("square.and.arrow.up") }
                        .buttonStyle(.plain).accessibilityLabel("공유하기").accessibilityIdentifier("reviewShare")
                } else {
                    iconLabel("square.and.arrow.up").opacity(0.4).accessibilityLabel("공유하기").accessibilityIdentifier("reviewShare")
                }
                Button { dismiss() } label: {
                    Text("닫기").font(.subheadline.weight(.medium)).foregroundStyle(FocusTheme.Screen.accentText).fixedSize()
                        .frame(minWidth: FocusTheme.Layout.minimumTapTarget, minHeight: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("reviewDone")
            }
            Text("이번 주 회고").font(.title2.bold()).foregroundStyle(FocusTheme.Screen.ink).accessibilityAddTraits(.isHeader)
            if let page = review.page {
                Text(Self.periodText(page.period, calendar: calendar)).font(.subheadline).foregroundStyle(FocusTheme.Screen.secondaryInk)
                    .accessibilityIdentifier("reviewPeriod")
            }
            if let saveMessage {
                Text(saveMessage).font(.footnote).foregroundStyle(FocusTheme.Screen.secondaryInk).accessibilityIdentifier("reviewSaveMessage")
            }
        }
        .padding(.top, FocusTheme.Layout.relatedSpacing).padding(.bottom, FocusTheme.Layout.relatedSpacing)
    }
    private func iconLabel(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.body.weight(.medium)).foregroundStyle(FocusTheme.Screen.accentText)
            .frame(minWidth: FocusTheme.Layout.minimumTapTarget, minHeight: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
    }
    private func iconButton(_ symbol: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { iconLabel(symbol) }.buttonStyle(.plain).disabled(shareImage == nil).accessibilityLabel(label).accessibilityIdentifier(identifier)
    }
    private var errorCard: some View {
        VStack(alignment: .leading, spacing: FocusTheme.Layout.relatedSpacing) {
            Text("기록을 불러오지 못했어요. 다시 확인해 주세요.").font(.subheadline).foregroundStyle(FocusTheme.Screen.secondaryInk)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("reviewError")
            Button("다시 확인하기") { review.retry() }.font(.subheadline.weight(.semibold)).foregroundStyle(FocusTheme.Screen.accentText)
                .frame(minHeight: FocusTheme.Layout.minimumTapTarget)
        }
        .modifier(FocusCard())
    }

    // MARK: Form A

    private func sheetForm(_ page: ReviewPage) -> some View {
        ScrollView {
            VStack(spacing: FocusTheme.Layout.relatedSpacing) {
                if let lastNote = page.lastNote { lastNoteCard(lastNote) }
                summaryCard(page, large: false)
                if let moment = page.moment { momentCard(moment) }
                noteCard(page)
                notificationRow
            }
            .padding(.horizontal, FocusTheme.Layout.screenInset).padding(.bottom, FocusTheme.Layout.sectionSpacing)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Form B

    private func pagesForm(_ page: ReviewPage) -> some View {
        let count = page.moment == nil ? 2 : 3
        return VStack(spacing: FocusTheme.Layout.relatedSpacing) {
            TabView(selection: $pageIndex) {
                pageScroll { summaryCard(page, large: true) }.tag(0)
                if let moment = page.moment { pageScroll { momentCard(moment) }.tag(1) }
                pageScroll {
                    VStack(spacing: FocusTheme.Layout.relatedSpacing) {
                        noteCard(page)
                        notificationRow
                    }
                }
                .tag(count - 1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            HStack(spacing: FocusTheme.Layout.inlineSpacing) {
                ForEach(0..<count, id: \.self) { index in
                    Circle().fill(index == pageIndex ? FocusTheme.Screen.accentText : FocusTheme.Screen.secondaryInk.opacity(0.3)).frame(width: 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore).accessibilityLabel("\(count)쪽 중 \(pageIndex + 1)쪽").accessibilityIdentifier("reviewPageIndicator")
            if pageIndex < count - 1 {
                Button("다음") { withAnimation { pageIndex += 1 } }
                    .buttonStyle(FocusFillButtonStyle(fill: FocusTheme.Palette.accent, label: FocusTheme.Palette.onAccent))
                    .accessibilityIdentifier("reviewNext")
                    .padding(.horizontal, FocusTheme.Layout.screenInset)
            }
        }
        .padding(.bottom, FocusTheme.Layout.inlineSpacing)
    }
    private func pageScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView { content().padding(.horizontal, FocusTheme.Layout.screenInset).padding(.bottom, FocusTheme.Layout.relatedSpacing) }
            .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Parts

    /// Absent until day 1 is fixed (access `unknown`), when nothing can be scheduled.
    @ViewBuilder private var notificationRow: some View {
        if review.schedule != nil { ReviewNotificationRow(review: review) }
    }

    private func lastNoteCard(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: FocusTheme.Layout.inlineSpacing) {
            Text("지난주의 내가 남긴 말").font(.footnote.weight(.medium)).foregroundStyle(FocusTheme.Screen.secondaryInk)
            Text(note).font(.subheadline).foregroundStyle(FocusTheme.Screen.secondaryInk).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reviewLastNote")
        }
        .modifier(FocusCard())
    }
    private func summaryCard(_ page: ReviewPage, large: Bool) -> some View {
        VStack(alignment: .leading, spacing: FocusTheme.Layout.relatedSpacing) {
            Text("이번 주 한 일").font(.footnote.weight(.medium)).foregroundStyle(FocusTheme.Screen.accentText)
            Text(Self.keepingWords(page.sentence)).font(large ? .title2.weight(.semibold) : .headline).foregroundStyle(FocusTheme.Screen.ink)
                .fixedSize(horizontal: false, vertical: true).accessibilityLabel(page.sentence).accessibilityIdentifier("reviewSummary")
            if page.summary.completedCount > 0 {
                Text("집중한 시간 \(SessionMonth.totalText(page.summary.focusDuration))").font(.subheadline).monospacedDigit().foregroundStyle(FocusTheme.Screen.secondaryInk)
                    .accessibilityIdentifier("reviewTotal")
            }
            ReviewBars(summary: page.summary, filled: FocusTheme.Screen.accentText, empty: FocusTheme.Screen.secondaryInk, label: FocusTheme.Screen.secondaryInk)
        }
        .modifier(FocusCard())
    }
    private func momentCard(_ moment: String) -> some View {
        VStack(alignment: .leading, spacing: FocusTheme.Layout.inlineSpacing) {
            Text("다시 꺼내 볼 순간").font(.footnote.weight(.medium)).foregroundStyle(FocusTheme.Screen.accentText)
            Text(Self.keepingWords(moment)).font(.subheadline).foregroundStyle(FocusTheme.Screen.ink).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(moment).accessibilityIdentifier("reviewMoment")
        }
        .modifier(FocusCard())
    }
    /// The most prominent part: a navy card with cream text.
    private func noteCard(_ page: ReviewPage) -> some View {
        VStack(alignment: .leading, spacing: FocusTheme.Layout.inlineSpacing) {
            Text("다음 주의 나에게").font(.title3.bold()).foregroundStyle(FocusTheme.Room.text).accessibilityAddTraits(.isHeader)
            Text("다음엔 어디서 다시 시작할까요?").font(.subheadline).foregroundStyle(FocusTheme.Room.secondaryText).fixedSize(horizontal: false, vertical: true)
            Group {
                if page.noteEditable {
                    TextField("", text: Binding(get: { review.page?.note ?? "" }, set: { review.updateNote($0) }),
                              prompt: Text("예: 월요일 아침, 오답 노트부터").foregroundStyle(FocusTheme.Room.secondaryText), axis: .vertical)
                        .lineLimit(3...10).foregroundStyle(FocusTheme.Room.text).tint(FocusTheme.Room.marker)
                } else {
                    Text(page.note.isEmpty ? "남긴 말이 없어요." : page.note).foregroundStyle(FocusTheme.Room.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                }
            }
            .font(.body).padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(FocusTheme.Room.text.opacity(0.08)))
            .accessibilityIdentifier("reviewNote")
        }
        .padding(.horizontal, 16).padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: FocusTheme.Screen.cornerRadius).fill(FocusTheme.Room.background))
        // The dark canvas is nearly the same navy, so in the dark appearance an amber border keeps this the most prominent card.
        .overlay(RoundedRectangle(cornerRadius: FocusTheme.Screen.cornerRadius).strokeBorder(FocusTheme.Room.marker, lineWidth: scheme == .dark ? 1.5 : 0))
    }

    // MARK: Share and save

    /// The image holds only the dates and "what I did": never the note, the last note or the moment.
    private func renderShareImage() {
        guard let page = review.page else { shareImage = nil; return }
        shareImage = WeeklyReviewShareCard.render(period: page.period, sentence: page.sentence, summary: page.summary, calendar: calendar)
    }
    private func save() {
        guard let shareImage else { return }
        saver.save(shareImage) { saved in saveMessage = saved ? "사진에 저장했어요." : "저장하지 못했어요. 사진 접근 권한을 확인해 주세요." }
    }

    /// Korean text breaks between any two syllables, which split "5번" over two lines; a word joiner inside each word leaves only the spaces as breaks.
    /// The views that show it keep the plain text as their accessibility label.
    static func keepingWords(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: false).map { $0.map(String.init).joined(separator: "\u{2060}") }.joined(separator: " ")
    }
    /// "11월 23일 – 11월 29일".
    static func periodText(_ period: ReviewPeriod, calendar: Calendar) -> String {
        let first = "\(period.first.month)월 \(period.first.day)일"
        return period.first == period.last ? first : "\(first) – \(period.last.month)월 \(period.last.day)일"
    }
}

/// One bar per day of the period. A day after today is a dimmed bar without a value; a day without a completed session reads "온:공 기록 없음".
struct ReviewBars: View {
    let summary: ReviewSummary
    let filled: Color
    let empty: Color
    let label: Color
    @ScaledMetric(relativeTo: .footnote) private var height: CGFloat = 64
    private var calendar: Calendar { .current }
    var body: some View {
        let longest = max(summary.days.compactMap(\.focusDuration).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: FocusTheme.Layout.inlineSpacing) {
            ForEach(Array(summary.days.enumerated()), id: \.offset) { index, day in
                VStack(spacing: FocusTheme.Layout.detailSpacing) {
                    ZStack(alignment: .bottom) {
                        Color.clear.frame(height: height)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(day.focusDuration == nil ? empty.opacity(0.12) : (day.focusDuration ?? 0) > 0 ? filled : empty.opacity(0.3))
                            .frame(height: day.focusDuration.map { $0 > 0 ? max(6, height * $0 / longest) : 4 } ?? height * 0.35)
                    }
                    Text(String(WeeklyReview.weekdayName(day.day, calendar: calendar).prefix(1))).font(.caption2).foregroundStyle(day.focusDuration == nil ? label.opacity(0.5) : label)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText(day))
                .accessibilityIdentifier("reviewDay-\(index)")
            }
        }
    }
    private func accessibilityText(_ day: ReviewSummary.Day) -> String {
        let name = WeeklyReview.weekdayName(day.day, calendar: calendar)
        guard let duration = day.focusDuration else { return name }
        return "\(name), \(day.completedCount > 0 ? SessionMonth.totalText(duration) : "온:공 기록 없음")"
    }
}

/// The image of the share and save buttons: a navy card with only the dates, the sentence, the day bars and the colon mark.
struct WeeklyReviewShareCard: View {
    let period: ReviewPeriod
    let sentence: String
    let summary: ReviewSummary
    let calendar: Calendar
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                Text(WeeklyReviewView.periodText(period, calendar: calendar)).font(.subheadline.weight(.medium)).foregroundStyle(FocusTheme.Room.secondaryText)
                Spacer()
                ColonMark(height: 44)
            }
            Text(WeeklyReviewView.keepingWords(sentence)).font(.title2.weight(.semibold)).foregroundStyle(FocusTheme.Room.text).fixedSize(horizontal: false, vertical: true)
            ReviewBars(summary: summary, filled: FocusTheme.Room.marker, empty: FocusTheme.Room.text, label: FocusTheme.Room.secondaryText)
        }
        .padding(28).frame(width: 360, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24).fill(FocusTheme.Room.background))
    }
    /// One fixed size and the default text size, so the image is the same at every text size of the device.
    @MainActor static func render(period: ReviewPeriod, sentence: String, summary: ReviewSummary, calendar: Calendar) -> UIImage? {
        let renderer = ImageRenderer(content: WeeklyReviewShareCard(period: period, sentence: sentence, summary: summary, calendar: calendar)
            .environment(\.dynamicTypeSize, .large).environment(\.colorScheme, .light))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// The explanation before the permission prompt (contract item 6). It shows once; both actions close it.
struct ReviewExplanationView: View {
    let review: WeeklyReviewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FocusTheme.Layout.sectionSpacing) {
                // The mark on a navy tile, as in the app icon: its cream ring does not show on the light canvas.
                ColonMark(height: 40).frame(width: 64, height: 64).background(RoundedRectangle(cornerRadius: 16).fill(FocusTheme.Room.background))
                    .padding(.top, FocusTheme.Layout.sectionSpacing)
                VStack(alignment: .leading, spacing: FocusTheme.Layout.inlineSpacing) {
                    Text("주간 회고 알림을 받아 볼까요?").font(.title2.weight(.semibold)).foregroundStyle(FocusTheme.Screen.ink)
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("reviewExplanation")
                    Text("일주일에 한 번, 저녁에 이번 주를 돌아볼 수 있게 알려 드려요. 요일과 시간은 회고 화면에서 바꾸거나 끌 수 있어요.")
                        .foregroundStyle(FocusTheme.Screen.secondaryInk).fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: FocusTheme.Layout.inlineSpacing) {
                    Button("알림 받기") { Task { await review.allowNotifications() }; dismiss() }
                        .buttonStyle(FocusFillButtonStyle(fill: FocusTheme.Palette.accent, label: FocusTheme.Palette.onAccent))
                        .accessibilityIdentifier("reviewExplanationAllow")
                    Button { review.dismissExplanation(); dismiss() } label: {
                        Text("다음에 할게요").font(.subheadline.weight(.medium)).foregroundStyle(FocusTheme.Screen.accentText)
                            .frame(maxWidth: .infinity, minHeight: FocusTheme.Layout.minimumTapTarget).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("reviewExplanationClose")
                }
            }
            .padding(.horizontal, FocusTheme.Layout.screenInset)
        }
        .background(FocusTheme.Screen.canvas.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // A swipe down closes it too, and it never shows again.
        .onDisappear { review.dismissExplanation() }
    }
}

/// The notification row: the weekday and time of the review notification, and the switch.
struct ReviewNotificationRow: View {
    let review: WeeklyReviewModel
    private static let weekdays = ["일요일", "월요일", "화요일", "수요일", "목요일", "금요일", "토요일"]
    var body: some View {
        VStack(alignment: .leading, spacing: FocusTheme.Layout.inlineSpacing) {
            if review.permission == .denied {
                Text("회고 알림").font(.subheadline.weight(.medium)).foregroundStyle(FocusTheme.Screen.ink)
                Text("알림이 꺼져 있어요. 설정 앱에서 켤 수 있어요.").font(.footnote).foregroundStyle(FocusTheme.Screen.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("reviewNotificationsOff")
                Button("설정 열기") { if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) } }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(FocusTheme.Screen.accentText).frame(minHeight: FocusTheme.Layout.minimumTapTarget)
            } else if let schedule = review.schedule {
                Toggle(isOn: Binding(get: { schedule.notificationsOn && review.permission == .authorized }, set: { on in Task { await review.setNotificationsOn(on) } })) {
                    Text("회고 알림").font(.subheadline.weight(.medium)).foregroundStyle(FocusTheme.Screen.ink)
                }
                .tint(FocusTheme.Palette.accent).frame(minHeight: FocusTheme.Layout.minimumTapTarget).accessibilityIdentifier("reviewNotificationToggle")
                if schedule.notificationsOn, review.permission == .authorized {
                    Divider()
                    HStack {
                        Text("요일").font(.subheadline).foregroundStyle(FocusTheme.Screen.ink)
                        Spacer(minLength: FocusTheme.Layout.inlineSpacing)
                        Picker("요일", selection: Binding(get: { schedule.weekday }, set: { weekday in Task { await review.setWeekday(weekday) } })) {
                            ForEach(1...7, id: \.self) { Text(Self.weekdays[$0 - 1]).tag($0) }
                        }
                        .pickerStyle(.menu).tint(FocusTheme.Screen.accentText).accessibilityIdentifier("reviewWeekday")
                    }
                    .frame(minHeight: FocusTheme.Layout.minimumTapTarget)
                    DatePicker(selection: Binding(get: { time(schedule.minute) }, set: { date in Task { await review.setMinute(minute(date)) } }), displayedComponents: .hourAndMinute) {
                        Text("시간").font(.subheadline).foregroundStyle(FocusTheme.Screen.ink)
                    }
                    .frame(minHeight: FocusTheme.Layout.minimumTapTarget).accessibilityIdentifier("reviewTime")
                }
            }
        }
        .modifier(FocusCard())
    }
    private func time(_ minute: Int) -> Date { ReviewDay(Date(), calendar: Calendar.current).date(atMinute: minute, in: Calendar.current) }
    private func minute(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 20) * 60 + (parts.minute ?? 0)
    }
}

/// Saves an image to Photos with the add-only permission (`NSPhotoLibraryAddUsageDescription`).
final class PhotoSaver: NSObject {
    private var completion: ((Bool) -> Void)?
    func save(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        self.completion = completion
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        let completion = completion; self.completion = nil
        DispatchQueue.main.async { completion?(error == nil) }
    }
}
