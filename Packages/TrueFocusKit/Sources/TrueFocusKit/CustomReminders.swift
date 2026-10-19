import Foundation

/// A moment TrueFocus speaks up. Each one can carry your own words instead of the tone's line.
/// The raw values are the JSON keys in `TFSettings.customReminders`; the browser extension
/// reads the same keys (`Extensions/web/core.js`, `REMINDER_MOMENTS`).
public enum ReminderMoment: String, CaseIterable, Codable, Sendable {
    case restOver
    case stuck
    case longFocus
    case idle
    case paused
    case bootOut
    case shield
    case budgetWarning
    case budgetSpent
    case passEnding

    public var label: String {
        switch self {
        case .restOver: return "Rest runs long"
        case .stuck: return "Stuck thinking"
        case .longFocus: return "Long focus"
        case .idle: return "Drifting with tasks left"
        case .paused: return "Paused too long"
        case .bootOut: return "Booted out of a feed"
        case .shield: return "Blocked app or site"
        case .budgetWarning: return "Scroll budget warning"
        case .budgetSpent: return "Scroll budget spent"
        case .passEnding: return "Post or reply ending"
        }
    }

    /// When it shows up, in a few words.
    public var detail: String {
        switch self {
        case .restOver: return "A micro-rest is over and the next task hasn't started."
        case .stuck: return "Think mode has gone on a while."
        case .longFocus: return "75 minutes into one task."
        case .idle: return "Nothing running, tasks still on the list."
        case .paused: return "A paused task is waiting for you."
        case .bootOut: return "The doom-scroll guard closes a feed."
        case .shield: return "You open a shielded app or site while you work."
        case .budgetWarning: return "iPhone: a couple of minutes before scroll apps lock."
        case .budgetSpent: return "iPhone: the scroll apps are locked."
        case .passEnding: return "iPhone: a minute before a Post or reply pass closes."
        }
    }
}

/// Your own words for each reminder moment. `nil` (or only whitespace) means
/// "use the tone's built-in line". How custom text is placed is decided in one place:
/// `Copy.apply(_:to:task:)`.
///
/// Decoding is tolerant: missing keys, or a value that isn't a string, fall back to `nil`
/// without disturbing the others.
public struct CustomReminders: Codable, Equatable, Sendable {
    public var restOver: String?
    public var stuck: String?
    public var longFocus: String?
    public var idle: String?
    public var paused: String?
    public var bootOut: String?
    public var shield: String?
    public var budgetWarning: String?
    public var budgetSpent: String?
    public var passEnding: String?

    /// Replaced with the task's title, or "your next task" when there isn't one.
    public static let taskPlaceholder = "{task}"
    /// What `{task}` becomes without a task.
    public static let noTask = "your next task"
    /// Custom text up to this many characters (after `{task}` is filled in) becomes the
    /// title; anything longer becomes the body under the tone's title.
    public static let titleLimit = 40
    /// The longest custom text kept. Notifications and shields have no room for more.
    public static let maxLength = 160

    public init(restOver: String? = nil, stuck: String? = nil, longFocus: String? = nil,
                idle: String? = nil, paused: String? = nil, bootOut: String? = nil,
                shield: String? = nil, budgetWarning: String? = nil, budgetSpent: String? = nil,
                passEnding: String? = nil) {
        self.restOver = restOver
        self.stuck = stuck
        self.longFocus = longFocus
        self.idle = idle
        self.paused = paused
        self.bootOut = bootOut
        self.shield = shield
        self.budgetWarning = budgetWarning
        self.budgetSpent = budgetSpent
        self.passEnding = passEnding
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func string(_ key: CodingKeys) -> String? {
            try? c.decodeIfPresent(String.self, forKey: key)
        }
        restOver = string(.restOver)
        stuck = string(.stuck)
        longFocus = string(.longFocus)
        idle = string(.idle)
        paused = string(.paused)
        bootOut = string(.bootOut)
        shield = string(.shield)
        budgetWarning = string(.budgetWarning)
        budgetSpent = string(.budgetSpent)
        passEnding = string(.passEnding)
    }

    /// The stored text for a moment, as typed. Setting empty or whitespace-only text clears it.
    public subscript(moment: ReminderMoment) -> String? {
        get {
            switch moment {
            case .restOver: return restOver
            case .stuck: return stuck
            case .longFocus: return longFocus
            case .idle: return idle
            case .paused: return paused
            case .bootOut: return bootOut
            case .shield: return shield
            case .budgetWarning: return budgetWarning
            case .budgetSpent: return budgetSpent
            case .passEnding: return passEnding
            }
        }
        set {
            let value = Self.clean(newValue)
            switch moment {
            case .restOver: restOver = value
            case .stuck: stuck = value
            case .longFocus: longFocus = value
            case .idle: idle = value
            case .paused: paused = value
            case .bootOut: bootOut = value
            case .shield: shield = value
            case .budgetWarning: budgetWarning = value
            case .budgetSpent: budgetSpent = value
            case .passEnding: passEnding = value
            }
        }
    }

    /// The custom text that applies to a moment: trimmed, or `nil` when there's none.
    public func text(for moment: ReminderMoment) -> String? {
        guard let raw = self[moment] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// True when no moment has custom text.
    public var isEmpty: Bool {
        ReminderMoment.allCases.allSatisfy { text(for: $0) == nil }
    }

    /// `{task}` (any case) replaced with the trimmed task title, or "your next task".
    public static func fill(_ text: String, task: String?) -> String {
        let title = task?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.replacingOccurrences(of: taskPlaceholder, with: title.isEmpty ? noTask : title,
                                         options: .caseInsensitive)
    }

    /// Drop blank entries and cap the length, so what's stored is what can be shown.
    public mutating func normalize() {
        for moment in ReminderMoment.allCases {
            self[moment] = self[moment]
        }
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        // One line only: titles and shields can't show line breaks.
        let flat = value.components(separatedBy: .newlines).joined(separator: " ")
        guard !flat.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return flat.count > maxLength ? String(flat.prefix(maxLength)) : flat
    }
}
