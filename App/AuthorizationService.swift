import Foundation
import FamilyControls
import Observation
import Combine

/// The UI value. `checking` is `.notDetermined` after an earlier request, or a value that this code does not know: access is not known yet, which is not a revocation.
/// `declined` is a request that the person declined while the published value still reads `.notDetermined`, as iOS 27 reads a denial (#38).
/// It is a UI value only: the engine keeps reading `unknown`.
enum AccessStatus { case notRequested, checking, approved, denied, declined }
@MainActor protocol AuthorizationProviding: AnyObject {
    var status: AccessStatus { get }
    func requestIndividual() async
    func refresh()
    /// The access value for an engine call, read on the main queue; `checking` reaches the engine as `unknown`.
    func accessState() -> AccessState
}
@MainActor @Observable final class AuthorizationService: AuthorizationProviding {
    private(set) var status: AccessStatus = .notRequested
    @ObservationIgnored private var subscription: AnyCancellable?
    @ObservationIgnored private let defaults: UserDefaults
    /// Set by a declined request, kept in memory until an approved or denied read or the next request, so the settings guidance stays on screen.
    @ObservationIgnored private var declined = false
    @ObservationIgnored private let read: () -> AuthorizationStatus
    @ObservationIgnored private let request: () async throws -> Void
    /// `read` and `request` are test seams; the app uses `AuthorizationCenter.shared` and observes its published value.
    init(defaults: UserDefaults = .standard, read: (() -> AuthorizationStatus)? = nil, request: (() async throws -> Void)? = nil) {
        self.defaults = defaults
        self.read = read ?? { AuthorizationCenter.shared.authorizationStatus }
        self.request = request ?? { try await AuthorizationCenter.shared.requestAuthorization(for: .individual) }
        refresh()
        guard read == nil else { return }
        subscription = AuthorizationCenter.shared.$authorizationStatus.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    func accessState() -> AccessState { ScreenTimeAccess.current() }
    func refresh() {
        let raw = read()
        status = Self.status(raw: raw, requested: defaults.bool(forKey: "individualAuthorizationRequested"), declined: declined)
        if status == .approved || status == .denied { declined = false }
    }
    /// The UI value of a published read; a declined request keeps `declined` while the read is not known yet.
    static func status(raw: AuthorizationStatus, requested: Bool, declined: Bool) -> AccessStatus {
        switch ScreenTimeAccess.state(raw) {
        case .approved: return .approved
        case .denied: return .denied
        case .unknown: return declined ? .declined : raw == .notDetermined && !requested ? .notRequested : .checking
        }
    }
    /// `authorizationCanceled` is the person's "Don't Allow"; every other error is not a decline (the 2026-11-11 access-state design).
    /// An individual request declined with this case on iOS 27.0.1 (device run of 2026-11-19, #38).
    static func isDecline(_ error: Error) -> Bool { (error as? FamilyControlsError) == .authorizationCanceled }
    /// Runs only on a person's tap, because the request can show system UI. In `checking` it is the recovery of the access-state design.
    func requestIndividual() async {
        guard status == .notRequested || status == .checking || status == .declined else { return }
        let wasChecking = status == .checking || status == .declined
        defaults.set(true, forKey: "individualAuthorizationRequested")
        declined = false
        do { try await request(); refresh() }
        // A declined request keeps the settings guidance; any other throw is not a revocation, and `checking` stays until the published value settles.
        catch {
            if Self.isDecline(error) { declined = true; refresh() }
            else if wasChecking { refresh() } else { status = .denied }
        }
    }
}
