import Foundation

/// Everything the day's scoreboard shows, derived from the segment timeline.
public struct DayStats: Equatable, Sendable {
    public var focusSeconds: TimeInterval = 0
    public var thinkSeconds: TimeInterval = 0
    public var restSeconds: TimeInterval = 0
    /// Rest time beyond what was planned (plus grace). The leak.
    public var restOverrunSeconds: TimeInterval = 0
    public var completed: Int = 0
    public var switches: Int = 0
    /// Consecutive finished tasks with no rest overrun between them.
    public var chain: Int = 0
    public var bestChain: Int = 0
    /// 0...100. Rises with finished tasks and focus time, leaks with long rests,
    /// idle gaps and doom-scroll boot-outs.
    public var momentum: Int = 0
    public var boots: Int = 0
    public var firstStart: Date?

    public init() {}

    /// Replays the day.
    /// - Parameters:
    ///   - segments: today's segments in any order (open segment allowed).
    ///   - boots: how many times a doom-scroll guard booted you out today.
    ///   - now: the moment to evaluate open segments and live decay at.
    public static func compute(segments: [SegmentRecord], boots: Int = 0, now: Date) -> DayStats {
        var stats = DayStats()
        stats.boots = boots
        let ordered = segments.sorted { $0.start < $1.start }
        stats.firstStart = ordered.first?.start

        var momentum: Double = 0
        var chain = 0
        var best = 0
        // After a completion, the chain survives if the next focus starts within this window.
        var chainDeadline: Date?
        var lastEnd: Date?

        func gain(_ amount: Double) {
            // Diminishing returns: the closer to 100, the harder it is to climb.
            momentum += amount * max(0, 1 - momentum / 130)
        }

        for segment in ordered {
            let end = segment.end ?? now
            let duration = segment.duration(now: now)

            // Idle gap between segments (after the first) leaks momentum past 3 minutes.
            if let previousEnd = lastEnd {
                let gap = segment.start.timeIntervalSince(previousEnd)
                if gap > 180 { momentum -= (gap - 180) / 60 * 1.0 }
                if gap > 0, let deadline = chainDeadline, segment.start > deadline {
                    chain = 0
                    chainDeadline = nil
                }
            }

            switch segment.mode {
            case .focus:
                stats.focusSeconds += duration
                gain(duration / 60 * 0.35)
                if let deadline = chainDeadline {
                    if segment.start > deadline { chain = 0 }
                    chainDeadline = nil
                }
                switch segment.outcome {
                case .completed?:
                    stats.completed += 1
                    gain(14)
                    chain += 1
                    best = max(best, chain)
                    chainDeadline = end.addingTimeInterval(300 + RestPolicy.chainSlack)
                case .switched?:
                    stats.switches += 1
                default:
                    break
                }
            case .think:
                stats.thinkSeconds += duration
                // Thinking is work. Small credit, no penalty.
                gain(duration / 60 * 0.15)
                // Finishing straight from think time counts like finishing from focus.
                if segment.outcome == .completed {
                    stats.completed += 1
                    gain(14)
                    chain += 1
                    best = max(best, chain)
                    chainDeadline = end.addingTimeInterval(300 + RestPolicy.chainSlack)
                }
            case .rest:
                stats.restSeconds += duration
                let planned = segment.plannedSeconds ?? 60
                let overrun = max(0, duration - planned - RestPolicy.grace)
                stats.restOverrunSeconds += overrun
                momentum -= overrun / 60 * 2.5
                if chainDeadline != nil {
                    chainDeadline = segment.start.addingTimeInterval(planned + RestPolicy.chainSlack)
                }
            case .idle:
                break
            }
            momentum = min(max(momentum, 0), 100)
            lastEnd = max(lastEnd ?? end, end)
        }

        // Live decay: the chain dies in real time if you sit in rest or idle too long.
        if let deadline = chainDeadline, now > deadline {
            let last = ordered.last
            if last == nil || last?.mode != .focus || last?.isOpen == false {
                chain = 0
            }
        }
        if let previousEnd = lastEnd, ordered.last?.isOpen == false {
            let gap = now.timeIntervalSince(previousEnd)
            if gap > 180 { momentum -= (gap - 180) / 60 * 1.0 }
        }

        momentum -= Double(boots) * 8
        stats.momentum = Int(min(max(momentum, 0), 100).rounded())
        stats.chain = chain
        stats.bestChain = best
        return stats
    }
}
