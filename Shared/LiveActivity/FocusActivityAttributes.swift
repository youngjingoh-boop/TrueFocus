#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation
import TrueFocusKit

/// The Live Activity that keeps the current task on the Lock Screen and in the
/// Dynamic Island. Compiled into the iOS app (which starts and updates it) and the
/// widget extension (which draws it).
struct FocusActivityAttributes: ActivityAttributes {
    /// Another task being juggled, small enough for the Lock Screen.
    struct JuggledTask: Codable, Hashable, Identifiable {
        var id: UUID
        var title: String
        var waiting: Bool
    }

    struct ContentState: Codable, Hashable {
        var modeRaw: String
        var title: String?
        var nextTitle: String?
        var breadcrumb: String?
        var modeStartedAt: Date?
        /// Focus already spent on the task before the current segment.
        var taskFocusBefore: Double
        var plannedRestEnd: Date?
        var doneToday: Int
        var plannedToday: Int
        var chain: Int
        var momentum: Int
        /// The other tasks in the air, in slot order. Optional so older states decode.
        var juggling: [JuggledTask]?
        /// Paused on `nextTitle` since then. Optional so older states decode.
        var pausedAt: Date?

        init(modeRaw: String, title: String? = nil, nextTitle: String? = nil, breadcrumb: String? = nil,
             modeStartedAt: Date? = nil, taskFocusBefore: Double = 0, plannedRestEnd: Date? = nil,
             doneToday: Int = 0, plannedToday: Int = 0, chain: Int = 0, momentum: Int = 0,
             juggling: [JuggledTask]? = nil, pausedAt: Date? = nil) {
            self.modeRaw = modeRaw
            self.title = title
            self.nextTitle = nextTitle
            self.breadcrumb = breadcrumb
            self.modeStartedAt = modeStartedAt
            self.taskFocusBefore = taskFocusBefore
            self.plannedRestEnd = plannedRestEnd
            self.doneToday = doneToday
            self.plannedToday = plannedToday
            self.chain = chain
            self.momentum = momentum
            self.juggling = juggling
            self.pausedAt = pausedAt
        }

        init(snapshot: LiveSnapshot) {
            self.init(modeRaw: snapshot.mode.rawValue,
                      title: snapshot.taskTitle,
                      nextTitle: snapshot.nextTaskTitle,
                      breadcrumb: snapshot.breadcrumb,
                      modeStartedAt: snapshot.modeStartedAt,
                      taskFocusBefore: snapshot.taskFocusBefore,
                      plannedRestEnd: snapshot.plannedRestEnd,
                      doneToday: snapshot.doneToday,
                      plannedToday: snapshot.plannedToday,
                      chain: snapshot.chain,
                      momentum: snapshot.momentum,
                      juggling: snapshot.juggledOthers.map {
                          JuggledTask(id: $0.id, title: $0.title, waiting: $0.isWaiting)
                      },
                      pausedAt: snapshot.isPaused ? snapshot.pausedAt : nil)
        }

        var mode: FlowMode { FlowMode(rawValue: modeRaw) ?? .idle }

        var juggled: [JuggledTask] { juggling ?? [] }

        var isPaused: Bool { mode == .idle && pausedAt != nil }

        /// The mode's symbol, or a pause glyph while paused.
        var symbol: String { isPaused ? "pause.fill" : mode.symbol }

        /// The task title worth showing: the current task, or the next one while resting.
        var headline: String {
            let text: String?
            switch mode {
            case .focus, .think: text = title
            case .rest, .idle: text = nextTitle
            }
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "Nothing planned" : trimmed
        }
    }

    /// When the activity was started. Static for its whole life.
    var startedAt: Date

    init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }
}
#endif
