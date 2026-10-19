import AppIntents
import Foundation
import TrueFocusKit

// App-only intents: Siri, Spotlight, Shortcuts, the Action Button, and the Focus filter.

struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task"
    static let description: IntentDescription? = IntentDescription("Adds a task to the end of today's plan.")

    @Parameter(title: "Task", requestValueDialog: "What do you need to do?")
    var taskTitle: String

    init() {}

    init(taskTitle: String) {
        self.taskTitle = taskTitle
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$taskTitle) to today")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        FocusController.shared.addTask(taskTitle)
        return .result(dialog: "Added.")
    }
}

struct CurrentTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "What Am I Working On"
    static let description: IntentDescription? = IntentDescription("Says the task you're focused on and how long you've been on it.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let snapshot = FocusController.shared.snapshot
        let title = snapshot.headline ?? "Nothing yet"
        let line: String
        switch snapshot.mode {
        case .focus:
            line = "\(title). \(TFFormat.short(snapshot.taskElapsed(now: Date()))) in."
        case .think:
            line = "Thinking through \(title)."
        case .rest:
            line = "Resting. Next: \(title)."
        case .idle:
            line = snapshot.nextTaskTitle.map { "Nothing running. Next up: \($0)." } ?? "Nothing planned."
        }
        return .result(value: title, dialog: IntentDialog(stringLiteral: line))
    }
}

struct EndDayIntent: AppIntent {
    static let title: LocalizedStringResource = "Shut Down the Day"
    static let description: IntentDescription? = IntentDescription("Stops the clock and the nudges. Unfinished tasks roll to tomorrow.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        FocusController.shared.endDay()
        return .result()
    }
}

struct OpenTrueFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Focus Screen"
    static let description: IntentDescription? = IntentDescription("Opens TruFocus on the immersive focus screen.")
    static let openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        FocusController.shared.isFocusScreenPresented = FocusController.shared.mode.isActive
        return .result()
    }
}

struct TFShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CompleteTaskIntent(),
            phrases: ["Done in \(.applicationName)", "Cross it off in \(.applicationName)"],
            shortTitle: "Done",
            systemImageName: "checkmark.circle.fill"
        )
        AppShortcut(
            intent: StartNextTaskIntent(),
            phrases: ["Next task in \(.applicationName)", "Start the next task in \(.applicationName)"],
            shortTitle: "Next Task",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: StuckIntent(),
            phrases: ["I'm stuck in \(.applicationName)"],
            shortTitle: "I'm Stuck",
            systemImageName: "brain"
        )
        AppShortcut(
            intent: BackToItIntent(),
            phrases: ["Back to it in \(.applicationName)"],
            shortTitle: "Back to It",
            systemImageName: "arrow.uturn.forward"
        )
        AppShortcut(
            intent: PauseIntent(),
            phrases: ["Pause \(.applicationName)", "Pause focus in \(.applicationName)"],
            shortTitle: "Pause",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: ResumeIntent(),
            phrases: ["Resume \(.applicationName)", "Resume focus in \(.applicationName)"],
            shortTitle: "Resume",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: ["Add a task in \(.applicationName)", "Add to \(.applicationName)"],
            shortTitle: "Add Task",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: CurrentTaskIntent(),
            phrases: ["What am I working on in \(.applicationName)"],
            shortTitle: "Current Task",
            systemImageName: "scope"
        )
    }
}

/// Add TrueFocus to a system Focus (Settings ▸ Focus ▸ Work ▸ Focus Filters) and turn on
/// "Deep Work shields". With "Share Across Devices" on, turning that Focus on from your Mac
/// raises the shields on your iPhone too — and silences notifications on both.
struct TrueFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "TruFocus"
    static let description: IntentDescription? = IntentDescription("Shields distracting apps and pins your current task while this Focus is on.")

    @Parameter(title: "Deep Work shields", default: false)
    var deepWork: Bool

    init() {}

    var displayRepresentation: DisplayRepresentation {
        let title: LocalizedStringResource = deepWork ? "Deep Work shields on" : "Shields off"
        let subtitle: LocalizedStringResource = deepWork ? "Distractions shielded while this Focus is on" : "Turn on to shield distractions"
        return DisplayRepresentation(title: title, subtitle: subtitle)
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // The system calls this again with default values when the Focus turns off.
        FocusController.shared.focusFilterChanged(deepWork: deepWork)
        return .result()
    }
}
