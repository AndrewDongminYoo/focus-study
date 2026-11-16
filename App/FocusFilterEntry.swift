import Foundation

/// The app's side of `FocusStudyFilter.perform()`: the process runtime, shared with the screens (2026-11-16 extension design, decision 9).
/// The App Intents extension has its own `FocusFilterEntry` in `Intents/`.
@MainActor enum FocusFilterEntry {
    static func didChange(startsSession: Bool, calledAt: Date) async {
        await FocusRuntime.focusFilterDidChange(startsSession: startsSession, calledAt: calledAt)
    }
}
