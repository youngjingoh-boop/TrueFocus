import Foundation

/// Turns a messy morning brain dump into a clean task list.
///
/// This is the offline, deterministic fallback. On devices with Apple Intelligence
/// the app first asks the on-device model, and falls back to this when it can't.
public enum BrainDump {
    /// Markers people type in front of list items.
    private static let prefixes: [String] = [
        "- [ ] ", "- [x] ", "- [X] ", "[ ] ", "[x] ", "[] ",
        "☐ ", "☑ ", "□ ", "○ ", "◦ ", "• ", "· ", "– ", "— ", "- ", "* ", "+ ", "> ",
    ]

    public static func extractTasks(from text: String, limit: Int = 60) -> [String] {
        var lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // One long line with commas or semicolons is a list someone typed fast.
        if lines.count == 1, let only = lines.first {
            let separators = CharacterSet(charactersIn: ";,")
            let pieces = only.components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if pieces.count >= 3 || only.contains(";") { lines = pieces }
        }

        var seen = Set<String>()
        var tasks: [String] = []
        for raw in lines {
            if isDoneMarker(raw) { continue }
            var line = stripPrefix(raw)
            line = line.trimmingCharacters(in: .whitespaces)
            // "Work:" style headers aren't tasks.
            if line.hasSuffix(":") { continue }
            if line.count < 2 { continue }
            if line.count > 140 {
                line = String(line.prefix(139)).trimmingCharacters(in: .whitespaces) + "…"
            }
            line = capitalizedFirst(line)
            let key = line.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            tasks.append(line)
            if tasks.count >= limit { break }
        }
        return tasks
    }

    static func isDoneMarker(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.hasPrefix("- [x]") || lowered.hasPrefix("[x]") || line.hasPrefix("☑") || line.hasPrefix("✓") || line.hasPrefix("✔")
    }

    static func stripPrefix(_ line: String) -> String {
        var result = line
        var changed = true
        while changed {
            changed = false
            for prefix in prefixes where result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
                changed = true
                break
            }
            // "1. ", "2) ", "10 - "
            if let range = result.range(of: #"^\d{1,3}\s*[\.\)\-:]\s+"#, options: .regularExpression) {
                result.removeSubrange(range)
                changed = true
            }
        }
        return result
    }

    static func capitalizedFirst(_ line: String) -> String {
        guard let first = line.first, first.isLowercase else { return line }
        return first.uppercased() + line.dropFirst()
    }
}
