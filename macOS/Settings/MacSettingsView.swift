import AppKit
import SafariServices
import SwiftUI
import TrueFocusKit
import UniformTypeIdentifiers

struct MacSettingsView: View {
    var body: some View {
        TabView {
            FlowTab()
                .tabItem { Label("Flow", systemImage: "bolt") }
            GuardTab()
                .tabItem { Label("Guard", systemImage: "shield.lefthalf.filled") }
            FocusTab()
                .tabItem { Label("Focus Mode", systemImage: "moon") }
            BrowserTab()
                .tabItem { Label("Browser", systemImage: "safari") }
        }
        .frame(width: 600, height: 560)
    }
}

// MARK: - Flow

private struct FlowTab: View {
    @Environment(FocusController.self) private var controller

    var body: some View {
        FlowSettingsView {
            SettingsSection("Menu bar", footnote: "Minutes, not seconds — a ticking clock in the corner of your eye is its own distraction.") {
                ToggleRow(title: "Show minutes next to the task", isOn: controller.binding(\.menuBarShowsTimer))
            }

            SettingsSection("Global shortcuts") {
                ShortcutRow(keys: "⌥⌘D", action: "Done with the current task")
                ShortcutRow(keys: "⌥⌘S", action: "Stuck → think time")
                ShortcutRow(keys: "⌥⌘B", action: "Back to it / start the next task")
                ShortcutRow(keys: "⌥⌘T", action: "Show TruFocus")
                ShortcutRow(keys: "⌥⌘K", action: "Next juggled task")
                ShortcutRow(keys: "⌥⌘P", action: "Pending: waiting on it → next task")
            }
        }
    }
}

private struct ShortcutRow: View {
    let keys: String
    let action: String

    var body: some View {
        HStack {
            Text(action)
            Spacer()
            Text(keys)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(TF.Palette.ink2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(TF.Palette.surface2))
        }
    }
}

// MARK: - Guard

private struct GuardTab: View {
    @Environment(FocusController.self) private var controller

    var body: some View {
        Form {
            Section {
                Toggle("Shield distracting apps while I work", isOn: controller.binding(\.shieldDuringFocus))
                Text("During focus and think time, opening a shielded app hides it again and reminds you what you're on. Nothing is quit or changed, and shields drop the moment you stop.")
                    .font(.callout)
                    .foregroundStyle(TF.Palette.ink2)
            }

            Section("Shielded apps") {
                ForEach(controller.settings.macBlockedApps, id: \.self) { bundleID in
                    AppRow(bundleID: bundleID) {
                        controller.updateSettings { $0.macBlockedApps.removeAll { $0 == bundleID } }
                    }
                }
                Button("Add App…", action: addApp)
                LabeledContent("Always shielded") {
                    Text(Blocklist.macFeedApps.values.sorted().joined(separator: ", "))
                        .foregroundStyle(TF.Palette.ink2)
                        .multilineTextAlignment(.trailing)
                }
            }

            DriftGuardSection()

            Section("Doom-scroll watch") {
                Toggle("Boot me out of feed apps when I doom-scroll", isOn: controller.binding(\.macWatchNativeScrolling))
                Text("While a feed app like Instagram or TikTok is in front, TruFocus counts scroll gestures — how many and how far. It never reads the screen, what you type, or anything in other apps. Websites are covered by the browser extension.")
                    .font(.callout)
                    .foregroundStyle(TF.Palette.ink2)
            }

            AdultFilterSection()
        }
        .formStyle(.grouped)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Shield"
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        controller.updateSettings { settings in
            for id in ids where !settings.macBlockedApps.contains(id) {
                settings.macBlockedApps.append(id)
            }
        }
    }
}

/// Notices when what's in front isn't the task, and nudges you back.
private struct DriftGuardSection: View {
    @Environment(FocusController.self) private var controller
    @State private var canReadTitles = ActivityWatcher.shared.canReadWindowTitles

    var body: some View {
        Section("Drift guard") {
            Toggle("Nudge me when I drift off the task", isOn: controller.binding(\.macDriftGuard))
            Text("When a task starts, say where it happens — its apps and sites. If something else holds the front for a minute or two (longer in the first five minutes), a small card asks if you want to head back. The browser extension adds the site and tab title.")
                .font(.callout)
                .foregroundStyle(TF.Palette.ink2)
            if controller.settings.macDriftGuard {
                Toggle("Let on-device AI judge what the rules can't place", isOn: controller.binding(\.macDriftUsesModel))
                    .disabled(!DriftJudge.shared.isAvailable)
                Text(DriftJudge.shared.isAvailable
                     ? "Apple Intelligence reads the app name, site and title — nothing else — on this Mac, and decides whether it fits the task. It also suggests topic words when a task starts."
                     : "Needs Apple Intelligence. Without it, the rules decide on their own.")
                    .font(.callout)
                    .foregroundStyle(TF.Palette.ink2)
                LabeledContent("Window titles") {
                    if canReadTitles {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(TF.Palette.restText)
                    } else {
                        Button("Allow…") { ActivityWatcher.shared.requestWindowTitleAccess() }
                    }
                }
                Text("Titles tell a marketing doc from a side project in the same app. macOS asks for Accessibility access; TruFocus only reads the front window's title.")
                    .font(.callout)
                    .foregroundStyle(TF.Palette.ink2)
            }
        }
        .task {
            // macOS doesn't announce the grant; look again every couple of seconds while open.
            while !Task.isCancelled {
                canReadTitles = ActivityWatcher.shared.canReadWindowTitles
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

private struct AppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 22, height: 22)
                Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 22, height: 22)
                Text(bundleID)
                    .foregroundStyle(TF.Palette.ink2)
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(TF.Palette.ink3)
            .help("Stop shielding")
        }
    }
}

/// The adult-content filter: on by default, and turning it off takes a cool-off, so the
/// choice is never made in a weak moment. The TrueFocus filter runs in the browser
/// extension; macOS's own Screen Time filter covers every app and browser.
private struct AdultFilterSection: View {
    @Environment(FocusController.self) private var controller
    @State private var confirmingOff = false

    var body: some View {
        let settings = controller.settings
        Section("Adult content filter") {
            if settings.adultFilterActive() {
                if let effective = settings.adultFilterOffEffectiveAt {
                    LabeledContent("Status") {
                        Text("On · turns off \(effective.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(TF.Palette.ink2)
                    }
                    Button("Keep it on") {
                        controller.updateSettings { $0.adultFilterOffRequestedAt = nil }
                    }
                } else {
                    LabeledContent("Status") {
                        Label("On", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(TF.Palette.rest)
                    }
                    Button("Turn Off…") { confirmingOff = true }
                }
            } else {
                LabeledContent("Status") {
                    Text("Off").foregroundStyle(TF.Palette.ink2)
                }
                Button("Turn On") {
                    controller.updateSettings {
                        $0.adultFilterEnabled = true
                        $0.adultFilterOffRequestedAt = nil
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("For a system-wide wall, also turn on macOS's own filter:")
                    .font(.callout)
                Text("System Settings ▸ Screen Time ▸ Content & Privacy ▸ Store, Web, Siri & Game Center ▸ Access to Web Content ▸ Limit Adult Websites")
                    .font(.callout)
                    .foregroundStyle(TF.Palette.ink2)
                    .textSelection(.enabled)
                Text("It works in every browser and app. If you want accountability, ask someone you trust to set the Screen Time passcode.")
                    .font(.callout)
                    .foregroundStyle(TF.Palette.ink2)
                Button("Open Screen Time Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Screen-Time-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .confirmationDialog("Turn off the adult content filter?", isPresented: $confirmingOff) {
            Button("Start \(Int(settings.adultFilterCoolOffHours))-hour cool-off", role: .destructive) {
                controller.updateSettings { $0.adultFilterOffRequestedAt = Date() }
            }
            Button("Keep it on", role: .cancel) {}
        } message: {
            Text("The filter stays on for the next \(Int(settings.adultFilterCoolOffHours)) hours, then turns off. You can cancel any time before then.")
        }
    }
}

// MARK: - Focus mode

private struct FocusTab: View {
    @Environment(FocusController.self) private var controller
    @State private var shortcuts: [String] = []
    @State private var testResult: String?

    var body: some View {
        let settings = controller.settings
        Form {
            Section {
                Toggle("Switch a macOS Focus on while I work", isOn: controller.binding(\.macRunFocusShortcuts))
                Text("TruFocus runs one shortcut when work starts and another when you go idle or shut down. With Share Across Devices on, your iPhone follows — notifications go quiet on both.")
                    .font(.callout)
                    .foregroundStyle(TF.Palette.ink2)
            }

            Section("Shortcuts") {
                shortcutField("Turn Focus on", text: controller.binding(\.macFocusOnShortcut), name: settings.macFocusOnShortcut)
                shortcutField("Turn Focus off", text: controller.binding(\.macFocusOffShortcut), name: settings.macFocusOffShortcut)
                if let testResult {
                    Text(testResult).font(.callout).foregroundStyle(TF.Palette.ink2)
                }
            }

            Section("Set it up once") {
                VStack(alignment: .leading, spacing: 6) {
                    step(1, "Open Shortcuts and create “\(settings.macFocusOnShortcut)” with one action: Set Focus ▸ Work ▸ On.")
                    step(2, "Create “\(settings.macFocusOffShortcut)” with: Set Focus ▸ Work ▸ Off.")
                    step(3, "System Settings ▸ Focus: turn on Share Across Devices.")
                    step(4, "In the Work Focus, allow notifications from TruFocus only, and add the TruFocus Focus filter with Deep Work shields on — that raises the shields on your iPhone too.")
                }
                Button("Open Shortcuts") {
                    if let url = URL(string: "shortcuts://") { NSWorkspace.shared.open(url) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            FocusModeBridge.shared.availableShortcuts { shortcuts = $0 }
        }
    }

    private func shortcutField(_ label: String, text: Binding<String>, name: String) -> some View {
        HStack {
            TextField(label, text: text)
            if !shortcuts.isEmpty {
                Image(systemName: shortcuts.contains(name) ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(shortcuts.contains(name) ? TF.Palette.rest : TF.Palette.signal)
                    .help(shortcuts.contains(name) ? "Found in Shortcuts" : "Not found in Shortcuts yet")
            }
            Button("Test") {
                FocusModeBridge.shared.run(shortcut: name) { _, message in
                    testResult = message
                }
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(TF.Palette.signal)
                .frame(width: 14)
            Text(text).font(.callout)
        }
    }
}

// MARK: - Browser

private struct BrowserTab: View {
    @State private var bridgeStatus: BridgeStatus = .checking
    @State private var copyMessage: String?

    enum BridgeStatus {
        case checking, running, unreachable
    }

    var body: some View {
        Form {
            Section("Safari") {
                Text("Turn on the TruFocus extension and allow it on all websites. It hides Reels and Shorts, keeps Instagram to your messages, boots you out of doom-scrolls, and filters adult sites.")
                    .font(.callout)
                    .foregroundStyle(TF.Palette.ink2)
                Button("Open Safari Extension Settings") {
                    let identifier = (Bundle.main.bundleIdentifier ?? "") + ".safari"
                    SFSafariApplication.showPreferencesForExtension(withIdentifier: identifier) { _ in }
                }
            }

            Section("Chrome, Arc, Brave, Edge") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Click “Copy Extension Folder” below.")
                    Text("2. Open chrome://extensions and turn on Developer mode.")
                    Text("3. Click Load unpacked and choose the folder that opens.")
                }
                .font(.callout)
                Button("Copy Extension Folder", action: copyExtension)
                if let copyMessage {
                    Text(copyMessage).font(.callout).foregroundStyle(TF.Palette.ink2)
                }
                LabeledContent("Link to TruFocus") {
                    switch bridgeStatus {
                    case .checking:
                        Text("Checking…").foregroundStyle(TF.Palette.ink2)
                    case .running:
                        Label("Connected", systemImage: "circle.fill")
                            .foregroundStyle(TF.Palette.rest)
                    case .unreachable:
                        Label("Not reachable", systemImage: "circle")
                            .foregroundStyle(TF.Palette.signal)
                    }
                }
                Text("Chrome-family browsers read your current task from TruFocus over a local-only connection on this Mac (127.0.0.1:52525).")
                    .font(.callout)
                    .foregroundStyle(TF.Palette.ink2)
            }
        }
        .formStyle(.grouped)
        .task { await checkBridge() }
    }

    private func checkBridge() async {
        guard let url = URL(string: "http://127.0.0.1:52525/state") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            bridgeStatus = ok ? .running : .unreachable
        } catch {
            bridgeStatus = .unreachable
        }
    }

    /// Copies the bundled web extension to Application Support so Chrome can load it from a stable place.
    private func copyExtension() {
        let fileManager = FileManager.default
        guard let source = Self.bundledExtensionFolder() else {
            copyMessage = "Couldn't find the extension inside TruFocus. Load the Extensions/web folder from the source code instead."
            return
        }
        do {
            let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
            let destination = support.appendingPathComponent("TrueFocus/ChromeExtension", isDirectory: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let items = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            for item in items {
                let name = item.lastPathComponent
                // Only the extension's own files, not the appex's compiled resources.
                guard ["json", "js", "css", "html", "png", "svg"].contains(item.pathExtension.lowercased()) else { continue }
                try fileManager.copyItem(at: item, to: destination.appendingPathComponent(name))
            }
            NSWorkspace.shared.activateFileViewerSelecting([destination])
            copyMessage = "Copied to \(destination.path)"
        } catch {
            copyMessage = "Couldn't copy the extension: \(error.localizedDescription)"
        }
    }

    /// The Safari extension's Resources folder holds the same web extension files.
    private static func bundledExtensionFolder() -> URL? {
        guard let plugins = Bundle.main.builtInPlugInsURL,
              let appexes = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil) else {
            return nil
        }
        for appex in appexes where appex.pathExtension == "appex" {
            let resources = appex.appendingPathComponent("Contents/Resources", isDirectory: true)
            if FileManager.default.fileExists(atPath: resources.appendingPathComponent("manifest.json").path) {
                return resources
            }
        }
        return nil
    }
}
