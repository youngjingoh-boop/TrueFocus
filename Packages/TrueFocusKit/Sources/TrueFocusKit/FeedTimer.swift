import Foundation

/// Off a task: time spent in each feed app today, and when to remind you to get out.
/// A reminder, not a lockout (unless "Lock me out instead" is on). "5 more min" moves the
/// next reminder on by five minutes; each day starts from zero. Mirrors `feedTime` in the
/// browser extension's core.js.
public struct FeedTimer: Sendable {
    public private(set) var day: Date
    private var seconds: [String: TimeInterval] = [:]
    private var nextAt: [String: TimeInterval] = [:]

    public init(now: Date = Date(), calendar: Calendar = .current) {
        day = calendar.tfDayStart(for: now)
    }

    /// Adds `dt` seconds in `app`. Returns the minutes spent when it's time to remind.
    public mutating func add(_ dt: TimeInterval, to app: String, limitMinutes: Int, now: Date = Date(),
                             calendar: Calendar = .current) -> Int? {
        let today = calendar.tfDayStart(for: now)
        if today != day {
            day = today
            seconds = [:]
            nextAt = [:]
        }
        let total = (seconds[app] ?? 0) + dt
        seconds[app] = total
        let due = nextAt[app] ?? Double(max(1, limitMinutes)) * 60
        nextAt[app] = due
        guard total >= due else { return nil }
        // Ask once; the answer (close it, or 5 more min) sets the next one.
        nextAt[app] = .infinity
        return Int((total / 60).rounded())
    }

    /// "5 more min".
    public mutating func snooze(_ app: String, minutes: Int = 5) {
        nextAt[app] = (seconds[app] ?? 0) + Double(minutes) * 60
    }

    /// "Close it": the next reminder comes after another full limit.
    public mutating func closed(_ app: String, limitMinutes: Int) {
        nextAt[app] = (seconds[app] ?? 0) + Double(max(1, limitMinutes)) * 60
    }
}
