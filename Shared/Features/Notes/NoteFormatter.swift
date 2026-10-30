import Foundation
import TrueFocusKit
#if os(iOS)
import UIKit
typealias NotePlatformFont = UIFont
typealias NotePlatformColor = UIColor
#elseif os(macOS)
import AppKit
typealias NotePlatformFont = NSFont
typealias NotePlatformColor = NSColor
#endif

extension NSAttributedString.Key {
    /// The paragraph's block kind (`NoteBlockKind.rawValue`). Every character of a
    /// paragraph, including its newline, carries it.
    static let tfNoteBlock = NSAttributedString.Key("TrueFocusNoteBlock")
    /// The paragraph's indent level (an Int, 0 to `NoteLine.maxIndent`).
    static let tfNoteIndent = NSAttributedString.Key("TrueFocusNoteIndent")
}

extension Notification.Name {
    /// The note text size changed; open editors re-lay themselves out.
    static let tfNoteTextScaleChanged = Notification.Name("TrueFocusNoteTextScaleChanged")
}

/// What a paragraph is, as the editor sees it.
enum NoteBlockKind: String {
    case title, heading, subheading, text, mono, bullet, dashed, numbered, quote, todo, done

    /// Paragraphs with a marker in their indent, which Return continues.
    var isList: Bool {
        switch self {
        case .bullet, .dashed, .numbered, .todo, .done: return true
        default: return false
        }
    }
    var isChecklist: Bool { self == .todo || self == .done }

    init(_ kind: NoteLine.Kind) {
        switch kind {
        case .title: self = .title
        case .heading: self = .heading
        case .subheading: self = .subheading
        case .text: self = .text
        case .mono: self = .mono
        case .bullet: self = .bullet
        case .dashed: self = .dashed
        case .numbered: self = .numbered
        case .quote: self = .quote
        case .checklist(let done): self = done ? .done : .todo
        }
    }

    var lineKind: NoteLine.Kind {
        switch self {
        case .title: return .title
        case .heading: return .heading
        case .subheading: return .subheading
        case .text: return .text
        case .mono: return .mono
        case .bullet: return .bullet
        case .dashed: return .dashed
        case .numbered: return .numbered
        case .quote: return .quote
        case .todo: return .checklist(done: false)
        case .done: return .checklist(done: true)
        }
    }
}

/// Converts NoteDocument markup to and from attributed text, with Apple Notes metrics:
/// system text styles and the default paragraph style — no added line or paragraph spacing.
enum NoteFormatter {

    // MARK: Text size

    /// The note text size on this device, as a multiple of the system body size.
    static let textScales: [CGFloat] = [0.85, 1.0, 1.15, 1.3, 1.5]
    private static let scaleKey = "tf.notes.textScale"

    static var textScale: CGFloat {
        let stored = UserDefaults.standard.double(forKey: scaleKey)
        return stored > 0 ? CGFloat(stored) : 1
    }

    /// Steps the text size up or down (0 resets it), and tells open editors.
    static func stepTextScale(_ direction: Int) {
        let next: CGFloat
        if direction == 0 {
            next = 1
        } else {
            let index = textScales.firstIndex { $0 >= textScale - 0.001 } ?? 1
            next = textScales[min(max(index + direction, 0), textScales.count - 1)]
        }
        UserDefaults.standard.set(Double(next), forKey: scaleKey)
        NotificationCenter.default.post(name: .tfNoteTextScaleChanged, object: nil)
    }

    // MARK: Fonts (Apple Notes parity: Title = Title 1 bold, Heading = Title 2 bold,
    // Subheading = Title 3 semibold, Body = Body, Monostyled = monospaced body)

    #if os(iOS)
    private static func base(_ style: UIFont.TextStyle) -> UIFont { UIFont.preferredFont(forTextStyle: style) }
    static var bodyFont: UIFont { base(.body).withSize((base(.body).pointSize * textScale).rounded()) }
    static var titleFont: UIFont { weighted(base(.title1), .bold) }
    static var headingFont: UIFont { weighted(base(.title2), .bold) }
    static var subheadingFont: UIFont { weighted(base(.title3), .semibold) }
    static var monoFont: UIFont { .monospacedSystemFont(ofSize: (base(.body).pointSize * 0.94 * textScale).rounded(), weight: .regular) }

    private static func weighted(_ font: UIFont, _ weight: UIFont.Weight) -> UIFont {
        .systemFont(ofSize: (font.pointSize * textScale).rounded(), weight: weight)
    }

    static var primaryColor: UIColor { .label }
    static var secondaryColor: UIColor { .secondaryLabel }
    static var tertiaryColor: UIColor { .tertiaryLabel }
    #elseif os(macOS)
    private static func base(_ style: NSFont.TextStyle) -> NSFont { NSFont.preferredFont(forTextStyle: style, options: [:]) }
    static var bodyFont: NSFont { base(.body).withSize((base(.body).pointSize * textScale).rounded()) }
    static var titleFont: NSFont { weighted(base(.title1), .bold) }
    static var headingFont: NSFont { weighted(base(.title2), .bold) }
    static var subheadingFont: NSFont { weighted(base(.title3), .semibold) }
    static var monoFont: NSFont { .monospacedSystemFont(ofSize: (base(.body).pointSize * 0.94 * textScale).rounded(), weight: .regular) }

    private static func weighted(_ font: NSFont, _ weight: NSFont.Weight) -> NSFont {
        .systemFont(ofSize: (font.pointSize * textScale).rounded(), weight: weight)
    }

    static var primaryColor: NSColor { .labelColor }
    static var secondaryColor: NSColor { .secondaryLabelColor }
    static var tertiaryColor: NSColor { .tertiaryLabelColor }
    #endif

    /// Ember, for the checked circle and the quote bar.
    static var checkColor: NotePlatformColor { NotePlatformColor(tfHex: 0xFF5A1F) }

    // MARK: Geometry

    /// Diameter of the checklist circle, sized to the body text like Notes.
    static var markerDiameter: CGFloat { (bodyFont.pointSize * 1.15).rounded() }
    /// Indent that leaves room for the circle.
    static var listIndent: CGFloat { markerDiameter + 10 }
    static var bulletIndent: CGFloat { (bodyFont.pointSize * 1.15).rounded() }
    /// Room for "10." in a numbered list.
    static var numberIndent: CGFloat { (bodyFont.pointSize * 1.7).rounded() }
    static var quoteIndent: CGFloat { (bodyFont.pointSize * 0.9).rounded() }
    /// One level of indent.
    static var indentStep: CGFloat { (bodyFont.pointSize * 1.6).rounded() }

    /// Where a paragraph's marker column starts: its indent level.
    static func indentOffset(_ level: Int) -> CGFloat { CGFloat(level) * indentStep }

    private static func paragraphStyle(_ kind: NoteBlockKind, indent level: Int) -> NSParagraphStyle {
        let markerRoom: CGFloat
        switch kind {
        case .todo, .done: markerRoom = listIndent
        case .bullet, .dashed: markerRoom = bulletIndent
        case .numbered: markerRoom = numberIndent
        case .quote: markerRoom = quoteIndent
        default: markerRoom = 0
        }
        let indent = indentOffset(level) + markerRoom
        guard indent > 0 else { return .default }
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        return style
    }

    // MARK: Attributes

    static func attributes(for kind: NoteBlockKind, indent: Int = 0) -> [NSAttributedString.Key: Any] {
        let level = kind == .title ? 0 : min(max(indent, 0), NoteLine.maxIndent)
        var attributes: [NSAttributedString.Key: Any] = [
            .tfNoteBlock: kind.rawValue,
            .tfNoteIndent: level,
            .foregroundColor: primaryColor,
            .paragraphStyle: paragraphStyle(kind, indent: level),
        ]
        switch kind {
        case .title: attributes[.font] = titleFont
        case .heading: attributes[.font] = headingFont
        case .subheading: attributes[.font] = subheadingFont
        case .mono: attributes[.font] = monoFont
        case .text, .bullet, .dashed, .numbered, .quote, .todo: attributes[.font] = bodyFont
        case .done:
            attributes[.font] = bodyFont
            attributes[.foregroundColor] = secondaryColor
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = secondaryColor
        }
        return attributes
    }

    static func kind(from attributes: [NSAttributedString.Key: Any]) -> NoteBlockKind? {
        (attributes[.tfNoteBlock] as? String).flatMap(NoteBlockKind.init(rawValue:))
    }

    static func indent(from attributes: [NSAttributedString.Key: Any]) -> Int {
        attributes[.tfNoteIndent] as? Int ?? 0
    }

    // MARK: Markup ⇄ attributed text

    /// Builds the editor text. `trailing` is the kind and indent of an empty last line, which
    /// has no characters to carry attributes (the editor tracks it separately).
    static func attributedString(from markup: String) -> (text: NSAttributedString, trailing: (kind: NoteBlockKind, indent: Int)?) {
        let document = NoteDocument(markup: markup)
        let result = NSMutableAttributedString(string: "")
        var trailing: (kind: NoteBlockKind, indent: Int)?
        for (index, line) in document.lines.enumerated() {
            let kind: NoteBlockKind = index == 0 ? .title : NoteBlockKind(line.kind)
            let isLast = index == document.lines.count - 1
            if isLast && index > 0 && line.text.isEmpty {
                trailing = (kind, line.indent)
                continue
            }
            let text = isLast ? line.text : line.text + "\n"
            result.append(NSAttributedString(string: text, attributes: attributes(for: kind, indent: line.indent)))
        }
        return (result, trailing)
    }

    static func isParagraphTerminator(_ character: unichar) -> Bool {
        character == 10 || character == 13 || character == 0x2029
    }

    /// Serializes editor text back to markup.
    static func markup(from text: NSAttributedString, trailingKind: NoteBlockKind?, trailingIndent: Int = 0) -> String {
        let string = text.string as NSString
        let length = string.length
        guard length > 0 else { return "" }
        var lines: [NoteLine] = []
        var cursor = 0
        while cursor < length {
            let paragraph = string.paragraphRange(for: NSRange(location: cursor, length: 0))
            guard paragraph.length > 0 else { break }
            let terminated = isParagraphTerminator(string.character(at: NSMaxRange(paragraph) - 1))
            let content = NSRange(location: paragraph.location, length: paragraph.length - (terminated ? 1 : 0))
            let lineText = string.substring(with: content)
            if lines.isEmpty {
                lines.append(NoteLine(.title, lineText))
            } else {
                let attributes = text.attributes(at: paragraph.location, effectiveRange: nil)
                let found = kind(from: attributes) ?? .text
                lines.append(NoteLine((found == .title ? .text : found).lineKind, lineText, indent: indent(from: attributes)))
            }
            cursor = NSMaxRange(paragraph)
        }
        if isParagraphTerminator(string.character(at: length - 1)) {
            let kind = trailingKind ?? .text
            lines.append(NoteLine((kind == .title ? .text : kind).lineKind, "", indent: trailingIndent))
        }
        return NoteDocument(lines: lines).markup
    }
}
