import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The principal class of the Shield Configuration extension: one layout for both layers (custom shield design, contract item 3), with the title, the subtitle and the buttons of the shield name and open button design.
final class FocusShieldConfiguration: ShieldConfigurationDataSource {
    /// Built once per extension process; it holds no value that changes with time.
    static let icon = ShieldContent.colonMark()

    /// Whether the action extension can answer "온:공 열기" with `openParentalControlsApp`.
    static var opensApp: Bool {
        if #available(iOS 26.5, *) {
            return true
        }
        return false
    }

    /// The configuration for one shielded item; `name` is the name that the system passed to the call, or nil.
    static func shield(name: String?, item: ShieldContent.Item, opensApp: Bool = opensApp) -> ShieldConfiguration {
        ShieldConfiguration(
            // On iOS 27.0.1 a nil blur style follows the system appearance, so the text, the mark and the button follow it too.
            backgroundBlurStyle: nil,
            backgroundColor: ShieldContent.navy,
            icon: icon,
            title: ShieldConfiguration.Label(text: ShieldContent.title(name: name, item: item), color: ShieldContent.text),
            subtitle: ShieldConfiguration.Label(text: ShieldContent.subtitle(opensApp: opensApp), color: ShieldContent.text),
            // iOS 27.0.1 draws the label white in dark mode whatever its color; in light mode the configured color shows through, so the button follows the appearance.
            primaryButtonLabel: ShieldConfiguration.Label(text: opensApp ? ShieldContent.openButton : ShieldContent.closeButton, color: ShieldContent.text),
            primaryButtonBackgroundColor: ShieldContent.buttonBackground,
            secondaryButtonLabel: opensApp ? ShieldConfiguration.Label(text: ShieldContent.closeButton, color: ShieldContent.text) : nil
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        Self.shield(name: application.localizedDisplayName, item: .application)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        Self.shield(name: application.localizedDisplayName, item: .application)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        Self.shield(name: webDomain.domain, item: .website)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        Self.shield(name: webDomain.domain, item: .website)
    }
}
