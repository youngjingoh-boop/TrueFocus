import AppKit
import Foundation
import Observation
import TrueFocusKit

/// Notices when what's in front on the Mac isn't the task you're on, and helps you back.
///
/// While a focus segment runs, every few seconds it looks at the frontmost app, its window title
/// and (via the extension) the browser tab, judges that against the task's start contract, and
/// after sustained drift shows a small panel: back to it, it's part of the task, or switch.
/// The rules decide most cases; the on-device model settles the ones they can't place.
@MainActor
@Observable
final class DriftGuard: FocusEffect {
    static let shared = DriftGuard()

    /// The current task's contract, if one was written.
    private(set) var contract: TaskContract?
    /// What the guard thinks of what's in front right now.
    private(set) var verdict: DriftVerdict?
    private(set) var book = DriftBook()

    @ObservationIgnored private var monitor = DriftMonitor()
    @ObservationIgnored private var snapshot = LiveSnapshot.idle
    @ObservationIgnored private var settings = TFSettings.default
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var promptedTasks: Set<UUID> = []
    @ObservationIgnored private var lastSample: ActivitySample?

    private static let tick: TimeInterval = 3

    private init() {
        book = SharedStore.shared.read(DriftBook.self, DriftBook.key) ?? DriftBook()
    }

    // MARK: FocusEffect

    func focusDidChange(_ snapshot: LiveSnapshot, previous: LiveSnapshot?, settings: TFSettings) {
        self.snapshot = snapshot
        self.settings = settings

        let watching = settings.macDriftGuard && snapshot.mode == .focus && snapshot.taskID != nil && !snapshot.dayEnded
        guard watching, let taskID = snapshot.taskID else {
            stop()
            return
        }

        if monitor.taskID != taskID {
            stop()
            start(taskID: taskID, title: snapshot.taskTitle ?? "your task")
        }
    }

    private func start(taskID: UUID, title: String) {
        var contract = book.contracts[taskID] ?? TaskContract(taskID: taskID, taskTitle: title)
        contract.taskTitle = title
        self.contract = contract
        monitor.begin(taskID: taskID, title: title, at: Date(), tally: book.tally(for: taskID, dayKey: Self.dayKey()))
        timer = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        // Started here on the Mac, with nothing written yet: ask where the task happens.
        let startedHere = snapshot.originDevice == TFDevice.name || snapshot.originDevice.isEmpty
        if startedHere, !contract.hasWorkspace, !promptedTasks.contains(taskID) {
            promptedTasks.insert(taskID)
            StartContractWindow.shared.show(for: contract)
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        if let taskID = monitor.taskID, let tally = monitor.end(at: Date()) {
            book.record(tally, for: taskID, dayKey: Self.dayKey())
            persist()
        }
        contract = nil
        verdict = nil
        DriftPanel.shared.dismiss()
    }

    // MARK: The loop

    private func check() {
        guard var contract, let sample = ActivityWatcher.shared.sample() else { return }
        // Our own windows are always fine (writing the contract, ticking the task off).
        if sample.appBundleID == Bundle.main.bundleIdentifier { return }

        var verdict = DriftClassifier.classify(sample, contract: contract)
        if verdict == .unsure && settings.macDriftUsesModel {
            if let judged = DriftJudge.shared.cachedVerdict(for: sample, contract: contract) {
                verdict = judged
            } else {
                DriftJudge.shared.judge(sample, contract: contract)
            }
        }
        self.verdict = verdict
        lastSample = sample

        if verdict == .onTask, DriftPanel.shared.isShowing {
            DriftPanel.shared.dismiss()
        }

        if let nudge = monitor.observe(sample, verdict: verdict, at: Date()) {
            show(nudge)
        }
        if let tally = monitor.tally, let taskID = monitor.taskID {
            book.record(tally, for: taskID, dayKey: Self.dayKey())
        }
        contract.taskTitle = snapshot.taskTitle ?? contract.taskTitle
        self.contract = contract
    }

    private func show(_ nudge: DriftNudge) {
        let line = Copy(tone: settings.tone).drift(task: nudge.taskTitle, label: nudge.label, minutes: nudge.minutes)
        DriftPanel.shared.show(
            title: line.title,
            message: line.body,
            breadcrumb: snapshot.breadcrumb ?? contract?.firstMove,
            onBack: { [weak self] in self?.backToIt(from: nudge) },
            onPartOfTask: { [weak self] in self?.partOfTask(nudge.sample) },
            onSwitch: { [weak self] in self?.switchTask() }
        )
        persist()
    }

    // MARK: Actions

    private func backToIt(from nudge: DriftNudge) {
        monitor.acknowledge(at: Date())
        if let last = nudge.lastOnTask, let id = last.appBundleID,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            app.activate()
        } else {
            WindowOpener.shared.openMain()
        }
        if let crumb = snapshot.breadcrumb ?? contract?.firstMove {
            HUDToast.shared.show(title: "Back to “\(TFFormat.truncate(nudge.taskTitle, to: 40))”", message: "↳ \(crumb)")
        }
    }

    /// "It's part of the task": remember the app or site and stop counting it as drift.
    private func partOfTask(_ sample: ActivitySample) {
        guard var contract else { return }
        contract.include(sample)
        save(contract)
        monitor.acknowledge(at: Date())
    }

    private func switchTask() {
        monitor.acknowledge(at: Date())
        WindowOpener.shared.openMain()
    }

    // MARK: Contracts

    func save(_ contract: TaskContract) {
        var contract = contract
        contract.updatedAt = Date()
        book.save(contract)
        if contract.taskID == monitor.taskID { self.contract = contract }
        DriftJudge.shared.forget(taskID: contract.taskID)
        persist()
    }

    func contract(for taskID: UUID, title: String) -> TaskContract {
        book.contracts[taskID] ?? TaskContract(taskID: taskID, taskTitle: title)
    }

    /// Opens the start contract for the current task (from the menu bar).
    func editCurrentContract() {
        guard let taskID = snapshot.taskID else { return }
        StartContractWindow.shared.show(for: contract(for: taskID, title: snapshot.taskTitle ?? "your task"))
    }

    // MARK: Today

    var today: (onTask: TimeInterval, offTask: TimeInterval, top: (label: String, seconds: TimeInterval)?) {
        book.today(dayKey: Self.dayKey())
    }

    private func persist() {
        SharedStore.shared.write(book, DriftBook.key)
    }

    static func dayKey(_ date: Date = Date()) -> String {
        // Days roll over at 4 am, like the rest of the app.
        let shifted = date.addingTimeInterval(-4 * 3600)
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
