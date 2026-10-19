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
}
