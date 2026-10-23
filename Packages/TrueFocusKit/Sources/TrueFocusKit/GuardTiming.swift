import Foundation

/// When the iPhone guard warns before it shields. iOS reports app use only in whole minutes,
/// so every threshold here is a minute mark.
public enum GuardTiming {
    /// Minute of use at which the scroll-budget warning fires: two minutes before the
    /// shield, one minute for a two-minute budget, none for a one-minute budget.
    public static func budgetWarningMinute(budget: Int) -> Int? {
        switch budget {
        case ..<2: return nil
        case 2: return 1
        default: return budget - 2
        }
    }

    /// Minute of use at which a pass warns that it's about to close.
    public static func passWarningMinute(pass: Int) -> Int? {
        pass >= 2 ? pass - 1 : nil
    }

    /// Clock time a pass may run for: iOS needs 15 minutes; longer passes get five spare.
    public static func passWindow(pass: Int) -> TimeInterval {
        Double(max(15, pass + 5)) * 60
    }

    /// Whether a pass that began at `start` could have been used for all `pass` minutes by
    /// `now`. iOS sometimes reports a threshold the moment monitoring starts; a pass can't be
    /// used up faster than the clock runs, so such a report is ignored.
    public static func passCouldBeUsedUp(startedAt start: Date?, pass: Int, now: Date) -> Bool {
        guard let start else { return true }
        return now.timeIntervalSince(start) >= Double(max(1, pass)) * 60 - 5
    }

    /// Whether the clock-time window of a pass that began at `start` is over. A new pass
    /// replaces the old one's schedule, and iOS reports the old one ending: that report
    /// arrives inside the new window and must not close the new pass.
    public static func passWindowOver(startedAt start: Date?, pass: Int, now: Date) -> Bool {
        guard let start else { return true }
        return now.timeIntervalSince(start) >= passWindow(pass: pass) - 60
    }

    /// Screen Time schedules name whole seconds. Ends round up, so a schedule never ends
    /// before the moment it stands for: an adult-filter cool-off checked when its schedule
    /// ends must already be over.
    public static func scheduleEnd(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.up))
    }

    /// Post or reply passes used on the TruFocus day (4 am to 4 am) containing `now`, given
    /// `used` counted on `day`. Passes used late at night still count after midnight.
    public static func passesUsed(_ used: Int, countedOn day: Date?, now: Date, calendar: Calendar = .current) -> Int {
        day == calendar.tfDayStart(for: now) ? used : 0
    }

    /// Whether a boot-out ending at `end` should start a fresh one-off budget until midnight.
    /// Not when it began on an earlier day: the daily monitor already started counting from
    /// zero at midnight, and a second monitor would warn and boot out twice.
    public static func restartsBudget(bootedAt start: Date?, cooldownEndedAt end: Date, calendar: Calendar = .current) -> Bool {
        guard let start else { return true }
        return calendar.isDate(start, inSameDayAs: end)
    }
}

