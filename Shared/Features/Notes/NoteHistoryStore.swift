import Foundation
import TrueFocusKit

/// Keeps each note's earlier versions in a file on this device. They aren't synced: they can
/// hold a lot of text, and each device only needs what was written or received on it.
enum NoteHistoryStore {
    private static var folder: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support.appendingPathComponent("NoteHistory", isDirectory: true)
    }

    private static func file(_ noteID: UUID) -> URL? {
        folder?.appendingPathComponent(noteID.uuidString + ".json")
    }

    static func load(noteID: UUID) -> NoteHistory {
        guard let file = file(noteID), let data = try? Data(contentsOf: file),
              let history = try? JSONDecoder().decode(NoteHistory.self, from: data) else { return NoteHistory() }
        return history
    }

    static func save(_ history: NoteHistory, noteID: UUID) {
        guard let folder, let file = file(noteID), let data = try? JSONEncoder().encode(history) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    static func remove(noteID: UUID) {
        guard let file = file(noteID) else { return }
        try? FileManager.default.removeItem(at: file)
    }
}
