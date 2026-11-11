import Foundation
import FamilyControls
import Observation
import Combine

/// The UI value. `checking` is `.notDetermined` after an earlier request, or a value that this code does not know: access is not known yet, which is not a revocation.
enum AccessStatus { case notRequested, checking, approved, denied }
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
    @ObservationIgnored private let defaults = UserDefaults.standard
    init() {
        refresh()
        subscription = AuthorizationCenter.shared.$authorizationStatus.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    func accessState() -> AccessState { ScreenTimeAccess.current() }
    func refresh() {
        let raw = AuthorizationCenter.shared.authorizationStatus
        switch ScreenTimeAccess.state(raw) {
        case .approved: status = .approved
        case .denied: status = .denied
        case .unknown: status = raw == .notDetermined && !defaults.bool(forKey: "individualAuthorizationRequested") ? .notRequested : .checking
        }
    }
    /// Runs only on a person's tap, because the request can show system UI. In `checking` it is the recovery of the access-state design.
    func requestIndividual() async {
        guard status == .notRequested || status == .checking else { return }
        let wasChecking = status == .checking
        defaults.set(true, forKey: "individualAuthorizationRequested")
        do { try await AuthorizationCenter.shared.requestAuthorization(for: .individual); refresh() }
        // A request that throws is not a revocation: `checking` stays until the published value settles.
        catch { if wasChecking { refresh() } else { status = .denied } }
    }
}
