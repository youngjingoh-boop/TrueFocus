import SwiftUI
import TrueFocusKit
import WidgetKit

// Building blocks shared by the Home/Lock Screen widgets and the Live Activity.
// The widget extension can't see the app's Components.swift, so these are small,
// self-contained re-tellings of the same design language.

enum WidgetCopy {
    static func modeLabel(_ mode: FlowMode) -> String {
        switch mode {
        case .focus: return "Focus"
        case .think: return "Think"
        case .rest: return "Rest"
        case .idle: return "Up next"
        }
    }
}

/// The mode's SF Symbol, tinted.
struct ModeGlyph: View {
    var mode: FlowMode
    var size: CGFloat = 12
    var tinted = true

    var body: some View {
        Image(systemName: mode.symbol)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(tinted ? TF.tint(for: mode) : Color.primary)
            .widgetAccentable()
    }
}

/// A plain colored dot for the mode.
struct ModeDotMark: View {
    var mode: FlowMode
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(TF.tint(for: mode))
            .frame(width: size, height: size)
            .widgetAccentable()
    }
}

/// The right clock for the mode, ticking live without timeline reloads:
/// focus counts up the total time on the task, think counts up the think time,
/// rest counts down to the planned end and then counts the overrun.
struct FlowTimerText: View {
    var mode: FlowMode
    var modeStartedAt: Date?
    var taskFocusBefore: Double
    var plannedRestEnd: Date?
    /// The moment this view is rendered for (the timeline entry date).
    var now: Date

    var body: some View {
        switch mode {
        case .focus:
            if let start = modeStartedAt {
                countUp(from: start.addingTimeInterval(-taskFocusBefore))
            } else {
                Text("0:00")
            }
        case .think:
            if let start = modeStartedAt {
                countUp(from: start)
            } else {
                Text("0:00")
            }
        case .rest:
            if let end = plannedRestEnd {
                if now < end {
                    let start = min(modeStartedAt ?? now, end)
                    Text(timerInterval: start...end, countsDown: true)
                } else {
                    // Past the planned end: count the overrun up from it.
                    Text("+\(Text(end, style: .timer))")
                }
            } else {
                Text("0:00")
            }
        case .idle:
            Text("—")
        }
    }

    private func countUp(from start: Date) -> Text {
        Text(timerInterval: start...start.addingTimeInterval(12 * 3600), countsDown: false)
    }
}

/// A thin 0–100 bar.
struct WidgetMomentumBar: View {
    var value: Int
    var tint: Color = TF.Palette.signal
    var track: Color = TF.Palette.hairline
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, proxy.size.width * CGFloat(min(max(value, 0), 100)) / 100))
                    .widgetAccentable()
            }
        }
        .frame(height: height)
    }
}

/// One dot per task in the unbroken chain.
struct WidgetChainDots: View {
    var chain: Int
    var tint: Color = TF.Palette.signal
    var maxDots = 7

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<min(max(chain, 0), maxDots), id: \.self) { _ in
                Circle().fill(tint).frame(width: 4, height: 4)
            }
            if chain > maxDots {
                Text("+\(chain - maxDots)")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
            }
        }
        .widgetAccentable()
    }
}

extension LiveSnapshot {
    /// What the widget gallery shows.
    static var widgetPreview: LiveSnapshot {
        LiveSnapshot(mode: .focus,
                     taskID: UUID(),
                     taskTitle: "Write the investor update",
                     breadcrumb: "Tighten the metrics paragraph",
                     modeStartedAt: Date().addingTimeInterval(-23 * 60),
                     taskFocusBefore: 0,
                     nextTaskTitle: "Reply to Sam about pricing",
                     doneToday: 3,
                     plannedToday: 7,
                     focusSecondsToday: 2 * 3600 + 12 * 60,
                     chain: 3,
                     momentum: 72,
                     outcome: "Ship the investor update")
    }

    /// "3 of 7"
    var progressText: String {
        plannedToday > 0 ? "\(doneToday) of \(plannedToday)" : ""
    }

    /// The task title worth showing, or a sensible empty state.
    var widgetHeadline: String {
        if dayEnded { return doneToday > 0 ? "Day shut down. \(doneToday) done." : "Day shut down." }
        if let headline, !headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return headline }
        return plannedToday == 0 ? "Plan today" : "List cleared"
    }
}
