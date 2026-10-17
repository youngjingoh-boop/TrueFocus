import Foundation
import ManagedSettings
import ManagedSettingsUI
import TrueFocusKit
import UIKit

/// The screen you see instead of a shielded app. Black, quiet, and it names the task
/// you're supposed to be on.
final class TFShieldConfiguration: ShieldConfigurationDataSource {
    private enum Kind {
        /// A focus or think segment is running.
        case focus
        /// The scroll budget is spent.
        case budget
        /// Shielded but not in either state (e.g. a stale store); still say something useful.
        case generic
    }

    private static let ember = UIColor(red: 1.0, green: 90.0 / 255.0, blue: 31.0 / 255.0, alpha: 1)
    private static let ink = UIColor(white: 0.96, alpha: 1)
    private static let ink2 = UIColor(white: 0.62, alpha: 1)
    private static let canvas = UIColor(red: 5.0 / 255.0, green: 5.0 / 255.0, blue: 6.0 / 255.0, alpha: 0.92)

    // MARK: ShieldConfigurationDataSource

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        let token = application.token
        let config = GuardStore.load()
        let offersPass = token.map { config.isReplyApp($0) } ?? false
        return make(appName: application.localizedDisplayName, offersReplyPass: offersPass, config: config)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        // Reply apps are never shielded through a category, so no pass here.
        make(appName: application.localizedDisplayName, offersReplyPass: false, config: GuardStore.load())
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        make(appName: webDomain.domain, offersReplyPass: false, config: GuardStore.load())
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        make(appName: webDomain.domain, offersReplyPass: false, config: GuardStore.load())
    }

    // MARK: Building

    private func kind(snapshot: LiveSnapshot, config: GuardConfig) -> Kind {
        if config.focusShieldActive && snapshot.shouldShield { return .focus }
        if config.budgetShieldActive { return .budget }
        if config.focusShieldActive { return .focus }
        return .generic
    }

    private func make(appName: String?, offersReplyPass: Bool, config: GuardConfig) -> ShieldConfiguration {
        let store = SharedStore.shared
        let snapshot = store.snapshot
        let settings = store.settings
        let copy = Copy(tone: settings.tone)
        let now = Date()

        let title: String
        let subtitle: String
        switch kind(snapshot: snapshot, config: config) {
        case .focus:
            title = copy.shieldTitle(during: snapshot.mode)
            let minutes = Int(snapshot.taskElapsed(now: now) / 60)
            subtitle = copy.shieldSubtitle(task: snapshot.taskTitle ?? snapshot.headline,
                                           minutesIn: snapshot.mode == .focus ? minutes : nil)
        case .budget:
            title = copy.budgetSpentTitle
            subtitle = budgetSubtitle(appName: appName, until: config.budgetShieldUntil, now: now,
                                      task: snapshot.headline)
        case .generic:
            title = copy.shieldTitle(during: snapshot.mode)
            subtitle = copy.shieldSubtitle(task: snapshot.headline, minutesIn: nil)
        }

        var secondary: ShieldConfiguration.Label?
        if offersReplyPass {
            let remaining = config.passesRemaining(settings: settings, now: now)
            if remaining > 0 {
                let text = "Reply · \(settings.respondPassMinutes) min  (\(remaining) left)"
                secondary = ShieldConfiguration.Label(text: text, color: Self.ink2)
            }
        }

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: Self.canvas,
            icon: icon(),
            title: ShieldConfiguration.Label(text: title, color: Self.ink),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: Self.ink2),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Back to work", color: .black),
            primaryButtonBackgroundColor: Self.ember,
            secondaryButtonLabel: secondary
        )
    }

    private func budgetSubtitle(appName: String?, until: Date?, now: Date, task: String?) -> String {
        let name = appName ?? "This app"
        var line = "\(name) is locked"
        if let until, until > now {
            let minutes = max(1, Int((until.timeIntervalSince(now) / 60).rounded(.up)))
            line += " for \(minutes) more min."
        } else {
            line += " for now."
        }
        if let task, !task.isEmpty {
            line += " Back to “\(task)”."
        }
        return line
    }

    private func icon() -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 40, weight: .semibold)
        return UIImage(systemName: "bolt.fill", withConfiguration: configuration)?
            .withTintColor(Self.ember, renderingMode: .alwaysOriginal)
    }
}
