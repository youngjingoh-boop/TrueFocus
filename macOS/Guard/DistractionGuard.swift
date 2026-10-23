import AppKit
import Foundation
import TrueFocusKit

/// Keeps distracting Mac apps out of the way while you work.
///
/// While a focus or think segment is running (or a system Focus with the TrueFocus filter is
/// on), activating a shielded app hides it again and shows a small reminder of what you're
/// on. It only ever *hides* apps — nothing is quit, nothing is changed — and it stands down
/// the moment the session ends or you turn it off in Settings.
@MainActor
final class DistractionGuard: FocusEffect {
    static let shared = DistractionGuard()

    private(set) var isArmed = false
    private var snapshot = LiveSnapshot.idle
    private var settings = TFSettings.default
    private var observer: NSObjectProtocol?
    /// Apps booted by the scroll watch stay hidden until their cooldown ends, even outside focus.
    private var cooldowns: [String: Date] = [:]
    private var lastBootAt: [String: Date] = [:]

    func focusDidChange(_ snapshot: LiveSnapshot, previous: LiveSnapshot?, settings: TFSettings) {
        self.snapshot = snapshot
        self.settings = settings
        observeActivationsIfNeeded()

        let shouldArm = snapshot.shouldShield && settings.shieldDuringFocus
        guard shouldArm != isArmed else { return }
        isArmed = shouldArm
        if shouldArm, let front = NSWorkspace.shared.frontmostApplication {
            handleActivation(of: front)
        }
    }

    /// Bundle IDs shielded during focus: your own list plus the known feed apps you haven't allowed.
    func blockedBundleIDs() -> Set<String> {
        Blocklist.macShieldedApps(custom: settings.macBlockedApps, allowedFeedApps: settings.macAllowedFeedApps)
    }

    func isBlocked(_ bundleID: String) -> Bool {
        blockedBundleIDs().contains(bundleID)
    }

    /// Keep an app hidden for a while (used after a doom-scroll boot-out).
    func startCooldown(for bundleID: String, duration: TimeInterval) {
        cooldowns[bundleID] = Date().addingTimeInterval(duration)
        observeActivationsIfNeeded()
    }

    func cooldownRemaining(for bundleID: String) -> TimeInterval? {
        guard let until = cooldowns[bundleID] else { return nil }
        let remaining = until.timeIntervalSinceNow
        if remaining <= 0 {
            cooldowns[bundleID] = nil
            return nil
        }
        return remaining
    }

    private func observeActivationsIfNeeded() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.handleActivation(of: app) }
        }
    }

    private func handleActivation(of app: NSRunningApplication) {
        guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return }
        let name = app.localizedName ?? Blocklist.macFeedApps[id] ?? "That app"

        if let remaining = cooldownRemaining(for: id) {
            app.hide()
            let minutes = max(1, Int((remaining / 60).rounded(.up)))
            HUDToast.shared.show(title: "\(name) is cooling off",
                                 message: "Back in \(minutes) min. \(backLine)",
                                 mode: snapshot.mode == .idle ? .focus : snapshot.mode)
            return
        }

        guard isArmed, isBlocked(id) else { return }
        app.hide()
        HUDToast.shared.show(title: backTitle,
                             message: "\(name) is shielded while you focus.",
                             mode: snapshot.mode == .idle ? .focus : snapshot.mode)

        // Opening a shielded app on autopilot counts as a boot, at most once a minute per app.
        let now = Date()
        if now.timeIntervalSince(lastBootAt[id] ?? .distantPast) > 60 {
            lastBootAt[id] = now
            FocusController.shared.recordBoot(source: "mac-native", site: name, reason: "shielded")
        }
    }

    private var backTitle: String {
        if let task = snapshot.headline, !task.isEmpty { return "Back to “\(TFFormat.truncate(task, to: 40))”" }
        return "Back to work"
    }

    private var backLine: String {
        if let task = snapshot.headline, !task.isEmpty { return "Back to “\(TFFormat.truncate(task, to: 40))”." }
        return "Back to what matters."
    }
}
