import SwiftUI
import TrueFocusKit

/// "Always allowed": sites you use for work that TrueFocus should never block or guard.
struct AllowedSitesEditor: View {
    @Environment(FocusController.self) private var controller
    @State private var entry = ""
    @State private var problem: String?
    @FocusState private var entryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Always allowed").font(.body).foregroundStyle(TF.Palette.ink)
                Text("Never blocked, guarded or locked, even in focus. The adult filter still applies.")
                    .font(.footnote)
                    .foregroundStyle(TF.Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let sites = controller.settings.allowedSites
            if !sites.isEmpty {
                VStack(spacing: 0) {
                    ForEach(sites, id: \.self) { site in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(TF.Palette.restText)
                                .frame(width: 22)
                            Text(site)
                                .font(.body)
                                .foregroundStyle(TF.Palette.ink)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                TFHaptics.tap()
                                remove(site)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(TF.Palette.ink3)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Stop allowing \(site)")
                        }
                        .padding(.leading, 12)
                        if site != sites.last { Hairline().padding(.leading, 44) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: TF.Radius.control).fill(TF.Palette.surface2))
            }

            HStack(spacing: 8) {
                TextField("Add a site, like notion.so", text: $entry)
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
        controller.updateSettings { settings in
            if !settings.allowedSites.contains(site) { settings.allowedSites.append(site) }
        }
        entry = ""
        problem = nil
    }

    private func remove(_ site: String) {
        controller.updateSettings { $0.allowedSites.removeAll { $0 == site } }
    }
}
