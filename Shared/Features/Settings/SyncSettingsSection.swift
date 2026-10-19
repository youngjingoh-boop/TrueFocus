import SwiftUI
import TrueFocusKit

/// Sync status and linking devices: one shows a code, the other types it in.
struct SyncSettingsSection: View {
    @State private var sync = SyncService.shared
    @State private var code: PairingCode?
    @State private var entering = false
    @State private var entry = ""
    @State private var working = false
    @State private var message: String?
    @FocusState private var entryFocused: Bool

    var body: some View {
        SettingsSection("Sync", footnote: footnote) {
            status
            if sync.isAvailable, let tag = sync.spaceTag {
                // Linked devices show the same id; a different one means they aren't linked.
                Text("Sync ID \(tag) · the same on every linked device")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(TF.Palette.ink3)
                    .textSelection(.enabled)
            }
            if sync.isAvailable {
                if let code {
                    shownCode(code)
                } else if entering {
                    codeEntry
                } else {
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
                            Button("Link a device") { Task { await makeCode() } }
                                .buttonStyle(QuietButtonStyle())
                        }
                        Button("Enter a code") {
                            message = nil
                            entering = true
                            entryFocused = true
                        }
                        .buttonStyle(QuietButtonStyle())
                    }
                    .disabled(working)
                }
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(TF.Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var footnote: String {
        sync.isAvailable
            ? "Encrypted on this device before it leaves. Only devices you link can read it."
            : "This build has no sync server configured, so everything stays on this device."
    }

    // MARK: Status

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
            if sync.isAvailable {
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

    // MARK: Showing a code

    private func shownCode(_ code: PairingCode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(spaced(code.code))
                .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(TF.Palette.ink)
                .textSelection(.enabled)
                .accessibilityLabel("Code \(code.code.map(String.init).joined(separator: " "))")
            Text("On the other device: Settings › Sync › Enter a code. Works once, for 10 minutes.")
                .font(.subheadline)
                .foregroundStyle(TF.Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button("Done") { self.code = nil }
                .buttonStyle(QuietButtonStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TF.Radius.control).fill(TF.Palette.surface2))
    }

    private func spaced(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }

    private func makeCode() async {
        TFHaptics.tap()
        working = true
        message = nil
        defer { working = false }
        do {
            code = try await sync.makeLinkCode()
        } catch {
            message = SyncService.describe(error)
        }
    }

    // MARK: Entering a code

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
                    .onSubmit { Task { await link() } }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: TF.Radius.control).fill(TF.Palette.surface2))
                Button(working ? "Linking…" : "Link") { Task { await link() } }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(entry.count != 6 || working)
            }
            Text("This device joins the other one. Its tasks and notes are merged in.")
                .font(.footnote)
                .foregroundStyle(TF.Palette.ink3)
            Button("Cancel") {
                entering = false
                entry = ""
            }
            .buttonStyle(QuietButtonStyle(foreground: TF.Palette.ink2))
        }
    }

    private func link() async {
        guard entry.count == 6, !working else { return }
        working = true
        message = nil
        defer { working = false }
        do {
            try await sync.link(code: entry)
            TFHaptics.success()
            entering = false
            entry = ""
            message = "Linked. This device now shares one plan with the other."
        } catch {
            message = SyncService.describe(error)
        }
    }
}
