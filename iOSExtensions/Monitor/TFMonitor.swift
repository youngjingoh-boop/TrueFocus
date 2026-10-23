import DeviceActivity
import Foundation
import ManagedSettings
import TrueFocusKit

/// Runs in the background whenever a TrueFocus Screen Time schedule or threshold fires:
/// the scroll budget and its warning, the cooldown, Post or reply passes, and the
/// adult-filter cool-off.
final class TFMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity == .scrollBudget {
            GuardReactions.newDay()
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        switch activity {
        case .cooldown:
            GuardReactions.cooldownEnded()
        case .replyPass:
            GuardReactions.replyPassScheduleEnded()
        case .adultCoolOff:
            AdultFilter.apply()
        default:
            break
        }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        switch event {
        case .budgetReached:
            // Ignore a stale event while a boot-out is already running.
            if GuardStore.load().budgetShieldActive { return }
            GuardReactions.budgetReached()
        case .budgetWarning:
            GuardReactions.budgetWarning()
        case .replyPassUsed:
            GuardReactions.replyPassUsedUp()
        case .replyPassWarning:
            GuardReactions.replyPassWarning()
        default:
            break
        }
    }
}
