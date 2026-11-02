import Foundation
import Observation

/// App-only settings: the focus length, whether onboarding has been finished once, and the display-only Focus filter values.
@MainActor @Observable final class FocusSettings {
    @ObservationIgnored private let defaults: UserDefaults
    private(set) var storedLength: Int
    private(set) var storedOnboarding: Bool
    /// Why the last Focus on call started no session. Display-only; the next filter start or refusal replaces it.
    private(set) var lastFilterRefusal: (reason: FocusFilterRefusal, at: Date)?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let length = defaults.integer(forKey: Keys.length)
        storedLength = FocusLength.allowedMinutes.contains(length) ? length : FocusLength.defaultMinutes
        storedOnboarding = defaults.bool(forKey: Keys.onboarding)
        if let raw = defaults.string(forKey: Keys.refusal), let reason = FocusFilterRefusal(rawValue: raw), let at = defaults.object(forKey: Keys.refusalTime) as? Date {
            lastFilterRefusal = (reason, at)
        }
    }
    var lengthMinutes: Int {
        get { storedLength }
        set {
            guard FocusLength.allowedMinutes.contains(newValue) else { return }
            storedLength = newValue; defaults.set(newValue, forKey: Keys.length)
        }
    }
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
        lastFilterRefusal = (reason, time); defaults.set(reason.rawValue, forKey: Keys.refusal); defaults.set(time, forKey: Keys.refusalTime)
    }
    func clearFilterRefusal() {
        lastFilterRefusal = nil; defaults.removeObject(forKey: Keys.refusal); defaults.removeObject(forKey: Keys.refusalTime)
    }
    /// The completion card of an `.expired` session that the filter path imported, until the next `FocusModel.refresh()` takes it.
    var pendingCompletion: (id: UUID, length: TimeInterval)? {
        guard let raw = defaults.string(forKey: Keys.pendingID), let id = UUID(uuidString: raw) else { return nil }
        return (id, defaults.double(forKey: Keys.pendingLength))
    }
    func recordPendingCompletion(id: UUID, length: TimeInterval) {
        defaults.set(id.uuidString, forKey: Keys.pendingID); defaults.set(length, forKey: Keys.pendingLength)
    }
    func takePendingCompletion() -> (id: UUID, length: TimeInterval)? {
        let pending = pendingCompletion
        defaults.removeObject(forKey: Keys.pendingID); defaults.removeObject(forKey: Keys.pendingLength)
        return pending
    }
    #if DEBUG
    /// The last Focus filter calls (time, value, result) for the device diagnostics. No tokens.
    var filterCallLog: [String] { defaults.stringArray(forKey: Keys.callLog) ?? [] }
    func appendFilterCall(_ entry: String) {
        defaults.set(Array((filterCallLog + [entry]).suffix(20)), forKey: Keys.callLog)
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
