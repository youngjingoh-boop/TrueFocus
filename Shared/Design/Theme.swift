import SwiftUI
import TrueFocusKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The TrueFocus design language.
///
/// Ink on warm paper. One hot accent — Ember — that only ever means "you are working".
/// Think is a cool violet, rest a quiet mint. Everything else is typography and space.
/// Compiled into the widget extension too, so keep it free of app-only types.
enum TF {
    enum Palette {
        /// Primary text and solid controls.
        static let ink = Color.tfDynamic(light: 0x111113, dark: 0xF2F1EC)
        /// Secondary text.
        static let ink2 = Color.tfDynamic(light: 0x6B6B70, dark: 0x9A9AA0)
        /// Tertiary text, placeholders, empty check circles.
        static let ink3 = Color.tfDynamic(light: 0xA9A9AE, dark: 0x58585E)
        /// App background.
        static let paper = Color.tfDynamic(light: 0xFAF9F6, dark: 0x0A0A0B)
        /// Raised surfaces: cards, sheets.
        static let surface = Color.tfDynamic(light: 0xFFFFFF, dark: 0x151517)
        static let surface2 = Color.tfDynamic(light: 0xF1F0EC, dark: 0x1D1D20)
        static let hairline = Color.tfDynamic(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.08, darkOpacity: 0.10)

        /// Ember. Focus, the live dot, the one primary action.
        static let signal = Color(tfHex: 0xFF5A1F)
        static let think = Color(tfHex: 0x7C7CFF)
        static let rest = Color(tfHex: 0x34C98E)
        static let alarm = Color(tfHex: 0xFF3B30)
        /// Text and glyphs on an Ember (or think/rest) fill. Dark reads better than white on Ember.
        static let onSignal = Color(tfHex: 0x111113)

        /// Accent colors deep enough for small text on paper (4.5:1), bright on night.
        static let signalText = Color.tfDynamic(light: 0xC2410C, dark: 0xFF7A47)
        static let thinkText = Color.tfDynamic(light: 0x4B4BC4, dark: 0x9C9CFF)
        static let restText = Color.tfDynamic(light: 0x1E7A55, dark: 0x4FD9A2)

        /// The immersive focus canvas is always dark, whatever the system appearance.
        static let night = Color(tfHex: 0x050506)
        static let nightInk = Color(tfHex: 0xF4F3EE)
        static let nightInk2 = Color(tfHex: 0x8E8E93)
    }

    static func tint(for mode: FlowMode) -> Color {
        switch mode {
        case .focus: return Palette.signal
        case .think: return Palette.think
        case .rest: return Palette.rest
        case .idle: return Palette.ink3
        }
    }

    /// The mode's color for small text and labels.
    static func textTint(for mode: FlowMode) -> Color {
        switch mode {
        case .focus: return Palette.signalText
        case .think: return Palette.thinkText
        case .rest: return Palette.restText
        case .idle: return Palette.ink2
        }
    }

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let huge: CGFloat = 48
        /// Page side margins.
        #if os(macOS)
        static let page: CGFloat = 28
        #else
        static let page: CGFloat = 20
        #endif
    }

    enum Radius {
        static let card: CGFloat = 24
        static let control: CGFloat = 14
        static let row: CGFloat = 10
    }

    enum Motion {
        static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.86)
        static let soft = Animation.spring(response: 0.5, dampingFraction: 0.9)
        static let check = Animation.spring(response: 0.28, dampingFraction: 0.62)
    }
}

extension Font {
    /// The immersive timer. Thin, tabular, enormous.
    static let tfTimerHero = Font.system(size: 96, weight: .thin).monospacedDigit()
    static let tfTimer = Font.system(size: 64, weight: .thin).monospacedDigit()
    static let tfTimerSmall = Font.system(size: 34, weight: .light).monospacedDigit()
    #if os(iOS)
    // iPhone text follows the reader's Dynamic Type size. At the default size each style
    // lands on the same points as the Mac (34 / 28 / 20 / 12 / 11).
    /// Page titles ("Today").
    static let tfDisplay = Font.system(.largeTitle, weight: .bold)
    /// The day's outcome and the task in focus.
    static let tfHeadline = Font.system(.title, weight: .semibold)
    static let tfTitle = Font.system(.title3, weight: .semibold)
    /// Small caps labels above sections ("NOW", "SAT · OCT 17").
    static let tfEyebrow = Font.system(.caption2, weight: .semibold)
    static let tfCaption = Font.system(.caption, weight: .medium).monospacedDigit()
    #else
    /// Page titles ("Today").
    static let tfDisplay = Font.system(size: 34, weight: .bold)
    /// The day's outcome and the task in focus.
    static let tfHeadline = Font.system(size: 28, weight: .semibold)
    static let tfTitle = Font.system(size: 20, weight: .semibold)
    /// Small caps labels above sections ("NOW", "SAT · OCT 17").
    static let tfEyebrow = Font.system(size: 11, weight: .semibold)
    static let tfCaption = Font.system(size: 12, weight: .medium).monospacedDigit()
    #endif
}

extension Text {
    /// Tracked uppercase label.
    func tfEyebrowStyle(_ color: Color = TF.Palette.ink2) -> some View {
        self.font(.tfEyebrow).tracking(1.4).textCase(.uppercase).foregroundStyle(color)
    }
}

// MARK: - Color helpers

extension Color {
    init(tfHex hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    static func tfDynamic(light: UInt32, dark: UInt32, lightOpacity: Double = 1, darkOpacity: Double = 1) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(tfHex: dark, alpha: darkOpacity)
                : UIColor(tfHex: light, alpha: lightOpacity)
        })
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(tfHex: dark, alpha: darkOpacity)
                : NSColor(tfHex: light, alpha: lightOpacity)
        })
        #else
        return Color(tfHex: light, opacity: lightOpacity)
        #endif
    }
}

#if canImport(UIKit)
extension UIColor {
    convenience init(tfHex hex: UInt32, alpha: Double = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: CGFloat(alpha))
    }
}
#elseif canImport(AppKit)
extension NSColor {
    convenience init(tfHex hex: UInt32, alpha: Double = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: CGFloat(alpha))
    }
}
#endif
