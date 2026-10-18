import Foundation

/// The single, tiny picture of "what am I doing right now" that every surface reads:
/// the Mac menu bar, the iPhone Lock Screen widget and Live Activity, the Screen Time
/// shield, the Safari/Chrome extension. Written by the app, read by everything else.
public struct LiveSnapshot: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var title: String
        public var breadcrumb: String?
        /// Set while you're waiting on someone or something for this task.
        public var waitingSince: Date?

        public init(id: UUID, title: String, breadcrumb: String? = nil, waitingSince: Date? = nil) {
            self.id = id
            self.title = title
            self.breadcrumb = breadcrumb
            self.waitingSince = waitingSince
        }

        public var isWaiting: Bool { waitingSince != nil }
    }

    public var mode: FlowMode
    public var taskID: UUID?
    public var taskTitle: String?
    /// "Where I left off" — the next step you wrote for this task.
    public var breadcrumb: String?
    public var modeStartedAt: Date?
    /// Focus time already spent on the current task before the current segment.
    public var taskFocusBefore: TimeInterval
    /// Rest only: when the planned micro-rest ends.
    public var plannedRestEnd: Date?
    public var nextTaskID: UUID?
    public var nextTaskTitle: String?
    /// The tasks you're juggling, in the order they joined (the current one included).
    public var inPlay: [Item]
    public var doneToday: Int
    public var plannedToday: Int
    /// Closed focus time today, not counting the open segment.
    public var focusSecondsToday: TimeInterval
    public var chain: Int
    public var momentum: Int
    public var outcome: String?
    public var bootsToday: Int
    public var dayEnded: Bool
    /// A system Focus with the TrueFocus filter ("Deep Work shields") is on for this device.
    public var systemFocusOn: Bool
    public var updatedAt: Date
    public var originDevice: String

    public init(mode: FlowMode = .idle, taskID: UUID? = nil, taskTitle: String? = nil,
                breadcrumb: String? = nil, modeStartedAt: Date? = nil, taskFocusBefore: TimeInterval = 0,
                plannedRestEnd: Date? = nil, nextTaskID: UUID? = nil, nextTaskTitle: String? = nil,
                inPlay: [Item] = [], doneToday: Int = 0, plannedToday: Int = 0,
                focusSecondsToday: TimeInterval = 0, chain: Int = 0, momentum: Int = 0,
                outcome: String? = nil, bootsToday: Int = 0, dayEnded: Bool = false,
                systemFocusOn: Bool = false, updatedAt: Date = Date(), originDevice: String = "") {
        self.mode = mode
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.breadcrumb = breadcrumb
        self.modeStartedAt = modeStartedAt
        self.taskFocusBefore = taskFocusBefore
        self.plannedRestEnd = plannedRestEnd
        self.nextTaskID = nextTaskID
        self.nextTaskTitle = nextTaskTitle
        self.inPlay = inPlay
        self.doneToday = doneToday
        self.plannedToday = plannedToday
        self.focusSecondsToday = focusSecondsToday
        self.chain = chain
        self.momentum = momentum
        self.outcome = outcome
        self.bootsToday = bootsToday
        self.dayEnded = dayEnded
        self.systemFocusOn = systemFocusOn
        self.updatedAt = updatedAt
        self.originDevice = originDevice
    }

    public static let idle = LiveSnapshot(updatedAt: Date(timeIntervalSince1970: 0))

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(FlowMode.self, forKey: .mode) ?? .idle
        taskID = try c.decodeIfPresent(UUID.self, forKey: .taskID)
        taskTitle = try c.decodeIfPresent(String.self, forKey: .taskTitle)
        breadcrumb = try c.decodeIfPresent(String.self, forKey: .breadcrumb)
        modeStartedAt = try c.decodeIfPresent(Date.self, forKey: .modeStartedAt)
        taskFocusBefore = try c.decodeIfPresent(TimeInterval.self, forKey: .taskFocusBefore) ?? 0
        plannedRestEnd = try c.decodeIfPresent(Date.self, forKey: .plannedRestEnd)
        nextTaskID = try c.decodeIfPresent(UUID.self, forKey: .nextTaskID)
        nextTaskTitle = try c.decodeIfPresent(String.self, forKey: .nextTaskTitle)
        inPlay = try c.decodeIfPresent([Item].self, forKey: .inPlay) ?? []
        doneToday = try c.decodeIfPresent(Int.self, forKey: .doneToday) ?? 0
        plannedToday = try c.decodeIfPresent(Int.self, forKey: .plannedToday) ?? 0
        focusSecondsToday = try c.decodeIfPresent(TimeInterval.self, forKey: .focusSecondsToday) ?? 0
        chain = try c.decodeIfPresent(Int.self, forKey: .chain) ?? 0
        momentum = try c.decodeIfPresent(Int.self, forKey: .momentum) ?? 0
        outcome = try c.decodeIfPresent(String.self, forKey: .outcome)
        bootsToday = try c.decodeIfPresent(Int.self, forKey: .bootsToday) ?? 0
        dayEnded = try c.decodeIfPresent(Bool.self, forKey: .dayEnded) ?? false
        systemFocusOn = try c.decodeIfPresent(Bool.self, forKey: .systemFocusOn) ?? false
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
        originDevice = try c.decodeIfPresent(String.self, forKey: .originDevice) ?? ""
    }

    // MARK: Derived

    public func elapsedInMode(now: Date) -> TimeInterval {
        guard let start = modeStartedAt else { return 0 }
        return max(0, now.timeIntervalSince(start))
    }

    /// Total focus on the current task, live.
    public func taskElapsed(now: Date) -> TimeInterval {
        mode == .focus ? taskFocusBefore + elapsedInMode(now: now) : taskFocusBefore
    }

    public func focusToday(now: Date) -> TimeInterval {
        mode == .focus ? focusSecondsToday + elapsedInMode(now: now) : focusSecondsToday
    }

    public func restRemaining(now: Date) -> TimeInterval {
        guard mode == .rest, let end = plannedRestEnd else { return 0 }
        return max(0, end.timeIntervalSince(now))
    }

    public func isRestOverrun(now: Date) -> Bool {
        guard mode == .rest, let end = plannedRestEnd else { return false }
        return now > end.addingTimeInterval(RestPolicy.grace)
    }

    /// The task title most worth showing right now (current, or next while resting).
    public var headline: String? {
        switch mode {
        case .focus, .think: return taskTitle
        case .rest: return nextTaskTitle
        case .idle: return nextTaskTitle
        }
    }

    /// Distractions should be shielded right now on this device.
    public var shouldShield: Bool { mode.isWorking || systemFocusOn }

    /// Same visible state, ignoring timestamps and live-decaying numbers.
    /// Platforms use this to skip redundant work (rescheduling, widget reloads).
    public func isSameState(as other: LiveSnapshot?) -> Bool {
        guard let other else { return false }
        return mode == other.mode && taskID == other.taskID && taskTitle == other.taskTitle
            && breadcrumb == other.breadcrumb && modeStartedAt == other.modeStartedAt
            && plannedRestEnd == other.plannedRestEnd && nextTaskID == other.nextTaskID
            && nextTaskTitle == other.nextTaskTitle && inPlay == other.inPlay
            && doneToday == other.doneToday && plannedToday == other.plannedToday
            && outcome == other.outcome && dayEnded == other.dayEnded
            && systemFocusOn == other.systemFocusOn && bootsToday == other.bootsToday
            && chain == other.chain
    }

    /// The juggled tasks other than the current one.
    public var juggledOthers: [Item] {
        inPlay.filter { $0.id != taskID }
    }

    /// True while more than one task is in the air.
    public var isJuggling: Bool { inPlay.count > 1 }

    public var progressFraction: Double {
        guard plannedToday > 0 else { return 0 }
        return min(1, Double(doneToday) / Double(plannedToday))
    }
}
