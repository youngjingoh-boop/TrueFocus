import SwiftUI
import TrueFocusKit

/// Your own website lists: "Always allowed" and "Blocked on tasks". Same lists as the browser
/// extension's popup, which changes them through the app.
struct SiteListEditor: View {
    @Environment(FocusController.self) private var controller
    @State private var entry = ""
    @State private var problem: String?
    @FocusState private var entryFocused: Bool

    /// `.allow` or `.block`: which list this edits.
    let rule: SiteRule

    private var title: String { rule == .block ? "Blocked on tasks" : "Always allowed" }

    private var explanation: String {
        rule == .block
            ? "Closed in your browser while you're on a task, messages included. Open again when you pause, rest or stop."
            : "Never blocked, guarded or locked, even in focus. The adult filter still applies."
    }

    private var sites: [String] {
        rule == .block ? controller.settings.blockedSites : controller.settings.allowedSites
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundStyle(TF.Palette.ink)
                Text(explanation)
                    .font(.footnote)
                    .foregroundStyle(TF.Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let sites = sites
            if !sites.isEmpty {
                VStack(spacing: 0) {
                    ForEach(sites, id: \.self) { site in
                        HStack(spacing: 10) {
                            Image(systemName: rule == .block ? "nosign" : "checkmark.shield")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(rule == .block ? TF.Palette.signalText : TF.Palette.restText)
                                .frame(width: 22)
                            Text(site)
                                .font(.body)
                                .foregroundStyle(TF.Palette.ink)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                TFHaptics.tap()
                                controller.updateSettings { $0.setSiteRule(site, .none) }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(TF.Palette.ink3)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(rule == .block ? "Stop blocking \(site)" : "Stop allowing \(site)")
                        }
                        .padding(.leading, 12)
                        if site != sites.last { Hairline().padding(.leading, 44) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: TF.Radius.control).fill(TF.Palette.surface2))
            }

            HStack(spacing: 8) {
                TextField(rule == .block ? "Add a site, like reddit.com" : "Add a site, like notion.so", text: $entry)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($entryFocused)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    #endif
                    .onSubmit(add)
                    .onChange(of: entry) { _, _ in problem = nil }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: TF.Radius.control).fill(TF.Palette.surface2))
                Button("Add", action: add)
                    .buttonStyle(QuietButtonStyle())
                    .fixedSize()
                    .disabled(entry.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(TF.Palette.alarm)
            }
        }
    }

    private func add() {
        guard let site = Blocklist.normalizedSite(entry) else {
            problem = "That doesn't look like a site. Try something like linkedin.com."
            return
        }
        TFHaptics.success()
        controller.updateSettings { $0.setSiteRule(site, rule) }
        entry = ""
        problem = nil
    }
}
