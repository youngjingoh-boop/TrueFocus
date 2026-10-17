import Foundation

/// One paragraph of a note.
public struct NoteLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The first line. Styled like the Apple Notes title.
        case title
        case heading
        case text
        case bullet
        case checklist(done: Bool)

        public var isChecklist: Bool {
            if case .checklist = self { return true }
            return false
        }
    }

    public var kind: Kind
    public var text: String

    public init(_ kind: Kind, _ text: String) {
        self.kind = kind
        self.text = text
    }
}

/// A note, stored as a tiny Markdown dialect so it syncs as plain text and
/// survives any editor:
///
///     Title line
///     ## Heading
///     plain text
///     - bullet
///     - [ ] open checklist item
///     - [x] crossed-off item
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

    static func parseBody(_ line: String) -> NoteLine {
        let lowered = line.lowercased()
        if lowered.hasPrefix("- [x] ") { return NoteLine(.checklist(done: true), String(line.dropFirst(6))) }
        if lowered == "- [x]" { return NoteLine(.checklist(done: true), "") }
        if line.hasPrefix("- [ ] ") { return NoteLine(.checklist(done: false), String(line.dropFirst(6))) }
        if line == "- [ ]" { return NoteLine(.checklist(done: false), "") }
        if line.hasPrefix("## ") { return NoteLine(.heading, String(line.dropFirst(3))) }
        if line.hasPrefix("- ") { return NoteLine(.bullet, String(line.dropFirst(2))) }
        return NoteLine(.text, line)
    }

    public var markup: String {
        lines.enumerated().map { index, line in
            if index == 0 { return line.text }
            return NoteDocument.serialize(line)
        }.joined(separator: "\n")
    }

    public static func serialize(_ line: NoteLine) -> String {
        switch line.kind {
        case .title: return line.text
        case .heading: return "## " + line.text
        case .text: return line.text
        case .bullet: return "- " + line.text
        case .checklist(let done):
            let marker = done ? "- [x]" : "- [ ]"
            return line.text.isEmpty ? marker : marker + " " + line.text
        }
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
