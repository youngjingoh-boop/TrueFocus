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

            if let crumb = snapshot.breadcrumb, mode.isWorking {
                Text("↳ \(crumb)")
                    .font(.subheadline)
                    .foregroundStyle(TF.Palette.ink2)
                    .lineLimit(2)
            }

            HStack(alignment: .center, spacing: 12) {
                timer(for: snapshot)
                    .foregroundStyle(mode == .rest && snapshot.isRestOverrun(now: Date()) ? TF.Palette.signal : TF.Palette.ink)
                Spacer(minLength: 8)
                actions(for: mode, tint: tint)
            }
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
        case .rest: return "Rest · next"
        case .idle: return "Up next"
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
            CountdownText(until: snapshot.plannedRestEnd ?? Date(), font: .tfTimerSmall)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private func actions(for mode: FlowMode, tint: Color) -> some View {
        switch mode {
        case .focus:
            HStack(spacing: 8) {
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
            Button("Back to it") { controller.backToIt() }
                .buttonStyle(QuietButtonStyle(foreground: TF.Palette.think))
        case .rest:
            Button("Go now") {
                TFHaptics.tap()
                controller.backToIt()
            }
            .buttonStyle(QuietButtonStyle(foreground: TF.Palette.rest))
        case .idle:
            EmptyView()
        }
    }
}

/// Tasks held "in play", for one-tap switching between parallel work.
struct InPlayStrip: View {
    @Environment(FocusController.self) private var controller
    var onDark = false

    var body: some View {
        let nowID = controller.nowTask?.id
        let held = controller.inPlayTasks.filter { $0.id != nowID }
        if !held.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("In play").tfEyebrowStyle(onDark ? TF.Palette.nightInk2 : TF.Palette.ink2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(held, id: \.id) { task in
                            Button {
                                TFHaptics.tap()
                                controller.start(task)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .lineLimit(1)
                                    if !task.breadcrumb.isEmpty {
                                        Text("↳ \(task.breadcrumb)")
                                            .font(.system(size: 12))
                                            .lineLimit(1)
                                            .opacity(0.6)
                                    }
                                }
                                .foregroundStyle(onDark ? TF.Palette.nightInk : TF.Palette.ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .frame(maxWidth: 220, alignment: .leading)
                                .background(
                                    Capsule().fill(onDark ? Color.white.opacity(0.08) : TF.Palette.surface2)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Take out of play", systemImage: "minus.circle") {
                                    controller.setInPlay(task, false)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
