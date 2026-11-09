import Foundation

/// Bold inside a note line, stored as `**text**` so a note stays readable plain text
/// and old builds simply show the asterisks.
public enum NoteInline {
    public struct Span: Equatable, Sendable {
        public var text: String
        public var isBold: Bool

        public init(_ text: String, bold: Bool = false) {
            self.text = text
            self.isBold = bold
        }
    }

    private static let marker = "**"

    /// Splits a line into runs. An unpaired or empty `**` is just text.
    public static func spans(in text: String) -> [Span] {
        var spans: [Span] = []
        var rest = Substring(text)
        var plain = ""
        while let open = rest.range(of: marker) {
            let after = rest[open.upperBound...]
            guard let close = after.range(of: marker), close.lowerBound > after.startIndex else {
                plain += rest[..<open.upperBound]
                rest = after
                continue
            }
            plain += rest[..<open.lowerBound]
            if !plain.isEmpty {
                spans.append(Span(plain))
                plain = ""
            }
            spans.append(Span(String(after[..<close.lowerBound]), bold: true))
            rest = after[close.upperBound...]
        }
        plain += rest
        if !plain.isEmpty { spans.append(Span(plain)) }
        return spans
    }

    /// The line without its bold markers: for titles, previews and tasks sent to the plan.
    public static func plain(_ text: String) -> String {
        spans(in: text).map(\.text).joined()
    }

    /// Writes runs back as a line, joining neighbours of the same weight.
    public static func markup(from spans: [Span]) -> String {
        var merged: [Span] = []
        for span in spans where !span.text.isEmpty {
            if let last = merged.last, last.isBold == span.isBold {
                merged[merged.count - 1].text += span.text
            } else {
                merged.append(span)
            }
        }
        return merged.map { $0.isBold ? marker + $0.text + marker : $0.text }.joined()
    }
}
