import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// TextKit 1 layout manager that draws Notes-style list markers in the indent of each
/// list paragraph's first line: an empty ring, an Ember circle with a white check, or a bullet.
final class NoteLayoutManager: NSLayoutManager {
    /// Kind of the empty last line, which has no characters (and so no attributes) of its own.
    var extraLineKind: NoteBlockKind?

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let string = storage.string as NSString
        let padding = container.lineFragmentPadding

        if string.length > 0, glyphsToShow.length > 0 {
            let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            let end = min(NSMaxRange(characters), string.length)
            var cursor = string.paragraphRange(for: NSRange(location: min(characters.location, string.length - 1), length: 0)).location
            while cursor < end {
                let paragraph = string.paragraphRange(for: NSRange(location: cursor, length: 0))
                guard paragraph.length > 0 else { break }
                if paragraph.location > 0,
                   let kind = NoteFormatter.kind(from: storage.attributes(at: paragraph.location, effectiveRange: nil)),
                   kind.isList {
                    let glyph = glyphIndexForCharacter(at: paragraph.location)
                    let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                    let baseline = line.minY + location(forGlyphAt: glyph).y
                    drawMarker(kind, lineRect: line, baseline: baseline, origin: origin, padding: padding)
                }
                cursor = NSMaxRange(paragraph)
            }
        }

        if let kind = extraLineKind, kind.isList {
            let extra = extraLineFragmentRect
            if extra.height > 0 {
                let baseline = extra.minY + NoteFormatter.bodyFont.ascender
                drawMarker(kind, lineRect: extra, baseline: baseline, origin: origin, padding: padding)
            }
        }
    }

    /// The rect of the marker for a line, in text-container coordinates.
    static func markerRect(lineRect: CGRect, baseline: CGFloat, padding: CGFloat) -> CGRect {
        let diameter = NoteFormatter.markerDiameter
        let centerY = baseline - NoteFormatter.bodyFont.capHeight / 2
        return CGRect(x: lineRect.minX + padding, y: centerY - diameter / 2, width: diameter, height: diameter)
    }

    private func drawMarker(_ kind: NoteBlockKind, lineRect: CGRect, baseline: CGFloat, origin: CGPoint, padding: CGFloat) {
        var rect = Self.markerRect(lineRect: lineRect, baseline: baseline, padding: padding)
        rect = rect.offsetBy(dx: origin.x, dy: origin.y)

        switch kind {
        case .bullet:
            let size = max(5, (NoteFormatter.bodyFont.pointSize * 0.3).rounded())
            let dot = CGRect(x: origin.x + lineRect.minX + padding + (NoteFormatter.bulletIndent - size) / 2 - 2,
                             y: rect.midY - size / 2, width: size, height: size)
            fillOval(dot, color: NoteFormatter.primaryColor)
        case .todo:
            strokeOval(rect.insetBy(dx: 0.75, dy: 0.75), color: NoteFormatter.tertiaryColor, width: 1.5)
        case .done:
            fillOval(rect, color: NoteFormatter.checkColor)
            drawCheck(in: rect)
        default:
            break
        }
    }

    // MARK: Platform drawing

    #if os(iOS)
    private func fillOval(_ rect: CGRect, color: UIColor) {
        color.setFill()
        UIBezierPath(ovalIn: rect).fill()
    }

    private func strokeOval(_ rect: CGRect, color: UIColor, width: CGFloat) {
        color.setStroke()
        let path = UIBezierPath(ovalIn: rect)
        path.lineWidth = width
        path.stroke()
    }

    private func drawCheck(in rect: CGRect) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.68))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.73, y: rect.minY + rect.height * 0.36))
        path.lineWidth = max(1.6, rect.width * 0.1)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        UIColor(tfHex: 0x111113).setStroke()
        path.stroke()
    }
    #elseif os(macOS)
    private func fillOval(_ rect: CGRect, color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    private func strokeOval(_ rect: CGRect, color: NSColor, width: CGFloat) {
        color.setStroke()
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = width
        path.stroke()
    }

    private func drawCheck(in rect: CGRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.52))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.68))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.73, y: rect.minY + rect.height * 0.36))
        path.lineWidth = max(1.4, rect.width * 0.1)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor(tfHex: 0x111113).setStroke()
        path.stroke()
    }
    #endif
}
