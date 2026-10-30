#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import AppIntents
import SwiftUI
import TrueFocusKit
import WidgetKit

/// The current task on the Lock Screen and in the Dynamic Island.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LiveBannerView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(TF.Palette.night.opacity(0.92))
                .activitySystemActionForegroundColor(TF.Palette.signal)
                .widgetURL(URL(string: "truefocus://focus"))
        } dynamicIsland: { context in
            let state = context.state
            let tint = TF.tint(for: state.mode)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: state.symbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(tint)
                        Text(LiveCopy.label(state))
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.1)
                            .foregroundStyle(tint)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveTimer(state: state)
                        .font(.system(size: 22, weight: .light).monospacedDigit())
                        .foregroundStyle(TF.Palette.nightInk)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 96, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.headline)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TF.Palette.nightInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        if let sub = LiveCopy.subline(state) {
                            Text(sub)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(TF.Palette.nightInk2)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        LiveActions(state: state, compact: true)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: state.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                    .padding(.leading, 2)
            } compactTrailing: {
                LiveTimer(state: state)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 46, alignment: .trailing)
            } minimal: {
                Image(systemName: state.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
            }
            .keylineTint(tint)
            .widgetURL(URL(string: "truefocus://focus"))
        }
    }
}

// MARK: - Lock Screen banner

private struct LiveBannerView: View {
    var state: FocusActivityAttributes.ContentState
    var isStale: Bool

    private var tint: Color { TF.tint(for: state.mode) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(LiveCopy.label(state))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(tint)
                Spacer(minLength: 8)
                if state.chain > 0 {
                    HStack(spacing: 3) {
                        ForEach(0..<min(state.chain, 6), id: \.self) { _ in
                            Circle().fill(TF.Palette.signal).frame(width: 4, height: 4)
                        }
                    }
                }
                if state.plannedToday > 0 {
                    Text("\(state.doneToday) of \(state.plannedToday)")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(TF.Palette.nightInk2)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if state.mode == .rest {
                        Text(state.isOnBreak ? "Back to" : "Next")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(TF.Palette.nightInk2)
                    }
                    Text(state.headline)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(TF.Palette.nightInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if !state.juggled.isEmpty, state.mode.isWorking {
                        LiveJuggleChips(tasks: state.juggled)
                    } else if let sub = LiveCopy.subline(state), state.mode != .rest {
                        Text(sub)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(TF.Palette.nightInk2)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                LiveTimer(state: state)
                    .font(.system(size: 34, weight: .thin).monospacedDigit())
                    .foregroundStyle(isStale ? TF.Palette.alarm : TF.Palette.nightInk)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .trailing)
            }

            if state.mode.isActive || state.isPaused {
                LiveActions(state: state, compact: false)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

// MARK: - Pieces

private enum LiveCopy {
    static func label(_ state: FocusActivityAttributes.ContentState) -> String {
        state.isPaused ? "PAUSED" : state.isOnBreak ? "BREAK" : label(state.mode)
    }

    static func label(_ mode: FlowMode) -> String {
        switch mode {
        case .focus: return "FOCUS"
        case .think: return "THINK"
        case .rest: return "REST"
        case .idle: return "UP NEXT"
        }
    }

    /// The line under the title: where you left off, or a nudge for the mode.
    static func subline(_ state: FocusActivityAttributes.ContentState) -> String? {
        if state.mode.isWorking, !state.juggled.isEmpty {
            let names = state.juggled.map { ($0.waiting ? "⏳ " : "") + TFFormat.truncate($0.title, to: 18) }
            return "Juggling " + names.joined(separator: " · ")
        }
        switch state.mode {
        case .focus:
            if let crumb = state.breadcrumb, !crumb.isEmpty { return "↳ " + crumb }
            return state.nextTitle.map { "Then: " + $0 }
        case .think:
            return "What's the smallest next step?"
        case .rest:
            return "Breathe. Then go."
        case .idle:
            guard state.isPaused else { return nil }
            if let crumb = state.breadcrumb, !crumb.isEmpty { return "↳ " + crumb }
            return "The clock waits for you."
        }
    }
}

/// The other juggled tasks as chips. Tapping one switches to it without unlocking.
private struct LiveJuggleChips: View {
    var tasks: [FocusActivityAttributes.JuggledTask]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tasks.prefix(3)) { task in
                Button(intent: SwitchJuggledTaskIntent(taskID: task.id)) {
                    HStack(spacing: 4) {
                        Image(systemName: task.waiting ? "hourglass" : "arrow.left.arrow.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(task.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(TF.Palette.nightInk)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Count-up for focus (total on the task) and think, countdown for rest.
private struct LiveTimer: View {
    var state: FocusActivityAttributes.ContentState

    var body: some View {
        FlowTimerText(mode: state.mode,
                      modeStartedAt: state.modeStartedAt,
                      taskFocusBefore: state.taskFocusBefore,
                      plannedRestEnd: state.plannedRestEnd,
                      paused: state.isPaused,
                      now: Date())
    }
}

/// Done / Stuck / Back to it — run in place via the flow intents.
private struct LiveActions: View {
    var state: FocusActivityAttributes.ContentState
    var compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            switch state.mode {
            case .focus:
                LiveButton(intent: CompleteTaskIntent(), title: "Done", symbol: "checkmark", prominent: true, compact: compact)
                LiveButton(intent: StuckIntent(), title: "Stuck", symbol: "brain", prominent: false, compact: compact)
                LiveIconButton(intent: PauseIntent(), symbol: "pause.fill", label: "Pause", compact: compact)
            case .think:
                LiveButton(intent: BackToItIntent(), title: "Back to it", symbol: "bolt.fill", prominent: true, compact: compact)
                LiveButton(intent: CompleteTaskIntent(), title: "Done", symbol: "checkmark", prominent: false, compact: compact)
                LiveIconButton(intent: PauseIntent(), symbol: "pause.fill", label: "Pause", compact: compact)
            case .rest:
                // Back to it resumes a break too.
                LiveButton(intent: BackToItIntent(), title: state.isOnBreak ? "Resume" : "Go now",
                           symbol: state.isOnBreak ? "play.fill" : "bolt.fill", prominent: true, compact: compact)
            case .idle:
                if state.isPaused {
                    LiveButton(intent: ResumeIntent(), title: "Resume", symbol: "play.fill", prominent: true, compact: compact)
                } else {
                    LiveButton(intent: StartNextTaskIntent(), title: "Start next", symbol: "bolt.fill", prominent: true, compact: compact)
                }
            }
        }
    }
}

/// A round, symbol-only control (Pause) beside the labelled ones.
private struct LiveIconButton<I: AppIntent>: View {
    var intent: I
    var symbol: String
    var label: String
    var compact: Bool

    var body: some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 12 : 13, weight: .bold))
                .foregroundStyle(TF.Palette.nightInk)
                .frame(width: compact ? 44 : 48, height: compact ? 36 : 42)
                .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct LiveButton<I: AppIntent>: View {
    var intent: I
    var title: String
    var symbol: String
    var prominent: Bool
    var compact: Bool

    var body: some View {
        Button(intent: intent) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 12 : 13, weight: .bold))
                Text(title)
                    .font(.system(size: compact ? 14 : 15, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(prominent ? TF.Palette.onSignal : TF.Palette.nightInk)
            .frame(maxWidth: .infinity, minHeight: compact ? 36 : 42)
            .background(
                Capsule().fill(prominent ? TF.Palette.signal : Color.white.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}
#endif
