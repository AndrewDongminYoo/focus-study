#if DEBUG
import Foundation
import DeviceActivity

/// Turns the Monitor timing on (the 2026-11-13 monitor timing design): `monitor-timing.json` in the App Group directory `SessionControl/`, next to `control.json`.
/// The Monitor extension gets no launch arguments, so the app writes this file when it runs with `--screen-time-diagnostics`.
struct MonitorTimingFlag: Codable, Equatable {
    static let fileName = "monitor-timing.json"
    static let currentSchemaVersion = 1
    /// The longest age at which a flag still counts, so that a flag that no launch removed goes stale.
    static let lifetime: TimeInterval = 24 * 60 * 60
    var schemaVersion = currentSchemaVersion
    /// The wall clock when the app wrote the file.
    var writtenAt: Date
    /// `0 <= age <= 24 hours`. A negative age is a flag that was written in the future.
    func isValid(at now: Date) -> Bool {
        let age = now.timeIntervalSince(writtenAt)
        return schemaVersion == Self.currentSchemaVersion && age >= 0 && age <= Self.lifetime
    }
    /// The Monitor's read: a missing, unreadable, undecodable, other-version or stale file is off.
    static func isOn(directory: URL, now: Date) -> Bool {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)),
              let flag = try? JSONDecoder().decode(MonitorTimingFlag.self, from: data) else { return false }
        return flag.isValid(at: now)
    }
    /// The call of `FocusRuntime.real()`: the launch arguments decide between the write and the removal.
    static func set(launchArguments: [String], directory: URL, now: Date = Date()) {
        set(launchArguments.contains("--screen-time-diagnostics"), directory: directory, now: now)
    }
    /// The write or the removal. Neither failure stops the launch: a failed write means no timing, and a failed removal leaves a flag that goes stale.
    /// `writeData` and `removeItem` are test seams; the defaults write and remove the file.
    static func set(_ on: Bool, directory: URL, now: Date = Date(),
                    writeData: (Data, URL, Data.WritingOptions) throws -> Void = { try $0.write(to: $1, options: $2) },
                    removeItem: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        let url = directory.appendingPathComponent(fileName)
        guard on else { try? removeItem(url); return }
        // A first launch writes the flag before any lock section has created the directory.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(MonitorTimingFlag(writtenAt: now)) else { return }
        try? writeData(data, url, SharedControlStore.fileWritingOptions)
    }
}

/// The short activity kind of a timing line. A line never carries the activity name itself.
enum MonitorTimingActivity: String {
    case focus, `break`, everyday, other
    /// `focus.<UUID>`, `focus.<UUID>.break.<n>`, `everyday.<UUID>.<part>`, and `other` for every other name, such as `probe.*`.
    init(activityName: String) {
        let name = DeviceActivityName(activityName)
        if ScreenTimeMonitoring.breakIndex(name) != nil { self = .break }
        else if ScreenTimeMonitoring.sessionID(name) != nil, activityName.count == "focus.".count + 36 { self = .focus }
        else if ScreenTimeMonitoring.everydayName(name) != nil { self = .everyday }
        else { self = .other }
    }
}

/// Builds the `MONITOR_TIMING` lines of one Monitor callback. One callback has one recorder, and the wrappers of its engine share it.
/// Its caller turns the activity name into a `MonitorTimingActivity` first. The recorder gets that kind and never the name, so every string in a line is a fixed value.
/// The lines of an acquired lock stay in memory until the lock is released, so `emit` never runs inside a lock section.
final class MonitorTimingRecorder {
    private static let numberLock = NSLock()
    private static var lastNumber = 0
    /// The `cb` value: a counter of timed callbacks in this process, from 1. Each recorder keeps its own number, so two callbacks at the same time cannot mix.
    static func nextNumber() -> Int {
        numberLock.lock(); defer { numberLock.unlock() }
        lastNumber += 1
        return lastNumber
    }
    private static func uptime() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
    private static func ms(_ duration: TimeInterval) -> String { String(format: "%.3f", duration * 1000) }

    private let prefix: String
    private let started: TimeInterval
    private let emit: (String) -> Void
    private var attempt = 0
    /// The lines of the lock section that is running; `nil` outside a section.
    private var held: [String]?
    /// A marker line that waits for the engine's next step, which shows its result.
    private var pendingMarker: String?
    private var sectionRan = false

    /// The flag read at the start of a callback, before the access read and outside any lock. `nil` without a valid flag: no number is used and no line is emitted.
    static func begin(directory: URL, activity: MonitorTimingActivity, kind: CallbackKind, now: Date = Date(), number: () -> Int = MonitorTimingRecorder.nextNumber,
                      emit: @escaping (String) -> Void) -> MonitorTimingRecorder? {
        let started = uptime()
        guard MonitorTimingFlag.isOn(directory: directory, now: now) else { return nil }
        let kindName: String
        switch kind {
        case .didStart: kindName = "didStart"
        case .didEnd: kindName = "didEnd"
        case .willEndWarning: kindName = "willEndWarning"
        }
        let recorder = MonitorTimingRecorder(prefix: "MONITOR_TIMING cb=\(number()) kind=\(kindName) activity=\(activity.rawValue)",
                                             started: started, emit: emit)
        recorder.line("step=begin flag_ms=\(ms(uptime() - started))")
        return recorder
    }
    private init(prefix: String, started: TimeInterval, emit: @escaping (String) -> Void) {
        self.prefix = prefix; self.started = started; self.emit = emit
    }
    private func line(_ text: String) {
        let line = "\(prefix) \(text)"
        if held != nil { held?.append(line) } else { emit(line) }
    }
    private func resolveMarker(skipped: Bool) {
        guard let marker = pendingMarker else { return }
        pendingMarker = nil
        line("\(marker) result=\(skipped ? "skip" : "continue")")
    }

    /// The engine of this callback: every value goes to the engine through a wrapper that forwards each call once.
    func engine(store: any ControlStore, monitoring: any MonitoringClient, shield: any ShieldClient, breakSelection: any BreakSelectionStore,
                everyday: any EverydayLayerStore) -> SessionControl {
        // The engine puts its marker wrapper around the timed client, so a `register` or `stop` time has no marker write or delete in it.
        SessionControl(store: TimedControlStore(base: store, recorder: self),
                       monitoring: DiagnosticMonitoring(base: monitoring, didMeasure: { [self] operation, duration in recordCall(operation, duration) }),
                       shield: TimedShield(base: shield, recorder: self), breakSelection: TimedBreakSelection(base: breakSelection, recorder: self),
                       everyday: TimedEverydayLayer(base: everyday, recorder: self))
    }
    /// The whole callback, from the flag read to the return or throw of `body`, which is the call of `handleCallbackRetryingLock`.
    func run(_ body: () throws -> Void) throws {
        var result = "error"
        defer { line("step=end total_ms=\(Self.ms(Self.uptime() - started)) result=\(result)") }
        do {
            try body()
            // A return right after a marker read is the skip; the wrapper does not evaluate the skip rule again.
            result = sectionRan && pendingMarker == nil ? "ran" : "skipped"
            resolveMarker(skipped: true)
        } catch {
            resolveMarker(skipped: false)
            if case ControlIssue.lockTimeout = error { result = "lock_timeout" }
            throw error
        }
    }
    /// One access read; the engine makes one before each lock attempt.
    func access(_ read: () -> AccessState) -> AccessState {
        resolveMarker(skipped: false)
        let began = Self.uptime()
        let state = read()
        let name: String
        switch state {
        case .approved: name = "approved"
        case .denied: name = "denied"
        case .unknown: name = "unknown"
        }
        line("step=access ms=\(Self.ms(Self.uptime() - began)) state=\(name)")
        return state
    }
    fileprivate func recordCall(_ operation: ScreenTimeOperation, _ duration: TimeInterval) {
        line("step=call op=\(operation.rawValue) ms=\(Self.ms(duration))")
    }
    fileprivate func call<T>(_ operation: ScreenTimeOperation, _ body: () -> T) -> T {
        measureScreenTime(operation, report: recordCall, body)
    }
    fileprivate func lockBegan() -> TimeInterval {
        resolveMarker(skipped: false)
        return Self.uptime()
    }
    /// The start of the section body: the end of the lock wait and the start of the hold time, with one uptime read.
    fileprivate func lockAcquired(since began: TimeInterval) -> TimeInterval {
        let now = Self.uptime()
        held = []; sectionRan = true
        line("step=lock attempt=\(attempt) wait_ms=\(Self.ms(now - began)) result=acquired")
        attempt += 1
        return now
    }
    fileprivate func sectionEnded(since began: TimeInterval) {
        line("step=section hold_ms=\(Self.ms(Self.uptime() - began))")
    }
    /// The busy probe before the access read. Only a busy probe has a line, `attempt=probe`, because it is no lock attempt and the attempt count does not change.
    fileprivate func lockProbe(_ probe: () -> Bool) -> Bool {
        resolveMarker(skipped: false)
        let began = Self.uptime()
        let busy = probe()
        if busy { line("step=lock attempt=probe wait_ms=\(Self.ms(Self.uptime() - began)) result=busy") }
        return busy
    }
    fileprivate func lockBusy(since began: TimeInterval) {
        line("step=lock attempt=\(attempt) wait_ms=\(Self.ms(Self.uptime() - began)) result=busy")
        attempt += 1
    }
    /// After the store returned or threw, so the lock is released.
    fileprivate func lockReleased() {
        guard let lines = held else { return }
        held = nil
        lines.forEach(emit)
    }
    fileprivate func markerRead(_ read: () -> RegistrationMarker?) -> RegistrationMarker? {
        resolveMarker(skipped: false)
        let began = Self.uptime()
        let marker = read()
        pendingMarker = "step=marker ms=\(Self.ms(Self.uptime() - began)) marker=\(marker?.call.rawValue ?? "none")"
        return marker
    }
}

/// Times each lock attempt and the section body, and gives the engine a timed marker store.
private final class TimedControlStore: ControlStore {
    private let base: any ControlStore
    private let recorder: MonitorTimingRecorder
    init(base: any ControlStore, recorder: MonitorTimingRecorder) { self.base = base; self.recorder = recorder }
    var registrationMarkers: (any RegistrationMarkerStore)? { base.registrationMarkers.map { TimedMarkerStore(base: $0, recorder: recorder) } }
    func isLockBusy() -> Bool { recorder.lockProbe(base.isLockBusy) }
    func withExclusiveAccess<T>(timeout: TimeInterval?, _ body: (LockedControl) throws -> T) throws -> T {
        let began = recorder.lockBegan()
        var entered = false
        defer { recorder.lockReleased() }
        do {
            return try base.withExclusiveAccess(timeout: timeout) { locked in
                entered = true
                let acquired = recorder.lockAcquired(since: began)
                defer { recorder.sectionEnded(since: acquired) }
                return try body(locked)
            }
        } catch ControlIssue.lockTimeout where !entered {
            recorder.lockBusy(since: began)
            throw ControlIssue.lockTimeout
        }
    }
}
/// Times the marker read after a busy probe or a busy lock attempt. Writes and deletes are the lock holder's and are only forwarded.
private final class TimedMarkerStore: RegistrationMarkerStore {
    private let base: any RegistrationMarkerStore
    private let recorder: MonitorTimingRecorder
    init(base: any RegistrationMarkerStore, recorder: MonitorTimingRecorder) { self.base = base; self.recorder = recorder }
    func read() -> RegistrationMarker? { recorder.markerRead(base.read) }
    func write(_ marker: RegistrationMarker) throws { try base.write(marker) }
    func delete() throws { try base.delete() }
    func uptime() -> TimeInterval { base.uptime() }
}
private final class TimedShield: ShieldClient {
    private let base: any ShieldClient
    private let recorder: MonitorTimingRecorder
    init(base: any ShieldClient, recorder: MonitorTimingRecorder) { self.base = base; self.recorder = recorder }
    func clear() { recorder.call(.clearShield, base.clear) }
}
/// `apply_shield` is the read of the copy, the apply and the match.
private final class TimedBreakSelection: BreakSelectionStore {
    private let base: any BreakSelectionStore
    private let recorder: MonitorTimingRecorder
    init(base: any BreakSelectionStore, recorder: MonitorTimingRecorder) { self.base = base; self.recorder = recorder }
    func restoreShield(id: UUID) -> Bool { recorder.call(.applyShield) { base.restoreShield(id: id) } }
    func exists(id: UUID) -> Bool { base.exists(id: id) }
    func remove(id: UUID) { base.remove(id: id) }
    func removeAll(except id: UUID?) { base.removeAll(except: id) }
}
/// `apply_everyday` is the read of the file, the apply and the match.
private final class TimedEverydayLayer: EverydayLayerStore {
    private let base: any EverydayLayerStore
    private let recorder: MonitorTimingRecorder
    init(base: any EverydayLayerStore, recorder: MonitorTimingRecorder) { self.base = base; self.recorder = recorder }
    func load() throws -> EverydaySchedule? { try base.load() }
    func storeMatches() -> Bool { base.storeMatches() }
    func applyStored() -> Bool { recorder.call(.applyEveryday, base.applyStored) }
    var hasShield: Bool { base.hasShield }
    func clearShield() { recorder.call(.clearEveryday, base.clearShield) }
}
#endif
