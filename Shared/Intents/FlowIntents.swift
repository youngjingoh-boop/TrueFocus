import AppIntents
import Foundation
import TrueFocusKit

// The flow verbs as App Intents. Compiled into the app *and* the widget extension, so
// widget buttons, Live Activity buttons and Control Center controls can use them.
//
// On iPhone they adopt LiveActivityIntent, which makes the system run them in the app's
// process even when tapped from a widget or the Lock Screen. If one ever does run inside
// an extension (TF_EXTENSION), it queues the command for the app to apply on next launch.

#if os(iOS)
typealias TFFlowIntent = LiveActivityIntent
#else
typealias TFFlowIntent = AppIntent
#endif

enum IntentRouter {
    @MainActor
    static func run(_ command: RemoteCommand.Kind) {
        run(RemoteCommand(kind: command))
    }

    @MainActor
    static func run(_ command: RemoteCommand) {
        #if TF_EXTENSION
        SharedStore.shared.enqueue(command)
        #else
        FocusController.shared.apply(command)
        #endif
    }
}

struct CompleteTaskIntent: TFFlowIntent {
    static let title: LocalizedStringResource = "Done with Current Task"
    static let description: IntentDescription? = IntentDescription("Crosses off the task you're focused on and starts a micro-rest.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.run(.complete)
        return .result()
    }
}

struct StuckIntent: TFFlowIntent {
    static let title: LocalizedStringResource = "I'm Stuck"
    static let description: IntentDescription? = IntentDescription("Switches the current task to think time. Distractions stay shielded.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.run(.stuck)
        return .result()
    }
}

struct BackToItIntent: TFFlowIntent {
    static let title: LocalizedStringResource = "Back to It"
    static let description: IntentDescription? = IntentDescription("Ends think time or rest and gets you working again.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.run(.backToIt)
        return .result()
    }
}

struct StartNextTaskIntent: TFFlowIntent {
    static let title: LocalizedStringResource = "Start Next Task"
    static let description: IntentDescription? = IntentDescription("Starts focusing on the next task in today's plan.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.run(.startNext)
        return .result()
    }
}

struct WaitOnTaskIntent: TFFlowIntent {
    static let title: LocalizedStringResource = "Waiting on Current Task"
    static let description: IntentDescription? = IntentDescription("Marks the current task as waiting, keeps it juggled, and moves to the next one.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.run(.wait)
        return .result()
    }
}

/// Switches to one of the tasks being juggled. Used by the Live Activity's task chips.
struct SwitchJuggledTaskIntent: TFFlowIntent {
    static let title: LocalizedStringResource = "Switch to Juggled Task"
    static let description: IntentDescription? = IntentDescription("Moves your focus to another task you're juggling.")
    static let isDiscoverable = false

    @Parameter(title: "Task ID")
    var taskID: String

    init() {}

    init(taskID: UUID) {
        self.taskID = taskID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: taskID) {
            IntentRouter.run(RemoteCommand(kind: .switchTo, taskID: id))
        }
        return .result()
    }
}
