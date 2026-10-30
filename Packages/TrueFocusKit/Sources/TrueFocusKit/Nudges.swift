import Foundation

/// How hard TrueFocus talks to you.
public enum NudgeTone: String, Codable, Sendable, CaseIterable {
    case calm, direct, savage

    public var label: String {
        switch self {
        case .calm: return "Calm"
        case .direct: return "Direct"
        case .savage: return "Savage"
        }
    }

    /// The line under the label in the tone picker. Savage is the one that swears.
    public var note: String {
        switch self {
        case .calm: return "Gentle"
        case .direct: return "Plain"
        case .savage: return "Strong language"
        }
    }

    /// The label with its warning, for one-line lists and VoiceOver: "Savage · strong language".
    public var fullLabel: String {
        self == .savage ? "\(label) · strong language" : label
    }
}

/// A reminder that should fire at a moment in the future unless the state changes first.
public struct Nudge: Equatable, Sendable {
    /// Stable identifier, e.g. "rest.2". Platforms prefix it when scheduling.
    public var id: String
    public var fireAt: Date
    /// 1 = gentle, 2 = firm, 3 = alarm (full-screen on Mac, time-sensitive on iPhone).
    public var level: Int
    public var title: String
    public var body: String

    public init(id: String, fireAt: Date, level: Int, title: String, body: String) {
        self.id = id
        self.fireAt = fireAt
        self.level = level
        self.title = title
        self.body = body
    }
}

public struct NudgeContext: Sendable {
    public var mode: FlowMode
    public var modeStartedAt: Date?
    public var plannedRestEnd: Date?
    public var taskTitle: String?
    public var nextTaskTitle: String?
    public var openTaskCount: Int
    /// True once the day has been shut down. No nudges after shutdown.
    public var dayEnded: Bool
    /// Idle because you paused on `nextTaskTitle`: gentler, later nudges to resume.
    public var paused: Bool
    /// Idle because you stopped on purpose: the first "start the next one" nudge waits 30 minutes.
    public var stopped: Bool
    public var tone: NudgeTone
    /// Your own words per moment (`TFSettings.customReminders`).
    public var customReminders: CustomReminders
    public var thinkNudgeMinutes: Double
    /// Ask once after 75 minutes of focus, in case the session was forgotten. Off by default:
    /// a long focus segment is usually hyperfocus, and a nudge would break it.
    public var focusCheckIn: Bool
    public var now: Date

    public init(mode: FlowMode, modeStartedAt: Date?, plannedRestEnd: Date? = nil,
                taskTitle: String? = nil, nextTaskTitle: String? = nil, openTaskCount: Int = 0,
                dayEnded: Bool = false, paused: Bool = false, stopped: Bool = false, tone: NudgeTone = .direct,
                customReminders: CustomReminders = CustomReminders(),
                thinkNudgeMinutes: Double = 5, focusCheckIn: Bool = false, now: Date) {
        self.mode = mode
        self.modeStartedAt = modeStartedAt
        self.plannedRestEnd = plannedRestEnd
        self.taskTitle = taskTitle
        self.nextTaskTitle = nextTaskTitle
        self.openTaskCount = openTaskCount
        self.dayEnded = dayEnded
        self.paused = paused
        self.stopped = stopped
        self.tone = tone
        self.customReminders = customReminders
        self.thinkNudgeMinutes = thinkNudgeMinutes
        self.focusCheckIn = focusCheckIn
        self.now = now
    }
}

/// Decides when to poke you. Pure: give it the state, get back the schedule.
/// Every platform re-plans on each state change and cancels what was pending.
public enum NudgePlanner {
    public static func plan(_ context: NudgeContext) -> [Nudge] {
        guard !context.dayEnded else { return [] }
        let copy = Copy(tone: context.tone, custom: context.customReminders)
        var nudges: [Nudge] = []

        switch context.mode {
        case .rest where context.plannedRestEnd == nil:
            // A break you took yourself lasts until you resume. Nothing asks you back.
            break

        case .rest:
            let end = context.plannedRestEnd ?? (context.modeStartedAt ?? context.now).addingTimeInterval(60)
            let next = context.nextTaskTitle
            let steps: [(TimeInterval, Int)] = [(RestPolicy.grace, 1), (120, 2), (300, 3), (600, 3), (1200, 3)]
            for (index, step) in steps.enumerated() {
                let line = copy.restOver(level: step.1, next: next)
                nudges.append(Nudge(id: "rest.\(index)", fireAt: end.addingTimeInterval(step.0),
                                    level: step.1, title: line.title, body: line.body))
            }

        case .think:
            let start = context.modeStartedAt ?? context.now
            let first = max(context.thinkNudgeMinutes, 1) * 60
            let steps: [(TimeInterval, Int)] = [(first, 1), (first * 2, 2), (first * 4, 3)]
            for (index, step) in steps.enumerated() {
                let line = copy.stuck(level: step.1, task: context.taskTitle)
                nudges.append(Nudge(id: "think.\(index)", fireAt: start.addingTimeInterval(step.0),
                                    level: step.1, title: line.title, body: line.body))
            }

        case .focus:
            // A long focus segment is fine; a forgotten one is not. Check in once, if asked to.
            guard context.focusCheckIn else { break }
            let start = context.modeStartedAt ?? context.now
            let line = copy.stillOnIt(task: context.taskTitle)
            nudges.append(Nudge(id: "focus.0", fireAt: start.addingTimeInterval(75 * 60),
                                level: 1, title: line.title, body: line.body))

        case .idle where context.paused:
            // You chose to stop: give the pause room, then ask you back to that task.
            guard let since = context.modeStartedAt else { break }
            let steps: [(TimeInterval, Int)] = [(600, 1), (1500, 2), (3000, 3)]
            for (index, step) in steps.enumerated() {
                let line = copy.paused(level: step.1, task: context.nextTaskTitle)
                nudges.append(Nudge(id: "paused.\(index)", fireAt: since.addingTimeInterval(step.0),
                                    level: step.1, title: line.title, body: line.body))
            }

        case .idle:
            guard context.openTaskCount > 0, let since = context.modeStartedAt else { break }
            // After a deliberate Stop, give the time off room before asking for the next task.
            let steps: [(TimeInterval, Int)] = context.stopped
                ? [(1800, 1), (3000, 2)]
                : [(180, 1), (600, 2), (1500, 3), (3000, 3)]
            for (index, step) in steps.enumerated() {
                let line = copy.idle(level: step.1, next: context.nextTaskTitle, left: context.openTaskCount)
                nudges.append(Nudge(id: "idle.\(index)", fireAt: since.addingTimeInterval(step.0),
                                    level: step.1, title: line.title, body: line.body))
            }
        }

        return nudges.filter { $0.fireAt > context.now }
    }
}
