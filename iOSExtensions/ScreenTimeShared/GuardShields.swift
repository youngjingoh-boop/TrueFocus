import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import TrueFocusKit

/// Applies and clears the guard's shields. Idempotent: call `reapply` whenever anything
/// changes and every store ends up matching `GuardConfig`.
enum GuardShields {
    static var focusStore: ManagedSettingsStore { ManagedSettingsStore(named: .focus) }
    static var budgetStore: ManagedSettingsStore { ManagedSettingsStore(named: .scrollBudget) }

    /// Brings both shield stores in line with the config.
    static func reapply(_ config: GuardConfig) {
        if config.focusShieldActive {
            shieldFocus(config)
        } else {
            focusStore.clearAllSettings()
        }
        if config.budgetShieldActive {
            shieldBudget(config)
        } else {
            budgetStore.clearAllSettings()
        }
    }

    /// While working: every scroll and reply app, their categories, and chosen sites.
    private static func shieldFocus(_ config: GuardConfig) {
        let store = focusStore
        let pass = config.passTokens
        store.shield.applications = config.shieldedApps.subtracting(pass).tfNilIfEmpty
        // Reply apps are shielded one by one (never through their category) so the
        // shield can offer them a Reply pass.
        let categories = config.categories
        if categories.isEmpty {
            store.shield.applicationCategories = nil
            store.shield.webDomainCategories = nil
        } else {
            store.shield.applicationCategories = .specific(categories, except: config.replyApps.union(pass))
            store.shield.webDomainCategories = .specific(categories, except: [])
        }
        store.shield.webDomains = config.webDomains.tfNilIfEmpty
    }

    /// After the scroll budget is spent: the apps only. Safari stays usable for
    /// messages, where the extension keeps feeds and Reels out.
    private static func shieldBudget(_ config: GuardConfig) {
        let store = budgetStore
        let pass = config.passTokens
        store.shield.applications = config.shieldedApps.subtracting(pass).tfNilIfEmpty
        let categories = config.categories
        store.shield.applicationCategories = categories.isEmpty
            ? nil
            : .specific(categories, except: config.replyApps.union(pass))
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
    }
}

/// The adult-content filter: Apple's automatic web filter plus TrueFocus's own list,
/// applied to Safari and every app that shows web content. Turning it off is honoured
/// once the cool-off in settings has passed.
enum AdultFilter {
    /// Apple's filter does the heavy lifting; the explicit list covers the biggest sites.
    private static let explicitDomainLimit = 50

    static var store: ManagedSettingsStore { ManagedSettingsStore(named: .adultFilter) }

    static func apply(settings: TFSettings = SharedStore.shared.settings, now: Date = Date()) {
        if settings.adultFilterActive(now: now) {
            let domains = Set(Blocklist.adultDomains.prefix(explicitDomainLimit).map { WebDomain(domain: $0) })
            store.webContent.blockedByFilter = .auto(domains, except: [])
        } else {
            store.clearAllSettings()
        }
    }
}

/// DeviceActivity scheduling. iOS requires every interval to be at least 15 minutes
/// and caps how many activities an app may monitor, so TrueFocus uses five names at most.
enum GuardMonitoring {
    static let minimumInterval: TimeInterval = 15 * 60

    private static var center: DeviceActivityCenter { DeviceActivityCenter() }

    private static let dateParts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]

    /// A one-off schedule between two moments, or nil if it would be too short for iOS.
    static func oneShot(from start: Date, to end: Date) -> DeviceActivitySchedule? {
        guard end.timeIntervalSince(start) >= minimumInterval else { return nil }
        let calendar = Calendar.current
        return DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(dateParts, from: start),
            intervalEnd: calendar.dateComponents(dateParts, from: end),
            repeats: false
        )
    }

    static var dailySchedule: DeviceActivitySchedule {
        DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
    }

    static func budgetEvent(_ config: GuardConfig, settings: TFSettings) -> DeviceActivityEvent {
        DeviceActivityEvent(
            applications: config.shieldedApps,
            categories: config.categories,
            webDomains: config.webDomains,
            threshold: DateComponents(minute: max(1, settings.scrollBudgetMinutes))
        )
    }

    /// (Re)starts the daily budget. Stops everything budget-related if nothing is selected.
    static func startDailyBudget(_ config: GuardConfig, settings: TFSettings) {
        guard config.hasSelection else {
            center.stopMonitoring([.scrollBudget, .budgetRestart, .cooldown])
            return
        }
        do {
            try center.startMonitoring(.scrollBudget, during: dailySchedule,
                                       events: [.budgetReached: budgetEvent(config, settings: settings)])
        } catch {
            print("TrueFocus: daily budget monitoring failed: \(error)")
        }
    }

    /// A fresh budget from now until midnight, counted from zero.
    static func restartBudget(_ config: GuardConfig, settings: TFSettings, from now: Date = Date()) {
        center.stopMonitoring([.budgetRestart])
        guard config.hasSelection, let end = endOfDay(after: now),
              let schedule = oneShot(from: now, to: end) else { return }
        do {
            try center.startMonitoring(.budgetRestart, during: schedule,
                                       events: [.budgetReached: budgetEvent(config, settings: settings)])
        } catch {
            print("TrueFocus: budget restart failed: \(error)")
        }
    }

    /// Starts the boot-out. Returns when it ends.
    @discardableResult
    static func startCooldown(minutes: Int, from now: Date = Date()) -> Date {
        let length = max(Double(minutes) * 60, minimumInterval)
        let end = now.addingTimeInterval(length)
        if let schedule = oneShot(from: now, to: end) {
            do {
                try center.startMonitoring(.cooldown, during: schedule)
            } catch {
                print("TrueFocus: cooldown monitoring failed: \(error)")
            }
        }
        return end
    }

    /// A Reply pass: lasts `minutes` of use of that app, or 15 minutes of clock time,
    /// whichever comes first.
    static func startReplyPass(for token: ApplicationToken, minutes: Int, from now: Date = Date()) -> Bool {
        guard let schedule = oneShot(from: now, to: now.addingTimeInterval(minimumInterval)) else { return false }
        let event = DeviceActivityEvent(
            applications: [token],
            categories: [],
            webDomains: [],
            threshold: DateComponents(minute: max(1, minutes))
        )
        do {
            try center.startMonitoring(.replyPass, during: schedule, events: [.replyPassUsed: event])
            return true
        } catch {
            print("TrueFocus: reply pass monitoring failed: \(error)")
            return false
        }
    }

    static func stopReplyPass() {
        center.stopMonitoring([.replyPass])
    }

    /// Wakes the monitor extension when a requested adult-filter turn-off takes effect,
    /// so it happens even if the app isn't open.
    static func scheduleAdultCoolOff(until end: Date, from now: Date = Date()) {
        center.stopMonitoring([.adultCoolOff])
        guard let schedule = oneShot(from: now, to: end) else { return }
        do {
            try center.startMonitoring(.adultCoolOff, during: schedule)
        } catch {
            print("TrueFocus: adult filter cool-off monitoring failed: \(error)")
        }
    }

    static func cancelAdultCoolOff() {
        center.stopMonitoring([.adultCoolOff])
    }

    /// 23:59:59 of the calendar day containing `date`.
    static func endOfDay(after date: Date) -> Date? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start)
    }
}

/// The reactions to Screen Time events, shared so the app can run them too.
enum GuardReactions {
    /// The scroll budget is spent: shield, record the boot-out, start the cooldown.
    static func budgetReached(now: Date = Date()) {
        let settings = SharedStore.shared.settings
        let until = GuardMonitoring.startCooldown(minutes: settings.scrollCooldownMinutes, from: now)
        let config = GuardStore.update { config in
            config.budgetShieldActive = true
            config.budgetShieldUntil = until
        }
        GuardShields.reapply(config)
        SharedStore.shared.appendBoot(BootEvent(at: now, source: "ios-budget", site: nil, reason: "budget"))
    }

    /// The cooldown is over: lift the shield and start a fresh budget.
    static func cooldownEnded(now: Date = Date()) {
        let settings = SharedStore.shared.settings
        let config = GuardStore.update { config in
            config.budgetShieldActive = false
            config.budgetShieldUntil = nil
        }
        GuardShields.reapply(config)
        GuardMonitoring.restartBudget(config, settings: settings, from: now)
    }

    /// A Reply pass ran out: shield those apps again.
    static func replyPassEnded() {
        let config = GuardStore.update { $0.passTokens = [] }
        GuardMonitoring.stopReplyPass()
        GuardShields.reapply(config)
    }

    /// Midnight: yesterday's boot-out and passes don't carry over (unless a cooldown is running).
    static func newDay(now: Date = Date()) {
        let config = GuardStore.update { config in
            if let until = config.budgetShieldUntil, until > now {
                // A cooldown that crosses midnight runs to its end.
            } else {
                config.budgetShieldActive = false
                config.budgetShieldUntil = nil
            }
            config.passTokens = []
            config.passesUsed = 0
            config.passesDay = Calendar.current.tfDayStart(for: now)
        }
        GuardShields.reapply(config)
    }

    /// Grants a Reply pass for a shielded reply app. Returns false if none are left.
    static func grantReplyPass(for token: ApplicationToken, now: Date = Date()) -> Bool {
        let settings = SharedStore.shared.settings
        var config = GuardStore.load()
        guard config.isReplyApp(token), config.passesRemaining(settings: settings, now: now) > 0 else { return false }
        // One pass at a time: a new pass replaces the previous one.
        guard GuardMonitoring.startReplyPass(for: token, minutes: settings.respondPassMinutes, from: now) else { return false }
        config.passTokens = [token]
        config.consumePass(now: now)
        GuardStore.save(config)
        GuardShields.reapply(config)
        return true
    }
}
