import AppIntents
import SwiftUI
import TrueFocusKit
import WidgetKit

// MARK: - Timeline

struct NowEntry: TimelineEntry {
    let date: Date
    let snapshot: LiveSnapshot
}

struct NowProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowEntry {
        NowEntry(date: Date(), snapshot: .widgetPreview)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowEntry) -> Void) {
        let snapshot = context.isPreview ? LiveSnapshot.widgetPreview : SharedStore.shared.snapshot
        completion(NowEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowEntry>) -> Void) {
        let now = Date()
        let snapshot = SharedStore.shared.snapshot
        var entries = [NowEntry(date: now, snapshot: snapshot)]
        // A rest flips from countdown to overrun at its planned end; give that moment its own entry.
        if snapshot.mode == .rest, let end = snapshot.plannedRestEnd, end > now {
            entries.append(NowEntry(date: end, snapshot: snapshot))
        }
        // The app reloads timelines on every change; this is just a safety net.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

// MARK: - Widget

struct NowWidget: Widget {
    static let kind = "app.truefocus.now"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NowProvider()) { entry in
            NowWidgetView(entry: entry)
        }
        .configurationDisplayName("Now")
        .description("The task you're on, how long you've been at it, and what's next.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .systemSmall, .systemMedium])
    }
}

struct NowWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: NowEntry

    var body: some View {
        content
            .widgetURL(URL(string: entry.snapshot.mode.isActive ? "truefocus://focus" : "truefocus://today"))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular:
            LockRectangularView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            LockInlineView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryCircular:
            LockCircularView(entry: entry)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .systemMedium:
            HomeMediumView(entry: entry)
                .containerBackground(for: .widget) { TF.Palette.paper }
        default:
            HomeSmallView(entry: entry)
                .containerBackground(for: .widget) { TF.Palette.paper }
        }
    }
}

// MARK: - Lock Screen

private struct LockRectangularView: View {
    var entry: NowEntry
    private var snapshot: LiveSnapshot { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                ModeGlyph(mode: snapshot.mode, size: 10, tinted: false)
                Text(WidgetCopy.label(snapshot).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                Spacer(minLength: 4)
                if snapshot.mode.isActive || snapshot.isPaused {
                    FlowTimerText(mode: snapshot.mode,
                                  modeStartedAt: snapshot.modeStartedAt,
                                  taskFocusBefore: snapshot.taskFocusBefore,
                                  plannedRestEnd: snapshot.plannedRestEnd,
                                  paused: snapshot.isPaused,
                                  now: entry.date)
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 56, alignment: .trailing)
                } else if !snapshot.progressText.isEmpty {
                    Text(snapshot.progressText)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                }
            }
            .foregroundStyle(.secondary)

            let juggling = snapshot.mode.isWorking ? Juggle.summary(snapshot.inPlay, excluding: snapshot.taskID, maxTitle: 14) : nil
            Text(snapshot.widgetHeadline)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(juggling == nil ? 2 : 1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let juggling {
                Text(juggling)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct LockInlineView: View {
    var entry: NowEntry
    private var snapshot: LiveSnapshot { entry.snapshot }

    var body: some View {
        if snapshot.mode == .focus, let start = snapshot.modeStartedAt {
            Label {
                Text(TFFormat.truncate(snapshot.widgetHeadline, to: 22) + " · ")
                    + Text(start.addingTimeInterval(-snapshot.taskFocusBefore), style: .timer)
            } icon: {
                Image(systemName: snapshot.mode.symbol)
            }
        } else {
            Label {
                Text(inlineText)
            } icon: {
                Image(systemName: snapshot.mode.symbol)
            }
        }
    }

    private var inlineText: String {
        switch snapshot.mode {
        case .rest: return "Rest · next: " + TFFormat.truncate(snapshot.widgetHeadline, to: 20)
        case .think: return "Think · " + TFFormat.truncate(snapshot.widgetHeadline, to: 22)
        case .idle where snapshot.nextTaskTitle != nil && !snapshot.dayEnded:
            return "Next: " + TFFormat.truncate(snapshot.widgetHeadline, to: 24)
        default: return snapshot.widgetHeadline
        }
    }
}

private struct LockCircularView: View {
    var entry: NowEntry
    private var snapshot: LiveSnapshot { entry.snapshot }

    var body: some View {
        if snapshot.mode == .rest, let end = snapshot.plannedRestEnd, end > entry.date {
            let start = min(snapshot.modeStartedAt ?? entry.date, end)
            ProgressView(timerInterval: start...end, countsDown: true) {
                Image(systemName: "leaf.fill")
            } currentValueLabel: {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 14, weight: .bold))
            }
            .progressViewStyle(.circular)
            .widgetAccentable()
        } else {
            Gauge(value: Double(min(max(snapshot.momentum, 0), 100)), in: 0...100) {
                Image(systemName: snapshot.mode.symbol)
            } currentValueLabel: {
                VStack(spacing: 0) {
                    Image(systemName: snapshot.mode.symbol)
                        .font(.system(size: 10, weight: .bold))
                    Text("\(snapshot.momentum)")
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                }
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        }
    }
}

// MARK: - Home Screen

private struct HomeHeader: View {
    var snapshot: LiveSnapshot

    var body: some View {
        HStack(spacing: 6) {
            ModeDotMark(mode: snapshot.mode)
            Text(WidgetCopy.label(snapshot))
                .font(.tfEyebrow)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(snapshot.mode == .idle ? TF.Palette.ink2 : TF.tint(for: snapshot.mode))
            Spacer(minLength: 4)
            if !snapshot.progressText.isEmpty {
                Text(snapshot.progressText)
                    .font(.tfCaption)
                    .foregroundStyle(TF.Palette.ink2)
            }
        }
    }
}

private struct HomeBody: View {
    var entry: NowEntry
    var titleLines: Int
    private var snapshot: LiveSnapshot { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HomeHeader(snapshot: snapshot)
            Spacer(minLength: 0)
            if snapshot.mode == .rest {
                Text("Next")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TF.Palette.ink2)
            }
            Text(snapshot.widgetHeadline)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(TF.Palette.ink)
                .lineLimit(titleLines)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            if snapshot.mode.isActive || snapshot.isPaused {
                FlowTimerText(mode: snapshot.mode,
                              modeStartedAt: snapshot.modeStartedAt,
                              taskFocusBefore: snapshot.taskFocusBefore,
                              plannedRestEnd: snapshot.plannedRestEnd,
                              paused: snapshot.isPaused,
                              now: entry.date)
                    .font(.system(size: 26, weight: .light).monospacedDigit())
                    .foregroundStyle(snapshot.mode == .rest && entry.date >= (snapshot.plannedRestEnd ?? .distantFuture)
                                     ? TF.Palette.alarm : TF.Palette.ink)
                    .lineLimit(1)
            } else if let outcome = snapshot.outcome, !snapshot.dayEnded {
                Text(outcome)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TF.Palette.ink2)
                    .lineLimit(1)
            }
            if snapshot.mode.isWorking, let juggling = Juggle.summary(snapshot.inPlay, excluding: snapshot.taskID, maxTitle: 16) {
                Text(juggling)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TF.Palette.ink2)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                WidgetMomentumBar(value: snapshot.momentum, tint: TF.tint(for: snapshot.mode == .idle ? .focus : snapshot.mode))
                if snapshot.chain > 0 {
                    WidgetChainDots(chain: snapshot.chain, maxDots: 5)
                }
            }
        }
    }
}

private struct HomeSmallView: View {
    var entry: NowEntry

    var body: some View {
        HomeBody(entry: entry, titleLines: 3)
    }
}

private struct HomeMediumView: View {
    var entry: NowEntry
    private var snapshot: LiveSnapshot { entry.snapshot }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            HomeBody(entry: entry, titleLines: 2)
            VStack(spacing: 8) {
                actions
            }
            .frame(width: 104)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch snapshot.mode {
        case .focus:
            WidgetActionButton(intent: CompleteTaskIntent(), title: "Done", symbol: "checkmark", prominent: true)
            WidgetActionButton(intent: StuckIntent(), title: "Stuck", symbol: "brain", prominent: false)
        case .think:
            WidgetActionButton(intent: BackToItIntent(), title: "Back to it", symbol: "bolt.fill", prominent: true)
            WidgetActionButton(intent: CompleteTaskIntent(), title: "Done", symbol: "checkmark", prominent: false)
        case .rest:
            WidgetActionButton(intent: BackToItIntent(), title: "Go now", symbol: "bolt.fill", prominent: true)
            Spacer(minLength: 0)
        case .idle:
            if snapshot.isPaused {
                WidgetActionButton(intent: ResumeIntent(), title: "Resume", symbol: "play.fill", prominent: true)
            } else if snapshot.nextTaskTitle != nil && !snapshot.dayEnded {
                WidgetActionButton(intent: StartNextTaskIntent(), title: "Start", symbol: "bolt.fill", prominent: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A compact capsule button that runs a flow intent in place.
private struct WidgetActionButton<I: AppIntent>: View {
    var intent: I
    var title: String
    var symbol: String
    var prominent: Bool

    /// StandBy, the tinted Home Screen and the Lock Screen repaint widgets in one or two
    /// tones, so a filled capsule and its label would come out the same colour.
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Button(intent: intent) {
            if renderingMode == .fullColor {
                label
                    .foregroundStyle(prominent ? TF.Palette.onSignal : TF.Palette.ink)
                    .background(Capsule().fill(prominent ? TF.Palette.signal : TF.Palette.surface2))
            } else {
                // One-tone modes: the label and an outline in the same tone, nothing filled
                // behind the text, so it always reads.
                label
                    .foregroundStyle(.primary)
                    .background(Capsule().fill(.primary.opacity(prominent ? 0.18 : 0.08)))
                    .overlay(Capsule().strokeBorder(.primary.opacity(prominent ? 0.9 : 0.45), lineWidth: 1.5))
            }
        }
        .buttonStyle(.plain)
        .widgetAccentable(prominent)
    }

    private var label: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 38)
    }
}
