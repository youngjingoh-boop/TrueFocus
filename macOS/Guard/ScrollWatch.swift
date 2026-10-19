import AppKit
import Foundation
import TrueFocusKit

/// Doom-scroll detection for native feed apps on the Mac (Instagram, TikTok, YouTube… —
/// including iPad apps running on Apple silicon). The web is covered by the browser extension.
///
/// Privacy: it listens to scroll-wheel/trackpad scroll events *only while a listed feed app is
/// frontmost*, and only counts how far you scrolled. It never reads the screen, keystrokes,
/// window contents, or anything in other apps.
@MainActor
final class ScrollWatch: FocusEffect {
    static let shared = ScrollWatch()

    private(set) var isEnabled = false
    /// The feed app currently being watched, if one is frontmost.
    private(set) var watchedApp: String?

    private var detector = DoomScrollDetector()
    private var snapshot = LiveSnapshot.idle
    private var settings = TFSettings.default
    private var scrollMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var tickTimer: Timer?

    // Trackpad gesture in progress.
    private var gestureDistance: CGFloat = 0
    // Mouse wheel notches, grouped into one stroke when less than 300 ms apart.
    private var wheelDistance: CGFloat = 0
    private var wheelFlush: DispatchWorkItem?
    private var lastWarnAt = Date.distantPast

    /// Movement shorter than this isn't a stroke (a nudge, a correction).
    private static let minStrokePoints: CGFloat = 40
    /// Roughly one viewport of a feed, in scroll points.
    private static let pointsPerScreen: CGFloat = 700
    /// Points per line for mice that report line-based deltas.
    private static let pointsPerLine: CGFloat = 12
    private static let cooldown: TimeInterval = 10 * 60

    func focusDidChange(_ snapshot: LiveSnapshot, previous: LiveSnapshot?, settings: TFSettings) {
        self.snapshot = snapshot
        self.settings = settings
        detector.config = settings.doomScroll
        detector.strict = snapshot.shouldShield
        setEnabled(settings.macWatchNativeScrolling)
    }

    static func isFeedApp(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return Blocklist.macFeedApps[bundleID] != nil
    }

    // MARK: Lifecycle

    private func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                MainActor.assumeIsolated { self?.frontmostChanged(to: bundleID) }
            }
            frontmostChanged(to: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        } else {
            if let activationObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            }
            activationObserver = nil
            stopWatching()
        }
    }

    private func frontmostChanged(to bundleID: String?) {
        guard let bundleID, Self.isFeedApp(bundleID) else {
            stopWatching()
            return
        }
        if bundleID != watchedApp { detector.reset() }
        startWatching(bundleID)
    }

    private func startWatching(_ bundleID: String) {
        watchedApp = bundleID
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let deltaY = event.scrollingDeltaY
            let phase = event.phase
            let momentum = event.momentumPhase
            let precise = event.hasPreciseScrollingDeltas
            MainActor.assumeIsolated {
                self?.handleScroll(deltaY: deltaY, phase: phase, momentum: momentum, precise: precise)
            }
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopWatching() {
        watchedApp = nil
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        tickTimer?.invalidate()
        tickTimer = nil
        wheelFlush?.cancel()
        wheelFlush = nil
        gestureDistance = 0
        wheelDistance = 0
    }

    // MARK: Counting

    private func handleScroll(deltaY: CGFloat, phase: NSEvent.Phase, momentum: NSEvent.Phase, precise: Bool) {
        guard watchedApp != nil,
              Self.isFeedApp(NSWorkspace.shared.frontmostApplication?.bundleIdentifier) else { return }
        // Inertia after a trackpad flick belongs to the gesture that started it.
        guard momentum.isEmpty else { return }

        // AppKit reports scrolling further down the content as negative deltaY.
        let points = precise ? deltaY : deltaY * Self.pointsPerLine

        if !phase.isEmpty {
            if phase.contains(.began) { gestureDistance = 0 }
            if phase.contains(.began) || phase.contains(.changed) { gestureDistance += points }
            if phase.contains(.ended) || phase.contains(.cancelled) {
                finishStroke(forwardDistance: -gestureDistance)
                gestureDistance = 0
            }
        } else {
            wheelDistance += points
            wheelFlush?.cancel()
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.flushWheel() }
            }
            wheelFlush = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    private func flushWheel() {
        let distance = -wheelDistance
        wheelDistance = 0
        finishStroke(forwardDistance: distance)
    }

    private func finishStroke(forwardDistance: CGFloat) {
        guard forwardDistance >= Self.minStrokePoints else { return }
        let screens = Double(forwardDistance / Self.pointsPerScreen)
        react(to: detector.stroke(at: Date(), screens: screens))
    }

    private func tick() {
        guard watchedApp != nil else { return }
        react(to: detector.tick(at: Date()))
    }

    // MARK: Verdicts

    private func react(to verdict: DoomScrollDetector.Verdict) {
        switch verdict {
        case .calm:
            break
        case .warn:
            guard Date().timeIntervalSince(lastWarnAt) > 20 else { return }
            lastWarnAt = Date()
            let task = snapshot.headline
            HUDToast.shared.show(title: "You're scrolling.",
                                 message: task.map { "Back to “\(TFFormat.truncate($0, to: 40))”?" } ?? "Is this what you sat down to do?",
                                 mode: .focus)
        case .boot(let reason):
            boot(reason: reason)
        }
    }

    private func boot(reason: DoomScrollDetector.Reason) {
        guard let bundleID = watchedApp else { return }
        let name = Blocklist.macFeedApps[bundleID] ?? "this app"
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            app.hide()
        }
        detector.reset()
        stopWatching()
        DistractionGuard.shared.startCooldown(for: bundleID, duration: Self.cooldown)
        FocusController.shared.recordBoot(source: "mac-native", site: name, reason: reason.rawValue)

        let line = Copy(settings: settings).bootOut(site: name, task: snapshot.headline)
        WakeUpOverlay.shared.show(.standard(title: line.title, message: line.body, snapshot: snapshot))
    }
}
