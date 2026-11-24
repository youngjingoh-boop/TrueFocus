import SwiftUI
import TrueFocusKit

/// One task on the plan. Reads and edits like a line in an Apple Notes checklist:
/// same body text style, tap the circle to cross it off, tap the text to edit.
struct TaskRow: View {
    @Environment(FocusController.self) private var controller
    let task: FocusTask
    /// Tighter lines once the plan gets long, so 15–20 tasks fit on one screen.
    var dense = false
    /// Where a new line is being typed on the plan, if anywhere. Return on a task opens one below it.
    var insertion: Binding<PlanInsertion?> = .constant(nil)
    /// Opens the task's memo.
    var onMemo: (FocusTask) -> Void = { _ in }

    @State private var draft = ""
    @State private var isHovering = false
    @FocusState private var editing: Bool

    private var isNow: Bool { controller.nowTask?.id == task.id }
    private var isPausedHere: Bool { controller.pausedTask?.id == task.id }
    private var bucket: PlanBucket { controller.bucket(of: task) }
    private var memoPreview: String? { controller.memoPreviews[task.id] }

    /// The colour of the row you're on: the mode's while working, a neutral while paused.
    private var liveTint: Color? {
        if isNow { return TF.tint(for: controller.mode) }
        return isPausedHere ? TF.Palette.ink2 : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if insertion.wrappedValue == PlanInsertion(anchor: task.id, side: .above) {
                InsertTaskField(anchor: task, side: .above, insertion: insertion, dense: dense)
            }
            row
            if insertion.wrappedValue == PlanInsertion(anchor: task.id, side: .below) {
                InsertTaskField(anchor: task, side: .below, insertion: insertion, dense: dense)
            }
        }
        .onAppear { draft = task.title }
        .onChange(of: task.title) { _, title in
            if !editing { draft = title }
        }
        .opacity(task.isDone ? 0.75 : 1)
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 12) {
            CheckCircle(isOn: task.isDone, tint: isNow ? TF.tint(for: controller.mode) : TF.Palette.signal,
                        ring: task.isDone ? nil : priorityColor,
                        label: task.title) {
                TFHaptics.success()
                withAnimation(TF.Motion.snappy) { controller.toggleDone(task) }
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                TextField("Task", text: $draft, axis: .vertical)
                    .font(.tf(.body).weight(liveTint != nil ? .semibold : .regular))
                    .textFieldStyle(.plain)
                    .foregroundStyle(titleColor)
                    .strikethrough(task.isDone, color: TF.Palette.ink3)
                    .focused($editing)
                    .disabled(task.isDone)
                    .onChange(of: draft) { _, value in
                        // Return ends the line (Notes behaviour) instead of inserting a newline.
                        guard value.contains("\n") else { return }
                        draft = value.replacingOccurrences(of: "\n", with: "")
                        endLine()
                    }
                    .onSubmit(endLine)
                    .onChange(of: editing) { _, isEditing in
                        if !isEditing { commit() }
                    }
                    #if os(macOS)
                    // In a reorderable list a text field waits out a rename delay before it
                    // takes a click, like a file name in Finder; take focus on the first one.
                    .simultaneousGesture(TapGesture().onEnded {
                        if !task.isDone { editing = true }
                    })
                    #endif

                if !task.breadcrumb.isEmpty, !task.isDone {
                    Text("↳ \(task.breadcrumb)")
                        .font(.tf(.footnote))
                        .foregroundStyle(TF.Palette.ink2)
                        .lineLimit(2)
                }
                if let memoPreview {
                    Button { onMemo(task) } label: {
                        Label(memoPreview, systemImage: "note.text")
                            .labelStyle(MemoLineLabelStyle())
                            .font(.tf(.footnote))
                            .foregroundStyle(TF.Palette.ink2)
                            .lineLimit(1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open memo: \(memoPreview)")
                }
                if showsMeta {
                    meta
                }
            }

            Spacer(minLength: 4)

            actions(expanded: false)
                .opacity(isHovering ? 0 : 1)
        }
        .padding(.vertical, TaskRowMetrics.padding(dense: dense) + (liveTint != nil ? 5 : 0))
        .contentShape(Rectangle())
        .background { highlight }
        #if os(macOS)
        .overlay(alignment: .topTrailing) {
            // Over the row rather than in it, so hovering never re-wraps a long title.
            if isHovering {
                actions(expanded: true)
                    .padding(.top, TaskRowMetrics.padding(dense: dense) + (liveTint != nil ? 5 : 0))
                    .padding(.leading, 6)
                    .background(TF.Palette.paper.opacity(liveTint != nil ? 0.75 : 0.92), in: .rect(cornerRadius: 8))
            }
        }
        .onHover { isHovering = $0 }
        #endif
        .modifier(RowMenu(enabled: rowMenuEnabled) { menu })
    }

    /// The task you're on sits on a soft wash of its colour with a bar down the side: seen at a
    /// glance from across the plan, without shouting over the tasks around it.
    @ViewBuilder
    private var highlight: some View {
        if let liveTint {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(liveTint.opacity(0.14))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(liveTint)
                        .frame(width: 3)
                        .padding(.vertical, 6)
                        .padding(.leading, 3)
                }
                .padding(.horizontal, -12)
                .accessibilityHidden(true)
        }
    }

    private var titleColor: Color {
        if task.isDone { return TF.Palette.ink3 }
        // Tomorrow and later read quieter than today.
        return bucket == .today ? TF.Palette.ink : TF.Palette.ink2
    }

    private var priorityColor: Color? {
        switch task.taskPriority {
        case .none: return nil
        case .important: return TF.Palette.important
        case .top: return TF.Palette.alarm
        }
    }

    private var showsMeta: Bool {
        task.focusSeconds >= 60 || isNow || isPausedHere || task.inPlay || laterDay != nil
    }

    /// A task planned for a particular day, past tomorrow.
    private var laterDay: Date? {
        guard !task.isDone, bucket == .later, let day = task.plannedFor, day != PlanSchedule.someday else { return nil }
        return day
    }

    private var meta: some View {
        HStack(spacing: 6) {
            if isNow {
                Text(controller.mode == .think ? "thinking" : "in focus")
            } else if isPausedHere {
                Text("paused")
            }
            if task.focusSeconds >= 60 {
                Text(TFFormat.short(task.focusSeconds))
            }
            if let laterDay {
                Text(laterDay, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
            }
            if task.waitingSince != nil && !isNow {
                Image(systemName: "hourglass")
                Text("waiting")
            } else if task.inPlay && !isNow && !isPausedHere {
                Text("juggling")
            }
        }
        .font(.tfCaption)
        .foregroundStyle(isNow ? TF.tint(for: controller.mode) : TF.Palette.ink3)
    }

    // MARK: Actions on the row

    /// At rest, what the task has (its priority, its memo) and the way to start it. Hovering on
    /// the Mac (`expanded`) brings the rest out.
    @ViewBuilder
    private func actions(expanded: Bool) -> some View {
        HStack(spacing: 0) {
            if !task.isDone {
                if expanded {
                    insertButton(.above)
                    insertButton(.below)
                }
                if expanded || task.taskPriority != .none {
                    priorityMenu
                }
            }
            if expanded || memoPreview != nil || showsMemoButtonAtRest {
                memoButton
            }
            if !task.isDone && !isNow {
                startButton
            }
        }
        .padding(.vertical, -10)
        .padding(.trailing, -8)
    }

    /// The iPhone has no hover, so the way into a memo always shows there.
    private var showsMemoButtonAtRest: Bool {
        #if os(iOS)
        !task.isDone
        #else
        false
        #endif
    }

    private func insertButton(_ side: PlanInsertion.Side) -> some View {
        Button {
            withAnimation(TF.Motion.snappy) { insertion.wrappedValue = PlanInsertion(anchor: task.id, side: side) }
        } label: {
            HStack(spacing: 1) {
                Image(systemName: "plus")
                Image(systemName: side == .above ? "arrow.up" : "arrow.down")
            }
            .font(.system(size: TFZoom.pt(9), weight: .bold))
            .foregroundStyle(TF.Palette.ink2)
            .frame(width: 30, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(side == .above ? "Add task above" : "Add task below")
        .help(side == .above ? "Add a task above this one" : "Add a task below this one (or press Return)")
    }

    private var priorityMenu: some View {
        Menu {
            priorityItems
        } label: {
            Image(systemName: task.taskPriority == .none ? "flag" : "flag.fill")
                .font(.system(size: TFZoom.pt(12), weight: .semibold))
                .foregroundStyle(priorityColor ?? TF.Palette.ink3)
                .frame(width: 34, height: 44)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Priority: \(task.taskPriority.label)")
        .help("How important this is")
    }

    @ViewBuilder
    private var priorityItems: some View {
        ForEach([TaskPriority.top, .important, .none], id: \.self) { level in
            Button {
                withAnimation(TF.Motion.snappy) { controller.setPriority(level, for: task) }
            } label: {
                if task.taskPriority == level {
                    Label(level.label, systemImage: "checkmark")
                } else {
                    Text(level.label)
                }
            }
        }
    }

    private var memoButton: some View {
        Button { onMemo(task) } label: {
            Image(systemName: memoPreview == nil ? "note.text.badge.plus" : "note.text")
                .font(.system(size: TFZoom.pt(13), weight: .semibold))
                .foregroundStyle(memoPreview == nil ? TF.Palette.ink3 : TF.Palette.ink2)
                .frame(width: 34, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(memoPreview == nil ? "Add a memo" : "Open memo")
        .help(memoPreview == nil ? "Add a memo to this task" : "Open this task's memo")
    }

    private var startButton: some View {
        Button {
            TFHaptics.tap()
            controller.start(task)
            #if os(iOS)
            controller.isFocusScreenPresented = true
            #endif
        } label: {
            Image(systemName: "bolt.fill")
                .font(.system(size: TFZoom.pt(13), weight: .semibold))
                .foregroundStyle(TF.Palette.ink3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start \(task.title)")
        .help("Focus on this")
    }

    // MARK: Menu

    @ViewBuilder
    private var menu: some View {
        if !task.isDone {
            Button("Focus on This", systemImage: "bolt.fill") { controller.start(task) }
            Button(memoPreview == nil ? "Add Memo" : "Open Memo", systemImage: "note.text") { onMemo(task) }
            Divider()
            Button("Add Task Above", systemImage: "arrow.up") {
                insertion.wrappedValue = PlanInsertion(anchor: task.id, side: .above)
            }
            Button("Add Task Below", systemImage: "arrow.down") {
                insertion.wrappedValue = PlanInsertion(anchor: task.id, side: .below)
            }
            Divider()
            Menu("Priority", systemImage: "flag") { priorityItems }
            if !isNow {
                Menu("Move To", systemImage: "calendar") {
                    ForEach(PlanBucket.allCases, id: \.self) { target in
                        Button(target.label) {
                            withAnimation(TF.Motion.snappy) { controller.move(task, to: target) }
                        }
                        .disabled(bucket == target)
                    }
                }
            }
            Divider()
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
            Button("Open Memo", systemImage: "note.text") { onMemo(task) }
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

    // MARK: Editing

    /// Return on a task: keep the edit, and open a new line right below it.
    private func endLine() {
        commit()
        editing = false
        guard task.isLive, !task.isDone else { return }
        withAnimation(TF.Motion.snappy) { insertion.wrappedValue = PlanInsertion(anchor: task.id, side: .below) }
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

/// A memo's icon and first line, sitting tight together.
private struct MemoLineLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            configuration.title
        }
    }
}

/// The new line that opens right above or below a task. Return adds the task and moves the line
/// down under it, so several can go in, in order, in the middle of the plan.
struct InsertTaskField: View {
    @Environment(FocusController.self) private var controller
    let anchor: FocusTask
    let side: PlanInsertion.Side
    @Binding var insertion: PlanInsertion?
    var dense = false

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NewTaskCircle()
            TextField("New task", text: $text, axis: .vertical)
                .font(.tf(.body))
                .textFieldStyle(.plain)
                .foregroundStyle(TF.Palette.ink)
                .focused($focused)
                .onChange(of: text) { _, value in
                    if value.contains("\n") { add(value, keepGoing: true) }
                }
                .onSubmit { add(text, keepGoing: true) }
                #if os(macOS)
                .onExitCommand { add("", keepGoing: false) }
                #endif
        }
        .padding(.vertical, TaskRowMetrics.padding(dense: dense))
        .task {
            // Once the row has made room for it.
            try? await Task.sleep(for: .milliseconds(60))
            focused = true
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { add(text, keepGoing: false) }
        }
    }

    /// Adds what's typed (a pasted list becomes several tasks). Nothing typed closes the line.
    private func add(_ value: String, keepGoing: Bool) {
        let here = PlanInsertion(anchor: anchor.id, side: side)
        guard insertion == here else { return }
        text = ""
        let lines = value.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            insertion = nil
            return
        }
        withAnimation(TF.Motion.snappy) {
            var last = controller.addTask(lines[0], next: anchor, side: side)
            for line in lines.dropFirst() {
                last = controller.addTask(line, next: last, side: .below)
            }
            insertion = keepGoing ? PlanInsertion(anchor: last.id, side: .below) : nil
        }
    }
}

/// The dashed circle of a line that isn't a task yet.
private struct NewTaskCircle: View {
    var body: some View {
        Circle()
            .strokeBorder(TF.Palette.ink3.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 3]))
            .frame(width: TFZoom.pt(22), height: TFZoom.pt(22))
            .padding(.top, 1)
    }
}

/// The "New task" line closing each day on the plan. Return adds and keeps the cursor,
/// so a whole list goes in without touching the screen.
struct NewTaskRow: View {
    @Environment(FocusController.self) private var controller
    var bucket: PlanBucket = .today
    @Binding var isFocused: Bool
    var dense = false
    @State private var text = ""
    @FocusState private var focused: Bool

    private var placeholder: String {
        switch bucket {
        case .today: return "New task"
        case .tomorrow: return "New task for tomorrow"
        case .later: return "New task for later"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NewTaskCircle()
            TextField(placeholder, text: $text, axis: .vertical)
                .font(.tf(.body))
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
                        controller.addTasks(lines, in: bucket)
                    } else if let line = lines.first {
                        withAnimation(TF.Motion.snappy) { _ = controller.addTask(line, in: bucket) }
                    }
                    keepCursor()
                }
                .onSubmit {
                    submit()
                    keepCursor()
                }
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
        withAnimation(TF.Motion.snappy) { _ = controller.addTask(clean, in: bucket) }
    }

    /// The list moves this row down to make room for the new task, which takes the cursor
    /// out of it. Put it back once the row has settled.
    private func keepCursor() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            focused = true
        }
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
