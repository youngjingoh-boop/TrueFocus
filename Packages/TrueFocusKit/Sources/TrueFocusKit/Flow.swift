import Foundation

/// The four states of a working day: working (focus / think), recovering (rest), or not
/// running (idle). A pause is idle with a task held for you (`SegmentOutcome.paused`), so
/// the timeline never has a clock that runs while nobody works.
public enum FlowMode: String, Codable, Sendable, CaseIterable {
    /// Nothing running. Either the day hasn't started or it has been shut down.
    case idle
    /// Attacking the current task.
    case focus
    /// Stuck on the current task and thinking it through. Shields stay up.
    case think
    /// Micro-rest between tasks — seconds, not minutes.
    case rest

    /// Shields and strict doom-scroll limits apply in these modes.
    public var isWorking: Bool { self == .focus || self == .think }
    public var isActive: Bool { self != .idle }

    public var label: String {
        switch self {
        case .idle: return "Idle"
        case .focus: return "Focus"
        case .think: return "Think"
        case .rest: return "Rest"
        }
    }

    /// SF Symbol name. Kept as a string so this module stays UI-free.
    public var symbol: String {
        switch self {
        case .idle: return "circle.dashed"
        case .focus: return "bolt.fill"
        case .think: return "brain"
        case .rest: return "leaf.fill"
        }
    }
}

/// Why a segment ended. Stored with each segment so the day can be replayed.
public enum SegmentOutcome: String, Codable, Sendable {
    /// The task was finished.
    case completed
    /// Switched to a different task (multi-tasking).
    case switched
    /// Focus turned into think time.
    case stuck
    /// Think or rest ended and work resumed.
    case resumed
    /// The day was shut down.
    case ended
    /// You paused: the clock stopped and the task waits for you to resume it.
    case paused
    /// You stopped: the task stays on the plan, but nothing holds its place or asks you back.
    /// (An older app reads an unknown outcome as none, so this syncs safely.)
    case stopped
    /// Another device started a newer segment; this one was closed to keep a single timeline.
    case superseded
}

/// A plain-value view of one contiguous block of a single mode.
/// The app persists these (SwiftData, synced through the TrueFocus server); the math below only sees values.
public struct SegmentRecord: Equatable, Sendable {
    public var mode: FlowMode
    public var taskID: UUID?
    public var start: Date
    public var end: Date?
    public var outcome: SegmentOutcome?
    /// For rest segments: how long the rest was meant to be.
    public var plannedSeconds: TimeInterval?

    public init(mode: FlowMode, taskID: UUID? = nil, start: Date, end: Date? = nil,
                outcome: SegmentOutcome? = nil, plannedSeconds: TimeInterval? = nil) {
        self.mode = mode
        self.taskID = taskID
        self.start = start
        self.end = end
        self.outcome = outcome
        self.plannedSeconds = plannedSeconds
    }

    public var isOpen: Bool { end == nil }

    public func duration(now: Date) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}

/// How long the micro-rest after a finished task should be.
///
/// Not pomodoro. The rest scales with how long you were in the task:
/// a six-minute email earns ~20 seconds, a long build earns a few minutes.
public enum RestPolicy {
    /// Seconds of overrun tolerated before the first nudge.
    public static let grace: TimeInterval = 15
    /// Extra slack before an overrun rest breaks the momentum chain.
    public static let chainSlack: TimeInterval = 90

    public static func plannedRest(afterFocus seconds: TimeInterval,
                                   base: TimeInterval = 45,
                                   adaptive: Bool = true) -> TimeInterval {
        let safeBase = min(max(base, 5), 600)
        guard adaptive else { return roundToFive(safeBase) }
        let minutes = seconds / 60
        let factor: Double
        switch minutes {
        case ..<10: factor = 0.45
        case ..<25: factor = 1.0
        case ..<50: factor = 1.6
        case ..<80: factor = 2.6
        default: factor = 4.0
        }
        return roundToFive(min(max(safeBase * factor, 10), 300))
    }

    private static func roundToFive(_ value: TimeInterval) -> TimeInterval {
        (value / 5).rounded() * 5
    }
}
