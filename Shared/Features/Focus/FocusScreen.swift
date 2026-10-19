import SwiftUI
import TrueFocusKit

/// The immersive canvas. Always dark. One task, one clock, three moves.
///
/// - Focus: the task, a thin count-up clock, Stuck · Done · Switch.
/// - Think: "Think." — write the smallest next step; shields stay up.
/// - Rest: a breathing ring that counts the micro-rest down, then sends you into the next task.
struct FocusScreen: View {
    @Environment(FocusController.self) private var controller
    @State private var showSwitcher = false

    var body: some View {
        let snapshot = controller.snapshot
        let tint = TF.tint(for: snapshot.mode)

        ZStack {
            TF.Palette.night.ignoresSafeArea()
            AmbientGlow(tint: tint, mode: snapshot.mode)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar(snapshot)
                    .padding(.horizontal, TF.Space.page)
                    .padding(.top, 8)

                Spacer(minLength: 20)

                Group {
                    switch snapshot.mode {
                    case .focus: FocusStage(snapshot: snapshot)
                    case .think: ThinkStage(snapshot: snapshot)
                    case .rest: RestStage(snapshot: snapshot)
                    case .idle: IdleStage()
                    }
                }
                .padding(.horizontal, TF.Space.page)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .id(snapshot.mode)

                Spacer(minLength: 20)

                actionRow(snapshot)
                    .padding(.horizontal, TF.Space.page)

                JugglePanel(onDark: true)
                    .padding(.horizontal, TF.Space.page)
                    .padding(.top, 22)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: 640)
        }
        .preferredColorScheme(.dark)
        .animation(TF.Motion.soft, value: snapshot.mode)
        .sheet(isPresented: $showSwitcher) {
            TaskSwitcher()
                .environment(controller)
        }
        #if os(macOS)
        .onExitCommand { close() }
        #endif
    }

    // MARK: Top bar

    private func topBar(_ snapshot: LiveSnapshot) -> some View {
        HStack {
            Button(action: close) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TF.Palette.nightInk2)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close focus screen")

            // Keeps the mode label centred against the close button.
            Color.clear.frame(width: 44, height: 44)

            Spacer()

            VStack(spacing: 2) {
                ModeLabel(mode: snapshot.mode, text: snapshot.isPaused ? "Paused" : nil)
                if snapshot.mode.isWorking {
                    MusicQuickButton(onDark: true)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(snapshot.doneToday)/\(max(snapshot.plannedToday, snapshot.doneToday))")
                    .font(.tfCaption)
                    .foregroundStyle(TF.Palette.nightInk2)
                ChainDots(chain: snapshot.chain, tint: TF.Palette.signal, maxDots: 6)
            }
            .frame(width: 60, alignment: .trailing)
        }
    }

    // MARK: Actions

    @ViewBuilder
    private func actionRow(_ snapshot: LiveSnapshot) -> some View {
        switch snapshot.mode {
        case .focus:
            HStack(spacing: 18) {
                VStack(spacing: 8) {
                    Button { controller.stuck() } label: { Image(systemName: "brain") }
                        .buttonStyle(OrbButtonStyle(tint: TF.Palette.think, size: 56))
                        .keyboardShortcut(".", modifiers: .command)
                        .accessibilityLabel("Stuck")
                    caption("Stuck")
                }
                VStack(spacing: 8) {
                    Button {
                        TFHaptics.tap()
                        withAnimation(TF.Motion.snappy) { controller.waitOnCurrent() }
                    } label: { Image(systemName: "hourglass") }
                        .buttonStyle(OrbButtonStyle(tint: TF.Palette.nightInk2, size: 56))
                        .accessibilityLabel("Waiting on it")
                        .accessibilityHint("Keeps this task juggled and moves to the next one")
                    caption("Waiting")
                }
                VStack(spacing: 8) {
                    Button {
                        TFHaptics.success()
                        controller.complete()
                    } label: { Image(systemName: "checkmark") }
                        .buttonStyle(OrbButtonStyle(tint: TF.Palette.signal, size: 84, filled: true))
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityLabel("Done")
                    caption("Done")
                }
                VStack(spacing: 8) {
                    Button { showSwitcher = true } label: { Image(systemName: "arrow.left.arrow.right") }
                        .buttonStyle(OrbButtonStyle(tint: TF.Palette.nightInk, size: 56))
                        .accessibilityLabel("Switch task")
                    caption("Switch")
                }
            }
        case .think:
            HStack(spacing: 12) {
                Button("Back to it") { controller.backToIt() }
                    .buttonStyle(PrimaryButtonStyle(tint: TF.Palette.think, foreground: .black))
                    .keyboardShortcut(.return, modifiers: .command)
                Button { showSwitcher = true } label: { Image(systemName: "arrow.left.arrow.right") }
                    .buttonStyle(OrbButtonStyle(tint: TF.Palette.nightInk, size: 52))
                    .accessibilityLabel("Switch task")
            }
        case .rest:
            HStack(spacing: 12) {
                Button("Go now") {
                    TFHaptics.tap()
                    controller.backToIt()
                }
                .buttonStyle(PrimaryButtonStyle(tint: TF.Palette.rest, foreground: .black))
                .keyboardShortcut(.return, modifiers: .command)
                Button { showSwitcher = true } label: { Image(systemName: "list.bullet") }
                    .buttonStyle(OrbButtonStyle(tint: TF.Palette.nightInk, size: 52))
                    .accessibilityLabel("Choose the next task")
            }
        case .idle:
            if let paused = controller.pausedTask {
                HStack(spacing: 12) {
                    Button {
                        TFHaptics.success()
                        withAnimation(TF.Motion.snappy) { controller.resume() }
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: TF.Palette.signal, foreground: TF.Palette.onSignal))
                    .keyboardShortcut(.return, modifiers: .command)
                    Button {
                        TFHaptics.success()
                        withAnimation(TF.Motion.snappy) { controller.toggleDone(paused) }
                    } label: { Image(systemName: "checkmark") }
                        .buttonStyle(OrbButtonStyle(tint: TF.Palette.nightInk, size: 52))
                        .accessibilityLabel("Done")
                }
            } else if controller.nextTask != nil {
                Button("Attack") {
                    TFHaptics.success()
                    controller.startNext()
                }
                .buttonStyle(PrimaryButtonStyle(tint: TF.Palette.signal, foreground: TF.Palette.onSignal))
                .keyboardShortcut(.return, modifiers: .command)
            } else if let waiting = controller.longestWaiting {
                Button("Pick It Back Up") {
                    TFHaptics.success()
                    controller.start(waiting)
                }
                .buttonStyle(PrimaryButtonStyle(tint: TF.Palette.signal, foreground: TF.Palette.onSignal))
                .keyboardShortcut(.return, modifiers: .command)
            } else {
                Button("Close") { close() }
                    .buttonStyle(QuietButtonStyle(foreground: TF.Palette.nightInk))
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).tfEyebrowStyle(TF.Palette.nightInk2)
    }

    private func close() {
        withAnimation(TF.Motion.soft) { controller.isFocusScreenPresented = false }
    }
}

// MARK: - Stages

private struct FocusStage: View {
    @Environment(FocusController.self) private var controller
    let snapshot: LiveSnapshot

    var body: some View {
        VStack(spacing: 22) {
            Text(snapshot.taskTitle ?? "")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(TF.Palette.nightInk)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.7)

            ElapsedText(since: snapshot.modeStartedAt ?? Date(), base: snapshot.taskFocusBefore, font: .tfTimerHero)
                .foregroundStyle(TF.Palette.nightInk)

            PauseChip()

            BreadcrumbField(placeholder: "Next step…")

            Text("\(TFFormat.short(snapshot.focusToday(now: Date()))) focused today")
                .font(.tfCaption)
                .foregroundStyle(TF.Palette.nightInk2)
        }
    }
}

private struct ThinkStage: View {
    let snapshot: LiveSnapshot
    @State private var promptIndex = 0

    private let prompts = [
        "What's the smallest next step?",
        "What would make this easy?",
        "What are you actually avoiding?",
        "What's the ugly first version?",
        "Who could unblock this in one message?",
    ]

    var body: some View {
        VStack(spacing: 22) {
            Text("Think.")
                .font(.system(size: 54, weight: .thin))
                .foregroundStyle(TF.Palette.think)

            Text(snapshot.taskTitle ?? "")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(TF.Palette.nightInk)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Text(prompts[promptIndex % prompts.count])
                .font(.title3)
                .foregroundStyle(TF.Palette.nightInk2)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .onTapGesture {
                    withAnimation(TF.Motion.soft) { promptIndex += 1 }
                }

            BreadcrumbField(placeholder: "Write the smallest next step")

            ElapsedText(since: snapshot.modeStartedAt ?? Date(), font: .tfTimerSmall)
                .foregroundStyle(TF.Palette.nightInk2)

            PauseChip()
        }
        .task {
            // A new question every 40 seconds keeps thinking from turning into staring.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(40))
                withAnimation(TF.Motion.soft) { promptIndex += 1 }
            }
        }
    }
}

private struct RestStage: View {
    @Environment(FocusController.self) private var controller
    let snapshot: LiveSnapshot

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let start = snapshot.modeStartedAt ?? now
            let end = snapshot.plannedRestEnd ?? start.addingTimeInterval(45)
            let planned = max(1, end.timeIntervalSince(start))
            let elapsed = now.timeIntervalSince(start)
            let overrun = now.timeIntervalSince(end)
            let level = overrun > 300 ? 3 : overrun > 120 ? 2 : 1
            let tint = overrun > RestPolicy.grace ? TF.Palette.signal : TF.Palette.rest
            let line = Copy(tone: controller.settings.tone).restOver(level: level, next: snapshot.nextTaskTitle)

            VStack(spacing: 26) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.07), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: min(1, elapsed / planned))
                        .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: elapsed)
                    BreathingDot(tint: tint)
                    VStack(spacing: 6) {
                        Text(overrun < 0 ? TFFormat.clock(-overrun) : "+" + TFFormat.clock(overrun))
                            .font(.tfTimer)
                            .foregroundStyle(TF.Palette.nightInk)
                            .contentTransition(.numericText())
                        Text(overrun < 0 ? "Breathe." : line.title)
                            .font(.headline)
                            .foregroundStyle(overrun < 0 ? TF.Palette.nightInk2 : tint)
                    }
                }
                .frame(width: 260, height: 260)

                VStack(spacing: 6) {
                    Text("Next").tfEyebrowStyle(TF.Palette.nightInk2)
                    Text(snapshot.nextTaskTitle ?? "—")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(TF.Palette.nightInk)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    if controller.settings.autoContinue && overrun < 0 {
                        Text("Starts automatically")
                            .font(.tfCaption)
                            .foregroundStyle(TF.Palette.nightInk2)
                    }
                }
            }
        }
    }
}

private struct IdleStage: View {
    @Environment(FocusController.self) private var controller

    var body: some View {
        VStack(spacing: 16) {
            if let paused = controller.pausedTask {
                PausedStage(task: paused, since: controller.pausedAt ?? Date())
            } else if let next = controller.nextTask {
                Text("Up next").tfEyebrowStyle(TF.Palette.nightInk2)
                Text(next.title)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(TF.Palette.nightInk)
                    .multilineTextAlignment(.center)
            } else if let waiting = controller.longestWaiting {
                Text("All waiting").tfEyebrowStyle(TF.Palette.nightInk2)
                Text(waiting.title)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(TF.Palette.nightInk)
                    .multilineTextAlignment(.center)
                Text("Waiting \(TFFormat.short(Date().timeIntervalSince(waiting.waitingSince ?? Date()))). Nudge it or add something new.")
                    .font(.callout)
                    .foregroundStyle(TF.Palette.nightInk2)
                    .multilineTextAlignment(.center)
            } else if !controller.doneToday.isEmpty {
                Text("Cleared.")
                    .font(.system(size: 54, weight: .thin))
                    .foregroundStyle(TF.Palette.rest)
                Text("\(controller.doneToday.count) done today. That's the day.")
                    .font(.title3)
                    .foregroundStyle(TF.Palette.nightInk2)
            } else {
                Text("Nothing planned.")
                    .font(.system(size: 40, weight: .thin))
                    .foregroundStyle(TF.Palette.nightInk)
                Text("Add a task on Today, then come back.")
                    .font(.title3)
                    .foregroundStyle(TF.Palette.nightInk2)
            }
        }
    }
}

/// A paused task: its clock frozen where you stopped, and how long ago that was.
private struct PausedStage: View {
    let task: FocusTask
    let since: Date

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 7) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("Paused").tfEyebrowStyle(TF.Palette.nightInk2)
            }
            .foregroundStyle(TF.Palette.nightInk2)

            Text(task.title)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(TF.Palette.nightInk)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.7)

            Text(TFFormat.clock(task.focusSeconds))
                .font(.tfTimerHero)
                .foregroundStyle(TF.Palette.nightInk.opacity(0.4))

            if !task.breadcrumb.isEmpty {
                Text("↳ \(task.breadcrumb)")
                    .font(.callout)
                    .foregroundStyle(TF.Palette.nightInk2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(TFFormat.pausedSince(since, now: context.date))
                    .font(.tfCaption)
                    .foregroundStyle(TF.Palette.nightInk2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The clock's own control: stop it, keep your place.
private struct PauseChip: View {
    @Environment(FocusController.self) private var controller

    var body: some View {
        Button {
            TFHaptics.tap()
            withAnimation(TF.Motion.snappy) { controller.pause() }
        } label: {
            Label("Pause", systemImage: "pause.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TF.Palette.nightInk)
                .padding(.horizontal, 18)
                .frame(minHeight: 36)
                .background(Capsule().fill(Color.white.opacity(0.10)))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Stops the clock. Resume picks up where you left off.")
    }
}

// MARK: - Pieces

/// "Where I left off" for the current task, saved as you type (debounced).
private struct BreadcrumbField: View {
    @Environment(FocusController.self) private var controller
    var placeholder: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TF.Palette.nightInk2)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(TF.Palette.nightInk)
                .focused($focused)
                .onSubmit { save() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .frame(maxWidth: 420)
        .onAppear { text = controller.nowTask?.breadcrumb ?? "" }
        .onChange(of: controller.nowTask?.id) { _, _ in text = controller.nowTask?.breadcrumb ?? "" }
        .onChange(of: focused) { _, isFocused in if !isFocused { save() } }
        .task(id: text) {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        guard let task = controller.nowTask else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean != task.breadcrumb { controller.setBreadcrumb(clean, for: task) }
    }
}

/// A slow, soft pulse in the middle of the rest ring: breathe with it.
private struct BreathingDot: View {
    var tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        Circle()
            .fill(tint.opacity(0.10))
            .frame(width: 200, height: 200)
            .scaleEffect(expanded || reduceMotion ? 1 : 0.72)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { expanded = true }
            }
            .accessibilityHidden(true)
    }
}

/// A faint wash of the mode's color from the top of the screen.
private struct AmbientGlow: View {
    var tint: Color
    var mode: FlowMode

    var body: some View {
        GeometryReader { proxy in
            RadialGradient(
                colors: [tint.opacity(mode == .idle ? 0.04 : 0.16), .clear],
                center: .init(x: 0.5, y: -0.05),
                startRadius: 0,
                endRadius: max(proxy.size.width, proxy.size.height) * 0.75
            )
        }
        .allowsHitTesting(false)
        .animation(TF.Motion.soft, value: mode)
    }
}

// MARK: - Switcher

/// Pick another task. Leaves a breadcrumb on the one you're leaving.
struct TaskSwitcher: View {
    @Environment(FocusController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @State private var crumb = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Switch to").font(.tfTitle).foregroundStyle(TF.Palette.ink)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(TF.Palette.ink2)
            }

            if let leaving = controller.nowTask {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Leaving “\(leaving.title)” — where were you?").tfEyebrowStyle()
                    TextField("Next step when you come back", text: $crumb)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: TF.Radius.control).fill(TF.Palette.surface2))
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let nowID = controller.nowTask?.id
                    let held = controller.inPlayTasks.filter { $0.id != nowID }
                    let rest = controller.openTasks.filter { $0.id != nowID && !$0.inPlay }
                    if !held.isEmpty {
                        Text("Juggling").tfEyebrowStyle().padding(.bottom, 4)
                        ForEach(held, id: \.id) { row($0) }
                        Spacer().frame(height: 16)
                    }
                    if !rest.isEmpty {
                        Text("Plan").tfEyebrowStyle().padding(.bottom, 4)
                        ForEach(rest, id: \.id) { row($0) }
                    }
                }
            }
        }
        .padding(TF.Space.xl)
        .tfPage()
        .onAppear { crumb = controller.nowTask?.breadcrumb ?? "" }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    private func row(_ task: FocusTask) -> some View {
        Button {
            if let leaving = controller.nowTask, crumb != leaving.breadcrumb {
                controller.setBreadcrumb(crumb.trimmingCharacters(in: .whitespacesAndNewlines), for: leaving)
            }
            TFHaptics.tap()
            controller.start(task)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: task.waitingSince != nil ? "hourglass" : task.inPlay ? "square.stack.3d.up.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(task.inPlay ? TF.Palette.think : TF.Palette.ink3)
                    .frame(width: 22)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title).font(.body).foregroundStyle(TF.Palette.ink)
                    if !task.breadcrumb.isEmpty {
                        Text("↳ \(task.breadcrumb)").font(.footnote).foregroundStyle(TF.Palette.ink2)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
