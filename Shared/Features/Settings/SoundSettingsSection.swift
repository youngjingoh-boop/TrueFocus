import SwiftUI
import TrueFocusKit

/// Sound: studio cues for each moment, music while you focus, a river under rests.
struct SoundSettingsSection: View {
    @Environment(FocusController.self) private var controller

    var body: some View {
        SettingsSection("Sound", footnote: "Effects from the Sonniss pro library (Rescopic Sound, CB Sounddesign, Orbital Emitter, Doex Studio, Stefano Cremona). Music: TruFocus originals made with ElevenLabs. Apple Music needs a subscription; without one you hear Drive.") {
            ToggleRow(title: "Sound effects", subtitle: "Done, rest, stuck, back to it, switching, shutting down",
                      isOn: controller.binding(\.soundEffects))

            VStack(alignment: .leading, spacing: 8) {
                Text("Focus music").font(.body).foregroundStyle(TF.Palette.ink)
                VStack(spacing: 0) {
                    ForEach(FocusMusic.allCases, id: \.self) { choice in
                        MusicChoiceRow(choice: choice, selected: controller.settings.focusMusic == choice) {
                            TFHaptics.tap()
                            controller.updateSettings { $0.focusMusic = choice }
                            if controller.mode != .focus {
                                AudioDirector.shared.preview(choice, volume: controller.settings.musicVolume)
                            }
                        }
                        if choice != FocusMusic.allCases.last { Hairline().padding(.leading, 44) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: TF.Radius.control).fill(TF.Palette.surface2))
            }

            if controller.settings.focusMusic != .off {
                SliderRow(title: "Music volume", value: controller.binding(\.musicVolume), range: 0...1, step: 0.05,
                          format: { "\(Int(($0 * 100).rounded()))%" })
            }

            ToggleRow(title: "River sounds during rests", isOn: controller.binding(\.restAmbience))
        }
    }
}

private struct MusicChoiceRow: View {
    let choice: FocusMusic
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? TF.Palette.signal : TF.Palette.ink3)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(choice.title).font(.body.weight(selected ? .semibold : .regular)).foregroundStyle(TF.Palette.ink)
                    Text(choice.subtitle).font(.footnote).foregroundStyle(TF.Palette.ink2)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TF.Palette.signal)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var symbol: String {
        switch choice {
        case .off: return "speaker.slash"
        case .appleMusic: return "music.note"
        default: return "waveform"
        }
    }
}

/// One tap through the focus tracks, for the Now card and the focus screen.
struct MusicQuickButton: View {
    @Environment(FocusController.self) private var controller
    var onDark = false

    var body: some View {
        let current = controller.settings.focusMusic
        Button {
            TFHaptics.tap()
            controller.updateSettings { $0.focusMusic = current.next }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: current == .off ? "speaker.slash" : "waveform")
                    .font(.system(size: 11, weight: .bold))
                    .symbolEffect(.variableColor.iterative, isActive: current != .off && controller.mode == .focus)
                Text(current == .off ? "Music" : current.title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(current == .off ? (onDark ? TF.Palette.nightInk2 : TF.Palette.ink3) : TF.Palette.signal)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(Capsule().fill(onDark ? Color.white.opacity(0.08) : TF.Palette.surface2))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(current == .off ? "Focus music off" : "Focus music: \(current.title)")
        .accessibilityHint("Switches to the next track")
        .help("Focus music — tap for the next track")
    }
}
