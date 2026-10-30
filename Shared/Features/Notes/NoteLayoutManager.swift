import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// TextKit 1 layout manager that draws Notes-style list markers in the indent of each
/// list paragraph's first line (an empty ring, an Ember circle with a white check, a bullet,
/// a dash or a number), and a bar beside block quotes.
final class NoteLayoutManager: NSLayoutManager {
    /// Kind and indent of the empty last line, which has no characters (and so no attributes) of its own.
    var extraLineKind: NoteBlockKind?
    var extraLineIndent = 0

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let string = storage.string as NSString
        let padding = container.lineFragmentPadding

        if string.length > 0, glyphsToShow.length > 0 {
            let numbers = Self.listNumbers(in: storage)
            let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            let end = min(NSMaxRange(characters), string.length)
            var cursor = string.paragraphRange(for: NSRange(location: min(characters.location, string.length - 1), length: 0)).location
            while cursor < end {
                let paragraph = string.paragraphRange(for: NSRange(location: cursor, length: 0))
                guard paragraph.length > 0 else { break }
                let attributes = storage.attributes(at: paragraph.location, effectiveRange: nil)
                if paragraph.location > 0, let kind = NoteFormatter.kind(from: attributes) {
                    let indent = NoteFormatter.indent(from: attributes)
                    if kind == .quote {
                        drawQuoteBar(paragraph: paragraph, indent: indent, origin: origin, padding: padding)
                    } else if kind.isList {
                        let glyph = glyphIndexForCharacter(at: paragraph.location)
                        let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                        let baseline = line.minY + location(forGlyphAt: glyph).y
                        drawMarker(kind, indent: indent, number: numbers[paragraph.location] ?? 1,
                                   lineRect: line, baseline: baseline, origin: origin, padding: padding)
                    }
                }
                cursor = NSMaxRange(paragraph)
            }
        }

        if let kind = extraLineKind, kind.isList {
            let extra = extraLineFragmentRect
            if extra.height > 0 {
                let baseline = extra.minY + NoteFormatter.bodyFont.ascender
                let number = kind == .numbered ? Self.trailingNumber(in: storage, indent: extraLineIndent) : 1
                drawMarker(kind, indent: extraLineIndent, number: number,
                           lineRect: extra, baseline: baseline, origin: origin, padding: padding)
            }
        }
    }

    /// The number of every numbered paragraph, keyed by its location (NoteDocument.listNumbers).
    static func listNumbers(in storage: NSAttributedString) -> [Int: Int] {
        let string = storage.string as NSString
        var result: [Int: Int] = [:]
        var counters: [Int: Int] = [:]
        var cursor = 0
        var first = true
        while cursor < string.length {
            let paragraph = string.paragraphRange(for: NSRange(location: cursor, length: 0))
            guard paragraph.length > 0 else { break }
            let attributes = storage.attributes(at: paragraph.location, effectiveRange: nil)
            let indent = NoteFormatter.indent(from: attributes)
            if !first, NoteFormatter.kind(from: attributes) == .numbered {
                let next = (counters[indent] ?? 0) + 1
                counters[indent] = next
                result[paragraph.location] = next
                counters = counters.filter { $0.key <= indent }
            } else {
                counters = counters.filter { $0.key < indent }
            }
            first = false
            cursor = NSMaxRange(paragraph)
        }
        return result
    }

    /// The number an empty numbered last line would show.
    private static func trailingNumber(in storage: NSAttributedString, indent: Int) -> Int {
        let string = storage.string as NSString
        guard string.length > 0 else { return 1 }
        let last = string.paragraphRange(for: NSRange(location: string.length - 1, length: 0))
        let attributes = storage.attributes(at: last.location, effectiveRange: nil)
        guard NoteFormatter.kind(from: attributes) == .numbered, NoteFormatter.indent(from: attributes) == indent else { return 1 }
        return (listNumbers(in: storage)[last.location] ?? 0) + 1
    }

    /// The rect of the checklist circle for a line, in text-container coordinates.
    static func markerRect(lineRect: CGRect, baseline: CGFloat, padding: CGFloat, indent: Int = 0) -> CGRect {
        let diameter = NoteFormatter.markerDiameter
        let centerY = baseline - NoteFormatter.bodyFont.capHeight / 2
        return CGRect(x: lineRect.minX + padding + NoteFormatter.indentOffset(indent),
                      y: centerY - diameter / 2, width: diameter, height: diameter)
    }

    private func drawMarker(_ kind: NoteBlockKind, indent: Int, number: Int, lineRect: CGRect, baseline: CGFloat,
                            origin: CGPoint, padding: CGFloat) {
        var rect = Self.markerRect(lineRect: lineRect, baseline: baseline, padding: padding, indent: indent)
        rect = rect.offsetBy(dx: origin.x, dy: origin.y)
        let left = origin.x + lineRect.minX + padding + NoteFormatter.indentOffset(indent)

        switch kind {
        case .bullet:
            let size = max(5, (NoteFormatter.bodyFont.pointSize * 0.3).rounded())
            let dot = CGRect(x: left + (NoteFormatter.bulletIndent - size) / 2 - 2,
                             y: rect.midY - size / 2, width: size, height: size)
            fillOval(dot, color: NoteFormatter.primaryColor)
        case .dashed:
            drawText("–", rightAlignedTo: left + NoteFormatter.bulletIndent - 4, baseline: origin.y + baseline)
        case .numbered:
            drawText("\(number).", rightAlignedTo: left + NoteFormatter.numberIndent - 5, baseline: origin.y + baseline)
        case .todo:
            strokeOval(rect.insetBy(dx: 0.75, dy: 0.75), color: NoteFormatter.tertiaryColor, width: 1.5)
        case .done:
            fillOval(rect, color: NoteFormatter.checkColor)
            drawCheck(in: rect)
        default:
            break
        }
    }

    /// A list marker drawn as body text (a dash or "3."), ending at `right`.
    private func drawText(_ text: String, rightAlignedTo right: CGFloat, baseline: CGFloat) {
        let font = NoteFormatter.bodyFont
        let marker = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NoteFormatter.secondaryColor])
        let width = marker.size().width
        #if os(iOS)
        marker.draw(at: CGPoint(x: right - width, y: baseline - font.ascender))
        #else
        // The text view is flipped: points are measured from the top, like iOS.
        marker.draw(at: NSPoint(x: right - width, y: baseline - font.ascender))
        #endif
    }

    /// A thin Ember bar down the left of every line of a block quote.
    private func drawQuoteBar(paragraph: NSRange, indent: Int, origin: CGPoint, padding: CGFloat) {
        let glyphs = glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
        var top = CGFloat.greatestFiniteMagnitude
        var bottom: CGFloat = 0
        var left: CGFloat = 0
        enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
            top = min(top, rect.minY)
            bottom = max(bottom, rect.maxY)
            left = rect.minX
        }
        guard bottom > top else { return }
        let bar = CGRect(x: origin.x + left + padding + NoteFormatter.indentOffset(indent) + 1,
                         y: origin.y + top + 2, width: 3, height: bottom - top - 4)
        fillRoundedRect(bar, color: NoteFormatter.checkColor.withAlphaComponent(0.7))
    }

    // MARK: Platform drawing

    #if os(iOS)
    private func fillRoundedRect(_ rect: CGRect, color: UIColor) {
        color.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: rect.width / 2).fill()
    }

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
    private func fillRoundedRect(_ rect: CGRect, color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2).fill()
    }

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
