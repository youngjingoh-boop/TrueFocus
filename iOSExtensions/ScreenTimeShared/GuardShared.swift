import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import TrueFocusKit

// Shared by the app and the Monitor, ShieldConfiguration and ShieldAction extensions.
// Everything here talks to Screen Time through named stores and the App Group, so any
// process can pick up where another left off.

extension ManagedSettingsStore.Name {
    /// Up while a focus or think segment runs (or a TrueFocus Focus filter is on).
    static let focus = Self("tf.focus")
    /// Up after the daily scroll budget is spent, for the cooldown.
    static let scrollBudget = Self("tf.scrollBudget")
    /// The adult-content web filter.
    static let adultFilter = Self("tf.adultFilter")
}

extension DeviceActivityName {
    /// Repeats every day, 00:00–23:59. Its event is the first budget of the day.
    static let scrollBudget = Self("tf.scrollBudget")
    /// One-off, from the end of a cooldown to midnight: a fresh budget counted from zero.
    static let budgetRestart = Self("tf.budgetRestart")
    /// One-off: how long a boot-out lasts.
    static let cooldown = Self("tf.cooldown")
    /// One-off: a short pass to post or answer messages in a reply app.
    static let replyPass = Self("tf.replyPass")
    /// One-off: ends when a requested adult-filter turn-off takes effect.
    static let adultCoolOff = Self("tf.adultCoolOff")
}

extension DeviceActivityEvent.Name {
    static let budgetReached = Self("tf.budgetReached")
    static let replyPassUsed = Self("tf.replyPassUsed")
    /// A couple of minutes before `budgetReached`: "Still scrolling? 2 minutes left."
    static let budgetWarning = Self("tf.budgetWarning")
    /// A minute before `replyPassUsed`.
    static let replyPassWarning = Self("tf.replyPassWarning")
}

/// What the guard shields and its live state, persisted in the App Group.
struct GuardConfig: Codable {
    /// Feeds you lose time in: Instagram, YouTube, TikTok, X…
    var scrollSelection = FamilyActivitySelection()
    /// Apps you still need to answer messages in. They're shielded too, but the shield
    /// offers a Post or reply pass.
    var replySelection = FamilyActivitySelection()
    /// Apps that are never shielded, even when their category is (a booking or banking app in
    /// Social or Sports, say), and even in focus.
    var allowedSelection = FamilyActivitySelection()
    /// Apps currently let through on a Post or reply pass.
    var passTokens: Set<ApplicationToken> = []
    var passesUsed = 0
    var passesDay: Date?
    /// Mirrors of what the stores are doing, so extensions can re-apply consistently.
    var focusShieldActive = false
    var budgetShieldActive = false
    var budgetShieldUntil: Date?
    /// When the current boot-out began, to tell whether it crossed midnight.
    var budgetShieldSince: Date?
    /// Fingerprint of the selection and budget the daily monitor was started with.
    var monitoringSignature: String?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scrollSelection = (try? c.decodeIfPresent(FamilyActivitySelection.self, forKey: .scrollSelection)) ?? FamilyActivitySelection()
        replySelection = (try? c.decodeIfPresent(FamilyActivitySelection.self, forKey: .replySelection)) ?? FamilyActivitySelection()
        allowedSelection = (try? c.decodeIfPresent(FamilyActivitySelection.self, forKey: .allowedSelection)) ?? FamilyActivitySelection()
        passTokens = (try? c.decodeIfPresent(Set<ApplicationToken>.self, forKey: .passTokens)) ?? []
        passesUsed = (try? c.decodeIfPresent(Int.self, forKey: .passesUsed)) ?? 0
        passesDay = try? c.decodeIfPresent(Date.self, forKey: .passesDay)
        focusShieldActive = (try? c.decodeIfPresent(Bool.self, forKey: .focusShieldActive)) ?? false
        budgetShieldActive = (try? c.decodeIfPresent(Bool.self, forKey: .budgetShieldActive)) ?? false
        budgetShieldUntil = try? c.decodeIfPresent(Date.self, forKey: .budgetShieldUntil)
        budgetShieldSince = try? c.decodeIfPresent(Date.self, forKey: .budgetShieldSince)
        monitoringSignature = try? c.decodeIfPresent(String.self, forKey: .monitoringSignature)
    }

    // MARK: Derived

    /// Every app the guard shields: scroll apps plus reply apps, minus the ones you always allow.
    var shieldedApps: Set<ApplicationToken> {
        scrollSelection.applicationTokens.union(replySelection.applicationTokens).subtracting(allowedApps)
    }

    /// Apps you always allow. Category shields leave them out too.
    var allowedApps: Set<ApplicationToken> {
        allowedSelection.applicationTokens
    }

    var categories: Set<ActivityCategoryToken> {
        scrollSelection.categoryTokens
    }

    var webDomains: Set<WebDomainToken> {
        scrollSelection.webDomainTokens.union(replySelection.webDomainTokens)
    }

    var hasSelection: Bool {
        !shieldedApps.isEmpty || !categories.isEmpty || !webDomains.isEmpty
    }

    var replyApps: Set<ApplicationToken> {
        replySelection.applicationTokens
    }

    var selectionCount: Int {
        scrollSelection.applicationTokens.count + scrollSelection.categoryTokens.count + scrollSelection.webDomainTokens.count
    }

    func isReplyApp(_ token: ApplicationToken) -> Bool {
        replySelection.applicationTokens.contains(token)
    }

    /// Passes left today (a TruFocus day: 4 am to 4 am).
    func passesRemaining(settings: TFSettings, now: Date = Date()) -> Int {
        max(0, settings.respondPassesPerDay - GuardTiming.passesUsed(passesUsed, countedOn: passesDay, now: now))
    }

    mutating func consumePass(now: Date = Date()) {
        let today = Calendar.current.tfDayStart(for: now)
        if passesDay != today {
            passesDay = today
            passesUsed = 0
        }
        passesUsed += 1
    }

    /// Changes whenever the daily budget monitor needs restarting.
    func signature(settings: TFSettings) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let scroll = (try? encoder.encode(scrollSelection)) ?? Data()
        let reply = (try? encoder.encode(replySelection)) ?? Data()
        // "v2": the budget gained a warning event, so monitors started before it restart once.
        return "v2|\(settings.scrollBudgetMinutes)|\(GuardConfig.stableHash(scroll))|\(GuardConfig.stableHash(reply))"
    }

    /// FNV-1a. `hashValue` is seeded per launch, so it can't be persisted.
    static func stableHash(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

/// Load/save for `GuardConfig`. Each process reads fresh: the extensions and the app
/// all write to it.
enum GuardStore {
    private static let key = "tf.guard.v1"

    static func load() -> GuardConfig {
        guard let data = SharedStore.shared.defaults.data(forKey: key),
              let config = try? JSONDecoder().decode(GuardConfig.self, from: data) else {
            return GuardConfig()
        }
        return config
    }

    static func save(_ config: GuardConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        SharedStore.shared.defaults.set(data, forKey: key)
    }

    /// Read-modify-write in one step.
    @discardableResult
    static func update(_ change: (inout GuardConfig) -> Void) -> GuardConfig {
        var config = load()
        change(&config)
        save(config)
        return config
    }
}

extension Set {
    /// `nil` for an empty set — ManagedSettings treats nil as "not set".
    var tfNilIfEmpty: Set? { isEmpty ? nil : self }
}
