import SwiftUI
import TrueFocusKit

/// How TrueFocus paces you and talks to you. Shared by iPhone and Mac settings;
/// a platform can append its own sections with `extra`.
struct FlowSettingsView<Extra: View>: View {
    @Environment(FocusController.self) private var controller
    private let extra: Extra

    init(@ViewBuilder extra: () -> Extra) {
        self.extra = extra()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                voice
                rhythm
                SoundSettingsSection()
                scrolling
                web
                SyncSettingsSection()
                extra
            }
            .padding(.horizontal, TF.Space.page)
            .padding(.vertical, TF.Space.xl)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.immediately)
        .tfPage()
    }

    // MARK: Voice

    private var voice: some View {
        SettingsSection("Voice", footnote: "How hard the nudges hit when a rest runs long or you drift.") {
            HStack(spacing: 8) {
                ForEach(NudgeTone.allCases, id: \.self) { tone in
                    let selected = controller.settings.tone == tone
                    Button {
                        TFHaptics.tap()
                        controller.updateSettings { $0.tone = tone }
                    } label: {
                        Text(tone.label)
                            .font(.system(size: 15, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? TF.Palette.paper : TF.Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(Capsule().fill(selected ? TF.Palette.ink : TF.Palette.surface2))
                    }
                    .buttonStyle(.plain)
                }
            }
            let sample = Copy(tone: controller.settings.tone).restOver(level: 3, next: "Investor update")
            VStack(alignment: .leading, spacing: 3) {
                Text(sample.title).font(.headline).foregroundStyle(TF.Palette.ink)
                Text(sample.body).font(.subheadline).foregroundStyle(TF.Palette.ink2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: TF.Radius.control).fill(TF.Palette.surface2))
        }
    }

    // MARK: Rhythm

    private var rhythm: some View {
        SettingsSection("Rhythm", footnote: "Rests scale with the task: a quick email earns seconds, a long build a few minutes.") {
            SliderRow(title: "Base micro-rest",
                      value: controller.binding(\.restBaseSeconds),
                      range: 10...120, step: 5,
                      format: { "\(Int($0))s" })
            ToggleRow(title: "Scale rest with task length", isOn: controller.binding(\.adaptiveRest))
            ToggleRow(title: "Start the next task when rest ends", isOn: controller.binding(\.autoContinue))
            StepperRow(title: "Stuck check-in after",
                       value: Binding(get: { Int(controller.settings.thinkNudgeMinutes) },
                                      set: { value in controller.updateSettings { $0.thinkNudgeMinutes = Double(value) } }),
                       range: 1...30, unit: "min")
            StepperRow(title: "Tasks you can juggle", value: controller.binding(\.juggleLimit), range: 1...Juggle.maxLimit, unit: "")
        }
    }

    // MARK: Doom-scroll

    private var scrolling: some View {
        SettingsSection("Doom-scroll guard", footnote: "During focus every limit tightens to a third. Booted out means booted out.") {
            HStack(spacing: 8) {
                preset("Gentle", .gentle)
                preset("Standard", .standard)
                preset("Ruthless", .ruthless)
            }
            ToggleRow(title: "Shield distractions while working", isOn: controller.binding(\.shieldDuringFocus))
        }
    }

    private func preset(_ title: String, _ config: DoomScrollConfig) -> some View {
        let selected = controller.settings.doomScroll == config
        return Button {
            TFHaptics.tap()
            controller.updateSettings { $0.doomScroll = config }
        } label: {
            VStack(spacing: 2) {
                Text(title).font(.system(size: 15, weight: selected ? .semibold : .regular))
                Text("\(config.burstStrokes) swipes/min").font(.tfCaption).opacity(0.7)
            }
            .foregroundStyle(selected ? TF.Palette.paper : TF.Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: TF.Radius.control).fill(selected ? TF.Palette.ink : TF.Palette.surface2))
        }
        .buttonStyle(.plain)
    }

    // MARK: Web

    private var web: some View {
        SettingsSection("On the web", footnote: "Applied by the TrueFocus browser extension in Safari and Chrome.") {
            ToggleRow(title: "Remove Reels, Shorts and TikTok", isOn: controller.binding(\.hideShortForm))
            ToggleRow(title: "Instagram opens to messages only", isOn: controller.binding(\.instagramMessagesOnly))
        }
    }
}

extension FlowSettingsView where Extra == EmptyView {
    init() {
        self.extra = EmptyView()
    }
}

// MARK: - Building blocks

/// A titled settings group without the generic grouped-form look.
struct SettingsSection<Content: View>: View {
    var title: String
    var footnote: String?
    @ViewBuilder var content: Content

    init(_ title: String, footnote: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).tfEyebrowStyle()
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(TF.Palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ToggleRow: View {
    var title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundStyle(TF.Palette.ink)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(TF.Palette.ink2)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(TF.Palette.signal)
    }
}

struct StepperRow: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var unit: String

    var body: some View {
        HStack {
            Text(title).font(.body).foregroundStyle(TF.Palette.ink)
            Spacer()
            Text(unit.isEmpty ? "\(value)" : "\(value) \(unit)")
                .font(.body.monospacedDigit())
                .foregroundStyle(TF.Palette.ink2)
                .contentTransition(.numericText())
            Stepper("", value: $value, in: range)
                .labelsHidden()
        }
    }
}

struct SliderRow: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.body).foregroundStyle(TF.Palette.ink)
                Spacer()
                Text(format(value))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(TF.Palette.ink2)
            }
            Slider(value: $value, in: range, step: step)
                .tint(TF.Palette.signal)
        }
    }
}
