import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The principal class of the Shield Configuration extension: the same static shield for both layers and for all four calls (custom shield design, contract items 2 and 3).
final class FocusShieldConfiguration: ShieldConfigurationDataSource {
    /// Built once per extension process; it holds no value that changes with time.
    static let shield = ShieldConfiguration(
        // On iOS 27.0.1 a nil blur style follows the system appearance, so the text, the mark and the button follow it too.
        backgroundBlurStyle: nil,
        backgroundColor: ShieldContent.navy,
        icon: ShieldContent.colonMark(),
        title: ShieldConfiguration.Label(text: ShieldContent.title, color: ShieldContent.text),
        subtitle: ShieldConfiguration.Label(text: ShieldContent.subtitle, color: ShieldContent.text),
        // iOS 27.0.1 draws the label white in dark mode whatever its color; in light mode the configured color shows through, so the button follows the appearance.
        primaryButtonLabel: ShieldConfiguration.Label(text: ShieldContent.primaryButton, color: ShieldContent.text),
        primaryButtonBackgroundColor: ShieldContent.buttonBackground,
        secondaryButtonLabel: nil
    )

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        Self.shield
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        Self.shield
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        Self.shield
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        Self.shield
    }
}
