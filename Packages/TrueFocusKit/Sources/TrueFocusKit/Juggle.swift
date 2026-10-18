import Foundation

/// Juggling: a few tasks in the air at once, for when the current one is waiting on
/// someone. The rules are here so every surface agrees on them.
public enum Juggle {
    /// The most tasks the setting allows in the air, the current one included.
    public static let maxLimit = 5

    /// Who to switch to when you leave `currentID`: the next task in the juggle that isn't
    /// waiting, going round from the current one's slot. Nil if every other one is waiting.
    public static func next(after currentID: UUID?, in items: [LiveSnapshot.Item]) -> LiveSnapshot.Item? {
        guard !items.isEmpty else { return nil }
        let start = items.firstIndex { $0.id == currentID } ?? -1
        for step in 1...items.count {
            let item = items[(start + step + items.count) % items.count]
            if item.id != currentID && !item.isWaiting { return item }
        }
        return nil
    }

    /// One line for small surfaces: "Juggling Reply to Ben · ⏳ Invoice".
    public static func summary(_ items: [LiveSnapshot.Item], excluding currentID: UUID?, maxTitle: Int = 22) -> String? {
        let others = items.filter { $0.id != currentID }
        guard !others.isEmpty else { return nil }
        let names = others.map { ($0.isWaiting ? "⏳ " : "") + TFFormat.truncate($0.title, to: maxTitle) }
        return "Juggling " + names.joined(separator: " · ")
    }
}
