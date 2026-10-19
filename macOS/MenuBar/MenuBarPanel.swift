import AppKit
import SwiftData
import SwiftUI
import TrueFocusKit

/// The menu bar panel: everything you need to keep moving without opening the window.
struct MenuBarPanel: View {
    @Environment(FocusController.self) private var controller
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

            NowSection()
                .padding(.horizontal, 12)

            JugglePanel()
                .padding(.horizontal, 18)
                .padding(.top, 10)

            UpNextList()
                .padding(.top, 14)

            QuickAddField()
                .padding(.horizontal, 18)
                .padding(.top, 10)

            Hairline().padding(.top, 14)

            footer
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
        .frame(width: 340)
        .background(TF.Palette.paper)
        .onAppear { WindowOpener.shared.openWindow = openWindow }
    }

    private var header: some View {
        let snapshot = controller.snapshot
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(TFFormat.dayEyebrow(Date())).tfEyebrowStyle()
                Spacer()
                Text("\(snapshot.doneToday)/\(max(snapshot.plannedToday, snapshot.doneToday)) done")
                    .font(.tfCaption)
                    .foregroundStyle(TF.Palette.ink2)
            }
            if let outcome = snapshot.outcome {
                Text(outcome)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TF.Palette.ink)
                    .lineLimit(2)
            }
        }
    }

    private var footer: some View {
        let snapshot = controller.snapshot
        return VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text("Momentum").tfEyebrowStyle()
                MomentumBar(value: snapshot.momentum)
                Text("\(snapshot.momentum)")
                    .font(.tfCaption)
                    .foregroundStyle(TF.Palette.ink2)
                    .frame(width: 26, alignment: .trailing)
            }
            HStack(spacing: 8) {
                if snapshot.chain > 0 {
                    ChainDots(chain: snapshot.chain)
                    Text("chain").font(.tfCaption).foregroundStyle(TF.Palette.ink3)
                }
                Spacer()
                Button {
                    WindowOpener.shared.openMain()
                } label: {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.plain)
                .foregroundStyle(TF.Palette.ink2)
                .help("Open TrueFocus")

                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(TF.Palette.ink2)
                .help("Settings")

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
                .foregroundStyle(TF.Palette.ink2)
                .help("Quit TrueFocus")
            }
            .font(.system(size: 13, weight: .medium))
        }
    }
}

// MARK: - Now

private struct NowSection: View {
    @Environment(FocusController.self) private var controller

    var body: some View {
        let snapshot = controller.snapshot
        VStack(alignment: .leading, spacing: 12) {
            switch snapshot.mode {
            case .focus, .think:
                working(snapshot)
            case .rest:
                resting(snapshot)
            case .idle:
                idle(snapshot)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tfCard(cornerRadius: 18, tint: snapshot.mode.isActive ? TF.tint(for: snapshot.mode) : nil)
    }

    @ViewBuilder
    private func working(_ snapshot: LiveSnapshot) -> some View {
        HStack {
            ModeLabel(mode: snapshot.mode, text: snapshot.mode == .think ? "Thinking" : "Now")
            Spacer()
            MusicQuickButton()
            if let start = snapshot.modeStartedAt {
                ElapsedText(since: start,
                            base: snapshot.mode == .focus ? snapshot.taskFocusBefore : 0,
                            font: .system(size: 15, weight: .light).monospacedDigit())
                    .foregroundStyle(TF.Palette.ink2)
            }
        }
        Text(snapshot.taskTitle ?? "—")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(TF.Palette.ink)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
        if let crumb = snapshot.breadcrumb {
            Text("↳ \(crumb)")
                .font(.system(size: 13))
                .foregroundStyle(TF.Palette.ink2)
                .lineLimit(2)
        }
        HStack(spacing: 8) {
            Button {
                TFHaptics.success()
                controller.complete()
            } label: {
                Label("Done", systemImage: "checkmark")
            }
            .buttonStyle(PrimaryButtonStyle(tint: TF.Palette.signal, foreground: .black))
            .layoutPriority(1)

            // Round icon buttons, like the iPhone card, so Done always has room for its label.
            if snapshot.mode == .focus {
                Button { controller.stuck() } label: { Image(systemName: "brain") }
                    .buttonStyle(OrbButtonStyle(tint: TF.Palette.think, size: 44))
                    .accessibilityLabel("I'm stuck")
                    .help("I'm stuck — think it through (⌘.)")
                Button {
                    withAnimation(TF.Motion.snappy) { controller.waitOnCurrent() }
                } label: { Image(systemName: "hourglass") }
                    .buttonStyle(OrbButtonStyle(tint: TF.Palette.ink2, size: 44))
                    .accessibilityLabel("Waiting on it")
                    .help("Waiting on it — keep it juggled and move to the next task")
            } else {
                Button("Back to it") { controller.backToIt() }
                    .buttonStyle(QuietButtonStyle())
                    .fixedSize()
            }
            Button {
                withAnimation(TF.Motion.snappy) { controller.pause() }
            } label: { Image(systemName: "pause.fill") }
                .buttonStyle(OrbButtonStyle(tint: TF.Palette.ink2, size: 44))
                .accessibilityLabel("Pause")
                .help("Pause — stop the clock, keep your place (⇧⌘P)")
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func resting(_ snapshot: LiveSnapshot) -> some View {
        HStack {
            ModeLabel(mode: .rest, text: "Rest")
            Spacer()
            if let end = snapshot.plannedRestEnd {
                CountdownText(until: end, font: .system(size: 15, weight: .light).monospacedDigit())
                    .foregroundStyle(TF.Palette.ink2)
            }
        }
        Text("Breathe. Then go.")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(TF.Palette.ink)
        if let next = snapshot.nextTaskTitle {
            Text("Next — \(next)")
                .font(.system(size: 13))
                .foregroundStyle(TF.Palette.ink2)
                .lineLimit(2)
        }
        Button {
            controller.backToIt()
        } label: {
            Label("Go now", systemImage: "bolt.fill")
        }
        .buttonStyle(PrimaryButtonStyle(tint: TF.Palette.ink, foreground: TF.Palette.paper))
        .disabled(snapshot.nextTaskTitle == nil)
    }

    @ViewBuilder
    private func idle(_ snapshot: LiveSnapshot) -> some View {
        if snapshot.dayEnded {
            ModeLabel(mode: .idle, text: "Shut down")
            Text("Done for today.")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(TF.Palette.ink)
            Button("Reopen the day") { controller.reopenDay() }
                .buttonStyle(QuietButtonStyle())
        } else if snapshot.isPaused, let title = snapshot.nextTaskTitle {
            HStack {
                ModeLabel(mode: .idle, text: "Paused")
                Spacer()
                Text(TFFormat.clock(snapshot.taskFocusBefore))
                    .font(.system(size: 15, weight: .light).monospacedDigit())
                    .foregroundStyle(TF.Palette.ink3)
            }
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(TF.Palette.ink)
                .lineLimit(3)
            if let crumb = snapshot.breadcrumb {
                Text("↳ \(crumb)")
                    .font(.system(size: 13))
                    .foregroundStyle(TF.Palette.ink2)
                    .lineLimit(2)
            }
            if let since = snapshot.pausedAt {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text(TFFormat.pausedSince(since, now: context.date))
                        .font(.tfCaption)
                        .foregroundStyle(TF.Palette.ink3)
                }
            }
            HStack(spacing: 8) {
                Button {
                    controller.resume()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle(tint: TF.Palette.signal, foreground: .black))
                Button {
                    if let paused = controller.pausedTask { controller.toggleDone(paused) }
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .buttonStyle(QuietButtonStyle())
            }
            .padding(.top, 2)
        } else if let next = snapshot.nextTaskTitle {
            ModeLabel(mode: .idle, text: "Up next")
            Text(next)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(TF.Palette.ink)
                .lineLimit(3)
            Button {
                controller.startNext()
            } label: {
                Label("Attack", systemImage: "bolt.fill")
            }
            .buttonStyle(PrimaryButtonStyle(tint: TF.Palette.signal, foreground: .black))
        } else if let waiting = controller.longestWaiting {
            ModeLabel(mode: .idle, text: "All waiting")
            Text(waiting.title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(TF.Palette.ink)
                .lineLimit(3)
            Text("Everything left is waiting on someone. Nudge it, or add something new below.")
                .font(.system(size: 13))
                .foregroundStyle(TF.Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                controller.start(waiting)
            } label: {
                Label("Pick it back up", systemImage: "hourglass.bottomhalf.filled")
            }
            .buttonStyle(QuietButtonStyle())
        } else if snapshot.doneToday > 0 {
            ModeLabel(mode: .rest, text: "Cleared")
            Text("\(snapshot.doneToday) done. That's the day.")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(TF.Palette.ink)
            Button {
                controller.endDay()
            } label: {
                Label("Shut down the day", systemImage: "moon.zzz.fill")
            }
            .buttonStyle(PrimaryButtonStyle(tint: TF.Palette.rest, foreground: .black))
        } else {
            ModeLabel(mode: .idle, text: "Today")
            Text("Empty your head. Plan the day.")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(TF.Palette.ink)
            Button("Plan today") {
                MacUIState.shared.section = .today
                WindowOpener.shared.openMain()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }
}

// MARK: - Up next

private struct UpNextList: View {
    @Environment(FocusController.self) private var controller
    /// "+N more" opens the rest right here, in a scrolling list, instead of the main window.
    @State private var expanded = false

    private static let collapsedCount = 3

    var body: some View {
        let all = controller.openTasks.filter { $0.id != controller.nowTask?.id && !$0.inPlay }
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Up next").tfEyebrowStyle()
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
                if expanded {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(all) { task in
                                UpNextRow(task: task)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                    .scrollIndicators(.automatic)
                } else {
                    ForEach(all.prefix(Self.collapsedCount)) { task in
                        UpNextRow(task: task)
                    }
                }
                let more = all.count - Self.collapsedCount
                if more > 0 {
                    Button {
                        withAnimation(TF.Motion.snappy) { expanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(expanded ? "Show less" : "+\(more) more")
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .frame(minHeight: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .font(.tfCaption)
                    .foregroundStyle(TF.Palette.ink2)
                    .padding(.horizontal, 18)
                    .padding(.top, 2)
                    .help(expanded ? "Show the next three only" : "Show every task left today")
                }
            }
        }
    }
}

private struct UpNextRow: View {
    @Environment(FocusController.self) private var controller
    let task: FocusTask
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            CheckCircle(isOn: task.isDone, size: 18, label: task.title) {
                controller.toggleDone(task)
            }
            Text(task.title)
                .font(.system(size: 13.5))
                .foregroundStyle(TF.Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 6)
            if hovering {
                if controller.mode.isWorking && controller.canJuggleMore {
                    Button {
                        withAnimation(TF.Motion.snappy) { _ = controller.juggle(task) }
                    } label: {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TF.Palette.ink2)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Juggle this alongside the current task")
                }
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TF.Palette.signal)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 30)
        .background(hovering ? TF.Palette.surface2 : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { controller.start(task) }
        .help("Start this task")
    }
}

// MARK: - Quick add

private struct QuickAddField: View {
    @Environment(FocusController.self) private var controller
    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(TF.Palette.ink3)
            TextField("Add a task", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .onSubmit {
                    let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return }
                    controller.addTask(title)
                    text = ""
                }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(TF.Palette.surface2))
    }
}
