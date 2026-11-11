import SwiftData
import SwiftUI
import TrueFocusKit

@main
struct TrueFocusMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate

    private let controller = FocusController.shared
    private let ui = MacUIState.shared

    var body: some Scene {
        Window("TruFocus", id: "main") {
            MacRootView()
                .environment(controller)
                .environment(ui)
                .modelContainer(controller.container)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 740)
        .commands {
            FlowCommands(controller: controller, ui: ui)
        }

        MenuBarExtra {
            MenuBarPanel()
                .environment(controller)
                .environment(ui)
                .modelContainer(controller.container)
        } label: {
            MenuBarLabel()
                .environment(controller)
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacSettingsView()
                .environment(controller)
                .modelContainer(controller.container)
        }
    }
}

/// The menu bar's Flow menu. Shortcuts here work whenever TrueFocus is the front app;
/// the ⌥⌘ global hotkeys (HotKeys.swift) work everywhere.
struct FlowCommands: Commands {
    let controller: FocusController
    let ui: MacUIState
    private var zoom: TFZoom { TFZoom.shared }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") {
                ui.section = .today
                ui.showQuickAdd = true
                WindowOpener.shared.openMain()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Flow") {
            Button("Done with Current Task") { controller.complete() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("I'm Stuck") { controller.stuck() }
                .keyboardShortcut(".", modifiers: .command)
            Button("Back to It") { controller.backToIt() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            Button("Start Next Task") { controller.startNext() }
                .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Focus Screen") {
                controller.isFocusScreenPresented.toggle()
                WindowOpener.shared.openMain()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button(controller.isPaused || controller.isOnBreak ? "Resume" : "Pause") { controller.togglePause() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Take a Break") { controller.takeBreak() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Stop Task") { controller.stop() }
                .keyboardShortcut(".", modifiers: [.command, .shift])

            Divider()

            Button("Shut Down the Day") { controller.endDay() }
        }

        CommandGroup(after: .sidebar) {
            Button("Today") { show(.today) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Notes") { show(.notes) }
                .keyboardShortcut("2", modifiers: .command)
            Button("Review") { show(.review) }
                .keyboardShortcut("3", modifiers: .command)

            Divider()

            // ⌘= works as well as ⌘+ (MacAppDelegate), like a browser.
            Button("Zoom In") { TFZoom.shared.step(1) }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!zoom.canZoomIn)
            Button("Zoom Out") { TFZoom.shared.step(-1) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!zoom.canZoomOut)
            Button("Actual Size") { TFZoom.shared.step(0) }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(zoom.scale == 1)
        }
    }

    private func show(_ section: MacSection) {
        ui.section = section
        controller.isFocusScreenPresented = false
        WindowOpener.shared.openMain()
    }
}
