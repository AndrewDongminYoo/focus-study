import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The principal class of the Shield Configuration extension: the same static shield for both layers and for all four calls (custom shield design, contract items 2 and 3).
final class FocusShieldConfiguration: ShieldConfigurationDataSource {
    /// Built once per extension process; it holds no value that changes with time.
    static let shield = ShieldConfiguration(
        backgroundBlurStyle: nil,
        backgroundColor: ShieldContent.navy,
        icon: ShieldContent.colonMark(),
        title: ShieldConfiguration.Label(text: ShieldContent.title, color: ShieldContent.cream),
        subtitle: ShieldConfiguration.Label(text: ShieldContent.subtitle, color: ShieldContent.cream),
        primaryButtonLabel: ShieldConfiguration.Label(text: ShieldContent.primaryButton, color: ShieldContent.navy),
        primaryButtonBackgroundColor: ShieldContent.cream,
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
