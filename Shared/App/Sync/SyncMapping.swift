import Foundation
import SwiftData
import TrueFocusKit

/// Between the SwiftData models and the sync payloads.
@MainActor
enum SyncMapping {
    /// Every syncable record on the device. Day plans are keyed by their day.
    static func scan(_ context: ModelContext) -> [LocalItem] {
        var items: [LocalItem] = []
        for task in all(FocusTask.self, context) {
            if let data = try? PayloadCoding.encode(task.syncPayload) {
                items.append(LocalItem(id: task.id, kind: .task, payload: data))
            }
        }
        for segment in all(FlowSegment.self, context) {
            if let data = try? PayloadCoding.encode(segment.syncPayload) {
                items.append(LocalItem(id: segment.id, kind: .segment, payload: data))
            }
        }
        for plan in preferredPlans(context) {
            if let data = try? PayloadCoding.encode(plan.syncPayload) {
                items.append(LocalItem(id: RecordID.plan(day: plan.day), kind: .plan, payload: data))
            }
        }
        for note in all(Note.self, context) {
            if let data = try? PayloadCoding.encode(note.syncPayload) {
                items.append(LocalItem(id: note.id, kind: .note, payload: data))
            }
        }
        // Duplicate IDs (left over from an older store) count once.
        var seen = Set<UUID>()
        return items.filter { seen.insert($0.id).inserted }
    }

    /// The record's payload as this device encodes it, or nil if it isn't here.
    static func payload(_ kind: RecordKind, id: UUID, in context: ModelContext) -> Data? {
        switch kind {
        case .task: return task(id, context).flatMap { try? PayloadCoding.encode($0.syncPayload) }
        case .segment: return segment(id, context).flatMap { try? PayloadCoding.encode($0.syncPayload) }
        case .plan: return plan(id, context).flatMap { try? PayloadCoding.encode($0.syncPayload) }
        case .note: return note(id, context).flatMap { try? PayloadCoding.encode($0.syncPayload) }
        }
    }

    /// Writes a server version into the store (nil payload deletes). False if it couldn't be read,
    /// for example a payload from a newer app version; the record is then left alone.
    @discardableResult
    static func apply(_ kind: RecordKind, id: UUID, payload: Data?, in context: ModelContext) -> Bool {
        switch kind {
        case .task:
            let existing = task(id, context)
            guard let payload else { if let existing { context.delete(existing) }; return true }
            guard let value = try? PayloadCoding.decode(TaskPayload.self, from: payload) else { return false }
            let task = existing ?? {
                let task = FocusTask(title: value.title, order: value.order)
                task.id = id
                context.insert(task)
                return task
            }()
            task.apply(value)
        case .segment:
            let existing = segment(id, context)
            guard let payload else { if let existing { context.delete(existing) }; return true }
            guard let value = try? PayloadCoding.decode(SegmentPayload.self, from: payload) else { return false }
            let segment = existing ?? {
                let segment = FlowSegment(mode: FlowMode(rawValue: value.mode) ?? .focus, taskID: value.taskID,
                                          taskTitle: value.taskTitle, startedAt: value.startedAt, device: value.device)
                segment.id = id
                context.insert(segment)
                return segment
            }()
            segment.apply(value)
        case .plan:
            guard let payload else { if let plan = plan(id, context) { context.delete(plan) }; return true }
            guard let value = try? PayloadCoding.decode(PlanPayload.self, from: payload) else { return false }
            let plan = preferred(plans(on: value.day, context)) ?? {
                let plan = DayPlan(day: value.day)
                context.insert(plan)
                return plan
            }()
            plan.apply(value)
        case .note:
            let existing = note(id, context)
            guard let payload else { if let existing { context.delete(existing) }; return true }
            guard let value = try? PayloadCoding.decode(NotePayload.self, from: payload) else { return false }
            let note = existing ?? {
                let note = Note(body: value.body)
                note.id = id
                context.insert(note)
                return note
            }()
            note.apply(value)
        }
        return true
    }

    // MARK: Fetching

    private static func all<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    private static func task(_ id: UUID, _ context: ModelContext) -> FocusTask? {
        var descriptor = FetchDescriptor<FocusTask>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func segment(_ id: UUID, _ context: ModelContext) -> FlowSegment? {
        var descriptor = FetchDescriptor<FlowSegment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func note(_ id: UUID, _ context: ModelContext) -> Note? {
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func plan(_ id: UUID, _ context: ModelContext) -> DayPlan? {
        preferredPlans(context).first { RecordID.plan(day: $0.day) == id }
    }

    private static func plans(on day: Date, _ context: ModelContext) -> [DayPlan] {
        (try? context.fetch(FetchDescriptor<DayPlan>(predicate: #Predicate { $0.day == day }))) ?? []
    }

    /// One plan per day, chosen the way `FocusController.refresh` chooses it.
    private static func preferredPlans(_ context: ModelContext) -> [DayPlan] {
        Dictionary(grouping: all(DayPlan.self, context), by: \.day).values.compactMap(preferred)
    }

    private static func preferred(_ plans: [DayPlan]) -> DayPlan? {
        plans.first { !$0.outcome.isEmpty } ?? plans.first
    }
}

extension FocusTask {
    var syncPayload: TaskPayload {
        TaskPayload(title: title, isDone: isDone, doneAt: doneAt, createdAt: createdAt, order: order,
                    focusSeconds: focusSeconds, breadcrumb: breadcrumb, inPlay: inPlay, inPlayAt: inPlayAt,
                    waitingSince: waitingSince)
    }

    func apply(_ value: TaskPayload) {
        title = value.title
        isDone = value.isDone
        doneAt = value.doneAt
        createdAt = value.createdAt
        order = value.order
        focusSeconds = value.focusSeconds
        breadcrumb = value.breadcrumb
        inPlay = value.inPlay
        inPlayAt = value.inPlayAt
        waitingSince = value.waitingSince
    }
}

extension FlowSegment {
    var syncPayload: SegmentPayload {
        SegmentPayload(mode: modeRaw, taskID: taskID, taskTitle: taskTitle, startedAt: startedAt, endedAt: endedAt,
                       outcome: outcomeRaw, plannedSeconds: plannedSeconds, device: device)
    }

    func apply(_ value: SegmentPayload) {
        modeRaw = value.mode
        taskID = value.taskID
        taskTitle = value.taskTitle
        startedAt = value.startedAt
        endedAt = value.endedAt
        outcomeRaw = value.outcome
        plannedSeconds = value.plannedSeconds
        device = value.device
    }
}

extension DayPlan {
    var syncPayload: PlanPayload {
        PlanPayload(day: day, outcome: outcome, brainDump: brainDump, bootCount: bootCount,
                    endedAt: endedAt, reflection: reflection)
    }

    func apply(_ value: PlanPayload) {
        day = value.day
        outcome = value.outcome
        brainDump = value.brainDump
        bootCount = value.bootCount
        endedAt = value.endedAt
        reflection = value.reflection
    }
}

extension Note {
    var syncPayload: NotePayload {
        NotePayload(body: body, createdAt: createdAt, updatedAt: updatedAt, isPinned: isPinned)
    }

    func apply(_ value: NotePayload) {
        body = value.body
        createdAt = value.createdAt
        updatedAt = value.updatedAt
        isPinned = value.isPinned
    }
}
