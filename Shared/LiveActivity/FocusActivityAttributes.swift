#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation
import TrueFocusKit

/// The Live Activity that keeps the current task on the Lock Screen and in the
/// Dynamic Island. Compiled into the iOS app (which starts and updates it) and the
/// widget extension (which draws it).
struct FocusActivityAttributes: ActivityAttributes {
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

        init(modeRaw: String, title: String? = nil, nextTitle: String? = nil, breadcrumb: String? = nil,
             modeStartedAt: Date? = nil, taskFocusBefore: Double = 0, plannedRestEnd: Date? = nil,
             doneToday: Int = 0, plannedToday: Int = 0, chain: Int = 0, momentum: Int = 0) {
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
                      momentum: snapshot.momentum)
        }

        var mode: FlowMode { FlowMode(rawValue: modeRaw) ?? .idle }

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
