import SwiftData
import SwiftUI
import TrueFocusKit

/// One note, full-bleed, like Apple Notes. Saves as you type (debounced), and can send
/// its open checklist items to today's plan.
struct NoteEditorView: View {
    var note: Note
    /// Called after the note is deleted from the editor (the Mac clears its selection).
    var onDelete: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var handle = NoteEditorHandle()
    @State private var pendingMarkup: String?
    @State private var saveTask: Task<Void, Never>?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var isGone = false

    var body: some View {
        Group {
            if isGone || !note.isLive {
                TF.Palette.paper
            } else {
                NoteTextView(noteID: note.id, markup: note.body, handle: handle,
                             autofocus: note.body.isEmpty) { markup in
                    scheduleSave(markup)
                }
            }
        }
        .background(TF.Palette.paper.ignoresSafeArea())
        .overlay(alignment: .bottom) { toastView }
        .toolbar { toolbarContent }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onDisappear(perform: flush)
        // Leaving the app (Home, the app switcher, a call) saves at once: a swipe-quit right
        // after typing shouldn't lose the last words to the save delay.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveNow() }
        }
    }

    private var openItems: [String] {
        NoteDocument(markup: pendingMarkup ?? note.body).openChecklistItems
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if !openItems.isEmpty {
                Button(action: sendToToday) {
                    Label("Send to Today", systemImage: "sun.max")
                }
                .help("Add open checklist items to today's plan")
            }
            Menu {
                formatMenu
            } label: {
                Label("Format", systemImage: "textformat")
            }
            .help("Format: styles, lists, indent and text size")
            Button {
                handle.toggleChecklist()
            } label: {
                Label("Checklist", systemImage: "checklist")
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .help("Checklist (⇧⌘L)")

            Menu {
                Button(action: sendToToday) {
                    Label("Send Open Items to Today", systemImage: "sun.max")
                }
                Button {
                    handle.toggleDone()
                } label: {
                    Label("Mark as Checked", systemImage: "checkmark.circle")
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                Button(action: togglePin) {
                    Label(note.isPinned ? "Unpin Note" : "Pin Note", systemImage: note.isPinned ? "pin.slash" : "pin")
                }
                Divider()
                Button(role: .destructive, action: deleteNote) {
                    Label("Delete Note", systemImage: "trash")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    /// Apple Notes' Aa menu, with its keyboard shortcuts.
    @ViewBuilder
    private var formatMenu: some View {
        Section {
            Button("Heading") { handle.applyStyle(.heading) }.keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Subheading") { handle.applyStyle(.subheading) }.keyboardShortcut("j", modifiers: [.command, .shift])
            Button("Body") { handle.applyStyle(.text) }.keyboardShortcut("b", modifiers: [.command, .shift])
            Button("Monostyled") { handle.applyStyle(.mono) }.keyboardShortcut("m", modifiers: [.command, .shift])
        }
        Section {
            Button("Bulleted List", systemImage: "list.bullet") { handle.applyStyle(.bullet) }
                .keyboardShortcut("7", modifiers: [.command, .shift])
            Button("Dashed List", systemImage: "list.dash") { handle.applyStyle(.dashed) }
                .keyboardShortcut("8", modifiers: [.command, .shift])
            Button("Numbered List", systemImage: "list.number") { handle.applyStyle(.numbered) }
                .keyboardShortcut("9", modifiers: [.command, .shift])
            Button("Block Quote", systemImage: "text.quote") { handle.applyStyle(.quote) }
                .keyboardShortcut("'", modifiers: [.command])
        }
        Section {
            Button("Indent", systemImage: "increase.indent") { handle.indent() }
                .keyboardShortcut("]", modifiers: [.command])
            Button("Outdent", systemImage: "decrease.indent") { handle.outdent() }
                .keyboardShortcut("[", modifiers: [.command])
        }
        Section("Text Size") {
            Button("Larger", systemImage: "plus.magnifyingglass") { NoteFormatter.stepTextScale(1) }
                .keyboardShortcut("+", modifiers: [.command, .option])
            Button("Smaller", systemImage: "minus.magnifyingglass") { NoteFormatter.stepTextScale(-1) }
                .keyboardShortcut("-", modifiers: [.command, .option])
            Button("Default Size") { NoteFormatter.stepTextScale(0) }
        }
    }

    // MARK: Toast

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(TF.Palette.signal)
                Text(toast)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(TF.Palette.paper)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Capsule().fill(TF.Palette.ink))
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
            .padding(.bottom, 28)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(TF.Motion.snappy) { toast = message }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(TF.Motion.soft) { toast = nil }
        }
    }

    // MARK: Saving

    private func scheduleSave(_ markup: String) {
        pendingMarkup = markup
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            commit(markup)
        }
    }

    private func commit(_ markup: String) {
        pendingMarkup = nil
        guard !isGone, note.isLive, note.body != markup else { return }
        note.body = markup
        note.updatedAt = Date()
        try? modelContext.save()
    }

    private func flush() {
        saveTask?.cancel()
        if let pending = pendingMarkup { commit(pending) }
    }

    /// Saves exactly what's on screen now.
    private func saveNow() {
        saveTask?.cancel()
        if let live = handle.currentMarkup() ?? pendingMarkup { commit(live) }
    }

    // MARK: Actions

    private func sendToToday() {
        if let live = handle.currentMarkup() { commit(live) }
        let controller = FocusController.shared
        let existing = Set(controller.openTasks.map { $0.title.lowercased() })
        let items = NoteDocument(markup: note.body).openChecklistItems.filter { !existing.contains($0.lowercased()) }
        guard !items.isEmpty else {
            showToast("Already on today's plan")
            return
        }
        controller.addTasks(items)
        TFHaptics.success()
        showToast(items.count == 1 ? "Added 1 task to Today" : "Added \(items.count) tasks to Today")
    }

    private func togglePin() {
        guard note.isLive else { return }
        note.isPinned.toggle()
        try? modelContext.save()
    }

    private func deleteNote() {
        saveTask?.cancel()
        pendingMarkup = nil
        isGone = true
        let context = modelContext
        let doomed = note
        if let onDelete {
            onDelete()
        } else {
            dismiss()
        }
        // Delete after the editor is off screen so nothing reads a deleted model.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            context.delete(doomed)
            try? context.save()
        }
    }
}
