import SwiftUI
import TrueFocusKit

/// Sync: off until you turn it on. Linking devices: one shows a code, the other types it in, and
/// both show the same match number before the key is handed over.
struct SyncSettingsSection: View {
    @State private var sync = SyncService.shared
    /// This device offered a code.
    @State private var hosted: SyncService.HostedLink?
    /// …and someone entered it.
    @State private var joined: SyncService.JoinedLink?
    /// This device entered a code and waits for the other to confirm.
    @State private var pending: SyncService.PendingJoin?
    /// The match number, once the other device has revealed its key.
    @State private var joinMatch: String?
    @State private var entering = false
    @State private var entry = ""
    @State private var working = false
    @State private var message: String?
    @State private var confirmingDelete = false
    @FocusState private var entryFocused: Bool

    var body: some View {
        SettingsSection("Sync", footnote: footnote) {
            if !sync.isAvailable {
                EmptyView()
            } else if let hosted {
                hostedLink(hosted)
            } else if let pending {
                pendingJoin(pending)
            } else if entering {
                codeEntry
            } else if sync.isEnabled {
                enabled
            } else {
                disabled
            }
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(TF.Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog("Delete synced data from the server?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete and stop syncing", role: .destructive) { Task { await deleteServerCopy() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes everything TrueFocus keeps on the server for this sync space. Your devices keep their own copies. Linked devices that stay on upload their future changes again.")
        }
    }

    private var footnote: String {
        sync.isAvailable
            ? "End-to-end encrypted: sealed on this device, and the key never goes to the server. Only devices you link can read it."
            : "This build has no sync server configured, so everything stays on this device."
    }

    // MARK: Off

    private var disabled: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Off on this device. Turn it on to keep your plan, notes and timeline in step on your iPhone and Mac.")
                .font(.body)
                .foregroundStyle(TF.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Turn on sync") {
                    Task {
                        working = true
                        await sync.turnOn()
                        working = false
                        message = nil
                    }
                }
                .buttonStyle(QuietButtonStyle())
                Button("Enter a code") { startEntering() }
                    .buttonStyle(QuietButtonStyle())
            }
            .disabled(working)
        }
    }

    // MARK: On

    private var enabled: some View {
        VStack(alignment: .leading, spacing: 12) {
            status
            if let tag = sync.spaceTag {
                // Linked devices show the same id; a different one means they aren't linked.
                Text("Sync ID \(tag) · the same on every linked device")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(TF.Palette.ink3)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                if sync.needsRelink {
                    Button("Start fresh here") {
                        Task {
                            await sync.startFreshSpace()
                            message = "This device has its own sync space now. Link your other devices to it."
                        }
                    }
                    .buttonStyle(QuietButtonStyle())
                } else {
                    Button("Link a device") { Task { await offerLink() } }
                        .buttonStyle(QuietButtonStyle())
                }
                Button("Enter a code") { startEntering() }
                    .buttonStyle(QuietButtonStyle())
            }
            .disabled(working)
            HStack(spacing: 8) {
                Button("Turn off here") {
                    Task {
                        await sync.turnOff()
                        message = "Sync is off on this device. Nothing leaves it until you turn it back on."
                    }
                }
                .buttonStyle(QuietButtonStyle(foreground: TF.Palette.ink2))
                if sync.spaceTag != nil {
                    Button("Delete server copy…") { confirmingDelete = true }
                        .buttonStyle(QuietButtonStyle(foreground: TF.Palette.alarm))
                }
            }
            .disabled(working)
        }
    }

    private var status: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.body)
                .foregroundStyle(TF.Palette.ink)
                .lineLimit(2)
            Spacer()
            Button {
                TFHaptics.tap()
                Task { await sync.syncNow() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(TF.Palette.ink2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(sync.status == .syncing)
            .accessibilityLabel("Sync now")
        }
    }

    private var statusColor: Color {
        switch sync.status {
        case .off: return TF.Palette.ink3
        case .failed: return TF.Palette.alarm
        case .syncing: return TF.Palette.think
        case .idle: return sync.lastSyncAt == nil ? TF.Palette.ink3 : TF.Palette.rest
        }
    }

    private var statusText: String {
        switch sync.status {
        case .off: return "Off"
        case .syncing: return "Syncing…"
        case .failed(let reason): return reason
        case .idle:
            guard let last = sync.lastSyncAt else { return "Not synced yet" }
            return "Synced \(last.formatted(.relative(presentation: .named)))"
        }
    }

    // MARK: Offering a code

    private func hostedLink(_ link: SyncService.HostedLink) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let joined {
                Text("Does the other device show \(joined.match)?")
                    .font(.headline)
                    .foregroundStyle(TF.Palette.ink)
                matchNumber(joined.match)
                Text("If the numbers differ, cancel: something is between your devices.")
                    .font(.subheadline)
                    .foregroundStyle(TF.Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(working ? "Linking…" : "They match") { Task { await approve(link, joined) } }
                        .buttonStyle(QuietButtonStyle())
                    Button("Cancel") { endLink() }
                        .buttonStyle(QuietButtonStyle(foreground: TF.Palette.ink2))
                }
                .disabled(working)
            } else {
                Text(spaced(link.code.code))
                    .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(TF.Palette.ink)
                    .textSelection(.enabled)
                    .accessibilityLabel("Code \(link.code.code.map(String.init).joined(separator: " "))")
                Text("On the other device: Settings › Sync › Enter a code. Works for 10 minutes.")
                    .font(.subheadline)
                    .foregroundStyle(TF.Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Cancel") { endLink() }
                    .buttonStyle(QuietButtonStyle(foreground: TF.Palette.ink2))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TF.Radius.control).fill(TF.Palette.surface2))
        .task(id: link.code.code) { await waitForJoiner(link) }
    }

    private func matchNumber(_ match: String) -> some View {
        Text(match.map(String.init).joined(separator: " "))
            .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(TF.Palette.ink)
            .accessibilityLabel("Match number \(match.map(String.init).joined(separator: " "))")
    }

    private func spaced(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }

    private func offerLink() async {
        TFHaptics.tap()
        working = true
        message = nil
        defer { working = false }
        do {
            joined = nil
            hosted = try await sync.offerLink()
        } catch {
            message = SyncService.describe(error)
        }
    }

    /// Polls until someone enters the code, the code expires, or the view goes away.
    private func waitForJoiner(_ link: SyncService.HostedLink) async {
        while !Task.isCancelled, joined == nil, link.code.expiresAt > Date() {
            do {
                if let found = try await sync.joiner(for: link) {
                    TFHaptics.tap()
                    joined = found
                    return
                }
            } catch {
                message = SyncService.describe(error)
                endLink()
                return
            }
            try? await Task.sleep(for: .seconds(1.5))
        }
        if joined == nil, !Task.isCancelled, hosted != nil {
            message = "That code expired. Make a new one."
            endLink()
        }
    }

    private func approve(_ link: SyncService.HostedLink, _ joined: SyncService.JoinedLink) async {
        working = true
        defer { working = false }
        do {
            try await sync.approve(link, joined)
            TFHaptics.success()
            message = "Linked. The other device is joining now."
            endLink()
        } catch {
            message = SyncService.describe(error)
        }
    }

    private func endLink() {
        hosted = nil
        joined = nil
    }

    // MARK: Entering a code

    private func startEntering() {
        message = nil
        entering = true
        entryFocused = true
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("6-digit code", text: $entry)
                    .font(.system(size: 22, weight: .medium, design: .rounded).monospacedDigit())
                    .textFieldStyle(.plain)
                    .focused($entryFocused)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    #endif
                    .onChange(of: entry) { _, value in
                        let digits = String(value.filter(\.isNumber).prefix(6))
                        if digits != value { entry = digits }
                    }
                    .onSubmit { Task { await join() } }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: TF.Radius.control).fill(TF.Palette.surface2))
                Button(working ? "Linking…" : "Link") { Task { await join() } }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(entry.count != 6 || working)
            }
            Text("This device joins the other one and turns sync on. Its tasks and notes are merged in.")
                .font(.footnote)
                .foregroundStyle(TF.Palette.ink3)
            Button("Cancel") {
                entering = false
                entry = ""
            }
            .buttonStyle(QuietButtonStyle(foreground: TF.Palette.ink2))
        }
    }

    private func pendingJoin(_ join: SyncService.PendingJoin) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let joinMatch {
                Text("Check the other device shows")
                    .font(.headline)
                    .foregroundStyle(TF.Palette.ink)
                matchNumber(joinMatch)
                Text("Then tap They match there. If it shows a different number, cancel.")
                    .font(.subheadline)
                    .foregroundStyle(TF.Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Waiting for the other device…")
                    .font(.headline)
                    .foregroundStyle(TF.Palette.ink)
            }
            HStack(spacing: 8) {
                ProgressView()
                Button("Cancel") { endJoin() }
                    .buttonStyle(QuietButtonStyle(foreground: TF.Palette.ink2))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TF.Radius.control).fill(TF.Palette.surface2))
        .task(id: join.code) { await waitForKey(join) }
    }

    private func endJoin() {
        pending = nil
        joinMatch = nil
    }

    private func join() async {
        guard entry.count == 6, !working else { return }
        working = true
        message = nil
        defer { working = false }
        do {
            joinMatch = nil
            pending = try await sync.join(code: entry)
            entering = false
            entry = ""
        } catch {
            message = SyncService.describe(error)
        }
    }

    /// Polls for the other device's key, then the sealed space key, for up to ten minutes.
    private func waitForKey(_ join: SyncService.PendingJoin) async {
        let giveUp = Date().addingTimeInterval(10 * 60)
        while !Task.isCancelled, Date() < giveUp {
            do {
                switch try await sync.checkJoin(join) {
                case .waiting:
                    break
                case .compare(let match):
                    if joinMatch != match {
                        TFHaptics.tap()
                        joinMatch = match
                    }
                case .joined:
                    TFHaptics.success()
                    endJoin()
                    message = "Linked. This device now shares one plan with the other."
                    return
                }
            } catch {
                endJoin()
                message = SyncService.describe(error)
                return
            }
            try? await Task.sleep(for: .seconds(1.5))
        }
        if !Task.isCancelled, pending != nil {
            endJoin()
            message = "The other device didn't confirm in time. Start again with a new code."
        }
    }

    // MARK: Deleting

    private func deleteServerCopy() async {
        working = true
        defer { working = false }
        do {
            try await sync.deleteServerCopy()
            message = "Deleted from the server. Sync is off on this device."
        } catch {
            message = SyncService.describe(error)
        }
    }
}
