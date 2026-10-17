import Foundation

/// Tuning for the doom-scroll detector. The same numbers drive the Safari/Chrome
/// extension (Extensions/web/core.js) and the Mac native scroll watcher.
public struct DoomScrollConfig: Codable, Equatable, Sendable {
    /// Rolling window for the burst rule.
    public var burstWindowSeconds: Double
    /// Strokes inside the window that count as skimming a feed.
    public var burstStrokes: Int
    /// Strokes in one sitting (no pause longer than `sessionGapSeconds`) that count as a binge.
    public var sessionStrokes: Int
    public var sessionGapSeconds: Double
    /// Engaged time on a feed surface before you get booted regardless of pace.
    public var dwellSeconds: Double
    /// While a focus session runs, every limit is multiplied by this.
    public var focusMultiplier: Double
    /// Fraction of a limit at which a soft warning appears.
    public var warnFraction: Double

    public init(burstWindowSeconds: Double = 60, burstStrokes: Int = 25, sessionStrokes: Int = 60,
                sessionGapSeconds: Double = 45, dwellSeconds: Double = 8 * 60,
                focusMultiplier: Double = 0.3, warnFraction: Double = 0.7) {
        self.burstWindowSeconds = burstWindowSeconds
        self.burstStrokes = burstStrokes
        self.sessionStrokes = sessionStrokes
        self.sessionGapSeconds = sessionGapSeconds
        self.dwellSeconds = dwellSeconds
        self.focusMultiplier = focusMultiplier
        self.warnFraction = warnFraction
    }

    public static let standard = DoomScrollConfig()
    public static let gentle = DoomScrollConfig(burstStrokes: 40, sessionStrokes: 100, dwellSeconds: 15 * 60)
    public static let ruthless = DoomScrollConfig(burstStrokes: 15, sessionStrokes: 35, dwellSeconds: 4 * 60, focusMultiplier: 0.2)

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DoomScrollConfig()
        burstWindowSeconds = try c.decodeIfPresent(Double.self, forKey: .burstWindowSeconds) ?? d.burstWindowSeconds
        burstStrokes = try c.decodeIfPresent(Int.self, forKey: .burstStrokes) ?? d.burstStrokes
        sessionStrokes = try c.decodeIfPresent(Int.self, forKey: .sessionStrokes) ?? d.sessionStrokes
        sessionGapSeconds = try c.decodeIfPresent(Double.self, forKey: .sessionGapSeconds) ?? d.sessionGapSeconds
        dwellSeconds = try c.decodeIfPresent(Double.self, forKey: .dwellSeconds) ?? d.dwellSeconds
        focusMultiplier = try c.decodeIfPresent(Double.self, forKey: .focusMultiplier) ?? d.focusMultiplier
        warnFraction = try c.decodeIfPresent(Double.self, forKey: .warnFraction) ?? d.warnFraction
    }

    /// Limits after applying strict (focus) mode.
    public func limits(strict: Bool) -> (burst: Double, session: Double, dwell: Double) {
        let m = strict ? min(max(focusMultiplier, 0.05), 1) : 1
        return (max(4, (Double(burstStrokes) * m).rounded()),
                max(8, (Double(sessionStrokes) * m).rounded()),
                max(60, dwellSeconds * m))
    }
}

/// Watches scroll strokes on a feed surface and decides when you're doom-scrolling.
///
/// Three rules, any one boots you:
/// - **burst** — too many downward strokes inside a short window (skimming).
/// - **binge** — too many strokes in one sitting, however slow (reels/shorts swiping).
/// - **dwell** — too much engaged time on the feed at all.
public struct DoomScrollDetector: Sendable {
    public enum Reason: String, Codable, Sendable {
        case burst, binge, dwell
    }

    public enum Verdict: Equatable, Sendable {
        case calm
        /// Fraction of the nearest limit, between `warnFraction` and 1.
        case warn(Double)
        case boot(Reason)
    }

    public var config: DoomScrollConfig
    public var strict: Bool

    private var strokeTimes: [Date] = []
    private var strokeWeights: [Double] = []
    private var sessionCount: Double = 0
    private var lastStroke: Date?
    private var lastTick: Date?
    private var engagedSeconds: TimeInterval = 0

    public init(config: DoomScrollConfig = .standard, strict: Bool = false) {
        self.config = config
        self.strict = strict
    }

    /// Clears all counters, e.g. after a boot or when leaving the feed.
    public mutating func reset() {
        strokeTimes.removeAll()
        strokeWeights.removeAll()
        sessionCount = 0
        lastStroke = nil
        lastTick = nil
        engagedSeconds = 0
    }

    /// Records one downward scroll stroke (a swipe, a wheel burst, a page-down).
    /// - Parameter screens: how far it travelled, in viewport heights. Long flings weigh more.
    @discardableResult
    public mutating func stroke(at time: Date, screens: Double = 1) -> Verdict {
        accrueEngagement(until: time)
        if let last = lastStroke, time.timeIntervalSince(last) > config.sessionGapSeconds {
            sessionCount = 0
        }
        let weight = min(max(screens, 0.5), 3)
        strokeTimes.append(time)
        strokeWeights.append(weight)
        sessionCount += weight
        lastStroke = time
        lastTick = time
        trimWindow(now: time)
        return evaluate()
    }

    /// Call periodically (every few seconds) while the feed is on screen.
    @discardableResult
    public mutating func tick(at time: Date) -> Verdict {
        accrueEngagement(until: time)
        lastTick = time
        trimWindow(now: time)
        return evaluate()
    }

    /// Highest fraction of any limit reached so far (0...1+).
    public var progress: Double {
        let l = config.limits(strict: strict)
        let burst = strokeWeights.reduce(0, +) / l.burst
        let binge = sessionCount / l.session
        let dwell = engagedSeconds / l.dwell
        return max(burst, binge, dwell)
    }

    public var engagedTime: TimeInterval { engagedSeconds }

    private mutating func accrueEngagement(until time: Date) {
        // Time only counts while you're actively scrolling (a stroke within the session gap).
        guard let last = lastStroke, let tick = lastTick else { return }
        let activeUntil = last.addingTimeInterval(config.sessionGapSeconds)
        let end = min(time, activeUntil)
        if end > tick { engagedSeconds += end.timeIntervalSince(tick) }
    }

    private mutating func trimWindow(now: Date) {
        let cutoff = now.addingTimeInterval(-config.burstWindowSeconds)
        while let first = strokeTimes.first, first < cutoff {
            strokeTimes.removeFirst()
            strokeWeights.removeFirst()
        }
    }

    private func evaluate() -> Verdict {
        let l = config.limits(strict: strict)
        if strokeWeights.reduce(0, +) >= l.burst { return .boot(.burst) }
        if sessionCount >= l.session { return .boot(.binge) }
        if engagedSeconds >= l.dwell { return .boot(.dwell) }
        let p = progress
        if p >= config.warnFraction { return .warn(min(p, 1)) }
        return .calm
    }
}
