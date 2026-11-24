import Foundation
import FamilyControls

/// The services of one runtime, shared by the screens and the Focus filter handler.
/// It is its own file so that the App Intents extension compiles it without the screen model (2026-11-16 extension design, decision 10).
@MainActor struct FocusServices {
    let authorization: any AuthorizationProviding
    let selection: any SelectionStoring
    let engine: SessionControl
    let applySelection: (FamilyActivitySelection) -> Void
    let matchesSelection: (FamilyActivitySelection) -> Bool
    var isFixture = false
    var settings = FocusSettings()
    /// Display-only notification, invoked after control/history work and outside every process lock.
    var activityDidChange: () -> Void = {}
    /// Writes the session-scoped selection copy for a break. Without one, no break can start, so the shield is never cleared.
    var saveBreakSelection: (FamilyActivitySelection, UUID) throws -> Void = { _, _ in throw ControlIssue.io }
    /// The stored everyday selection; an unreadable everyday file gives `nil`, because the layer then blocks nothing.
    var everydaySelection: () -> FamilyActivitySelection? = { nil }
    /// `true` when the new everyday selection holds every app and website of the stored one.
    var everydayContains: (FamilyActivitySelection) throws -> Bool = { _ in true }
    /// Writes `everyday-layer.json`; it runs inside the engine's save section.
    var writeEveryday: (EverydaySchedule, FamilyActivitySelection) throws -> Void = { _, _ in throw ControlIssue.io }
    /// Writes `everyday-layer.json` again with the stored selection and the schedule's `offDay`; it runs inside the engine's off-for-today section.
    var writeEverydayOffDay: (EverydaySchedule) throws -> Void = { _ in throw ControlIssue.io }
    /// Writes the home screen widget's snapshot after a history read of today; only `FocusRuntime.real()` sets it, so a fixture writes nothing and asks for no reload.
    var writeTodaySnapshot: (TodaySnapshot) throws -> Void = { _ in }
    /// Access to the paid features, read synchronously from the last confirmed facts; never awaits StoreKit.
    /// The default grants, so every caller that sets nothing keeps the behavior before the paid build (docs/specs/2026-11-24-paid-access-design.md).
    var paidAccess: () -> PaidAccessState = { .granted }
    #if DEBUG
    var diagnostics: DeviceDiagnostics?
    /// Opt-in timing of the complete synchronous start call; never carries selection or usage data.
    var didMeasureStart: ((TimeInterval) -> Void)?
    /// Opt-in timing of each accepted synchronous break transition call; never carries selection or usage data.
    var didMeasureBreak: ((BreakAction, TimeInterval) -> Void)?
    /// Opt-in timing of each session end, from the tap to the return of the engine call; never carries selection or usage data.
    var didMeasureEnd: ((TimeInterval) -> Void)?
    /// `--ui-testing ending-soon`: the focus seconds left when `start()` begins a session; the start time moves into the past.
    var fixtureFocusLeft: TimeInterval?
    /// `--break-delay`: seconds that the break feedback stays on screen before the transition runs; the main thread is not blocked.
    var fixtureBreakHold: TimeInterval = 0
    /// `--ui-testing history-failure`: wraps the app's history, so that every read of today's records fails.
    var fixtureHistory: ((any SessionHistoryProviding) -> any SessionHistoryProviding)?
    #endif

}
/// The four break transitions; the raw value names the action in the `BREAK_LATENCY` log.
enum BreakAction: String { case request, cancelWait, startBreak, resume }
