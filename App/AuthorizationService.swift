import Foundation
import FamilyControls
import Observation
import Combine

enum AccessStatus { case notRequested, approved, denied }
@MainActor protocol AuthorizationProviding: AnyObject {
    var status: AccessStatus { get }
    func requestIndividual() async
    func refresh()
    func hasAccessNow() -> Bool
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
    func hasAccessNow() -> Bool { ScreenTimeAccess.isApproved(AuthorizationCenter.shared.authorizationStatus) }
    func refresh() {
        if hasAccessNow() { status = .approved }
        else if AuthorizationCenter.shared.authorizationStatus == .notDetermined && !defaults.bool(forKey: "individualAuthorizationRequested") { status = .notRequested }
        else { status = .denied }
    }
    func requestIndividual() async {
        guard status == .notRequested else { return }
        defaults.set(true, forKey: "individualAuthorizationRequested")
        do { try await AuthorizationCenter.shared.requestAuthorization(for: .individual); refresh() }
        catch { status = .denied }
    }
}
