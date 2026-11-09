import Foundation

/// The earlier versions of one note, behind its Before button.
///
/// Undo ends when the note closes, and text deleted last week is out of its reach. This keeps
/// the note's state from time to time: edits in one sitting share a version, a new one starts
/// after a minute, and a large deletion always starts one, so what it removed stays recoverable.
public struct NoteHistory: Codable, Equatable, Sendable {
    public struct Version: Codable, Equatable, Sendable {
        public var markup: String
        /// When this version began.
        public var at: Date

        public init(markup: String, at: Date) {
            self.markup = markup
            self.at = at
        }
    }

    public static let limit = 100
    /// Edits closer together than this share a version.
    public static let sittingSeconds: TimeInterval = 60
    /// Removing this many characters at once always keeps the text from before it.
    public static let largeDeletion = 15

    public private(set) var versions: [Version]

    public init(versions: [Version] = []) {
        self.versions = versions
    }

    /// Notes the note's current text. `sealing` starts a new version whatever the timing, for
    /// typing over a restored version: the newest one is then not what's being edited.
    public mutating func record(_ markup: String, at now: Date, sealing: Bool = false) {
        guard let last = versions.last else {
            versions.append(Version(markup: markup, at: now))
            return
        }
        guard last.markup != markup else { return }
        let sameSitting = now.timeIntervalSince(last.at) < NoteHistory.sittingSeconds
        let removed = last.markup.count - markup.count
        if sameSitting && !sealing && removed < NoteHistory.largeDeletion {
            versions[versions.count - 1].markup = markup
        } else {
            versions.append(Version(markup: markup, at: now))
            if versions.count > NoteHistory.limit { versions.removeFirst(versions.count - NoteHistory.limit) }
        }
    }
}
