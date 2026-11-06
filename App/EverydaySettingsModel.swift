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
    var draft: EverydaySchedule {
        didSet { if !Self.sameEditableSchedule(draft, oldValue) { clearFeedback() } }
    }
    var draftSelection: FamilyActivitySelection {
        didSet { if !Self.sameSelection(draftSelection, oldValue) { clearFeedback() } }
    }
    private var savedDraft = EverydaySchedule.standard
    private var savedSelection = FamilyActivitySelection(includeEntireCategory: true)
    private(set) var refusalMessage: String?
    private(set) var successMessage: String?
    init(focus: FocusModel) {
        self.focus = focus
        draft = .standard; draftSelection = FamilyActivitySelection(includeEntireCategory: true)
    }
    /// No edit combines with a focus phase; the save checks it again under the lock.
    var canEdit: Bool { !focus.isInSession && !focus.isStarting }
    var hasChanges: Bool { !Self.sameEditableSchedule(draft, savedDraft) || !Self.sameSelection(draftSelection, savedSelection) }
    /// An unreadable file can be replaced with the standard draft without inventing an edit.
    private var needsSave: Bool { hasChanges || status?.issue == .unreadable }
    var canSave: Bool { canEdit && needsSave && draftIssue == nil }
    var canAddWindow: Bool { draft.windows.count < EverydaySchedule.maxWindows }
    var counts: (apps: Int, websites: Int) { (draftSelection.applicationTokens.count, draftSelection.webDomainTokens.count) }
    /// The first problem of the draft, before any save.
    var draftIssue: String? {
        if let issue = draft.issue { return Self.message(for: issue) }
        if draft.enabled { return SelectionFeedback.draftIssue(appCount: counts.apps, websiteCount: counts.websites) }
        return nil
    }
    var rangeIssue: String? {
        guard let issue = draft.issue else { return nil }
        switch issue {
        case .offGrid where draft.rangeStart % EverydaySchedule.grid != 0 || draft.rangeEnd % EverydaySchedule.grid != 0:
            return Self.message(for: issue)
        case .outOfDay, .rangeTooShort: return Self.message(for: issue)
        default: return nil
        }
    }
    var windowsIssue: String? { rangeIssue == nil ? draft.issue.map(Self.message(for:)) : nil }
    var selectionIssue: String? {
        draft.enabled ? SelectionFeedback.draftIssue(appCount: counts.apps, websiteCount: counts.websites) : nil
    }
    /// Display-only intervals inside the daily range; no selection tokens or engine state are changed.
    struct PreviewSegment: Equatable {
        let start: Int
        let end: Int
        let blocked: Bool
    }
    /// `nil` refuses an invalid schedule; an empty result means the everyday layer is off.
    static func previewSegments(for schedule: EverydaySchedule) -> [PreviewSegment]? {
        guard schedule.issue == nil else { return nil }
        guard schedule.enabled else { return [] }
        var result: [PreviewSegment] = []
        var cursor = schedule.rangeStart
        for window in schedule.windows.sorted(by: { $0.start < $1.start }) {
            if cursor < window.start { result.append(PreviewSegment(start: cursor, end: window.start, blocked: true)) }
            result.append(PreviewSegment(start: window.start, end: window.end, blocked: false))
            cursor = window.end
        }
        if cursor < schedule.rangeEnd { result.append(PreviewSegment(start: cursor, end: schedule.rangeEnd, blocked: true)) }
        return result
    }
    /// The stored range locks edits even during an unblocked window; the engine rechecks at save time.
    var strictOnlyMessage: String? {
        guard let schedule = status?.schedule, schedule.enabled,
              schedule.isInsideRange(at: clock(), calendar: services.engine.calendar) else { return nil }
        return "제한 시간에는 더 엄격하게만 바꿀 수 있어요. \(Self.time(schedule.rangeEnd))부터 자유롭게 바꿀 수 있어요."
    }
    private func clearFeedback() { refusalMessage = nil; successMessage = nil }
    private static func sameEditableSchedule(_ lhs: EverydaySchedule, _ rhs: EverydaySchedule) -> Bool {
        func windows(_ schedule: EverydaySchedule) -> [EverydayWindow] {
            schedule.windows.sorted {
                if $0.start != $1.start { return $0.start < $1.start }
                if $0.end != $1.end { return $0.end < $1.end }
                return $0.kind.rawValue < $1.kind.rawValue
            }
        }
        return lhs.enabled == rhs.enabled && lhs.rangeStart == rhs.rangeStart && lhs.rangeEnd == rhs.rangeEnd && windows(lhs) == windows(rhs)
    }
    private static func sameSelection(_ lhs: FamilyActivitySelection, _ rhs: FamilyActivitySelection) -> Bool {
        lhs.applicationTokens == rhs.applicationTokens && lhs.webDomainTokens == rhs.webDomainTokens && lhs.categoryTokens == rhs.categoryTokens
    }
    /// Loads the stored layer into the draft. An unreadable file starts from the standard layer, so the person can set it up again.
    func refresh() {
        refreshStatus()
        var schedule = status?.schedule ?? .standard
        schedule.windows.sort { $0.start < $1.start }
        draft = schedule
        draftSelection = services.everydaySelection() ?? FamilyActivitySelection(includeEntireCategory: true)
        savedDraft = draft; savedSelection = draftSelection
        clearFeedback()
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
        clearFeedback()
        guard canEdit else { refusalMessage = SelectionFeedback.message(for: ControlIssue.busy); return }
        guard needsSave else { return }
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
        if refusalMessage == nil { refresh(); successMessage = "매일 제한을 저장했어요." }
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
