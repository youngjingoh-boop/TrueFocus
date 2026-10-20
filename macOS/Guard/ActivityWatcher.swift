import AppKit
import ApplicationServices
import Foundation
import TrueFocusKit

/// What's in front right now, for the drift guard: the app, its focused window's title, and,
/// when a browser is in front, the tab the TruFocus extension last reported.
///
/// Privacy: names and titles only (no screenshots, keystrokes or page contents), read only
/// while a task is running, and never written anywhere except today's drift tally on this Mac.
@MainActor
final class ActivityWatcher {
    static let shared = ActivityWatcher()

    /// Tab reports from Chrome-family browsers arrive over the loopback bridge.
    private var browserReport: BrowserTabReport?
    /// Sites seen recently, newest first, for the start contract's suggestions.
    private(set) var recentHosts: [String] = []

    /// Window titles need Accessibility access (System Settings ▸ Privacy & Security ▸ Accessibility).
    /// `AXIsProcessTrusted()` never prompts, so checking it every tick is cheap and silent.
    var canReadWindowTitles: Bool { AXIsProcessTrusted() }

    private var askedForAccess = false

    /// The first time, macOS shows its own "Open System Settings" alert; after that it may stay
    /// silent, so open the Accessibility list directly.
    func requestWindowTitleAccess() {
        if askedForAccess,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
            return
        }
        askedForAccess = true
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Called by the bridge when the extension reports the active tab. Ignored unless a focus
    /// task is being watched, so nothing about browsing is held outside focus.
    func receiveBrowserTab(host: String, title: String) {
        guard DriftGuard.shared.isWatching, let report = BrowserTabReport.make(host: host, title: title) else { return }
        browserReport = report
        remember(report.host)
    }

    /// Forgets the last tab (the bridge's in memory, Safari's in the App Group) when watching
    /// stops, so no page title outlives the focus segment it was read in.
    func forgetTabs() {
        browserReport = nil
        SharedStore.shared.defaults.removeObject(forKey: BrowserTabReport.key)
    }

    func sample() -> ActivitySample? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let id = app.bundleIdentifier
        var sample = ActivitySample(appBundleID: id, appName: app.localizedName,
                                    windowTitle: canReadWindowTitles ? Self.focusedWindowTitle(of: app) : nil)
        if let id, DriftClassifier.browsers.contains(id) {
            let safari = SharedStore.shared.read(BrowserTabReport.self, BrowserTabReport.key)
            if let tab = BrowserTabReport.current(forBrowser: id, windowTitle: sample.windowTitle,
                                                  bridge: browserReport, safari: safari) {
                remember(tab.host)
                sample.host = tab.host
                sample.pageTitle = tab.title
            }
        }
        return sample
    }

    private func remember(_ host: String) {
        recentHosts.removeAll { $0 == host }
        recentHosts.insert(host, at: 0)
        if recentHosts.count > 12 { recentHosts.removeLast(recentHosts.count - 12) }
    }

    private static func focusedWindowTitle(of app: NSRunningApplication) -> String? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // AX calls are synchronous IPC on the main thread; the default timeout is 6 s, so a hung
        // app in front would freeze TruFocus every tick. A quarter second is plenty.
        AXUIElementSetMessagingTimeout(element, 0.25)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success,
              let text = (title as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return String(text.prefix(200))
    }

    struct WorkApp: Identifiable, Hashable {
        let id: String
        let name: String
    }

    /// Regular apps open right now (not ours, not utilities, not browsers), for suggestions.
    func openWorkApps() -> [WorkApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> WorkApp? in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                      !DriftClassifier.neutralApps.contains(id), !DriftClassifier.browsers.contains(id),
                      Blocklist.macFeedApps[id] == nil, let name = app.localizedName else { return nil }
                return WorkApp(id: id, name: name)
            }
    }
}
