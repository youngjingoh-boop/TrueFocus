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
    /// Brand Ink (#050506): the label on an Ember fill.
    private static let onEmber = UIColor(red: 5.0 / 255.0, green: 5.0 / 255.0, blue: 6.0 / 255.0, alpha: 1)
    /// The mark's gradients (docs/brand/tokens.json): ring #FF7A40 → #E2460E, core #FFE6D6 → #FF9560 → Ember.
    private static let ringTop = UIColor(red: 1.0, green: 122.0 / 255.0, blue: 64.0 / 255.0, alpha: 1)
    private static let ringBottom = UIColor(red: 226.0 / 255.0, green: 70.0 / 255.0, blue: 14.0 / 255.0, alpha: 1)
    private static let coreHot = UIColor(red: 1.0, green: 230.0 / 255.0, blue: 214.0 / 255.0, alpha: 1)
    private static let coreMid = UIColor(red: 1.0, green: 149.0 / 255.0, blue: 96.0 / 255.0, alpha: 1)
    private static let ink = UIColor(white: 0.96, alpha: 1)
    private static let ink2 = UIColor(white: 0.74, alpha: 1)
    /// The secondary button sits on a light glass pill (iOS 26), so its label is dark.
    private static let onGlass = UIColor(white: 0.08, alpha: 1)
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
        let copy = Copy(settings: settings)
        let now = Date()

        let line: Copy.Line
        switch kind(snapshot: snapshot, config: config) {
        case .focus:
            let minutes = Int(snapshot.taskElapsed(now: now) / 60)
            line = copy.shield(during: snapshot.mode, task: snapshot.taskTitle ?? snapshot.headline,
                               minutesIn: snapshot.mode == .focus ? minutes : nil)
        case .budget:
            let subtitle = budgetSubtitle(appName: appName, until: config.budgetShieldUntil, now: now,
                                          task: snapshot.headline)
            line = copy.budgetSpent(subtitle: subtitle, task: snapshot.headline)
        case .generic:
            line = copy.shield(during: snapshot.mode, task: snapshot.headline, minutesIn: nil)
        }
        let title = line.title
        let subtitle = line.body

        var secondary: ShieldConfiguration.Label?
        if offersReplyPass {
            let remaining = config.passesRemaining(settings: settings, now: now)
            if remaining > 0 {
                let text = "Post or reply · \(settings.respondPassMinutes) min · \(remaining) left"
                secondary = ShieldConfiguration.Label(text: text, color: Self.onGlass)
            }
        }

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: Self.canvas,
            icon: icon(),
            title: ShieldConfiguration.Label(text: title, color: Self.ink),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: Self.ink2),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Back to work", color: Self.onEmber),
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

    /// The TruFocus mark (docs/brand, "Ember Open"): one ring, one point of light. The shield is
    /// always dark, so this is the glow cut. Drawn on the brand's 100-unit field: ring radius 37,
    /// stroke 5.5; core radius 17; a soft Signal glow behind the core and along the ring.
    private func icon() -> UIImage? {
        let side: CGFloat = 64
        let u = side / 100
        let center = CGPoint(x: side / 2, y: side / 2)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
            func circle(_ radius: CGFloat) -> CGRect {
                CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            }

            // Core glow: Signal at 65%, fading out inside the ring.
            if let glow = CGGradient(colorsSpace: space,
                                     colors: [Self.ember.withAlphaComponent(0.65).cgColor,
                                              Self.ember.withAlphaComponent(0).cgColor] as CFArray,
                                     locations: [0.5, 1]) {
                cg.drawRadialGradient(glow, startCenter: center, startRadius: 0,
                                      endCenter: center, endRadius: 34 * u, options: [])
            }

            // Ring glow: Signal at 30%, blurred.
            cg.saveGState()
            cg.setShadow(offset: .zero, blur: 6.4 * u, color: Self.ember.withAlphaComponent(0.6).cgColor)
            cg.setStrokeColor(Self.ember.withAlphaComponent(0.3).cgColor)
            cg.setLineWidth(5.5 * u)
            cg.strokeEllipse(in: circle(37 * u))
            cg.restoreGState()

            // Ring: vertical gradient, top to bottom.
            cg.saveGState()
            cg.addEllipse(in: circle(37 * u))
            cg.setLineWidth(5.5 * u)
            cg.replacePathWithStrokedPath()
            cg.clip()
            if let ring = CGGradient(colorsSpace: space,
                                     colors: [Self.ringTop.cgColor, Self.ringBottom.cgColor] as CFArray,
                                     locations: [0, 1]) {
                cg.drawLinearGradient(ring, start: CGPoint(x: center.x, y: 11 * u), end: CGPoint(x: center.x, y: 89 * u),
                                      options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            cg.restoreGState()

            // Core: centred radial gradient.
            cg.saveGState()
            cg.addEllipse(in: circle(17 * u))
            cg.clip()
            if let core = CGGradient(colorsSpace: space,
                                     colors: [Self.coreHot.cgColor, Self.coreMid.cgColor, Self.ember.cgColor] as CFArray,
                                     locations: [0, 0.45, 1]) {
                cg.drawRadialGradient(core, startCenter: center, startRadius: 0,
                                      endCenter: center, endRadius: 17 * u, options: [.drawsAfterEndLocation])
            }
            cg.restoreGState()
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}
