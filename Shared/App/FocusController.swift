import CoreData
import Foundation
import Observation
import SwiftData
import SwiftUI
import TrueFocusKit
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The one source of truth for the working day, on every device.
///
/// Views read its state and call its verbs (`start`, `complete`, `stuck`, …). Every change
/// is written to SwiftData (synced by `SyncService`), condensed into a `LiveSnapshot` for
/// widgets and extensions, and fanned out to the platform's `FocusEffect`s.
@MainActor
@Observable
final class FocusController {
    static let shared = FocusController()

    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    // MARK: State

    /// Open tasks, in plan order. Unfinished tasks roll over to the next day.
    private(set) var openTasks: [FocusTask] = []
    /// Tasks crossed off today, in the order they were finished.
    private(set) var doneToday: [FocusTask] = []
    private(set) var segmentsToday: [FlowSegment] = []
    /// The open segment, if any. Its mode is the current mode.
    private(set) var current: FlowSegment?
    private(set) var plan: DayPlan?
    private(set) var snapshot: LiveSnapshot = .idle
    private(set) var stats = DayStats()
    private(set) var settings: TFSettings
    /// Set by the TrueFocus Focus filter when a system Focus turns it on.
    private(set) var systemFocusOn = false

    /// UI request for the immersive focus screen (iPhone full-screen cover, Mac focus window).
    var isFocusScreenPresented = false

    private let sharedStore = SharedStore.shared
    @ObservationIgnored private var effects: [any FocusEffect] = []
    @ObservationIgnored private var restTimer: Timer?
    @ObservationIgnored private var statsTimer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var refreshScheduled = false

    init(inMemory: Bool = false) {
        container = TFStore.makeContainer(inMemory: inMemory)
        settings = SharedStore.shared.settings
        systemFocusOn = SharedStore.shared.defaults.bool(forKey: Self.focusFilterKey)
        refresh()
        observeRemoteChanges()
        // Once a minute: live momentum decay, and boot-outs the browser extension recorded.
        statsTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.drainSharedQueues()
                self?.publish()
            }
        }
    }

    // MARK: Derived

    var mode: FlowMode { current?.mode ?? .idle }

    var dayStart: Date { Calendar.current.tfDayStart(for: Date()) }

    /// The task being worked on (focus or think).
    var nowTask: FocusTask? {
        guard let current, current.mode.isWorking, let id = current.taskID else { return nil }
        return task(id: id)
    }

    /// What comes next: the next juggled task that isn't waiting, else the first open task
    /// that isn't the current one (preferring ones you aren't waiting on).
    var nextTask: FocusTask? {
        if let juggled = nextJuggled(after: nowTask) { return juggled }
        let nowID = nowTask?.id
        return openTasks.first { $0.id != nowID && $0.waitingSince == nil } ?? openTasks.first { $0.id != nowID }
    }

    /// The tasks you're juggling, in the order they joined (the current one included).
    var inPlayTasks: [FocusTask] {
        openTasks.filter(\.inPlay).sorted { ($0.inPlayAt ?? .distantPast) < ($1.inPlayAt ?? .distantPast) }
    }

    /// How many tasks can be in the air at once, the current one included.
    var juggleLimit: Int { max(1, settings.juggleLimit) }

    var canJuggleMore: Bool { inPlayTasks.count < juggleLimit }

    /// Open tasks that could join the juggle.
    var juggleCandidates: [FocusTask] { openTasks.filter { !$0.inPlay } }

    /// The juggled task to move to after `task`: next slot round, skipping waiting ones.
    private func nextJuggled(after task: FocusTask?) -> FocusTask? {
        let held = inPlayTasks
        let items = held.map { LiveSnapshot.Item(id: $0.id, title: $0.title, waitingSince: $0.waitingSince) }
        guard let id = Juggle.next(after: task?.id, in: items)?.id else { return nil }
        return held.first { $0.id == id }
    }

    var dayEnded: Bool { plan?.endedAt != nil }

    var hasStartedToday: Bool { !segmentsToday.isEmpty }

    /// True when today needs the morning ritual: no plan, nothing done, nothing running.
    var needsMorningRitual: Bool {
        segmentsToday.isEmpty && doneToday.isEmpty && (plan?.outcome.isEmpty ?? true) && !dayEnded
    }

    var plannedRestEnd: Date? {
        guard let current, current.mode == .rest else { return nil }
        return current.startedAt.addingTimeInterval(current.plannedSeconds ?? settings.restBaseSeconds)
    }

    func task(id: UUID) -> FocusTask? {
        openTasks.first { $0.id == id } ?? doneToday.first { $0.id == id } ?? fetchTask(id: id)
    }

    // MARK: Effects

    func register(_ effect: any FocusEffect) {
        effects.append(effect)
        effect.focusDidChange(snapshot, previous: nil, settings: settings)
    }

    // MARK: Settings

    func updateSettings(_ change: (inout TFSettings) -> Void) {
        var next = settings
        change(&next)
        sharedStore.settings = next
        settings = sharedStore.settings
        publish(force: true)
    }

    /// A two-way binding to one setting, for forms.
    func binding<Value>(_ keyPath: WritableKeyPath<TFSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { value in self.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }

    // MARK: Plan editing

    @discardableResult
    func addTask(_ title: String, after anchor: FocusTask? = nil) -> FocusTask {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let order: Double
        if let anchor, let index = openTasks.firstIndex(where: { $0.id == anchor.id }) {
            let nextOrder = index + 1 < openTasks.count ? openTasks[index + 1].order : anchor.order + 2
            order = (anchor.order + nextOrder) / 2
        } else {
            order = (openTasks.last?.order ?? 0) + 1
        }
        let task = FocusTask(title: clean, order: order)
        context.insert(task)
        commit()
        return task
    }

    func addTasks(_ titles: [String]) {
        var order = (openTasks.last?.order ?? 0) + 1
        for title in titles {
            let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            context.insert(FocusTask(title: clean, order: order))
            order += 1
        }
        commit()
    }

    func rename(_ task: FocusTask, to title: String) {
        guard task.title != title else { return }
        task.title = title
        if let current, current.taskID == task.id { current.taskTitle = title }
        commit()
    }

    func delete(_ task: FocusTask) {
        if let current, current.taskID == task.id {
            close(current, at: Date(), outcome: .ended)
        }
        context.delete(task)
        commit()
    }

    /// Reorders open tasks (List `onMove` semantics).
    func moveOpenTasks(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = openTasks
        let moving = source.sorted().map { reordered[$0] }
        for index in source.sorted(by: >) { reordered.remove(at: index) }
        let removedBefore = source.filter { $0 < destination }.count
        reordered.insert(contentsOf: moving, at: max(0, min(reordered.count, destination - removedBefore)))
        for (index, task) in reordered.enumerated() { task.order = Double(index + 1) }
        commit()
    }

    /// Moves a task to the top of the plan so it's next.
    func makeNext(_ task: FocusTask) {
        let first = openTasks.first { $0.id != nowTask?.id }?.order ?? 1
        task.order = first - 1
        commit()
    }

    /// The circle on a task row. Crossing off the current task completes it (and starts a rest).
    func toggleDone(_ task: FocusTask) {
        if task.isDone {
            task.isDone = false
            task.doneAt = nil
            task.order = (openTasks.last?.order ?? 0) + 1
            commit()
        } else if task.id == nowTask?.id {
            complete()
        } else {
            task.isDone = true
            task.doneAt = Date()
            task.inPlay = false
            task.waitingSince = nil
            commit()
        }
    }

    func setBreadcrumb(_ text: String, for task: FocusTask) {
        task.breadcrumb = text
        commit()
    }

    func setInPlay(_ task: FocusTask, _ inPlay: Bool) {
        task.inPlay = inPlay
        task.inPlayAt = inPlay ? Date() : nil
        if inPlay { trimInPlay(keeping: task) } else { task.waitingSince = nil }
        commit()
    }

    // MARK: Juggling

    /// Adds a task to the juggle without switching to it. False when the juggle is full.
    @discardableResult
    func juggle(_ task: FocusTask) -> Bool {
        if task.inPlay { return true }
        guard canJuggleMore, !task.isDone else { return false }
        setInPlay(task, true)
        return true
    }

    /// Takes a task out of the juggle. It stays on the plan.
    func drop(_ task: FocusTask) {
        setInPlay(task, false)
    }

    func setWaiting(_ task: FocusTask, _ waiting: Bool) {
        task.waitingSince = waiting ? (task.waitingSince ?? Date()) : nil
        if waiting && !task.inPlay {
            task.inPlay = true
            task.inPlayAt = Date()
            trimInPlay(keeping: task)
        }
        commit()
    }

    /// The current task is waiting on someone: mark it, keep it in the juggle, and move to
    /// the next juggled task (or the next one on the plan). With nothing else to do, stop.
    func waitOnCurrent() {
        guard let task = nowTask else { return }
        task.waitingSince = Date()
        if !task.inPlay {
            task.inPlay = true
            task.inPlayAt = Date()
        }
        if let next = nextJuggled(after: task) ?? openTasks.first(where: { $0.id != task.id && $0.waitingSince == nil }) {
            start(next)
        } else {
            if let current { close(current, at: Date(), outcome: .switched) }
            commit()
        }
    }

    /// Moves to the next juggled task that isn't waiting.
    func switchToNextJuggled() {
        if let next = nextJuggled(after: nowTask) { start(next) }
    }

    func setOutcome(_ text: String) {
        ensurePlan().outcome = text
        commit()
    }

    func setBrainDump(_ text: String) {
        ensurePlan().brainDump = text
        commit()
    }

    func setReflection(_ text: String) {
        ensurePlan().reflection = text
        commit()
    }

    // MARK: Flow

    /// Focus on a task. Switching from another task keeps both in play.
    func start(_ task: FocusTask) {
        let now = Date()
        if let current, current.mode == .focus, current.taskID == task.id { return }
        if let current {
            let outcome: SegmentOutcome = current.mode == .focus && current.taskID != task.id ? .switched : .resumed
            close(current, at: now, outcome: outcome)
        }
        if task.isDone {
            task.isDone = false
            task.doneAt = nil
        }
        // Back on it, so no longer waiting.
        task.waitingSince = nil
        open(.focus, task: task, at: now)
        if !task.inPlay {
            task.inPlay = true
            task.inPlayAt = now
        }
        trimInPlay(keeping: task)
        reopenDayIfNeeded()
        commit()
    }

    /// Start the next task in the plan (or the current one, from think).
    func startNext() {
        if mode == .think, let task = nowTask {
            start(task)
        } else if let next = nextTask {
            start(next)
        }
    }

    /// Cross off the current task, then a micro-rest sized to how long it took.
    func complete() {
        guard let current, current.mode.isWorking, let task = nowTask else { return }
        let now = Date()
        let focusThisStint = current.mode == .focus ? current.duration(now: now) : 0
        let totalOnTask = task.focusSeconds + focusThisStint
        close(current, at: now, outcome: .completed)
        task.isDone = true
        task.doneAt = now
        task.inPlay = false
        task.inPlayAt = nil
        task.waitingSince = nil

        if openTasks.contains(where: { $0.id != task.id }) {
            let planned = RestPolicy.plannedRest(afterFocus: totalOnTask,
                                                 base: settings.restBaseSeconds,
                                                 adaptive: settings.adaptiveRest)
            open(.rest, task: nil, at: now, planned: planned)
        }
        commit()
    }

    /// Focus became stuck: think it through without leaving the task (shields stay up).
    func stuck() {
        guard let current, current.mode == .focus, let task = nowTask else { return }
        let now = Date()
        close(current, at: now, outcome: .stuck)
        open(.think, task: task, at: now)
        commit()
    }

    /// From think: back to the same task. From rest or idle: the next task.
    func backToIt() {
        switch mode {
        case .think:
            if let task = nowTask { start(task) }
        case .rest, .idle:
            if let next = nextTask { start(next) }
        case .focus:
            break
        }
    }

    /// Shut the day down. Nudges stop; unfinished tasks roll to tomorrow.
    func endDay() {
        if let current { close(current, at: Date(), outcome: .ended) }
        ensurePlan().endedAt = Date()
        isFocusScreenPresented = false
        commit()
    }

    func reopenDay() {
        plan?.endedAt = nil
        commit()
    }

    /// Stop the clock without finishing anything (e.g. a meeting). Back to idle.
    func stopForNow() {
        guard let current else { return }
        close(current, at: Date(), outcome: .ended)
        commit()
    }

    func apply(_ command: RemoteCommand.Kind) {
        apply(RemoteCommand(kind: command))
    }

    func apply(_ command: RemoteCommand) {
        switch command.kind {
        case .complete: complete()
        case .stuck: stuck()
        case .backToIt: backToIt()
        case .startNext: startNext()
        case .endDay: endDay()
        case .switchTo:
            if let id = command.taskID, let task = task(id: id), !task.isDone { start(task) }
        case .wait: waitOnCurrent()
        }
    }

    /// Called by the Focus filter when a system Focus with "Deep Work shields" turns on or off.
    func focusFilterChanged(deepWork: Bool) {
        systemFocusOn = deepWork
        sharedStore.defaults.set(deepWork, forKey: Self.focusFilterKey)
        publish(force: true)
    }

    /// Doom-scroll boot-outs recorded by extensions and watchers.
    func recordBoots(_ events: [BootEvent]) {
        guard !events.isEmpty else { return }
        ensurePlan().bootCount += events.count
        commit()
    }

    func recordBoot(source: String, site: String?, reason: String?) {
        recordBoots([BootEvent(source: source, site: site, reason: reason)])
    }

    /// Pull in anything other processes queued while we weren't looking.
    func drainSharedQueues() {
        let boots = sharedStore.drainBoots()
        if !boots.isEmpty { recordBoots(boots) }
        for command in sharedStore.drainCommands() where Date().timeIntervalSince(command.at) < 6 * 3600 {
            apply(command)
        }
    }

    // MARK: Lifecycle

    /// Call when the app comes to the foreground.
    func appBecameActive() {
        drainSharedQueues()
        refresh()
    }

    // MARK: Segments

    private func open(_ mode: FlowMode, task: FocusTask?, at date: Date, planned: TimeInterval? = nil) {
        let segment = FlowSegment(mode: mode, taskID: task?.id, taskTitle: task?.title ?? "",
                                  startedAt: date, plannedSeconds: planned, device: TFDevice.name)
        context.insert(segment)
        current = segment
    }

    private func close(_ segment: FlowSegment, at date: Date, outcome: SegmentOutcome) {
        guard segment.endedAt == nil else { return }
        let end = max(date, segment.startedAt)
        segment.endedAt = end
        segment.outcomeRaw = outcome.rawValue
        if segment.mode == .focus, let id = segment.taskID, let task = task(id: id) {
            task.focusSeconds += end.timeIntervalSince(segment.startedAt)
        }
        if current?.id == segment.id { current = nil }
    }

    /// Keeps the juggle within the limit. The oldest tasks you aren't waiting on go first;
    /// `keep` and the current task always stay.
    private func trimInPlay(keeping keep: FocusTask) {
        let limit = juggleLimit
        var held = inPlayTasks
        if !held.contains(where: { $0.id == keep.id }) { held.append(keep) }
        guard held.count > limit else { return }
        let droppable = held
            .filter { $0.id != keep.id && $0.id != nowTask?.id }
            .sorted { ($0.waitingSince == nil ? 0 : 1, $0.inPlayAt ?? .distantPast)
                    < ($1.waitingSince == nil ? 0 : 1, $1.inPlayAt ?? .distantPast) }
        for task in droppable.prefix(held.count - limit) {
            task.inPlay = false
            task.inPlayAt = nil
            task.waitingSince = nil
        }
    }

    private func ensurePlan() -> DayPlan {
        if let plan { return plan }
        let plan = DayPlan(day: dayStart)
        context.insert(plan)
        self.plan = plan
        return plan
    }

    private func reopenDayIfNeeded() {
        if plan?.endedAt != nil { plan?.endedAt = nil }
    }

    // MARK: Persistence

    private func commit() {
        do {
            try context.save()
        } catch {
            print("TrueFocus: save failed: \(error)")
        }
        refresh()
    }

    private func fetchTask(id: UUID) -> FocusTask? {
        var descriptor = FetchDescriptor<FocusTask>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Re-reads everything and republishes. Cheap: a day is a few dozen rows.
    func refresh() {
        let start = dayStart
        let tasks = (try? context.fetch(FetchDescriptor<FocusTask>(sortBy: [SortDescriptor(\.order)]))) ?? []
        openTasks = tasks.filter { !$0.isDone }
        doneToday = tasks
            .filter { $0.isDone && ($0.doneAt ?? .distantPast) >= start }
            .sorted { ($0.doneAt ?? .distantPast) < ($1.doneAt ?? .distantPast) }

        let openDescriptor = FetchDescriptor<FlowSegment>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        var openSegments = (try? context.fetch(openDescriptor)) ?? []
        var repaired = false
        // One timeline: if two devices each opened a segment, the newest wins.
        if openSegments.count > 1, let newest = openSegments.first {
            for stale in openSegments.dropFirst() {
                stale.endedAt = max(stale.startedAt, newest.startedAt)
                stale.outcomeRaw = SegmentOutcome.superseded.rawValue
            }
            openSegments = [newest]
            repaired = true
        }
        // A segment left running overnight is closed where the day ended.
        if let open = openSegments.first, open.startedAt < start {
            open.endedAt = min(open.startedAt.addingTimeInterval(3 * 3600), start)
            open.outcomeRaw = SegmentOutcome.ended.rawValue
            openSegments = []
            repaired = true
        }
        current = openSegments.first

        let dayDescriptor = FetchDescriptor<FlowSegment>(
            predicate: #Predicate { $0.startedAt >= start },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        segmentsToday = (try? context.fetch(dayDescriptor)) ?? []

        let planDescriptor = FetchDescriptor<DayPlan>(predicate: #Predicate { $0.day == start })
        let plans = (try? context.fetch(planDescriptor)) ?? []
        plan = plans.first { !$0.outcome.isEmpty } ?? plans.first

        if repaired { try? context.save() }
        publish()
    }

    private func observeRemoteChanges() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        })
    }

    /// Coalesces bursts of store change notifications into one refresh.
    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.refreshScheduled = false
                self.refresh()
            }
        }
    }

    // MARK: Publishing

    private static let focusFilterKey = "tf.focusFilter.deepWork"

    private func makeSnapshot(now: Date) -> LiveSnapshot {
        let records = segmentsToday.map(\.record)
        let dayStats = DayStats.compute(segments: records, boots: plan?.bootCount ?? 0, now: now)
        stats = dayStats

        var snap = LiveSnapshot()
        snap.mode = mode
        snap.modeStartedAt = current?.startedAt
        snap.plannedRestEnd = plannedRestEnd
        if let task = nowTask {
            snap.taskID = task.id
            snap.taskTitle = task.title
            snap.breadcrumb = task.breadcrumb.isEmpty ? nil : task.breadcrumb
            snap.taskFocusBefore = task.focusSeconds
        }
        if let next = nextTask {
            snap.nextTaskID = next.id
            snap.nextTaskTitle = next.title
        }
        snap.inPlay = inPlayTasks.map {
            LiveSnapshot.Item(id: $0.id, title: $0.title, breadcrumb: $0.breadcrumb.isEmpty ? nil : $0.breadcrumb,
                              waitingSince: $0.waitingSince)
        }
        snap.doneToday = doneToday.count
        snap.plannedToday = doneToday.count + openTasks.count
        let openFocus = (current?.mode == .focus) ? (current?.duration(now: now) ?? 0) : 0
        snap.focusSecondsToday = max(0, dayStats.focusSeconds - openFocus)
        snap.chain = dayStats.chain
        snap.momentum = dayStats.momentum
        let outcome = plan?.outcome.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        snap.outcome = outcome.isEmpty ? nil : outcome
        snap.bootsToday = plan?.bootCount ?? 0
        snap.dayEnded = dayEnded
        snap.systemFocusOn = systemFocusOn
        snap.updatedAt = now
        snap.originDevice = current?.device ?? TFDevice.name
        return snap
    }

    /// Rebuilds the snapshot; if anything visible changed, shares it and runs the effects.
    func publish(force: Bool = false) {
        let now = Date()
        let previous = snapshot
        let next = makeSnapshot(now: now)
        snapshot = next
        sharedStore.snapshot = next
        scheduleRestTimer()

        let changed = !next.isSameState(as: previous)
        guard changed || force else { return }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        for effect in effects {
            effect.focusDidChange(next, previous: previous, settings: settings)
        }
    }

    /// While resting, tick every second so auto-continue can start the next task on time.
    private func scheduleRestTimer() {
        restTimer?.invalidate()
        restTimer = nil
        guard mode == .rest else { return }
        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.restTick() }
        }
    }

    private func restTick() {
        guard mode == .rest, let end = plannedRestEnd, let current else { return }
        // Only the device that started the rest auto-continues, so two devices never both start.
        guard settings.autoContinue, current.device == TFDevice.name, Date() >= end else { return }
        backToIt()
    }
}
