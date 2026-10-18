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
            ModeLabel(mode: snapshot.mode, text: snapshot.mode == .think ? "Think" : "Now")
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

            if snapshot.mode == .focus {
                Button("Stuck") { controller.stuck() }
                    .buttonStyle(QuietButtonStyle())
                Button {
                    withAnimation(TF.Motion.snappy) { controller.waitOnCurrent() }
                } label: {
                    Image(systemName: "hourglass")
                        .accessibilityLabel("Waiting on it")
                }
                .buttonStyle(QuietButtonStyle())
                .help("Waiting on it — keep it juggled and move to the next task")
            } else {
                Button("Back to it") { controller.backToIt() }
                    .buttonStyle(QuietButtonStyle())
            }
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
            Label("Start now", systemImage: "bolt.fill")
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
        } else if let next = snapshot.nextTaskTitle {
            ModeLabel(mode: .idle, text: "Up next")
            Text(next)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(TF.Palette.ink)
                .lineLimit(3)
            Button {
                controller.startNext()
            } label: {
                Label("Attack it", systemImage: "bolt.fill")
            }
            .buttonStyle(PrimaryButtonStyle(tint: TF.Palette.signal, foreground: .black))
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

    var body: some View {
        let upcoming = Array(controller.openTasks.filter { $0.id != controller.nowTask?.id && !$0.inPlay }.prefix(3))
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Up next").tfEyebrowStyle()
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
                ForEach(upcoming) { task in
                    UpNextRow(task: task)
                }
                let more = controller.juggleCandidates.count - upcoming.count
                if more > 0 {
                    Button("+\(more) more") {
                        MacUIState.shared.section = .today
                        WindowOpener.shared.openMain()
                    }
                    .buttonStyle(.plain)
                    .font(.tfCaption)
                    .foregroundStyle(TF.Palette.ink3)
                    .padding(.horizontal, 18)
                    .padding(.top, 2)
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
            CheckCircle(isOn: task.isDone, size: 18) {
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
