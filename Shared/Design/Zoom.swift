import Observation
import SwiftUI

/// Mac page zoom (⌘+, ⌘−, ⌘0), like a browser's: every font, icon and checkbox circle on
/// the Mac is sized through `TFZoom.pt`, so the page re-lays itself out at the new size and
/// stays sharp. macOS has no Dynamic Type for this to ride on. The iPhone keeps the reader's
/// Dynamic Type and a zoom of 1.
@Observable
final class TFZoom {
    static let shared = TFZoom()

    static let levels: [CGFloat] = [0.8, 0.9, 1.0, 1.1, 1.25, 1.4, 1.6, 1.8]
    private static let key = "tf.mac.zoom"

    private(set) var scale: CGFloat

    private init() {
        let stored = CGFloat(UserDefaults.standard.double(forKey: TFZoom.key))
        scale = TFZoom.levels.contains(stored) ? stored : 1
    }

    /// A point size at the current zoom.
    static func pt(_ points: CGFloat) -> CGFloat {
        #if os(macOS)
        points * shared.scale
        #else
        points
        #endif
    }

    var percent: Int { Int((scale * 100).rounded()) }
    var canZoomIn: Bool { scale < (TFZoom.levels.last ?? 1) }
    var canZoomOut: Bool { scale > (TFZoom.levels.first ?? 1) }

    /// One step bigger (+1) or smaller (−1); 0 is actual size.
    func step(_ direction: Int) {
        let next: CGFloat
        if direction == 0 {
            next = 1
        } else {
            let index = TFZoom.levels.firstIndex { $0 >= scale - 0.001 } ?? 2
            next = TFZoom.levels[min(max(index + direction, 0), TFZoom.levels.count - 1)]
        }
        guard next != scale else { return }
        scale = next
        UserDefaults.standard.set(Double(next), forKey: TFZoom.key)
        NotificationCenter.default.post(name: .tfZoomChanged, object: nil)
    }
}

extension Notification.Name {
    static let tfZoomChanged = Notification.Name("TrueFocusZoomChanged")
}

extension Font {
    /// A system text style. On the iPhone it is that style, following Dynamic Type; on the Mac,
    /// the style's point size at the current zoom.
    static func tf(_ style: Font.TextStyle) -> Font {
        #if os(macOS)
        let size: CGFloat
        var weight: Font.Weight = .regular
        switch style {
        case .largeTitle: size = 26
        case .title: size = 22
        case .title2: size = 17
        case .title3: size = 15
        case .headline: size = 13; weight = .bold
        case .subheadline: size = 11
        case .callout: size = 12
        case .footnote, .caption, .caption2: size = 10
        default: size = 13
        }
        return .system(size: TFZoom.pt(size), weight: weight)
        #else
        return .system(style)
        #endif
    }
}
