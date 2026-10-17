import Foundation
import TrueFocusKit

/// Flips a macOS Focus on when work starts and off when the day goes idle, by running two
/// Shortcuts you create once ("TrueFocus On" / "TrueFocus Off" — each a single "Set Focus"
/// action). With "Share Across Devices" on, your iPhone follows, so notifications are
/// silenced on both and the TrueFocus Focus filter raises the iPhone shields.
@MainActor
final class FocusModeBridge: FocusEffect {
    static let shared = FocusModeBridge()

    /// The last state we asked Shortcuts for. Nil until the first real transition, so launching
    /// TrueFocus never switches off a Focus you turned on yourself.
    private var requestedOn: Bool?
    private var wasEnabled = false
    private(set) var lastResult: String?

    func focusDidChange(_ snapshot: LiveSnapshot, previous: LiveSnapshot?, settings: TFSettings) {
        let wantOn = snapshot.mode.isActive && !snapshot.dayEnded
        let enabled = settings.macRunFocusShortcuts
        defer { wasEnabled = enabled }
        guard enabled else {
            requestedOn = nil
            return
        }
        // Launch, or the setting was just switched on: remember the state, don't act on it.
        guard wasEnabled, previous != nil else {
            requestedOn = wantOn
            return
        }
        guard wantOn != requestedOn else { return }
        requestedOn = wantOn
        let name = wantOn ? settings.macFocusOnShortcut : settings.macFocusOffShortcut
        run(shortcut: name)
    }

    /// Runs a shortcut by name off the main thread and records how it went.
    func run(shortcut name: String, completion: (@MainActor (Bool, String) -> Void)? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastResult = "No shortcut name set."
            completion?(false, "No shortcut name set.")
            return
        }
        Self.execute(["run", trimmed]) { [weak self] status, output in
            let ok = status == 0
            let message = ok ? "Ran “\(trimmed)”." : "Couldn't run “\(trimmed)”. Create it in the Shortcuts app first."
            if !ok, !output.isEmpty { print("TrueFocus: shortcuts run failed: \(output)") }
            self?.lastResult = message
            completion?(ok, message)
        }
    }

    /// Names of the shortcuts on this Mac, for the settings screen.
    func availableShortcuts(_ completion: @escaping @MainActor ([String]) -> Void) {
        Self.execute(["list"]) { status, output in
            guard status == 0 else { completion([]); return }
            let names = output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            completion(names)
        }
    }

    private nonisolated static func execute(_ arguments: [String],
                                            completion: @escaping @MainActor (Int32, String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            var status: Int32 = -1
            var output = ""
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                status = process.terminationStatus
                output = String(data: data, encoding: .utf8) ?? ""
            } catch {
                output = error.localizedDescription
            }
            let finalStatus = status
            let finalOutput = output
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(finalStatus, finalOutput) }
            }
        }
    }
}
