import SwiftUI
import TrueFocusKit

/// The live card at the top of Today: what you're on, for how long, and the next move.
struct NowCard: View {
    @Environment(FocusController.self) private var controller

    var body: some View {
        let snapshot = controller.snapshot
        let mode = snapshot.mode
        let tint = TF.tint(for: mode)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ModeLabel(mode: mode, text: label(for: snapshot))
                Spacer(minLength: 8)
                if mode.isWorking {
                    MusicQuickButton()
                }
                if snapshot.originDevice != TFDevice.name, !snapshot.originDevice.isEmpty {
                    Label("on \(snapshot.originDevice)", systemImage: snapshot.originDevice == "Mac" ? "laptopcomputer" : "iphone")
                        .labelStyle(.titleAndIcon)
                        .font(.tfCaption)
                        .foregroundStyle(TF.Palette.ink3)
                }
            }

            Text(snapshot.headline ?? "Next task")
                .font(.tfHeadline)
                .foregroundStyle(TF.Palette.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let crumb = snapshot.breadcrumb, mode.isWorking || snapshot.isPaused {
                Text("↳ \(crumb)")
                    .font(.subheadline)
                    .foregroundStyle(TF.Palette.ink2)
                    .lineLimit(2)
            }

            HStack(alignment: .center, spacing: 12) {
                timer(for: snapshot)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(mode == .rest && snapshot.isRestOverrun(now: Date()) ? TF.Palette.signal : TF.Palette.ink)
                Spacer(minLength: 8)
                actions(for: snapshot, tint: tint)
            }

            // One box: the main task above, the rest of what you're juggling below.
            JuggleSection(main: controller.nowTask?.id ?? controller.pausedTask?.id ?? snapshot.taskID)
        }
        .padding(20)
        .tfCard(tint: tint)
        .contentShape(RoundedRectangle(cornerRadius: TF.Radius.card, style: .continuous))
        .onTapGesture {
            withAnimation(TF.Motion.soft) { controller.isFocusScreenPresented = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint("Opens the focus screen")
    }

    private func label(for snapshot: LiveSnapshot) -> String {
        switch snapshot.mode {
        case .focus: return "Now"
        case .think: return "Thinking"
        case .rest: return snapshot.isOnBreak ? "Break · back to" : "Rest · next"
        case .idle: return snapshot.isPaused ? "Paused" : "Up next"
        }
    }

    @ViewBuilder
    private func timer(for snapshot: LiveSnapshot) -> some View {
        switch snapshot.mode {
        case .focus:
            ElapsedText(since: snapshot.modeStartedAt ?? Date(), base: snapshot.taskFocusBefore, font: .tfTimerSmall)
        case .think:
            ElapsedText(since: snapshot.modeStartedAt ?? Date(), font: .tfTimerSmall)
        case .rest:
            if snapshot.isOnBreak {
                ElapsedText(since: snapshot.modeStartedAt ?? Date(), font: .tfTimerSmall)
            } else {
                CountdownText(until: snapshot.plannedRestEnd ?? Date(), font: .tfTimerSmall)
            }
        case .idle:
            if snapshot.isPaused {
                // Frozen where you stopped.
                Text(TFFormat.clock(snapshot.taskFocusBefore))
                    .font(.tfTimerSmall)
                    .opacity(0.45)
            }
        }
    }

    @ViewBuilder
    private func actions(for snapshot: LiveSnapshot, tint: Color) -> some View {
        switch snapshot.mode {
        case .focus:
            HStack(spacing: 6) {
                Button {
                    TFHaptics.tap()
                    withAnimation(TF.Motion.snappy) { controller.pause() }
                } label: {
                    Image(systemName: "pause.fill")
                }
                .buttonStyle(OrbButtonStyle(tint: TF.Palette.ink2, size: 44))
                .accessibilityLabel("Pause")
                .help("Pause — stop the clock, keep your place. Hold or right-click for Rest or Stop.")
                .contextMenu { restAndStop }

                Button {
                    TFHaptics.tap()
                    withAnimation(TF.Motion.snappy) { controller.waitOnCurrent() }
                } label: {
                    Image(systemName: "hourglass")
                }
                .buttonStyle(OrbButtonStyle(tint: TF.Palette.ink2, size: 44))
                .accessibilityLabel("Waiting on it")
                .help("Waiting on it — keep it juggled and move to the next task")

                Button {
                    controller.stuck()
                } label: {
                    Image(systemName: "brain")
                }
                .buttonStyle(OrbButtonStyle(tint: TF.Palette.think, size: 44))
                .accessibilityLabel("I'm stuck")
                .help("I'm stuck — think it through")

                Button {
                    TFHaptics.success()
                    controller.complete()
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(OrbButtonStyle(tint: TF.Palette.signal, size: 44, filled: true))
                .accessibilityLabel("Done")
                .help("Done — cross it off")
            }
        case .think:
            HStack(spacing: 6) {
                Button {
                    TFHaptics.tap()
                    withAnimation(TF.Motion.snappy) { controller.pause() }
                } label: {
                    Image(systemName: "pause.fill")
                }
                .buttonStyle(OrbButtonStyle(tint: TF.Palette.ink2, size: 44))
                .accessibilityLabel("Pause")
                .contextMenu { restAndStop }
                Button("Back to it") { controller.backToIt() }
                    .buttonStyle(QuietButtonStyle(foreground: TF.Palette.think))
            }
        case .rest where snapshot.isOnBreak:
            HStack(spacing: 6) {
                Button {
                    TFHaptics.tap()
                    withAnimation(TF.Motion.snappy) { controller.stop() }
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(OrbButtonStyle(tint: TF.Palette.ink2, size: 44))
                .accessibilityLabel("Stop")
                .help("Stop — end the task for now; it stays on the plan")

                Button {
                    TFHaptics.success()
                    withAnimation(TF.Motion.snappy) { controller.resume() }
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(OrbButtonStyle(tint: TF.Palette.signal, size: 44, filled: true))
                .accessibilityLabel("Resume")
                .help("Resume — back to the task, its clock picking up where it stopped")
            }
        case .rest:
            Button("Go now") {
                TFHaptics.tap()
                controller.backToIt()
            }
            .buttonStyle(QuietButtonStyle(foreground: TF.Palette.rest))
        case .idle:
            if snapshot.isPaused {
                HStack(spacing: 6) {
                    Button {
                        TFHaptics.success()
                        if let paused = controller.pausedTask { controller.toggleDone(paused) }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(OrbButtonStyle(tint: TF.Palette.ink2, size: 44))
                    .accessibilityLabel("Done")
                    .help("Done — cross it off")

                    Button {
                        TFHaptics.tap()
                        withAnimation(TF.Motion.snappy) { controller.stop() }
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(OrbButtonStyle(tint: TF.Palette.ink2, size: 44))
                    .accessibilityLabel("Stop")
                    .help("Stop — end the task for now; it stays on the plan, and nothing asks you back")

                    Button {
                        TFHaptics.tap()
                        withAnimation(TF.Motion.snappy) { controller.takeBreak() }
                    } label: {
                        Image(systemName: "cup.and.saucer.fill")
                    }
                    .buttonStyle(OrbButtonStyle(tint: TF.Palette.rest, size: 44))
                    .accessibilityLabel("Rest")
                    .help("Rest — a break as long as you like, with rest music")

                    Button {
                        TFHaptics.success()
                        withAnimation(TF.Motion.snappy) { controller.resume() }
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(OrbButtonStyle(tint: TF.Palette.signal, size: 44, filled: true))
                    .accessibilityLabel("Resume")
                    .help("Resume — the clock picks up where it stopped")
                }
            }
        }
    }

    /// Rest and Stop, behind a hold (iPhone) or right-click (Mac) on Pause.
    @ViewBuilder
    private var restAndStop: some View {
        Button {
            withAnimation(TF.Motion.snappy) { controller.takeBreak() }
        } label: {
            Label("Rest", systemImage: "cup.and.saucer.fill")
        }
        Button {
            withAnimation(TF.Motion.snappy) { controller.stop() }
        } label: {
            Label("Stop", systemImage: "stop.fill")
        }
    }
}
