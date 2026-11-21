import ManagedSettings

/// The principal class of the Shield Action extension (shield name and open button design, contract item 5).
/// It receives tokens only, reads no stored data and logs nothing.
final class FocusShieldAction: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(Self.response(for: action))
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(Self.response(for: action))
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(Self.response(for: action))
    }

    /// On iOS 26.5 and later the primary button is "온:공 열기" and the secondary button is "닫기"; below, the only button is "닫기".
    static func response(for action: ShieldAction) -> ShieldActionResponse {
        if #available(iOS 26.5, *), action == .primaryButtonPressed {
            return .openParentalControlsApp
        }
        return .close
    }
}
