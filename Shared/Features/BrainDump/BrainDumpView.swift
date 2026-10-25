import SwiftUI
import TrueFocusKit

/// The morning ritual, in three moves:
/// 1. Empty your head — type everything, no structure.
/// 2. Keep what matters — the dump becomes a list, every line as written (or sorted by the
///    on-device model or parser, if you ask); untick the noise.
/// 3. Pick the win — the one outcome that makes today count. Then attack.
struct BrainDumpView: View {
    @Environment(FocusController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    private enum Step: Int { case dump, keep, win }

    private struct Candidate: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var keep = true
    }

    @State private var step: Step = .dump
    @State private var dump = ""
    @State private var candidates: [Candidate] = []
    @State private var outcome = ""
    @State private var working = false
    /// The list is every line as written, not sorted.
    @State private var asWritten = true
    @FocusState private var dumpFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
                .padding(.horizontal, TF.Space.page)
                .padding(.top, TF.Space.l)

            Group {
                switch step {
                case .dump: dumpStep
                case .keep: keepStep
                case .win: winStep
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            bottomBar
                .padding(.horizontal, TF.Space.page)
                .padding(.bottom, TF.Space.l)
        }
        .tfPage()
        .animation(TF.Motion.soft, value: step)
        .onAppear {
            dump = controller.plan?.brainDump ?? ""
            outcome = controller.plan?.outcome ?? ""
            dumpFocused = true
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 620)
        #else
        .interactiveDismissDisabled(!dump.isEmpty && step != .dump)
        #endif
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Capsule()
                        .fill(index <= step.rawValue ? TF.Palette.signal : TF.Palette.hairline)
                        .frame(width: index == step.rawValue ? 22 : 8, height: 4)
                }
            }
            .animation(TF.Motion.snappy, value: step)
            Spacer()
            Button("Close") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(TF.Palette.ink2)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        switch step {
        case .dump:
            let empty = dump.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            HStack(spacing: 12) {
                Button {
                    Task { await sortList() }
                } label: {
                    HStack(spacing: 8) {
                        if working { ProgressView().controlSize(.small) }
                        Text(working ? "Sorting…" : "Sort it for me")
                    }
                }
                .buttonStyle(QuietButtonStyle())
                .frame(width: 150)
                .disabled(empty || working)
                Button("Make it a list") { makeList() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(empty || working)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        case .keep:
            HStack(spacing: 12) {
                Button("Back") { step = .dump }
                    .buttonStyle(QuietButtonStyle())
                    .frame(width: 96)
                if candidates.isEmpty {
                    Button("Back to Today") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.return, modifiers: .command)
                } else {
                    Button("Pick the win") {
                        if outcome.isEmpty, let first = kept.first { outcome = first }
                        step = .win
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(kept.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        case .win:
            HStack(spacing: 12) {
                Button("Back") { step = .keep }
                    .buttonStyle(QuietButtonStyle())
                    .frame(width: 96)
                Button {
                    attack()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                        Text("Attack")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(tint: TF.Palette.signal, foreground: TF.Palette.onSignal))
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    // MARK: Steps

    private var dumpStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Empty your head.")
                .font(.tfDisplay)
                .foregroundStyle(TF.Palette.ink)
            Text("Everything on your mind. No order.")
                .font(.body)
                .foregroundStyle(TF.Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            ZStack(alignment: .topLeading) {
                if dump.isEmpty {
                    Text("reply to Sam about the term sheet\nfix onboarding bug\nrecord the demo…")
                        .font(.body)
                        .foregroundStyle(TF.Palette.ink3)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $dump)
                    .font(.body)
                    .foregroundStyle(TF.Palette.ink)
                    .scrollContentBackground(.hidden)
                    .focused($dumpFocused)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, TF.Space.page)
        .padding(.top, TF.Space.xl)
    }

    private var keepStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keep what matters.")
                .font(.tfDisplay)
                .foregroundStyle(TF.Palette.ink)
            HStack(alignment: .firstTextBaseline) {
                Text(asWritten ? "Every line, as you wrote it. Untick what isn't today."
                     : TaskExtractor.usesOnDeviceModel ? "Sorted on-device. Untick what isn't today."
                     : "Untick what isn't today.")
                    .font(.body)
                    .foregroundStyle(TF.Palette.ink2)
                Spacer(minLength: 12)
                if !candidates.isEmpty {
                    let allKept = candidates.allSatisfy(\.keep)
                    Button(allKept ? "Clear all" : "Select all") {
                        TFHaptics.tap()
                        for index in candidates.indices { candidates[index].keep = !allKept }
                    }
                    .buttonStyle(.plain)
                    .font(.body.weight(.medium))
                    .foregroundStyle(TF.Palette.signal)
                }
            }
            if candidates.isEmpty {
                Text("Nothing new in there — it's all on the plan already.")
                    .font(.body)
                    .foregroundStyle(TF.Palette.ink3)
                    .padding(.top, TF.Space.l)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach($candidates) { $candidate in
                        HStack(alignment: .top, spacing: 12) {
                            CheckCircle(isOn: candidate.keep, tint: TF.Palette.signal, label: candidate.title) {
                                TFHaptics.tap()
                                candidate.keep.toggle()
                            }
                            .padding(.top, 1)
                            TextField("Task", text: $candidate.title, axis: .vertical)
                                .font(.body)
                                .textFieldStyle(.plain)
                                .foregroundStyle(candidate.keep ? TF.Palette.ink : TF.Palette.ink3)
                        }
                        .padding(.vertical, 10)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, TF.Space.page)
        .padding(.top, TF.Space.xl)
    }

    private var winStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick the win.")
                .font(.tfDisplay)
                .foregroundStyle(TF.Palette.ink)
            Text("If only one thing happens today, what makes it a good day?")
                .font(.body)
                .foregroundStyle(TF.Palette.ink2)
            TextField("Today is a win if…", text: $outcome, axis: .vertical)
                .font(.tfHeadline)
                .textFieldStyle(.plain)
                .foregroundStyle(TF.Palette.ink)
                .padding(.vertical, 16)
            Hairline()
            Text("Or tap one").tfEyebrowStyle().padding(.top, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(kept, id: \.self) { title in
                        Button {
                            TFHaptics.tap()
                            outcome = title
                        } label: {
                            Text(title)
                                .font(.system(size: 15, weight: outcome == title ? .semibold : .regular))
                                .foregroundStyle(outcome == title ? TF.Palette.onSignal : TF.Palette.ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Capsule().fill(outcome == title ? TF.Palette.signal : TF.Palette.surface2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, TF.Space.page)
        .padding(.top, TF.Space.xl)
    }

    // MARK: Logic

    private var kept: [String] {
        candidates.filter(\.keep).map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Every line becomes a task, as written.
    private func makeList() {
        controller.setBrainDump(dump)
        asWritten = true
        showCandidates(BrainDump.lines(from: dump))
    }

    /// The on-device model (or the parser) cleans the dump up into tasks.
    private func sortList() async {
        working = true
        controller.setBrainDump(dump)
        let tasks = await TaskExtractor.extract(from: dump)
        asWritten = false
        working = false
        showCandidates(tasks)
    }

    /// Anything already on the plan starts unticked.
    private func showCandidates(_ tasks: [String]) {
        let existing = Set(controller.openTasks.map { $0.title.lowercased() })
        candidates = tasks.map { Candidate(title: $0, keep: !existing.contains($0.lowercased())) }
        step = .keep
    }

    private func attack() {
        var titles = kept
        let win = outcome.trimmingCharacters(in: .whitespacesAndNewlines)
        // The win goes first in the plan when it is one of the tasks.
        if let index = titles.firstIndex(of: win) {
            titles.insert(titles.remove(at: index), at: 0)
        }
        let existing = Set(controller.openTasks.map { $0.title.lowercased() })
        let fresh = titles.filter { !existing.contains($0.lowercased()) }
        controller.setOutcome(win)
        controller.addTasks(fresh)
        // The win starts first when it's a task, even one already on the plan (a leftover).
        let winTask: FocusTask? = win.isEmpty ? nil : controller.openTasks.first(where: { $0.title.lowercased() == win.lowercased() })
        if let first = winTask ?? fresh.first.flatMap({ title in controller.openTasks.first { $0.title == title } }) {
            controller.makeNext(first)
            controller.start(first)
        } else {
            controller.startNext()
        }
        TFHaptics.success()
        dismiss()
        #if os(iOS)
        let focus = controller
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            focus.isFocusScreenPresented = true
        }
        #endif
    }
}
