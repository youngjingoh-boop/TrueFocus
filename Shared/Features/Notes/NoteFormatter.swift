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
}

/// What a paragraph is, as the editor sees it.
enum NoteBlockKind: String {
    case title, heading, text, bullet, todo, done

    var isList: Bool { self == .bullet || self == .todo || self == .done }
    var isChecklist: Bool { self == .todo || self == .done }

    init(_ kind: NoteLine.Kind) {
        switch kind {
        case .title: self = .title
        case .heading: self = .heading
        case .text: self = .text
        case .bullet: self = .bullet
        case .checklist(let done): self = done ? .done : .todo
        }
    }

    var lineKind: NoteLine.Kind {
        switch self {
        case .title: return .title
        case .heading: return .heading
        case .text: return .text
        case .bullet: return .bullet
        case .todo: return .checklist(done: false)
        case .done: return .checklist(done: true)
        }
    }
}

/// Converts NoteDocument markup to and from attributed text, with Apple Notes metrics:
/// system text styles and the default paragraph style — no added line or paragraph spacing.
enum NoteFormatter {

    // MARK: Fonts (Apple Notes parity: Title = Title 1 bold, Heading = Title 2 bold, Body = Body)

    #if os(iOS)
    static let bodyFont: UIFont = UIFont.preferredFont(forTextStyle: .body)
    static let titleFont: UIFont = bolded(UIFont.preferredFont(forTextStyle: .title1))
    static let headingFont: UIFont = bolded(UIFont.preferredFont(forTextStyle: .title2))

    private static func bolded(_ font: UIFont) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    static var primaryColor: UIColor { .label }
    static var secondaryColor: UIColor { .secondaryLabel }
    static var tertiaryColor: UIColor { .tertiaryLabel }
    #elseif os(macOS)
    static let bodyFont: NSFont = NSFont.preferredFont(forTextStyle: .body, options: [:])
    static let titleFont: NSFont = bolded(NSFont.preferredFont(forTextStyle: .title1, options: [:]))
    static let headingFont: NSFont = bolded(NSFont.preferredFont(forTextStyle: .title2, options: [:]))

    private static func bolded(_ font: NSFont) -> NSFont {
        let descriptor = font.fontDescriptor.withSymbolicTraits(.bold)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? NSFont.boldSystemFont(ofSize: font.pointSize)
    }

    static var primaryColor: NSColor { .labelColor }
    static var secondaryColor: NSColor { .secondaryLabelColor }
    static var tertiaryColor: NSColor { .tertiaryLabelColor }
    #endif

    /// Ember, for the checked circle.
    static var checkColor: NotePlatformColor { NotePlatformColor(tfHex: 0xFF5A1F) }

    // MARK: Geometry

    /// Diameter of the checklist circle, sized to the body text like Notes.
    static var markerDiameter: CGFloat { (bodyFont.pointSize * 1.15).rounded() }
    /// Indent that leaves room for the circle.
    static var listIndent: CGFloat { markerDiameter + 10 }
    static var bulletIndent: CGFloat { (bodyFont.pointSize * 1.15).rounded() }

    private static let listParagraph: NSParagraphStyle = indented(listIndent)
    private static let bulletParagraph: NSParagraphStyle = indented(bulletIndent)

    private static func indented(_ indent: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        return style
    }

    // MARK: Attributes

    static func attributes(for kind: NoteBlockKind) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.tfNoteBlock: kind.rawValue]
        switch kind {
        case .title:
            attributes[.font] = titleFont
            attributes[.foregroundColor] = primaryColor
            attributes[.paragraphStyle] = NSParagraphStyle.default
        case .heading:
            attributes[.font] = headingFont
            attributes[.foregroundColor] = primaryColor
            attributes[.paragraphStyle] = NSParagraphStyle.default
        case .text:
            attributes[.font] = bodyFont
            attributes[.foregroundColor] = primaryColor
            attributes[.paragraphStyle] = NSParagraphStyle.default
        case .bullet:
            attributes[.font] = bodyFont
            attributes[.foregroundColor] = primaryColor
            attributes[.paragraphStyle] = bulletParagraph
        case .todo:
            attributes[.font] = bodyFont
            attributes[.foregroundColor] = primaryColor
            attributes[.paragraphStyle] = listParagraph
        case .done:
            attributes[.font] = bodyFont
            attributes[.foregroundColor] = secondaryColor
            attributes[.paragraphStyle] = listParagraph
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = secondaryColor
        }
        return attributes
    }

    static func kind(from attributes: [NSAttributedString.Key: Any]) -> NoteBlockKind? {
        (attributes[.tfNoteBlock] as? String).flatMap(NoteBlockKind.init(rawValue:))
    }

    // MARK: Markup ⇄ attributed text

    /// Builds the editor text. `trailingKind` is the kind of an empty last line, which has
    /// no characters to carry attributes (the editor tracks it separately).
    static func attributedString(from markup: String) -> (text: NSAttributedString, trailingKind: NoteBlockKind?) {
        let document = NoteDocument(markup: markup)
        let result = NSMutableAttributedString(string: "")
        var trailing: NoteBlockKind?
        for (index, line) in document.lines.enumerated() {
            let kind: NoteBlockKind = index == 0 ? .title : NoteBlockKind(line.kind)
            let isLast = index == document.lines.count - 1
            if isLast && index > 0 && line.text.isEmpty {
                trailing = kind
                continue
            }
            let text = isLast ? line.text : line.text + "\n"
            result.append(NSAttributedString(string: text, attributes: attributes(for: kind)))
        }
        return (result, trailing)
    }

    static func isParagraphTerminator(_ character: unichar) -> Bool {
        character == 10 || character == 13 || character == 0x2029
    }

    /// Serializes editor text back to markup.
    static func markup(from text: NSAttributedString, trailingKind: NoteBlockKind?) -> String {
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
            let kind: NoteBlockKind
            if lines.isEmpty {
                kind = .title
            } else {
                let found = self.kind(from: text.attributes(at: paragraph.location, effectiveRange: nil)) ?? .text
                kind = found == .title ? .text : found
            }
            lines.append(NoteLine(kind.lineKind, lineText))
            cursor = NSMaxRange(paragraph)
        }
        if isParagraphTerminator(string.character(at: length - 1)) {
            let kind = trailingKind ?? .text
            lines.append(NoteLine((kind == .title ? .text : kind).lineKind, ""))
        }
        return NoteDocument(lines: lines).markup
    }
}
