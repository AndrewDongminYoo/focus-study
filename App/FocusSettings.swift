import Foundation
import Observation

/// App-only settings: the focus length and whether onboarding has been finished once.
@MainActor @Observable final class FocusSettings {
    @ObservationIgnored private let defaults: UserDefaults
    private(set) var storedLength: Int
    private(set) var storedOnboarding: Bool
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let length = defaults.integer(forKey: Keys.length)
        storedLength = FocusLength.allowedMinutes.contains(length) ? length : FocusLength.defaultMinutes
        storedOnboarding = defaults.bool(forKey: Keys.onboarding)
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
    /// Runs once per install: a person who already had access and a selection before onboarding existed skips it.
    func migrateIfNeeded(accessApproved: Bool, hasSelection: Bool) {
        guard !defaults.bool(forKey: Keys.migration) else { return }
        defaults.set(true, forKey: Keys.migration)
        if accessApproved && hasSelection { hasCompletedOnboarding = true }
    }
    private enum Keys {
        static let length = "focusLengthMinutes", onboarding = "onboardingCompleted", migration = "onboardingMigrationV1Done"
    }
}
