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
                        Image(systemName: state.mode.symbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(tint)
                        Text(LiveCopy.label(state.mode))
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
                Image(systemName: state.mode.symbol)
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
                Image(systemName: state.mode.symbol)
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
                Text(LiveCopy.label(state.mode))
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
                        Text("Next")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(TF.Palette.nightInk2)
                    }
                    Text(state.headline)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(TF.Palette.nightInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if let sub = LiveCopy.subline(state), state.mode != .rest {
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

            if state.mode.isActive {
                LiveActions(state: state, compact: false)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

// MARK: - Pieces

private enum LiveCopy {
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
        switch state.mode {
        case .focus:
            if let crumb = state.breadcrumb, !crumb.isEmpty { return "↳ " + crumb }
            return state.nextTitle.map { "Then: " + $0 }
        case .think:
            return "What's the smallest next step?"
        case .rest:
            return "Breathe. Then go."
        case .idle:
            return nil
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
            case .think:
                LiveButton(intent: BackToItIntent(), title: "Back to it", symbol: "bolt.fill", prominent: true, compact: compact)
                LiveButton(intent: CompleteTaskIntent(), title: "Done", symbol: "checkmark", prominent: false, compact: compact)
            case .rest:
                LiveButton(intent: BackToItIntent(), title: "Go now", symbol: "bolt.fill", prominent: true, compact: compact)
            case .idle:
                LiveButton(intent: StartNextTaskIntent(), title: "Start next", symbol: "bolt.fill", prominent: true, compact: compact)
            }
        }
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
            .foregroundStyle(prominent ? Color.black : TF.Palette.nightInk)
            .frame(maxWidth: .infinity, minHeight: compact ? 36 : 42)
            .background(
                Capsule().fill(prominent ? TF.Palette.signal : Color.white.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}
#endif
