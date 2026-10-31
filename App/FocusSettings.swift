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
    /// Runs once per install: a person who saved a selection before onboarding existed skips it.
    /// Safe on the selection alone because launch runs this before any onboarding screen can save one;
    /// access is not read here, so a launch-time access read cannot strand that person in onboarding.
    func migrateIfNeeded(hasSelection: Bool) {
        guard !defaults.bool(forKey: Keys.migration) else { return }
        defaults.set(true, forKey: Keys.migration)
        if hasSelection { hasCompletedOnboarding = true }
    }
    private enum Keys {
        static let length = "focusLengthMinutes", onboarding = "onboardingCompleted", migration = "onboardingMigrationV1Done"
    }
}
