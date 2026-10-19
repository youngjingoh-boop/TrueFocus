import Foundation
import SwiftData
import TrueFocusKit

// SwiftData models, kept on each device and synced by `SyncService` so iPhone and Mac
// share one plan. Records reference each other by UUID rather than relationships, and
// every field has a mirror in the sync payloads (`SyncMapping`).

/// A task on the plan.
@Model
final class FocusTask {
    var id: UUID = UUID()
    var title: String = ""
    var isDone: Bool = false
    var doneAt: Date?
    var createdAt: Date = Date()
    /// Sort key. Fractional so inserting between two tasks never renumbers the list.
    var order: Double = 0
    /// Focus time spent on this task across all closed segments.
    var focusSeconds: Double = 0
    /// "Where I left off": the next step, written when switching away.
    var breadcrumb: String = ""
    /// Being juggled: one of the few tasks in the air at once.
    var inPlay: Bool = false
    /// When it joined the juggle. Orders the juggle, so tasks keep their slots.
    var inPlayAt: Date?
    /// Juggling: set while you're waiting on someone or something for this task.
    var waitingSince: Date?

    init(title: String, order: Double) {
        self.id = UUID()
        self.title = title
        self.order = order
        self.createdAt = Date()
    }
}

extension FocusTask {
    /// Still in the store. A deleted task must not be read or written again.
    var isLive: Bool { !isDeleted && modelContext != nil }
}

/// One contiguous block of a single mode. The day is a timeline of these.
@Model
final class FlowSegment {
    var id: UUID = UUID()
    var modeRaw: String = "focus"
    var taskID: UUID?
    var taskTitle: String = ""
    var startedAt: Date = Date()
    var endedAt: Date?
    var outcomeRaw: String?
    /// Rest segments: the planned length of the micro-rest.
    var plannedSeconds: Double?
    /// Which device opened the segment ("iPhone", "Mac").
    var device: String = ""

    init(mode: FlowMode, taskID: UUID?, taskTitle: String, startedAt: Date,
         plannedSeconds: Double? = nil, device: String) {
        self.id = UUID()
        self.modeRaw = mode.rawValue
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.startedAt = startedAt
        self.plannedSeconds = plannedSeconds
        self.device = device
    }

    var mode: FlowMode {
        FlowMode(rawValue: modeRaw) ?? .focus
    }

    var outcome: SegmentOutcome? {
        outcomeRaw.flatMap(SegmentOutcome.init(rawValue:))
    }

    var record: SegmentRecord {
        SegmentRecord(mode: mode, taskID: taskID, start: startedAt, end: endedAt,
                      outcome: outcome, plannedSeconds: plannedSeconds)
    }

    func duration(now: Date = Date()) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }
}

/// The day's intent: the outcome that makes it a win, the morning brain dump, the shutdown.
@Model
final class DayPlan {
    /// `Calendar.tfDayStart` of the day this plan belongs to.
    var day: Date = Date()
    var outcome: String = ""
    var brainDump: String = ""
    var bootCount: Int = 0
    var endedAt: Date?
    var reflection: String = ""

    init(day: Date) {
        self.day = day
    }
}

/// A free-form note, stored as NoteDocument markup (title line, text, checklists).
@Model
final class Note {
    var id: UUID = UUID()
    var body: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isPinned: Bool = false

    init(body: String = "") {
        self.id = UUID()
        self.body = body
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var document: NoteDocument { NoteDocument(markup: body) }
}

extension Note {
    /// Still in the store. Once a delete is saved (here, or synced from another device)
    /// `isDeleted` reads false again, so check the context too before touching the note.
    var isLive: Bool { !isDeleted && modelContext != nil }
}
