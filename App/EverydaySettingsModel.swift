import Foundation
import FamilyControls
import Observation

/// The everyday layer screen: a draft of the schedule and the selection, saved under the engine's strict-only rule.
@MainActor @Observable final class EverydaySettingsModel {
    let focus: FocusModel
    private var services: FocusServices { focus.services }
    /// Tests inject a fixed time; the engine's calendar reads it.
    @ObservationIgnored var clock: () -> Date = Date.init
    private(set) var status: EverydayStatus?
    var draft: EverydaySchedule
    var draftSelection: FamilyActivitySelection
    private(set) var refusalMessage: String?
    init(focus: FocusModel) {
        self.focus = focus
        draft = .standard; draftSelection = FamilyActivitySelection(includeEntireCategory: true)
    }
    /// No edit combines with a focus phase; the save checks it again under the lock.
    var canEdit: Bool { !focus.isInSession && !focus.isStarting }
    var canAddWindow: Bool { draft.windows.count < EverydaySchedule.maxWindows }
    var counts: (apps: Int, websites: Int) { (draftSelection.applicationTokens.count, draftSelection.webDomainTokens.count) }
    /// The first problem of the draft, before any save.
    var draftIssue: String? {
        if let issue = draft.issue { return Self.message(for: issue) }
        if draft.enabled { return SelectionFeedback.draftIssue(appCount: counts.apps, websiteCount: counts.websites) }
        return nil
    }
    /// Loads the stored layer into the draft. An unreadable file starts from the standard layer, so the person can set it up again.
    func refresh() {
        refreshStatus()
        var schedule = status?.schedule ?? .standard
        schedule.windows.sort { $0.start < $1.start }
        draft = schedule
        draftSelection = services.everydaySelection() ?? FamilyActivitySelection(includeEntireCategory: true)
    }
    /// Reads the status again and keeps the draft. The screen calls it after the app's lock sections and when a boundary passes.
    func refreshStatus() {
        do { status = try services.engine.everydayStatus(now: clock(), authorized: focus.access == .approved) }
        catch {
            var kept = status ?? EverydayStatus(schedule: nil, blocksNow: false, nextChange: nil, issue: nil)
            kept.issue = .unchecked; status = kept
        }
    }
    /// Seconds after a boundary before the screen reads the status, so that the Monitor callback applies the layer first.
    static let boundaryGrace: TimeInterval = 2
    /// Seconds before the one extra read of a status whose issue a Monitor callback can clear.
    static let issueRetry: TimeInterval = 10
    /// How long the open screen waits before it reads the status again, or nil when only a lock section of the app or a save changes it.
    /// `retried`: the screen already read once for this status. A lock timeout keeps a next change that has passed, so it gets no boundary read.
    static func statusReadDelay(_ status: EverydayStatus?, now: Date, retried: Bool) -> TimeInterval? {
        guard let status else { return nil }
        let boundary = status.nextChange.flatMap { $0 > now ? $0.timeIntervalSince(now) + boundaryGrace : nil }
        let retry = !retried && (status.issue == .notApplied || status.issue == .notCleared || status.issue == .unchecked) ? issueRetry : nil
        return [boundary, retry].compactMap { $0 }.min()
    }
    /// Reads the status again after each `statusReadDelay`, until the task is cancelled or no read is due.
    /// The settings row and this screen each run it for the status they show, because a boundary changes it without any lock section of the app.
    static func followStatus(_ status: () -> EverydayStatus?, now: () -> Date,
                             sleep: (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
                             read: () -> Void) async {
        var retried = false
        while !Task.isCancelled, let wait = statusReadDelay(status(), now: now(), retried: retried) {
            await sleep(wait)
            if Task.isCancelled { return }
            retried = true
            read()
        }
    }
    /// A template adds its suggested time; a custom window takes the first free 30 minutes of the range.
    func addWindow(_ kind: EverydayWindowKind) {
        guard canAddWindow else { return }
        let window = EverydaySchedule.template(kind) ?? EverydayWindow(kind: .custom, start: firstFreeStart(length: 30), end: firstFreeStart(length: 30) + 30)
        draft.windows.append(window); draft.windows.sort { $0.start < $1.start }
    }
    func removeWindow(at index: Int) {
        guard draft.windows.indices.contains(index) else { return }
        draft.windows.remove(at: index)
    }
    private func firstFreeStart(length: Int) -> Int {
        stride(from: draft.rangeStart, through: draft.rangeEnd - length, by: EverydaySchedule.grid).first { start in
            !draft.windows.contains { $0.start < start + length && start < $0.end }
        } ?? draft.rangeStart
    }
    func save() {
        refusalMessage = nil
        guard canEdit else { refusalMessage = SelectionFeedback.message(for: ControlIssue.busy); return }
        if let draftIssue { refusalMessage = draftIssue; return }
        let selection = draftSelection
        var schedule = draft
        schedule.revision = UUID(); schedule.windows.sort { $0.start < $1.start }
        let storedEnd = status?.schedule?.rangeEnd
        do {
            try SelectionFeedback.validateUnion(selection, services.selection.selection)
            try services.engine.saveEveryday(schedule, now: clock(), authorized: { self.services.authorization.hasAccessNow() },
                                             containsStoredSelection: { try self.services.everydayContains(selection) },
                                             write: { try self.services.writeEveryday(schedule, selection) })
        } catch ControlIssue.everydayLocked {
            refusalMessage = "제한 시간에는 더 엄격하게만 바꿀 수 있어요." + (storedEnd.map { " \(Self.time($0))부터 자유롭게 바꿀 수 있어요." } ?? "")
        } catch ControlIssue.unauthorized {
            refusalMessage = "스크린 타임 권한을 허용하면 저장할 수 있어요."
        } catch let error where error is SelectionUnionLimit || error is SelectionIssue || error as? ControlIssue == .busy {
            refusalMessage = SelectionFeedback.message(for: error)
        } catch {
            refusalMessage = "매일 제한을 저장하지 못했어요. 다시 저장해 주세요."
        }
        focus.refreshEveryday(); refreshStatus()
        if refusalMessage == nil { refresh() }
    }

    // MARK: Copy

    /// The settings row: one line about the stored layer.
    static func statusLine(_ status: EverydayStatus?, calendar: Calendar = .autoupdatingCurrent) -> String {
        guard let status else { return "꺼져 있어요" }
        switch status.issue {
        case .unreadable: return "설정을 불러오지 못했어요. 다시 설정해 주세요."
        case .unchecked: return "상태를 확인하지 못했어요. 잠시 후 다시 확인해 주세요."
        case .registrationFailed: return "일정을 등록하지 못했어요. 앱을 다시 열면 다시 등록해요."
        case .notApplied: return "제한을 적용하지 못했어요. 앱을 다시 열면 다시 적용해요."
        case .notCleared: return "제한이 아직 풀리지 않았어요. 앱을 다시 열면 풀어요."
        case nil: break
        }
        guard let schedule = status.schedule, schedule.enabled else { return "꺼져 있어요" }
        let next = status.nextChange.map { Self.clock($0, calendar: calendar) }
        if status.blocksNow { return "지금 제한하고 있어요" + (next.map { " · \($0)까지" } ?? "") }
        return "켜져 있어요" + (next.map { " · \($0)부터 제한해요" } ?? "")
    }
    /// The draft line for the first broken rule of the schedule, in the terms of the screen.
    static func message(for issue: EverydayScheduleIssue) -> String {
        switch issue {
        case .offGrid: "시간은 5분 단위로 정할 수 있어요."
        case .outOfDay: "제한 시간은 00:00부터 23:55 사이로 정할 수 있어요."
        case .rangeTooShort: "제한 끝을 제한 시작보다 1시간 이상 늦게 정해 주세요."
        case .tooManyWindows: "잠시 풀어 두는 시간은 3개까지 정할 수 있어요."
        case .windowLength: "잠시 풀어 두는 시간은 한 번에 15분에서 2시간까지 정할 수 있어요."
        case .windowOutsideRange: "잠시 풀어 두는 시간은 제한 시간 안에서 정할 수 있어요."
        case .windowsOverlap: "잠시 풀어 두는 시간이 서로 겹쳐요. 겹치지 않게 바꿔 주세요."
        case .windowsCoverRange: "잠시 풀어 두는 시간이 제한 시간을 모두 채우고 있어요. 제한할 시간을 남겨 주세요."
        }
    }
    static func time(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
    private static func clock(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return time((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }
    static func label(_ kind: EverydayWindowKind) -> String {
        switch kind {
        case .lunch: "점심"
        case .toSchool: "등교"
        case .fromSchool: "하교"
        case .custom: "직접 정한 시간"
        }
    }
}
