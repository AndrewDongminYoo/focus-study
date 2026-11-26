import Foundation

/// The rules of the 순공 calendar share image (docs/specs/2026-11-26-share-image-design.md) that need no SwiftUI:
/// the weeks of a month, the summary words and the hand-stamped variation of each stamp.
enum CalendarShare {
    /// The weeks of the month as rows of seven, with `nil` before the first day and after the last.
    /// The calendar sheet and the share image use the same rows.
    static func weeks(_ month: DateInterval, calendar: Calendar) -> [[Date?]] {
        let count = calendar.range(of: .day, in: .month, for: month.start)?.count ?? 30
        let lead = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for offset in 0..<count { cells.append(calendar.date(byAdding: .day, value: offset, to: month.start).map { calendar.startOfDay(for: $0) }) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }
    /// The weekday letters in the order of `calendar.firstWeekday`.
    static func weekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = ["일", "월", "화", "수", "목", "금", "토"], first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The day part of the summary line: "하루 동안" for one recorded day, otherwise "N일에 걸쳐".
    static func dayWords(_ recordedDays: Int) -> String { recordedDays == 1 ? "하루 동안" : "\(recordedDays)일에 걸쳐" }
    /// The time part of the summary line without a zero part: "35시간", "35시간 20분" or "40분".
    static func timeWords(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60, hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest)분" }
        return rest == 0 ? "\(hours)시간" : "\(hours)시간 \(rest)분"
    }

    /// One stamp's variation. The values are in the 44 × 44 unit box of the stamp, except `offsetX` and `offsetY`, which are in points.
    struct Stamp: Equatable {
        struct Gap: Equatable { var angle: Double }
        struct Grain: Equatable { var x, y, width, height: Double }
        var rotation: Double
        var offsetX: Double
        var offsetY: Double
        var scale: Double
        /// Three under-inked gaps on the outer ring, as angles in radians.
        var gaps: [Gap]
        /// 23 paper-grain dots inside the stamp.
        var grains: [Grain]
    }
    /// The variation of the stamp of a local day. It is a function of the year, the month and the day only, never of the focus time,
    /// so the same month always gives the same image. It uses SplitMix64, because the seed of `Hasher` changes per process.
    static func stamp(year: Int, month: Int, day: Int) -> Stamp {
        var random = SplitMix64(seed: UInt64(year * 10_000 + month * 100 + day))
        func value(_ low: Double, _ high: Double) -> Double { low + (high - low) * random.unit() }
        let rotation = value(-8, 8), offsetX = value(-1.5, 1.5), offsetY = value(-1, 1), scale = value(0.94, 1.04)
        let gaps = (0..<3).map { _ in Stamp.Gap(angle: value(0, 2 * .pi)) }
        let grains = (0..<23).map { _ in Stamp.Grain(x: value(6, 38), y: value(6, 38), width: value(0.6, 1.6), height: value(0.4, 1.0)) }
        return Stamp(rotation: rotation, offsetX: offsetX, offsetY: offsetY, scale: scale, gaps: gaps, grains: grains)
    }
    struct SplitMix64 {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        /// A value in 0..<1 from the top 53 bits.
        mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
    }
}
