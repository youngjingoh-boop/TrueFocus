import DeviceActivity
import Foundation
import ManagedSettings
import TrueFocusKit

/// Handles the two buttons on the shield.
/// "Back to work" closes the app. "Post or reply" lets a reply app through for a few minutes.
final class TFShieldAction: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        // Anything but "Post or reply" (the primary button, or a button added later) closes the app.
        guard action == .secondaryButtonPressed, let pass = GuardReactions.openReplyPass(for: application) else {
            completionHandler(.close)
            return
        }
        // The token is no longer shielded; deferring re-evaluates and lets you in. Answer
        // before the slower Screen Time scheduling: iOS holds the whole screen until we do.
        completionHandler(.defer)
        pass.start()
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
