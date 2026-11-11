import SwiftUI
import TrueFocusKit

/// A task's memo, opened from its row: the notes you left yourself for when you come back to it.
/// It's a full note, with the task's title as its first line, so it's in Notes as well.
struct TaskMemoView: View {
    @Environment(FocusController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    let note: Note

    var body: some View {
        NavigationStack {
            NoteEditorView(note: note, onDelete: { dismiss() })
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 360, idealWidth: 760, minHeight: 420, idealHeight: 700)
        #endif
        .onDisappear {
            // After the editor has saved its last words: a memo with nothing in it goes away.
            let controller = controller
            let note = note
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                controller.memoClosed(note)
            }
        }
    }
}
