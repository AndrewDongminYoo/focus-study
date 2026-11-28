import Foundation

// The app's side of the everyday plan file (everyday plan widget design, "Data path"). The widget does not compile this file.

extension EverydayPlan {
    /// The plan fields of a stored schedule; the revision stays out.
    public init(_ schedule: EverydaySchedule) {
        self.init(enabled: schedule.enabled, rangeStart: schedule.rangeStart, rangeEnd: schedule.rangeEnd, windows: schedule.windows,
                  weekdays: schedule.weekdays, offDay: schedule.offDay)
    }
}

extension EverydayPlanFile {
    /// The plan file for one everyday status read of the app with the access value of that read, or `nil` for no write.
    /// A read or decode error writes nothing, so the last plan file stays; a missing file writes no schedule;
    /// a schedule with an issue or with access `denied` writes the schedule with `needsCheck`.
    static func written(for status: EverydayStatus, access: AccessState) -> EverydayPlanFile? {
        if status.issue == .unreadable || status.issue == .unchecked { return nil }
        guard let schedule = status.schedule else { return EverydayPlanFile(plan: nil, needsCheck: false) }
        return EverydayPlanFile(plan: EverydayPlan(schedule), needsCheck: status.issue != nil || access == .denied)
    }
}
