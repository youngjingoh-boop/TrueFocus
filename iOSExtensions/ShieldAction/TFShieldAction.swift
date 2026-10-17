import DeviceActivity
import Foundation
import ManagedSettings
import TrueFocusKit

/// Handles the two buttons on the shield.
/// "Back to work" closes the app. "Reply" lets a reply app through for a couple of minutes.
final class TFShieldAction: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            completionHandler(.close)
        case .secondaryButtonPressed:
            if GuardReactions.grantReplyPass(for: application) {
                // The token is no longer shielded; deferring re-evaluates and lets you in.
                completionHandler(.defer)
            } else {
                completionHandler(.close)
            }
        @unknown default:
            completionHandler(.close)
        }
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }
}
