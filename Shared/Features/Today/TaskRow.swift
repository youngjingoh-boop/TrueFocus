import SwiftUI
import TrueFocusKit

/// One task on the plan. Reads and edits like a line in an Apple Notes checklist:
/// same body text style, tap the circle to cross it off, tap the text to edit.
struct TaskRow: View {
    @Environment(FocusController.self) private var controller
    let task: FocusTask
    /// Tighter lines once the plan gets long, so 15–20 tasks fit on one screen.
    var dense = false
    /// Called when Return is pressed, so the list can open a new line below.
    var onReturn: (FocusTask) -> Void = { _ in }

    @State private var draft = ""
    @FocusState private var editing: Bool

    private var isNow: Bool { controller.nowTask?.id == task.id }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CheckCircle(isOn: task.isDone, tint: isNow ? TF.tint(for: controller.mode) : TF.Palette.signal,
                        label: task.title) {
                TFHaptics.success()
                withAnimation(TF.Motion.snappy) { controller.toggleDone(task) }
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                TextField("Task", text: $draft, axis: .vertical)
                    .font(.body)
                    .textFieldStyle(.plain)
                    .foregroundStyle(task.isDone ? TF.Palette.ink3 : TF.Palette.ink)
                    .strikethrough(task.isDone, color: TF.Palette.ink3)
                    .focused($editing)
                    .disabled(task.isDone)
                    .onChange(of: draft) { _, value in
                        // Return ends the line (Notes behaviour) instead of inserting a newline.
                        guard value.contains("\n") else { return }
                        draft = value.replacingOccurrences(of: "\n", with: "")
                        commit()
                        editing = false
                        onReturn(task)
                    }
                    .onChange(of: editing) { _, isEditing in
                        if !isEditing { commit() }
                    }

                if !task.breadcrumb.isEmpty, !task.isDone {
                    Text("↳ \(task.breadcrumb)")
                        .font(.footnote)
                        .foregroundStyle(TF.Palette.ink2)
                        .lineLimit(2)
                }
                if task.focusSeconds >= 60 || isNow || task.inPlay {
                    meta
                }
            }

            Spacer(minLength: 4)

            trailing
        }
        .padding(.vertical, TaskRowMetrics.padding(dense: dense))
        .contentShape(Rectangle())
        .onAppear { draft = task.title }
        .onChange(of: task.title) { _, title in
            if !editing { draft = title }
        }
        .modifier(RowMenu(enabled: rowMenuEnabled) { menu })
        .opacity(task.isDone ? 0.75 : 1)
    }

    private var meta: some View {
        HStack(spacing: 6) {
            if isNow {
                ModeDot(mode: controller.mode, size: 6)
                Text(controller.mode == .think ? "thinking" : "in focus")
            }
            if task.focusSeconds >= 60 {
                Text(TFFormat.short(task.focusSeconds))
            }
            if task.waitingSince != nil && !isNow {
                Image(systemName: "hourglass")
                Text("waiting")
            } else if task.inPlay && !isNow {
                Text("juggling")
            }
        }
        .font(.tfCaption)
        .foregroundStyle(isNow ? TF.tint(for: controller.mode) : TF.Palette.ink3)
    }

    @ViewBuilder
    private var trailing: some View {
        if !task.isDone && !isNow {
            Button {
                TFHaptics.tap()
                controller.start(task)
                #if os(iOS)
                controller.isFocusScreenPresented = true
                #endif
            } label: {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TF.Palette.ink3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -10)
            .padding(.trailing, -8)
            .accessibilityLabel("Start \(task.title)")
            .help("Focus on this")
        }
    }

    @ViewBuilder
    private var menu: some View {
        if !task.isDone {
            Button("Focus on This", systemImage: "bolt.fill") { controller.start(task) }
            if task.inPlay {
                Button("Drop from Juggle", systemImage: "minus.circle") { controller.drop(task) }
            } else {
                Button("Juggle", systemImage: "square.stack.3d.up") { controller.juggle(task) }
                    .disabled(!controller.canJuggleMore)
            }
            if !isNow {
                Button(task.waitingSince != nil ? "Not Waiting Anymore" : "Waiting on It", systemImage: "hourglass") {
                    controller.setWaiting(task, task.waitingSince == nil)
                }
            }
            Button("Do Next", systemImage: "arrow.up.to.line") { controller.makeNext(task) }
        } else {
            Button("Mark Not Done", systemImage: "arrow.uturn.backward") { controller.toggleDone(task) }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { controller.delete(task) }
    }

    /// iPhone: holding an open task picks it up to reorder (in either direction), so its
    /// actions live behind a swipe (More) instead of a long-press menu, which would win the
    /// gesture. Done tasks don't reorder, so they keep the menu. The Mac uses right-click.
    private var rowMenuEnabled: Bool {
        #if os(iOS)
        task.isDone
        #else
        true
        #endif
    }

    private func commit() {
        guard task.isLive else { return }
        let clean = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            // An emptied line disappears, like deleting a checklist line in Notes.
            if !task.isDone { controller.delete(task) }
        } else if clean != task.title {
            controller.rename(task, to: clean)
        }
    }
}

/// The "New task" line at the bottom of the plan. Return adds and keeps the cursor,
/// so a whole list goes in without touching the screen.
struct NewTaskRow: View {
    @Environment(FocusController.self) private var controller
    @Binding var isFocused: Bool
    var dense = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .strokeBorder(TF.Palette.ink3.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 3]))
                .frame(width: 22, height: 22)
                .padding(.top, 1)
            TextField("New task", text: $text, axis: .vertical)
                .font(.body)
                .textFieldStyle(.plain)
                .foregroundStyle(TF.Palette.ink)
                .focused($focused)
                .onChange(of: text) { _, value in
                    guard value.contains("\n") else { return }
                    let lines = value.components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    text = ""
                    if lines.count > 1 {
                        controller.addTasks(lines)
                    } else if let line = lines.first {
                        withAnimation(TF.Motion.snappy) { _ = controller.addTask(line) }
                    }
                    focused = true
                }
                .onSubmit { submit() }
        }
        .padding(.vertical, TaskRowMetrics.padding(dense: dense))
        .onChange(of: isFocused) { _, value in focused = value }
        .onChange(of: focused) { _, value in
            if isFocused != value { isFocused = value }
            if !value { submit() }
        }
    }

    private func submit() {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        text = ""
        withAnimation(TF.Motion.snappy) { _ = controller.addTask(clean) }
    }
}

/// Line spacing for the plan, close to an Apple Notes checklist.
enum TaskRowMetrics {
    /// From this many tasks on the screen, lines tighten further.
    static let denseFrom = 10

    static func padding(dense: Bool) -> CGFloat {
        dense ? 2 : 6
    }
}

/// The row's long-press / right-click menu, attached only when `enabled`.
private struct RowMenu<MenuItems: View>: ViewModifier {
    var enabled: Bool
    @ViewBuilder var items: () -> MenuItems

    func body(content: Content) -> some View {
        if enabled {
            content.contextMenu { items() }
        } else {
            content
        }
    }
}
