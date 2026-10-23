import Foundation

/// "Working or scrolling?" for a feed app or site you've opened for work. Instead of booting
/// you out, it asks after two minutes of scrolling, then after five more each time you say
/// you're working. A stroke counts as scrolling for a few seconds, so reading a profile or
/// writing a post doesn't add up; ten quiet minutes start the count over.
/// Mirrored by `ScrollCheckIn` in the browser extension's core.js.
public struct ScrollCheckIn: Codable, Equatable, Sendable {
    public static let firstAsk: TimeInterval = 120
    public static let askAgain: TimeInterval = 300
    /// How long one stroke keeps you "scrolling".
    public static let activeWindow: TimeInterval = 8
    public static let idleReset: TimeInterval = 600

    /// Scrolling time counted toward the next question.
    public private(set) var scrolled: TimeInterval = 0
    public private(set) var threshold: TimeInterval = firstAsk
    /// A question is up and hasn't been answered.
    public private(set) var asking = false
    private var lastStroke: Date?
    private var lastUpdate: Date?

    public init() {}

    /// Minutes of scrolling the current question is about.
    public var minutes: Int { Int((threshold / 60).rounded()) }

    public mutating func stroke(at now: Date) {
        if let lastStroke, now.timeIntervalSince(lastStroke) > Self.idleReset, !asking {
            scrolled = 0
            threshold = Self.firstAsk
            lastUpdate = now
        }
        accrue(to: now)
        lastStroke = now
    }

    /// True once, when it's time to ask; then not again until answered.
    public mutating func tick(at now: Date) -> Bool {
        accrue(to: now)
        guard !asking, scrolled >= threshold else { return false }
        asking = true
        return true
    }

    /// "Working": quiet until five more minutes of scrolling.
    public mutating func working() {
        asking = false
        scrolled = 0
        threshold = Self.askAgain
        // The last stroke's tail belongs to the question just answered.
        lastStroke = nil
    }

    public mutating func reset() {
        self = ScrollCheckIn()
    }

    /// Adds the part of the time since the last update that falls within a stroke's window.
    private mutating func accrue(to now: Date) {
        defer { lastUpdate = now }
        guard let lastStroke, let lastUpdate else { return }
        let start = max(lastUpdate, lastStroke)
        let end = min(now, lastStroke.addingTimeInterval(Self.activeWindow))
        if end > start { scrolled += end.timeIntervalSince(start) }
    }
}
