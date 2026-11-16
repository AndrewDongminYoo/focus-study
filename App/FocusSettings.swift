import Foundation
import Observation

/// The focus length and the display-only Focus filter values live in the App Group, so the App Intents extension reads and writes them too;
/// the onboarding flag stays in the app's own defaults (2026-11-16 extension design, decisions 13 to 15).
@MainActor @Observable final class FocusSettings {
    /// The app's own defaults: the onboarding flags, and the values of a build before the move.
    @ObservationIgnored private let defaults: UserDefaults
    /// The App Group defaults. Tests and fixtures without an App Group pass none and use `defaults` for both.
    @ObservationIgnored private let shared: UserDefaults
    private(set) var storedLength: Int
    private(set) var storedOnboarding: Bool
    /// Why the last Focus on call started no session. Display-only; the next filter start or refusal replaces it.
    private(set) var lastFilterRefusal: (reason: FocusFilterRefusal, at: Date)?
    init(defaults: UserDefaults = .standard, shared: UserDefaults? = nil) {
        self.defaults = defaults; self.shared = shared ?? defaults
        storedLength = FocusLength.defaultMinutes; storedOnboarding = defaults.bool(forKey: Keys.onboarding)
        storedLength = Self.allowed(readLength()) ?? FocusLength.defaultMinutes
        if let raw = string(Keys.refusal), let reason = FocusFilterRefusal(rawValue: raw), let at = object(Keys.refusalTime) as? Date {
            lastFilterRefusal = (reason, at)
        }
    }
    /// The settings of the real runtime: the App Group suite named by `FocusAppGroupIdentifier`, or the app's defaults when the suite is unavailable.
    static func app() -> FocusSettings { FocusSettings(shared: GroupConfiguration.sharedDefaults()) }
    var lengthMinutes: Int {
        get { storedLength }
        set {
            guard FocusLength.allowedMinutes.contains(newValue) else { return }
            storedLength = newValue; shared.set(newValue, forKey: Keys.length)
        }
    }
    /// An allowed length is stored in the App Group. The extension refuses with `error` when a selection exists without one (decision 16).
    var hasStoredLength: Bool { Self.allowed(shared.object(forKey: Keys.length) as? Int) != nil }
    /// Moves the length first, then the display-only values, and removes each old key only after its copy reads back (decision 16).
    /// Returns `false` when a copy did not read back; the old values stay and the next launch tries again.
    @discardableResult
    func migrateToAppGroup() -> Bool {
        guard shared !== defaults else { return true }
        if !hasStoredLength {
            let length = Self.allowed(defaults.object(forKey: Keys.length) as? Int) ?? FocusLength.defaultMinutes
            shared.set(length, forKey: Keys.length)
            guard shared.object(forKey: Keys.length) as? Int == length else { return false }
        }
        defaults.removeObject(forKey: Keys.length)
        for key in [Keys.refusal, Keys.refusalTime, Keys.pendingID, Keys.pendingLength] {
            guard let value = defaults.object(forKey: key) else { continue }
            if shared.object(forKey: key) == nil { shared.set(value, forKey: key) }
            guard shared.object(forKey: key) != nil else { return false }
            defaults.removeObject(forKey: key)
        }
        return true
    }
    private func readLength() -> Int? { (shared.object(forKey: Keys.length) ?? defaults.object(forKey: Keys.length)) as? Int }
    private static func allowed(_ minutes: Int?) -> Int? { minutes.flatMap { FocusLength.allowedMinutes.contains($0) ? $0 : nil } }
    /// The App Group value when it exists, else the value of a build before the move.
    private func object(_ key: String) -> Any? { shared.object(forKey: key) ?? defaults.object(forKey: key) }
    private func string(_ key: String) -> String? { object(key) as? String }
    var lengthSeconds: TimeInterval { TimeInterval(lengthMinutes * 60) }
    var hasCompletedOnboarding: Bool {
        get { storedOnboarding }
        set { storedOnboarding = newValue; defaults.set(newValue, forKey: Keys.onboarding) }
    }
    /// Runs once per install: a person who saved a selection before onboarding existed skips it.
    /// Safe on the selection alone because launch runs this before any onboarding screen can save one;
    /// access is not read here, so a launch-time access read cannot strand that person in onboarding.
    func migrateIfNeeded(hasSelection: Bool) {
        guard !defaults.bool(forKey: Keys.migration) else { return }
        defaults.set(true, forKey: Keys.migration)
        if hasSelection { hasCompletedOnboarding = true }
    }
    func recordFilterRefusal(_ reason: FocusFilterRefusal, at time: Date) {
        lastFilterRefusal = (reason, time); shared.set(reason.rawValue, forKey: Keys.refusal); shared.set(time, forKey: Keys.refusalTime)
    }
    func clearFilterRefusal() {
        lastFilterRefusal = nil
        for store in [shared, defaults] { store.removeObject(forKey: Keys.refusal); store.removeObject(forKey: Keys.refusalTime) }
    }
    /// The completion card of an `.expired` session that the filter path imported, until the next `FocusModel.refresh()` takes it.
    var pendingCompletion: (id: UUID, length: TimeInterval)? {
        guard let raw = string(Keys.pendingID), let id = UUID(uuidString: raw) else { return nil }
        return (id, (object(Keys.pendingLength) as? Double) ?? 0)
    }
    func recordPendingCompletion(id: UUID, length: TimeInterval) {
        shared.set(id.uuidString, forKey: Keys.pendingID); shared.set(length, forKey: Keys.pendingLength)
    }
    func takePendingCompletion() -> (id: UUID, length: TimeInterval)? {
        let pending = pendingCompletion
        for store in [shared, defaults] { store.removeObject(forKey: Keys.pendingID); store.removeObject(forKey: Keys.pendingLength) }
        return pending
    }
    #if DEBUG
    /// The last Focus filter calls (time, value, result) for the device diagnostics. No tokens.
    var filterCallLog: [String] { shared.stringArray(forKey: Keys.callLog) ?? [] }
    func appendFilterCall(_ entry: String) {
        shared.set(Array((filterCallLog + [entry]).suffix(20)), forKey: Keys.callLog)
    }
    #endif
    private enum Keys {
        static let length = "focusLengthMinutes", onboarding = "onboardingCompleted", migration = "onboardingMigrationV1Done"
        static let refusal = "focusFilterRefusal", refusalTime = "focusFilterRefusalTime", pendingID = "pendingCompletionID", pendingLength = "pendingCompletionLength"
        #if DEBUG
        static let callLog = "focusFilterCallLog"
        #endif
    }
}
