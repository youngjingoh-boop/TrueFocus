import SwiftUI
import TrueFocusKit
#if os(iOS)
import UIKit
#endif

// Small, reusable pieces of the TrueFocus look. App targets only.

/// The Apple Notes–style check circle, in Ember.
struct CheckCircle: View {
    var isOn: Bool
    var tint: Color = TF.Palette.signal
    var size: CGFloat = 22
    /// What's being checked, for VoiceOver ("Reply to Sam").
    var label: String? = nil
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = false
    @State private var burstVisible = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(isOn ? tint : TF.Palette.ink3, lineWidth: 1.5)
                Circle()
                    .fill(tint)
                    .scaleEffect(isOn ? 1 : 0.2)
                    .opacity(isOn ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(TF.Palette.onSignal)
                    .scaleEffect(isOn ? 1 : 0.4)
                    .opacity(isOn ? 1 : 0)
            }
            .frame(width: size, height: size)
            // Crossing off sends a ring out from the circle, once.
            .background(
                Circle()
                    .stroke(tint, lineWidth: 2)
                    .scaleEffect(burst ? 2.1 : 1)
                    .opacity(burst ? 0 : (burstVisible ? 0.6 : 0))
            )
            // 44 pt to the finger, whatever the drawn size.
            .contentShape(Circle().inset(by: -max(11, (44 - size) / 2)))
            .animation(TF.Motion.check, value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? "Done")
        .accessibilityValue(isOn ? "Completed" : "Not completed")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .onChange(of: isOn) { wasOn, nowOn in
            guard nowOn, !wasOn, !reduceMotion else { return }
            burstVisible = true
            burst = false
            withAnimation(.easeOut(duration: 0.55)) { burst = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                burstVisible = false
                burst = false
            }
        }
    }
}

/// Today's progress as one thin line: crossed off over planned.
struct DayProgressBar: View {
    var done: Int
    var total: Int

    var body: some View {
        let fraction = total > 0 ? CGFloat(done) / CGFloat(total) : 0
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(TF.Palette.hairline)
                Capsule()
                    .fill(TF.Palette.signal)
                    .frame(width: max(fraction > 0 ? 4 : 0, proxy.size.width * fraction))
            }
        }
        .frame(height: 4)
        .animation(TF.Motion.soft, value: fraction)
        .opacity(total > 0 ? 1 : 0)
        .accessibilityElement()
        .accessibilityLabel("\(done) of \(total) done")
    }
}

/// A live dot with the mode's color. Pulses while working.
///
/// The ring is drawn from the clock (TimelineView), not a `repeatForever` animation: one
/// started with `withAnimation` in `onAppear` also captures every other change made in
/// that update (row text, list backgrounds, the tab highlight) and replays it forever,
/// which made the Mac window flicker every 1.6 seconds.
struct ModeDot: View {
    var mode: FlowMode
    var size: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period: TimeInterval = 1.6

    var body: some View {
        let pulsing = mode.isWorking && !reduceMotion
        Circle()
            .fill(TF.tint(for: mode))
            .frame(width: size, height: size)
            .overlay {
                if pulsing {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: Self.period) / Self.period
                        // Ease-out: fast out of the dot, slow fade at the edge.
                        let eased = 1 - pow(1 - phase, 3)
                        Circle()
                            .stroke(TF.tint(for: mode).opacity(0.5), lineWidth: 1)
                            .scaleEffect(1 + 1.4 * eased)
                            .opacity(0.8 * (1 - eased))
                    }
                }
            }
            .accessibilityHidden(true)
    }
}

/// "● FOCUS" — the mode, as a label.
struct ModeLabel: View {
    var mode: FlowMode
    var text: String? = nil

    var body: some View {
        HStack(spacing: 7) {
            ModeDot(mode: mode)
            Text(text ?? mode.label).tfEyebrowStyle(TF.textTint(for: mode))
        }
    }
}

/// Counts up from a date, once a second, using tabular digits.
struct ElapsedText: View {
    var since: Date
    var base: TimeInterval = 0
    var font: Font = .tfCaption

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(TFFormat.clock(base + max(0, context.date.timeIntervalSince(since))))
                .font(font)
                .contentTransition(.numericText())
        }
    }
}

/// Counts down to a date; shows "+0:12" once it's past.
struct CountdownText: View {
    var until: Date
    var font: Font = .tfCaption

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = until.timeIntervalSince(context.date)
            Text(remaining >= 0 ? TFFormat.clock(remaining) : "+" + TFFormat.clock(-remaining))
                .font(font)
                .contentTransition(.numericText())
        }
    }
}

/// A thin momentum meter: 0–100.
struct MomentumBar: View {
    var value: Int
    var tint: Color = TF.Palette.signal
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(TF.Palette.hairline)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * CGFloat(min(max(value, 0), 100)) / 100)
                    .animation(TF.Motion.soft, value: value)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Momentum \(value) of 100")
    }
}

/// One dot per task finished in an unbroken chain.
struct ChainDots: View {
    var chain: Int
    var tint: Color = TF.Palette.signal
    var maxDots = 12

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<min(chain, maxDots), id: \.self) { _ in
                Circle().fill(tint).frame(width: 5, height: 5)
            }
            if chain > maxDots {
                Text("+\(chain - maxDots)").font(.tfCaption).foregroundStyle(tint)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Chain of \(chain)")
    }
}

/// A big number with a small label underneath. Used on the scoreboard.
struct StatTile: View {
    var value: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 26, weight: .semibold).monospacedDigit())
                .foregroundStyle(TF.Palette.ink)
                .contentTransition(.numericText())
            Text(label).tfEyebrowStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Buttons

/// Solid ink capsule. The one primary action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = TF.Palette.ink
    var foreground: Color = TF.Palette.paper

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(foreground)
            // A label never wraps inside a capsule; it shrinks a little first.
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 22)
            .frame(minHeight: 52)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(tint))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(TF.Motion.snappy, value: configuration.isPressed)
    }
}

/// Hairline capsule for secondary actions.
struct QuietButtonStyle: ButtonStyle {
    var foreground: Color = TF.Palette.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(Capsule().strokeBorder(foreground.opacity(0.18), lineWidth: 1))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(TF.Motion.snappy, value: configuration.isPressed)
    }
}

/// A round icon button used on the immersive focus screen.
struct OrbButtonStyle: ButtonStyle {
    var tint: Color
    var size: CGFloat = 64
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.34, weight: .semibold))
            .foregroundStyle(filled ? TF.Palette.onSignal : tint)
            .frame(width: size, height: size)
            .background(
                Circle().fill(filled ? tint : tint.opacity(0.12))
            )
            .overlay(Circle().strokeBorder(tint.opacity(filled ? 0 : 0.35), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(TF.Motion.snappy, value: configuration.isPressed)
    }
}

// MARK: - Surfaces

extension View {
    /// The raised card used for "Now" and the morning ritual. Liquid Glass on top of paper.
    func tfCard(cornerRadius: CGFloat = TF.Radius.card, tint: Color? = nil) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(TF.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(tint?.opacity(0.35) ?? TF.Palette.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 8)
    }

    /// Floating glass for controls that sit above content.
    func tfGlass(cornerRadius: CGFloat = 22) -> some View {
        self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    /// Standard page background.
    func tfPage() -> some View {
        self.background(TF.Palette.paper.ignoresSafeArea())
    }
}

/// A one-line hairline separator.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(TF.Palette.hairline).frame(height: 1)
    }
}

// MARK: - Haptics

enum TFHaptics {
    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func tap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }

    static func warning() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}

// MARK: - Brand mark

/// The TruFocus symbol: one ring, one point of light (docs/brand, "Ember Open").
/// Drawn on a 100-unit field: ring radius 37, core radius 17. The glow is for dark surfaces only,
/// and below 24 pt the mark switches to the small cut: thicker ring, solid core, no gradient or glow.
struct TFMark: View {
    var size: CGFloat = 28
    /// Glow on dark, flat on light.
    var onDark: Bool = true

    private static let ringTop = Color(tfHex: 0xFF7A40)
    private static let ringBottom = Color(tfHex: 0xE2460E)
    private static let coreHot = Color(tfHex: 0xFFE6D6)
    private static let coreMid = Color(tfHex: 0xFF9560)

    var body: some View {
        let u = size / 100
        let small = size < 24
        ZStack {
            if onDark && !small {
                Circle()
                    .stroke(TF.Palette.signal.opacity(0.3), lineWidth: 5.5 * u)
                    .frame(width: 74 * u, height: 74 * u)
                    .blur(radius: 3.2 * u)
                Circle()
                    .fill(TF.Palette.signal.opacity(0.65))
                    .frame(width: 44.2 * u, height: 44.2 * u)
                    .blur(radius: 6 * u)
            }
            if small {
                Circle()
                    .stroke(TF.Palette.signal, lineWidth: 9 * u)
                    .frame(width: 74 * u, height: 74 * u)
                Circle()
                    .fill(Color(tfHex: 0xFF8A55))
                    .frame(width: 36 * u, height: 36 * u)
            } else {
                Circle()
                    .stroke(LinearGradient(colors: [Self.ringTop, Self.ringBottom], startPoint: .top, endPoint: .bottom),
                            lineWidth: 5.5 * u)
                    .frame(width: 74 * u, height: 74 * u)
                Circle()
                    .fill(RadialGradient(stops: [.init(color: Self.coreHot, location: 0),
                                                 .init(color: Self.coreMid, location: 0.45),
                                                 .init(color: TF.Palette.signal, location: 1)],
                                         center: .center, startRadius: 0, endRadius: 17 * u))
                    .frame(width: 34 * u, height: 34 * u)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The mark on a surface that follows the system appearance. On light it sits on an Ink
/// rounded square (the app icon in miniature); on dark the Ember ring stands on its own.
struct TFMarkBadge: View {
    var size: CGFloat = 20
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                TFMark(size: size, onDark: true)
            } else {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .fill(TF.Palette.night)
                TFMark(size: size * 0.8, onDark: true)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
