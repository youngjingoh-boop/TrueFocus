import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import TrueFocusKit
import UserNotifications

/// Applies and clears the guard's shields. Idempotent: call `reapply` whenever anything
/// changes and every store ends up matching `GuardConfig`.
///
/// Only settings that differ are written. Every write makes iOS re-evaluate every shield on
/// screen, and a burst of them while the shield is waiting on a button froze the phone for
/// seconds: a Post or reply pass now changes one setting, not six.
enum GuardShields {
    static var focusStore: ManagedSettingsStore { ManagedSettingsStore(named: .focus) }
    static var budgetStore: ManagedSettingsStore { ManagedSettingsStore(named: .scrollBudget) }

    private struct Shields {
        var applications: Set<ApplicationToken>?
        var applicationCategories: ShieldSettings.ActivityCategoryPolicy<Application>?
        var webDomains: Set<WebDomainToken>?
        var webDomainCategories: ShieldSettings.ActivityCategoryPolicy<WebDomain>?
    }

    /// Brings both shield stores in line with the config.
    static func reapply(_ config: GuardConfig, now: Date = Date()) {
        let pass = config.livePassTokens(now: now)
        write(config.focusShieldActive ? focusShields(config, pass: pass) : Shields(), to: focusStore)
        write(config.budgetShieldActive ? budgetShields(config, pass: pass) : Shields(), to: budgetStore)
    }

    private static func write(_ shields: Shields, to store: ManagedSettingsStore) {
        if store.shield.applications != shields.applications {
            store.shield.applications = shields.applications
        }
        if store.shield.applicationCategories != shields.applicationCategories {
            store.shield.applicationCategories = shields.applicationCategories
        }
        if store.shield.webDomains != shields.webDomains {
            store.shield.webDomains = shields.webDomains
        }
        if store.shield.webDomainCategories != shields.webDomainCategories {
            store.shield.webDomainCategories = shields.webDomainCategories
        }
    }

    /// While working: every scroll and reply app, their categories, and chosen sites.
    private static func focusShields(_ config: GuardConfig, pass: Set<ApplicationToken>) -> Shields {
        var shields = Shields()
        shields.applications = config.shieldedApps.subtracting(pass).tfNilIfEmpty
        // Reply apps are shielded one by one (never through their category) so the
        // shield can offer them a Post or reply pass.
        let categories = config.categories
        if !categories.isEmpty {
            shields.applicationCategories = .specific(categories, except: config.replyApps.union(pass).union(config.allowedApps))
            shields.webDomainCategories = .specific(categories, except: [])
        }
        shields.webDomains = config.webDomains.tfNilIfEmpty
        return shields
    }

    /// After the scroll budget is spent: the apps only. Safari stays usable for
    /// messages, where the extension keeps feeds and Reels out.
    private static func budgetShields(_ config: GuardConfig, pass: Set<ApplicationToken>) -> Shields {
        var shields = Shields()
        shields.applications = config.shieldedApps.subtracting(pass).tfNilIfEmpty
        let categories = config.categories
        if !categories.isEmpty {
            shields.applicationCategories = .specific(categories, except: config.replyApps.union(pass).union(config.allowedApps))
        }
        return shields
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
            intervalEnd: calendar.dateComponents(dateParts, from: GuardTiming.scheduleEnd(end)),
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

    /// Time in the scroll and reply apps, counted toward a threshold.
    private static func usageEvent(_ config: GuardConfig, minutes: Int) -> DeviceActivityEvent {
        DeviceActivityEvent(
            applications: config.shieldedApps,
            categories: config.categories,
            webDomains: config.webDomains,
            threshold: DateComponents(minute: max(1, minutes))
        )
    }

    /// The budget, plus a warning a couple of minutes before it runs out.
    static func budgetEvents(_ config: GuardConfig, settings: TFSettings) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        let budget = max(1, settings.scrollBudgetMinutes)
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [.budgetReached: usageEvent(config, minutes: budget)]
        if let warn = GuardTiming.budgetWarningMinute(budget: budget) {
            events[.budgetWarning] = usageEvent(config, minutes: warn)
        }
        return events
    }

    /// (Re)starts the daily budget. Stops everything budget-related if nothing is selected.
    static func startDailyBudget(_ config: GuardConfig, settings: TFSettings) {
        guard config.hasSelection else {
            center.stopMonitoring([.scrollBudget, .budgetRestart, .cooldown])
            return
        }
        do {
            try center.startMonitoring(.scrollBudget, during: dailySchedule,
                                       events: budgetEvents(config, settings: settings))
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
                                       events: budgetEvents(config, settings: settings))
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

    /// A Post or reply pass: lasts `minutes` of use of that app, or a little longer in clock
    /// time (iOS needs at least 15 minutes), whichever comes first. Warns a minute before.
    static func startReplyPass(for token: ApplicationToken, minutes: Int, from now: Date = Date()) -> Bool {
        let length = max(1, minutes)
        guard let schedule = oneShot(from: now, to: now.addingTimeInterval(GuardTiming.passWindow(pass: length))) else { return false }
        func used(_ minutes: Int) -> DeviceActivityEvent {
            DeviceActivityEvent(applications: [token], categories: [], webDomains: [],
                                threshold: DateComponents(minute: minutes))
        }
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [.replyPassUsed: used(length)]
        if let warn = GuardTiming.passWarningMinute(pass: length) {
            events[.replyPassWarning] = used(warn)
        }
        do {
            try center.startMonitoring(.replyPass, during: schedule, events: events)
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
            config.budgetShieldSince = now
        }
        GuardShields.reapply(config)
        SharedStore.shared.appendBoot(BootEvent(at: now, source: "ios-budget", site: nil, reason: "budget"))
    }

    /// You chose to end a lockout early. It counts as one more boot-out today, then the shield
    /// lifts and a fresh budget starts, exactly as when a cooldown runs out.
    static func unlockEarly(now: Date = Date()) {
        guard GuardStore.load().budgetShieldActive else { return }
        DeviceActivityCenter().stopMonitoring([.cooldown])
        SharedStore.shared.appendBoot(BootEvent(at: now, source: "ios-budget", site: nil, reason: "unlocked-early"))
        cooldownEnded(now: now)
    }

    /// The cooldown is over: lift the shield and start a fresh budget.
    static func cooldownEnded(now: Date = Date()) {
        let settings = SharedStore.shared.settings
        var bootedAt: Date?
        let config = GuardStore.update { config in
            bootedAt = config.budgetShieldSince
            config.budgetShieldActive = false
            config.budgetShieldUntil = nil
            config.budgetShieldSince = nil
        }
        GuardShields.reapply(config)
        // A boot-out that crossed midnight already has a fresh budget: the daily monitor
        // started over at 00:00. A second monitor would warn and boot out twice.
        if GuardTiming.restartsBudget(bootedAt: bootedAt, cooldownEndedAt: now) {
            GuardMonitoring.restartBudget(config, settings: settings, from: now)
        }
    }

    /// A couple of minutes before the budget shields: a heads-up, so it isn't a surprise.
    static func budgetWarning() {
        let config = GuardStore.load()
        // Nothing to warn about while a boot-out or a focus shield is already up.
        guard !config.budgetShieldActive, !config.focusShieldActive else { return }
        let store = SharedStore.shared
        let minutes = store.settings.scrollBudgetMinutes
        guard let warn = GuardTiming.budgetWarningMinute(budget: minutes) else { return }
        let line = Copy(settings: store.settings).budgetWarning(minutesLeft: minutes - warn, task: store.snapshot.headline)
        GuardNotice.post(line, id: "tf.guard.budgetWarning")
    }

    /// A minute before a pass closes.
    static func replyPassWarning() {
        guard !GuardStore.load().passTokens.isEmpty else { return }
        let store = SharedStore.shared
        GuardNotice.post(Copy(settings: store.settings).passEnding(task: store.snapshot.headline), id: "tf.guard.passWarning")
    }

    /// The pass's time in the app is used up. Ignored when it came too soon to be true:
    /// iOS can report a threshold the moment monitoring starts.
    static func replyPassUsedUp(now: Date = Date()) {
        let config = GuardStore.load()
        guard GuardTiming.passCouldBeUsedUp(startedAt: config.passStartedAt, pass: config.passMinutes ?? 1, now: now) else { return }
        replyPassEnded()
    }

    /// The pass's schedule ended. Ignored when a newer pass replaced it: starting the new
    /// schedule ends the old one, and that must not close the new pass.
    static func replyPassScheduleEnded(now: Date = Date()) {
        let config = GuardStore.load()
        guard GuardTiming.passWindowOver(startedAt: config.passStartedAt, pass: config.passMinutes ?? 1, now: now) else { return }
        replyPassEnded()
    }

    /// A Post or reply pass ran out: shield those apps again.
    static func replyPassEnded() {
        let config = GuardStore.update { config in
            config.passTokens = []
            config.passStartedAt = nil
            config.passMinutes = nil
        }
        GuardMonitoring.stopReplyPass()
        GuardShields.reapply(config)
    }

    /// Midnight: yesterday's boot-out and pass don't carry over (unless a cooldown is running).
    /// The count of passes used rolls over with the TruFocus day at 4 am, not here
    /// (`GuardTiming.passesUsed`): zeroing it at midnight too gave out a second day's worth.
    static func newDay(now: Date = Date()) {
        let config = GuardStore.update { config in
            if let until = config.budgetShieldUntil, until > now {
                // A cooldown that crosses midnight runs to its end.
            } else {
                config.budgetShieldActive = false
                config.budgetShieldUntil = nil
                config.budgetShieldSince = nil
            }
            config.passTokens = []
            config.passStartedAt = nil
            config.passMinutes = nil
        }
        GuardShields.reapply(config)
    }

    /// A pass about to be granted. Opening the shield comes first, so the shield can answer
    /// at once; `start` then sets up when it ends.
    struct ReplyPass {
        fileprivate let token: ApplicationToken
        fileprivate let minutes: Int
        fileprivate let now: Date
        fileprivate let before: GuardConfig

        /// Starts the Screen Time schedule that closes the pass. If iOS refuses it, the pass
        /// is taken back and refunded.
        func start() {
            guard !GuardMonitoring.startReplyPass(for: token, minutes: minutes, from: now) else { return }
            let config = GuardStore.update { config in
                config.passTokens = before.passTokens
                config.passStartedAt = before.passStartedAt
                config.passMinutes = before.passMinutes
                config.passesUsed = before.passesUsed
                config.passesDay = before.passesDay
            }
            GuardShields.reapply(config)
        }
    }

    /// Lets a shielded reply app through on a Post or reply pass: one shield setting changes,
    /// nothing else. Returns nil if it isn't a reply app or no passes are left; otherwise call
    /// `start()` on the result once the shield has had its answer.
    static func openReplyPass(for token: ApplicationToken, now: Date = Date()) -> ReplyPass? {
        let settings = SharedStore.shared.settings
        let before = GuardStore.load()
        guard before.isReplyApp(token), before.passesRemaining(settings: settings, now: now) > 0 else { return nil }
        let minutes = max(1, settings.respondPassMinutes)
        var config = before
        // One pass at a time: a new pass replaces the previous one.
        config.passTokens = [token]
        config.passStartedAt = now
        config.passMinutes = minutes
        config.consumePass(now: now)
        GuardStore.save(config)
        GuardShields.reapply(config, now: now)
        return ReplyPass(token: token, minutes: minutes, now: now, before: before)
    }
}

/// Local notifications from the guard. The Monitor extension posts them while you're in
/// another app; TrueFocus asked for notification permission when it set up nudges.
enum GuardNotice {
    static func post(_ line: Copy.Line, id: String) {
        let content = UNMutableNotificationContent()
        content.title = line.title
        content.body = line.body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("TrueFocus: guard notice failed: \(error)") }
        }
    }
}
