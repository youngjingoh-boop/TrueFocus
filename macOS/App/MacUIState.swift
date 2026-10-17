import AppKit
import Observation
import SwiftUI
import TrueFocusKit

enum MacSection: String, CaseIterable, Identifiable {
    case today, notes, review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .notes: return "Notes"
        case .review: return "Review"
        }
    }
}

/// Window-level UI state that menu commands and hotkeys also need to reach.
@MainActor
@Observable
final class MacUIState {
    static let shared = MacUIState()

    var section: MacSection = .today
    /// The floating "new task" capture bar (⌘N).
    var showQuickAdd = false
}

/// Opens or raises the main window from anywhere (hotkeys, menu bar, Dock, URLs).
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()

    /// Captured from a SwiftUI view so code outside the view tree can open scenes.
    var openWindow: OpenWindowAction?

    func openMain() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true && $0.canBecomeMain }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            return
        }
        openWindow?.callAsFunction(id: "main")
    }
}

/// `truefocus://done`, `stuck`, `back`, `next`, `focus`, `today`, `notes`, `review`,
/// `add?title=…`, `end` — handy for Raycast, Stream Deck, or other automations.
enum MacURLRouter {
    @MainActor
    static func handle(_ url: URL) {
        guard url.scheme == "truefocus" else { return }
        let controller = FocusController.shared
        let ui = MacUIState.shared
        let route = (url.host ?? url.path).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch route {
        case "done": controller.complete()
        case "stuck": controller.stuck()
        case "back": controller.backToIt()
        case "next": controller.startNext()
        case "end": controller.endDay()
        case "focus":
            controller.isFocusScreenPresented = controller.mode.isActive
            WindowOpener.shared.openMain()
        case "today", "notes", "review":
            ui.section = MacSection(rawValue: route) ?? .today
            WindowOpener.shared.openMain()
        case "add":
            let title = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "title" })?.value ?? ""
            if !title.trimmingCharacters(in: .whitespaces).isEmpty {
                controller.addTask(title)
            } else {
                ui.section = .today
                ui.showQuickAdd = true
                WindowOpener.shared.openMain()
            }
        default:
            WindowOpener.shared.openMain()
        }
    }
}
