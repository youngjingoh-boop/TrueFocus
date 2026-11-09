import Foundation

/// How much a task matters. Stored as its raw value.
public enum TaskPriority: Int, CaseIterable, Sendable {
    case none = 0
    case important = 1
    case top = 2

    public init(stored: Int) {
        self = TaskPriority(rawValue: stored) ?? .none
    }

    public var label: String {
        switch self {
        case .none: return "No Priority"
        case .important: return "Important"
        case .top: return "Top Priority"
        }
    }
}

/// Where a task sits on the plan.
public enum PlanBucket: String, CaseIterable, Sendable {
    case today, tomorrow, later

    public var label: String {
        switch self {
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .later: return "Later"
        }
    }
}

/// When a task is planned for. A task stores a date, not a bucket, so tomorrow's tasks become
/// today's by themselves when the day turns over:
///
///     nil, or a day that has arrived   Today
///     the next day                     Tomorrow
///     any day after that               Later, until that day comes
///     `someday`                        Later, until you move it
public enum PlanSchedule {
    public static let someday = Date.distantFuture

    public static func bucket(plannedFor: Date?, now: Date, calendar: Calendar = .current) -> PlanBucket {
        guard let plannedFor else { return .today }
        let today = calendar.tfDayStart(for: now)
        if plannedFor <= today { return .today }
        return plannedFor < nextDay(after: today, days: 2, calendar: calendar) ? .tomorrow : .later
    }

    /// What to store for a task moved into `bucket`.
    public static func plannedFor(_ bucket: PlanBucket, now: Date, calendar: Calendar = .current) -> Date? {
        switch bucket {
        case .today: return nil
        case .tomorrow: return nextDay(after: calendar.tfDayStart(for: now), days: 1, calendar: calendar)
        case .later: return someday
        }
    }

    private static func nextDay(after day: Date, days: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: days, to: day) ?? day.addingTimeInterval(Double(days) * 86_400)
    }

    /// Dividers typed as tasks, like "----- TOMORROW -----": the plan's old way of showing days.
    public static func divider(in title: String, now: Date, calendar: Calendar = .current) -> Divider? {
        let pattern = #"^[-–—=_*~ ]{3,}([\p{L} ]+?)[-–—=_*~ ]{3,}$"#
        guard let range = title.range(of: pattern, options: .regularExpression) else { return nil }
        let name = title[range]
            .trimmingCharacters(in: CharacterSet(charactersIn: "-–—=_*~ "))
            .lowercased()
        let today = calendar.tfDayStart(for: now)
        switch name {
        case "today", "now":
            return Divider(plannedFor: nil)
        case "tomorrow":
            return Divider(plannedFor: nextDay(after: today, days: 1, calendar: calendar))
        case "the day after tomorrow", "day after tomorrow":
            return Divider(plannedFor: nextDay(after: today, days: 2, calendar: calendar))
        case "later", "someday", "maybe", "maybe later", "next week":
            return Divider(plannedFor: someday)
        default:
            return nil
        }
    }

    public struct Divider: Equatable, Sendable {
        /// What the tasks under the divider are planned for.
        public var plannedFor: Date?
    }

    /// Reads old dividers out of an ordered plan: which rows were dividers, and what each task
    /// under one is now planned for. Tasks above the first divider aren't touched.
    public static func convertDividers(_ tasks: [(id: UUID, title: String)], now: Date,
                                       calendar: Calendar = .current) -> (dividers: [UUID], plannedFor: [UUID: Date?]) {
        var dividers: [UUID] = []
        var plans: [UUID: Date?] = [:]
        var active: Divider?
        for task in tasks {
            if let divider = divider(in: task.title, now: now, calendar: calendar) {
                dividers.append(task.id)
                active = divider
            } else if let active {
                plans[task.id] = active.plannedFor
            }
        }
        return (dividers, plans)
    }
}

/// The plan as one list: Today's tasks, then a heading and the tasks for each later bucket,
/// with a "New task" line closing each bucket. Being one list is what lets a task be dragged
/// across a heading, which is how it moves to another day.
public enum PlanLayout {
    public enum Row: Hashable, Sendable {
        case task(UUID)
        case heading(PlanBucket)
        case newTask(PlanBucket)
    }

    public static func rows(_ tasks: [(id: UUID, bucket: PlanBucket)]) -> [Row] {
        PlanBucket.allCases.flatMap { bucket -> [Row] in
            let heading: [Row] = bucket == .today ? [] : [.heading(bucket)]
            return heading + tasks.filter { $0.bucket == bucket }.map { .task($0.id) } + [.newTask(bucket)]
        }
    }

    /// Applies a list move (`onMove` offsets) and reads the plan back: every task in its new
    /// order, in the bucket of the heading above it. Headings and new-task lines stay put.
    public static func move(_ rows: [Row], fromOffsets source: IndexSet, toOffset destination: Int) -> [(id: UUID, bucket: PlanBucket)] {
        var reordered = rows
        let movable = source.filter { index in
            guard rows.indices.contains(index), case .task = rows[index] else { return false }
            return true
        }.sorted()
        let moving = movable.map { rows[$0] }
        for index in movable.reversed() { reordered.remove(at: index) }
        let before = movable.filter { $0 < destination }.count
        reordered.insert(contentsOf: moving, at: max(0, min(reordered.count, destination - before)))

        var bucket = PlanBucket.today
        var result: [(id: UUID, bucket: PlanBucket)] = []
        for row in reordered {
            switch row {
            case .heading(let next): bucket = next
            case .task(let id): result.append((id, bucket))
            case .newTask: break
            }
        }
        return result
    }
}
