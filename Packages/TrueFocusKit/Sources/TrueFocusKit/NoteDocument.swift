import Foundation

/// One paragraph of a note.
public struct NoteLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The first line. Styled like the Apple Notes title.
        case title
        case heading
        case subheading
        case text
        /// Monostyled: a fixed-width line, for code or anything that should line up.
        case mono
        case bullet
        /// A dashed list item ("–").
        case dashed
        /// A numbered list item. The number is worked out from its place in the list.
        case numbered
        case quote
        case checklist(done: Bool)

        public var isChecklist: Bool {
            if case .checklist = self { return true }
            return false
        }
    }

    /// Deepest indent, like Apple Notes' practical limit.
    public static let maxIndent = 4

    public var kind: Kind
    public var text: String
    /// How far the paragraph is indented, 0 to `maxIndent`.
    public var indent: Int

    public init(_ kind: Kind, _ text: String, indent: Int = 0) {
        self.kind = kind
        self.text = text
        self.indent = min(max(indent, 0), NoteLine.maxIndent)
    }
}

/// A note, stored as a tiny Markdown dialect so it syncs as plain text and
/// survives any editor:
///
///     Title line
///     ## Heading
///     ### Subheading
///     plain text
///     ` monostyled
///     - bullet
///     – dashed
///     1. numbered
///     > quote
///     - [ ] open checklist item
///     - [x] crossed-off item
///     \t- an indented bullet (one tab per level)
///
/// The first line is always the title, like Apple Notes.
public struct NoteDocument: Equatable, Sendable {
    public var lines: [NoteLine]

    public init(lines: [NoteLine]) {
        self.lines = lines
    }

    public init(markup: String) {
        let raw = markup.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var parsed: [NoteLine] = []
        for (index, line) in raw.enumerated() {
            if index == 0 {
                var title = line
                if title.hasPrefix("# ") { title.removeFirst(2) }
                parsed.append(NoteLine(.title, title))
            } else {
                parsed.append(NoteDocument.parseBody(line))
            }
        }
        if parsed.isEmpty { parsed = [NoteLine(.title, "")] }
        lines = parsed
    }

    static func parseBody(_ raw: String) -> NoteLine {
        // Leading tabs are the indent.
        let indent = min(raw.prefix(while: { $0 == "\t" }).count, NoteLine.maxIndent)
        let line = String(raw.dropFirst(raw.prefix(while: { $0 == "\t" }).count))
        func make(_ kind: NoteLine.Kind, _ drop: Int) -> NoteLine {
            NoteLine(kind, String(line.dropFirst(drop)), indent: indent)
        }
        let lowered = line.lowercased()
        if lowered.hasPrefix("- [x] ") { return make(.checklist(done: true), 6) }
        if lowered == "- [x]" { return make(.checklist(done: true), 5) }
        if line.hasPrefix("- [ ] ") { return make(.checklist(done: false), 6) }
        if line == "- [ ]" { return make(.checklist(done: false), 5) }
        if line.hasPrefix("### ") { return make(.subheading, 4) }
        if line.hasPrefix("## ") { return make(.heading, 3) }
        if line.hasPrefix("- ") { return make(.bullet, 2) }
        if line.hasPrefix("– ") { return make(.dashed, 2) }
        if line.hasPrefix("> ") { return make(.quote, 2) }
        if line.hasPrefix("` ") { return make(.mono, 2) }
        if let range = line.range(of: #"^\d{1,3}\. "#, options: .regularExpression) {
            return NoteLine(.numbered, String(line[range.upperBound...]), indent: indent)
        }
        return NoteLine(.text, line, indent: indent)
    }

    public var markup: String {
        let numbers = listNumbers
        return lines.enumerated().map { index, line in
            if index == 0 { return line.text }
            return NoteDocument.serialize(line, number: numbers[index])
        }.joined(separator: "\n")
    }

    public static func serialize(_ line: NoteLine, number: Int = 1) -> String {
        let tabs = String(repeating: "\t", count: line.indent)
        let body: String
        switch line.kind {
        case .title: return line.text
        case .heading: body = "## " + line.text
        case .subheading: body = "### " + line.text
        case .text: body = line.text
        case .mono: body = "` " + line.text
        case .bullet: body = "- " + line.text
        case .dashed: body = "– " + line.text
        case .numbered: body = "\(number). " + line.text
        case .quote: body = "> " + line.text
        case .checklist(let done):
            let marker = done ? "- [x]" : "- [ ]"
            body = line.text.isEmpty ? marker : marker + " " + line.text
        }
        return tabs + body
    }

    /// The number each numbered line shows (1 for every other line). A list counts up at its
    /// own indent; a deeper line inside it doesn't break the count, anything shallower does.
    public var listNumbers: [Int] {
        var numbers = Array(repeating: 1, count: lines.count)
        var counters: [Int: Int] = [:]
        for (index, line) in lines.enumerated() {
            if case .numbered = line.kind {
                let next = (counters[line.indent] ?? 0) + 1
                counters[line.indent] = next
                numbers[index] = next
                counters = counters.filter { $0.key <= line.indent }
            } else {
                // Any other line ends the lists at its indent and deeper.
                counters = counters.filter { $0.key < line.indent }
            }
        }
        return numbers
    }

    /// The title, or a fallback built from the first non-empty line.
    public var title: String {
        let first = lines.first?.text.trimmingCharacters(in: .whitespaces) ?? ""
        if !first.isEmpty { return first }
        return lines.dropFirst().first { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }?.text ?? "New Note"
    }

    /// Second line of a list cell: the first meaningful line after the title.
    public var preview: String {
        lines.dropFirst()
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "No additional text"
    }

    public var openChecklistItems: [String] {
        lines.compactMap { line in
            guard case .checklist(false) = line.kind else { return nil }
            let text = line.text.trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
    }

    public var checklistProgress: (done: Int, total: Int) {
        var done = 0
        var total = 0
        for line in lines {
            if case .checklist(let isDone) = line.kind {
                total += 1
                if isDone { done += 1 }
            }
        }
        return (done, total)
    }

    public mutating func toggleChecklist(at index: Int) {
        guard lines.indices.contains(index), case .checklist(let done) = lines[index].kind else { return }
        lines[index].kind = .checklist(done: !done)
    }
}
