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
    var canReadWindowTitles: Bool { AXIsProcessTrusted() }

    func requestWindowTitleAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Called by the bridge when the extension reports the active tab.
    func receiveBrowserTab(host: String, title: String) {
        guard let report = BrowserTabReport.make(host: host, title: title) else { return }
        browserReport = report
        remember(report.host)
    }

    func sample() -> ActivitySample? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let id = app.bundleIdentifier
        var sample = ActivitySample(appBundleID: id, appName: app.localizedName,
                                    windowTitle: canReadWindowTitles ? Self.focusedWindowTitle(of: app) : nil)
        if let id, DriftClassifier.browsers.contains(id), let tab = latestTab(), Self.isCurrent(tab, windowTitle: sample.windowTitle) {
            sample.host = tab.host
            sample.pageTitle = tab.title
        }
        return sample
    }

    /// The extension re-sends the active tab at least every 30 seconds while working, and the
    /// browser's window title carries the page title, so either one says the report still holds.
    private static func isCurrent(_ tab: BrowserTabReport, windowTitle: String?) -> Bool {
        if Date().timeIntervalSince(tab.at) < 45 { return true }
        guard let windowTitle, !tab.title.isEmpty else { return false }
        return windowTitle.contains(tab.title)
    }

    /// The newer of the bridge report (Chrome family) and the App Group report (Safari).
    private func latestTab() -> BrowserTabReport? {
        let safari = SharedStore.shared.read(BrowserTabReport.self, BrowserTabReport.key)
        if let safari { remember(safari.host) }
        switch (browserReport, safari) {
        case let (a?, b?): return a.at >= b.at ? a : b
        case let (a?, nil): return a
        case let (nil, b?): return b
        default: return nil
        }
    }

    private func remember(_ host: String) {
        recentHosts.removeAll { $0 == host }
        recentHosts.insert(host, at: 0)
        if recentHosts.count > 12 { recentHosts.removeLast(recentHosts.count - 12) }
    }

    private static func focusedWindowTitle(of app: NSRunningApplication) -> String? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success,
              let text = title as? String, !text.isEmpty else { return nil }
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
