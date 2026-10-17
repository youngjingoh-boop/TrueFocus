import Foundation

public enum TFFormat {
    /// "4:05", "12:30", "1:04:05".
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// "45s", "12m", "1h 05m".
    public static func short(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        if total < 60 { return "\(total)s" }
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        return "\(m)m"
    }

    /// "SAT · OCT 17"
    public static func dayEyebrow(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let weekday = DateFormatter()
        weekday.locale = locale
        weekday.timeZone = timeZone
        weekday.setLocalizedDateFormatFromTemplate("EEE")
        let day = DateFormatter()
        day.locale = locale
        day.timeZone = timeZone
        day.setLocalizedDateFormatFromTemplate("MMM d")
        return "\(weekday.string(from: date)) · \(day.string(from: date))".uppercased(with: locale)
    }

    /// Truncates for tight spaces like the menu bar.
    public static func truncate(_ text: String, to length: Int) -> String {
        guard text.count > length, length > 1 else { return text }
        return String(text.prefix(length - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

public extension Calendar {
    /// Days start at 4am: working past midnight still counts as "today".
    func tfDayStart(for date: Date, rolloverHour: Int = 4) -> Date {
        let shifted = date.addingTimeInterval(-Double(rolloverHour) * 3600)
        return self.startOfDay(for: shifted).addingTimeInterval(Double(rolloverHour) * 3600)
    }
}
