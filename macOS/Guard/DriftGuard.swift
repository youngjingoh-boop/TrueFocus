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

    /// Every timing (sample rate, warm-up, how long before a nudge, idle) is in `DriftConfig`.
    @ObservationIgnored private let config = DriftConfig.standard
    @ObservationIgnored private var monitor = DriftMonitor(config: .standard)
    @ObservationIgnored private var snapshot = LiveSnapshot.idle
    @ObservationIgnored private var settings = TFSettings.default
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastSample: ActivitySample?
    /// When the loop last ran: a long gap means the Mac slept.
    @ObservationIgnored private var lastTick: Date?
    /// The day the running tally belongs to.
    @ObservationIgnored private var tallyDay = ""
    @ObservationIgnored private var lastPersist = Date.distantPast

    private init() {
        book = SharedStore.shared.read(DriftBook.self, DriftBook.key) ?? DriftBook()
        // Yesterday's tally doesn't outlive yesterday, even on a day without focus.
        if book.prune(dayKey: Self.dayKey()) { persist() }
    }

    /// True while a focus task is being watched.
    var isWatching: Bool { monitor.taskID != nil }

    // MARK: FocusEffect

    func focusDidChange(_ snapshot: LiveSnapshot, previous: LiveSnapshot?, settings: TFSettings) {
        self.snapshot = snapshot
        self.settings = settings

        // Focus only: rest, think, pause (idle) and a finished day are never watched.
        let watching = settings.macDriftGuard && snapshot.mode == .focus && snapshot.taskID != nil && !snapshot.dayEnded
        guard watching, let taskID = snapshot.taskID else {
            if isWatching { ActivityWatcher.shared.forgetTabs() }
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
        let now = Date()
        tallyDay = Self.dayKey(now)
        book.prune(dayKey: tallyDay)
        monitor.begin(taskID: taskID, title: title, at: now, tally: book.tally(for: taskID, dayKey: tallyDay))
        lastTick = nil
        let timer = Timer(timeInterval: config.sampleSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 0.5
        // Common modes: keep looking while a menu is open or a window is being dragged.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // Started here on the Mac, with nothing written yet: ask where the task happens, once
        // per task. Marked as asked before showing, so a skip, a close or a relaunch all stick.
        let startedHere = snapshot.originDevice == TFDevice.name || snapshot.originDevice.isEmpty
        if startedHere, contract.needsStartQuestion {
            contract.askedAt = now
            save(contract)
            StartContractWindow.shared.show(for: self.contract ?? contract, activate: false)
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
        let now = Date()
        // The timer doesn't fire while the Mac sleeps: a long gap is time away, not drift.
        if let lastTick, now.timeIntervalSince(lastTick) > config.maxGapSeconds {
            monitor.away(at: lastTick)
        }
        lastTick = now

        // Days roll over at 4 am: a task running across it starts today's tally from zero.
        let day = Self.dayKey(now)
        if day != tallyDay {
            tallyDay = day
            monitor.startNewTally()
            book.prune(dayKey: day)
        }

        // No keyboard or mouse for a while: you've stepped away. Nothing is sampled or counted.
        if Self.secondsSinceInput() >= config.idleSeconds {
            monitor.away(at: now)
            return
        }

        guard let contract, let sample = ActivityWatcher.shared.sample() else { return }
        var verdict: DriftVerdict
        if sample.appBundleID == Bundle.main.bundleIdentifier || StartContractWindow.shared.isAnswering {
            // Our own windows (writing the contract, ticking the task off) are neither task nor
            // drift. The start panel doesn't activate TruFocus, so check it by itself.
            verdict = .neutral
        } else {
            verdict = DriftClassifier.classify(sample, contract: contract, workAccess: Blocklist.workAccess(settings))
            if verdict == .unsure && settings.macDriftUsesModel {
                if let judged = DriftJudge.shared.cachedVerdict(for: sample, contract: contract) {
                    verdict = judged
                } else {
                    DriftJudge.shared.judge(sample, contract: contract)
                }
            }
        }
        if self.verdict != verdict { self.verdict = verdict }
        lastSample = sample

        if verdict == .onTask, DriftPanel.shared.isShowing {
            DriftPanel.shared.dismiss()
        }

        if let nudge = monitor.observe(sample, verdict: verdict, at: now) {
            show(nudge)
        }
        if let tally = monitor.tally, let taskID = monitor.taskID {
            book.record(tally, for: taskID, dayKey: day)
        }
        // Keep today's tally on disk every half minute, so a quit or crash loses little.
        if now.timeIntervalSince(lastPersist) >= 30 { persist() }
        if let title = snapshot.taskTitle, title != contract.taskTitle {
            self.contract?.taskTitle = title
        }
    }

    /// Seconds since the last keyboard, mouse or trackpad event in this login session. Needs no
    /// permission.
    private static func secondsSinceInput() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    /// Writes today's tally and the contracts now (the app is quitting).
    func flush() {
        if let tally = monitor.tally, let taskID = monitor.taskID {
            book.record(tally, for: taskID, dayKey: Self.dayKey())
        }
        persist()
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
        StartContractWindow.shared.show(for: contract(for: taskID, title: snapshot.taskTitle ?? "your task"), activate: true)
    }

    // MARK: Today

    var today: (onTask: TimeInterval, offTask: TimeInterval, top: (label: String, seconds: TimeInterval)?) {
        book.today(dayKey: Self.dayKey())
    }

    private func persist() {
        SharedStore.shared.write(book, DriftBook.key)
        lastPersist = Date()
    }

    static func dayKey(_ date: Date = Date()) -> String {
        // Days roll over at 4 am, like the rest of the app.
        let shifted = date.addingTimeInterval(-4 * 3600)
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
