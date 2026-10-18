import SwiftUI
import TrueFocusKit

/// The day's scoreboard and the shutdown ritual.
struct ReviewView: View {
    @Environment(FocusController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @State private var reflection = ""
    /// When shown as a page (Mac) rather than a sheet, there's nothing to dismiss.
    var isSheet = true

    var body: some View {
        let stats = controller.stats
        let snapshot = controller.snapshot

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(TFFormat.dayEyebrow(Date())).tfEyebrowStyle()
                        Text("Scoreboard").font(.tfDisplay).foregroundStyle(TF.Palette.ink)
                    }
                    Spacer()
                    if isSheet {
                        Button("Close") { dismiss() }
                            .buttonStyle(.plain)
                            .foregroundStyle(TF.Palette.ink2)
                    }
                }

                if let outcome = snapshot.outcome {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("The win").tfEyebrowStyle(TF.Palette.signal)
                        Text(outcome).font(.tfHeadline).foregroundStyle(TF.Palette.ink)
                    }
                }

                momentumHero(stats)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                          alignment: .leading, spacing: 22) {
                    StatTile(value: "\(controller.doneToday.count)/\(snapshot.plannedToday)", label: "Done")
                    StatTile(value: TFFormat.short(stats.focusSeconds), label: "Focused")
                    StatTile(value: "\(stats.bestChain)", label: "Best chain")
                    StatTile(value: TFFormat.short(stats.thinkSeconds), label: "Thinking")
                    StatTile(value: TFFormat.short(stats.restOverrunSeconds), label: "Rest overrun")
                    StatTile(value: "\(stats.boots)", label: "Boot-outs")
                }

                if !controller.segmentsToday.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("The day").tfEyebrowStyle()
                        DayTimeline(segments: controller.segmentsToday)
                            .frame(height: 28)
                        HStack(spacing: 14) {
                            legend("Focus", TF.Palette.signal)
                            legend("Think", TF.Palette.think)
                            legend("Rest", TF.Palette.rest)
                        }
                    }
                }

                if !controller.doneToday.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Crossed off").tfEyebrowStyle().padding(.bottom, 6)
                        ForEach(controller.doneToday, id: \.id) { task in
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(TF.Palette.signal)
                                Text(task.title)
                                    .font(.body)
                                    .foregroundStyle(TF.Palette.ink)
                                Spacer()
                                Text(TFFormat.short(task.focusSeconds))
                                    .font(.tfCaption)
                                    .foregroundStyle(TF.Palette.ink3)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("One line on today").tfEyebrowStyle()
                    TextField("What worked, what leaked?", text: $reflection, axis: .vertical)
                        .font(.body)
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: TF.Radius.control).fill(TF.Palette.surface2))
                        .onSubmit { controller.setReflection(reflection) }
                }

                shutdownButton
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, TF.Space.page)
            .padding(.top, TF.Space.xl)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.immediately)
        .tfPage()
        .onAppear { reflection = controller.plan?.reflection ?? "" }
        .onDisappear {
            if reflection != (controller.plan?.reflection ?? "") { controller.setReflection(reflection) }
        }
        #if os(macOS)
        .frame(minWidth: isSheet ? 520 : 0, minHeight: isSheet ? 640 : 0)
        #endif
    }

    private func momentumHero(_ stats: DayStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text("\(stats.momentum)")
                    .font(.system(size: 72, weight: .thin).monospacedDigit())
                    .foregroundStyle(TF.Palette.ink)
                    .contentTransition(.numericText())
                Text("momentum").tfEyebrowStyle()
                Spacer()
                if stats.chain > 0 {
                    VStack(alignment: .trailing, spacing: 4) {
                        ChainDots(chain: stats.chain)
                        Text("chain \(stats.chain)").font(.tfCaption).foregroundStyle(TF.Palette.ink2)
                    }
                }
            }
            MomentumBar(value: stats.momentum, height: 4)
            Text(verdict(stats))
                .font(.subheadline)
                .foregroundStyle(TF.Palette.ink2)
        }
        .padding(20)
        .tfCard()
    }

    private func verdict(_ stats: DayStats) -> String {
        switch stats.momentum {
        case 80...: return "Locked in. Protect this tomorrow."
        case 55..<80: return "Strong day. The leaks were small."
        case 30..<55: return "Decent. Tighten the rests and the starts."
        default:
            return controller.doneToday.isEmpty ? "Pick one task and start the clock." : "Momentum leaked. Shorter rests, fewer exits."
        }
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.tfCaption).foregroundStyle(TF.Palette.ink2)
        }
    }

    @ViewBuilder
    private var shutdownButton: some View {
        if controller.dayEnded {
            Button("Reopen the day") { controller.reopenDay() }
                .buttonStyle(QuietButtonStyle())
        } else {
            Button {
                controller.setReflection(reflection)
                controller.endDay()
                TFHaptics.success()
                if isSheet { dismiss() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "moon.fill")
                    Text("Shut down the day")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            Text("Stops the clock and the nudges. Anything unfinished rolls to tomorrow.")
                .font(.footnote)
                .foregroundStyle(TF.Palette.ink3)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }
}

/// A horizontal strip of the day: focus, think and rest blocks in proportion, gaps as paper.
struct DayTimeline: View {
    let segments: [FlowSegment]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            GeometryReader { proxy in
                let now = context.date
                let start = segments.first?.startedAt ?? now
                let end = max(now, segments.compactMap(\.endedAt).max() ?? now)
                let span = max(60, end.timeIntervalSince(start))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(TF.Palette.surface2)
                    ForEach(segments, id: \.id) { segment in
                        let x = segment.startedAt.timeIntervalSince(start) / span * proxy.size.width
                        let w = max(1.5, segment.duration(now: now) / span * proxy.size.width)
                        Rectangle()
                            .fill(TF.tint(for: segment.mode))
                            .frame(width: w)
                            .offset(x: x)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .accessibilityLabel("Timeline of today's focus, think and rest blocks")
    }
}
