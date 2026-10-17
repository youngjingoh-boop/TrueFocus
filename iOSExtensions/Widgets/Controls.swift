import AppIntents
import SwiftUI
import WidgetKit

// Control Center / Lock Screen / Action Button controls.

struct DoneControl: ControlWidget {
    static let kind = "app.truefocus.control.done"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: CompleteTaskIntent()) {
                Label("Done", systemImage: "checkmark.circle.fill")
            }
        }
        .displayName("Done with Task")
        .description("Cross off the task you're focused on and take a micro-rest.")
    }
}

struct NextTaskControl: ControlWidget {
    static let kind = "app.truefocus.control.next"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartNextTaskIntent()) {
                Label("Next Task", systemImage: "bolt.fill")
            }
        }
        .displayName("Start Next Task")
        .description("Start focusing on the next task in today's plan.")
    }
}
