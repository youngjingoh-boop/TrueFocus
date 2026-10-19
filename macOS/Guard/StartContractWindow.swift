import AppKit
import SwiftUI
import TrueFocusKit

/// The start contract: a ten-second "where does this task happen?" asked when a task starts on
/// the Mac. Pick the apps and sites it lives in, optionally the first move and when it's done.
/// The drift guard judges everything else against this.
@MainActor
final class StartContractWindow {
    static let shared = StartContractWindow()

    private var window: NSWindow?

    func show(for contract: TaskContract) {
        let watcher = ActivityWatcher.shared
        let view = StartContractView(
            contract: contract,
            openApps: watcher.openWorkApps(),
            recentSites: watcher.recentHosts,
            onSave: { [weak self] contract in
                DriftGuard.shared.save(contract)
                self?.close()
            },
            onSkip: { [weak self] in self?.close() }
        )
        let hosting = NSHostingController(rootView: view)
        let window = self.window ?? makeWindow()
        window.contentViewController = hosting
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Where does it happen?"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        return window
    }
}

private struct StartContractView: View {
    @State private var contract: TaskContract
    let openApps: [ActivityWatcher.WorkApp]
    let recentSites: [String]
    let onSave: (TaskContract) -> Void
    let onSkip: () -> Void

    @State private var suggestedSites: [String] = []
    @State private var suggestedWords: [String] = []
    @State private var thinking = false
    @State private var addText = ""

    init(contract: TaskContract, openApps: [ActivityWatcher.WorkApp], recentSites: [String],
         onSave: @escaping (TaskContract) -> Void, onSkip: @escaping () -> Void) {
        _contract = State(initialValue: contract)
        self.openApps = openApps
        self.recentSites = recentSites
        self.onSave = onSave
        self.onSkip = onSkip
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("STARTING").tfEyebrowStyle(TF.textTint(for: .focus))
                Text("Where does “\(TFFormat.truncate(contract.taskTitle, to: 48))” happen?")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TF.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Pick what this task uses. Anything else for more than a minute or two gets a nudge.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(TF.Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !openApps.isEmpty || !customApps.isEmpty {
                section("Apps") {
                    ChipFlow(spacing: 6) {
                        ForEach(openApps) { app in
                            Chip(text: app.name, on: contract.apps.contains(app.id)) { toggle(app.id, in: \.apps) }
                        }
                        ForEach(customApps, id: \.self) { app in
                            Chip(text: app, on: true) { toggle(app, in: \.apps) }
                        }
                    }
                }
            }

            section("Sites") {
                ChipFlow(spacing: 6) {
                    ForEach(siteOptions, id: \.self) { site in
                        Chip(text: site, on: contract.sites.contains(site)) { toggle(site, in: \.sites) }
                    }
                }
                HStack(spacing: 8) {
                    TextField("Add a site or app (docs.google.com, Figma)", text: $addText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addTyped)
                    Button("Add", action: addTyped)
                        .disabled(addText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if thinking || !suggestedWords.isEmpty || !contract.keywords.isEmpty {
                section(thinking ? "Topic words (thinking…)" : "Topic words") {
                    ChipFlow(spacing: 6) {
                        ForEach(wordOptions, id: \.self) { word in
                            Chip(text: word, on: contract.keywords.contains(word)) { toggle(word, in: \.keywords) }
                        }
                    }
                }
            }

            section("First move") {
                TextField("Open the research doc and list three channels", text: optional(\.firstMove))
                    .textFieldStyle(.roundedBorder)
            }
            section("Done when") {
                TextField("Optional", text: optional(\.doneWhen))
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 10) {
                Button("Skip", action: onSkip)
                    .buttonStyle(QuietButtonStyle())
                    .fixedSize()
                    .keyboardShortcut(.cancelAction)
                Button("Start") { onSave(contract) }
                    .buttonStyle(PrimaryButtonStyle(tint: TF.Palette.signal, foreground: TF.Palette.onSignal))
                    .keyboardShortcut(.defaultAction)
            }
            Text("Only app names, window titles and sites are read, on this Mac, while a task runs. No screenshots or page contents.")
                .font(.system(size: 11))
                .foregroundStyle(TF.Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .padding(.top, 8)
        .frame(width: 460)
        .background(TF.Palette.paper)
        .task { await loadSuggestions() }
    }

    // MARK: Options

    /// Sites already chosen, then the model's ideas, then what's been open recently.
    private var siteOptions: [String] {
        unique(contract.sites + suggestedSites + recentSites)
    }

    private var wordOptions: [String] {
        unique(contract.keywords + suggestedWords)
    }

    /// Apps added by name that aren't among the open ones.
    private var customApps: [String] {
        contract.apps.filter { app in !openApps.contains { $0.id == app } }
    }

    private func loadSuggestions() async {
        guard FocusController.shared.settings.macDriftUsesModel, DriftJudge.shared.isAvailable else { return }
        thinking = true
        defer { thinking = false }
        guard let ideas = await DriftJudge.shared.suggest(title: contract.taskTitle, firstMove: contract.firstMove) else { return }
        suggestedSites = ideas.sites
        suggestedWords = ideas.keywords
        // Topic words are cheap to keep; sites stay a choice.
        for word in ideas.keywords where !contract.keywords.contains(word) {
            contract.keywords.append(word)
        }
    }

    private func addTyped() {
        let text = addText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if text.contains("."), !text.contains(" "), let site = Blocklist.normalizedSite(text) {
            if !contract.sites.contains(site) { contract.sites.append(site) }
        } else if let app = openApps.first(where: { $0.name.caseInsensitiveCompare(text) == .orderedSame }) {
            if !contract.apps.contains(app.id) { contract.apps.append(app.id) }
        } else if !contract.apps.contains(text) {
            contract.apps.append(text)
        }
        addText = ""
    }

    private func toggle(_ item: String, in path: WritableKeyPath<TaskContract, [String]>) {
        if let index = contract[keyPath: path].firstIndex(of: item) {
            contract[keyPath: path].remove(at: index)
        } else {
            contract[keyPath: path].append(item)
        }
    }

    private func optional(_ path: WritableKeyPath<TaskContract, String?>) -> Binding<String> {
        Binding(
            get: { contract[keyPath: path] ?? "" },
            set: { contract[keyPath: path] = $0.isEmpty ? nil : $0 }
        )
    }

    private func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).tfEyebrowStyle()
            content()
        }
    }
}

/// A toggleable capsule.
private struct Chip: View {
    let text: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                Text(text).lineLimit(1)
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(on ? TF.Palette.onSignal : TF.Palette.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(on ? TF.Palette.signal : TF.Palette.surface2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Lays chips out left to right, wrapping onto new lines.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var items: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if !row.items.isEmpty, needed > width {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
