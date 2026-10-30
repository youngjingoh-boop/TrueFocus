import SwiftUI
import TrueFocusKit

/// Today: what's live now, and the plan to attack.
struct TodayView: View {
    @Environment(FocusController.self) private var controller
    @State private var showBrainDump = false
    @State private var showReview = false
    @State private var showSettings = false
    @State private var showDone = true
    @State private var newTaskFocused = false
    /// iPhone: the task whose More actions are showing (swipe › More).
    @State private var actionsFor: FocusTask?

    var body: some View {
        List {
            header
                .listRowInsets(rowInsets(top: 8, bottom: 4))
                .tfListRow()

            Text("Focus")
                .tfEyebrowStyle(TF.Palette.signalText)
                .listRowInsets(rowInsets(top: 4, bottom: 10))
                .tfListRow()

            if controller.needsMorningRitual {
                MorningCard { showBrainDump = true }
                    .listRowInsets(rowInsets(top: 0, bottom: 22))
                    .tfListRow()
            }

            if controller.mode.isActive || controller.isPaused {
                NowCard()
                    .listRowInsets(rowInsets(top: 0, bottom: 18))
                    .tfListRow()
            } else if controller.doneToday.count > 0 && controller.openTasks.isEmpty {
                ClearedCard { showReview = true }
                    .listRowInsets(rowInsets(top: 0, bottom: 18))
                    .tfListRow()
            }

            // With a live card the juggle sits inside it; on its own only when nothing is live.
            if !(controller.mode.isActive || controller.isPaused) {
                JugglePanel()
                    .listRowInsets(rowInsets(top: 0, bottom: 14))
                    .tfListRow()
            }

            Section {
                ForEach(controller.openTasks, id: \.id) { task in
                    TaskRow(task: task, dense: isDense) { _ in newTaskFocused = true }
                        .listRowInsets(rowInsets(top: 0, bottom: 0))
                        .tfListRow()
                        #if os(iOS)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                controller.start(task)
                                controller.isFocusScreenPresented = true
                            } label: {
                                Label("Focus", systemImage: "bolt.fill")
                            }
                            .tint(TF.Palette.signal)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                controller.delete(task)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                actionsFor = task
                            } label: {
                                Label("More", systemImage: "ellipsis.circle")
                            }
                            .tint(TF.Palette.ink2)
                            Button {
                                if task.inPlay { controller.drop(task) } else { controller.juggle(task) }
                            } label: {
                                Label(task.inPlay ? "Drop" : "Juggle", systemImage: "square.stack.3d.up")
                            }
                            .tint(TF.Palette.think)
                        }
                        #endif
                }
                .onMove { source, destination in
                    controller.moveOpenTasks(fromOffsets: source, toOffset: destination)
                }

                NewTaskRow(isFocused: $newTaskFocused, dense: isDense)
                    .listRowInsets(rowInsets(top: 0, bottom: 0))
                    .tfListRow()
            } header: {
                sectionHeader("Plan", trailing: planCount)
            }

            if !controller.doneToday.isEmpty {
                Section {
                    if showDone {
                        ForEach(controller.doneToday.reversed(), id: \.id) { task in
                            TaskRow(task: task, dense: isDense)
                                .listRowInsets(rowInsets(top: 0, bottom: 0))
                                .tfListRow()
                        }
                    }
                } header: {
                    Button {
                        withAnimation(TF.Motion.snappy) { showDone.toggle() }
                    } label: {
                        sectionHeader("Done", trailing: "\(controller.doneToday.count)  \(showDone ? "▾" : "▸")")
                    }
                    .buttonStyle(.plain)
                }
            }

            footer
                .listRowInsets(rowInsets(top: 28, bottom: 120))
                .tfListRow()
        }
        .listStyle(.plain)
        // Scrolling the plan puts the keyboard away (a half-typed task is kept as a task).
        .scrollDismissesKeyboard(.immediately)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .tfPage()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { attackBar }
        #endif
        .sheet(isPresented: $showBrainDump) {
            BrainDumpView()
                .environment(controller)
        }
        #if os(iOS)
        .confirmationDialog(liveActionsFor?.title ?? "Task",
                            isPresented: Binding(get: { liveActionsFor != nil }, set: { if !$0 { actionsFor = nil } }),
                            titleVisibility: .visible,
                            presenting: liveActionsFor) { task in
            Button("Focus on This") {
                controller.start(task)
                controller.isFocusScreenPresented = true
            }
            if task.inPlay {
                Button("Drop from Juggle") { controller.drop(task) }
            } else if controller.canJuggleMore {
                Button("Juggle") { _ = controller.juggle(task) }
            }
            if controller.nowTask?.id != task.id {
                Button(task.waitingSince != nil ? "Not Waiting Anymore" : "Waiting on It") {
                    controller.setWaiting(task, task.waitingSince == nil)
                }
            }
            Button("Do Next") { controller.makeNext(task) }
            Button("Delete", role: .destructive) { controller.delete(task) }
        }
        #endif
        .sheet(isPresented: $showReview) {
            ReviewView()
                .environment(controller)
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
    }

    /// The task whose More actions are showing, unless another device deleted it meanwhile:
    /// a deleted model must not be read, so the dialog goes away instead.
    private var liveActionsFor: FocusTask? {
        actionsFor.flatMap { $0.isLive ? $0 : nil }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 8) {
                // One line: "TODAY · MON · OCT 19".
                HStack(spacing: 6) {
                    Text("Today").tfEyebrowStyle(TF.Palette.ink)
                    Text("·").tfEyebrowStyle(TF.Palette.ink3)
                    Text(TFFormat.dayEyebrow(Date())).tfEyebrowStyle()
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                DayProgressBar(done: controller.doneToday.count,
                               total: controller.doneToday.count + controller.openTasks.count)
                    .frame(width: 120)
                    .padding(.top, 2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 2) {
                    Button { showBrainDump = true } label: {
                        Image(systemName: "brain.head.profile")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .help("Empty your head into the plan")
                    .accessibilityLabel("Brain dump")
                    Button { showReview = true } label: {
                        Image(systemName: "chart.bar.xaxis")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .help("Today's scoreboard")
                    .accessibilityLabel("Scoreboard")
                    #if os(iOS)
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Settings")
                    #endif
                }
                .padding(.trailing, -12)
                .buttonStyle(.plain)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(TF.Palette.ink2)

                momentum
            }
        }
    }

    private var momentum: some View {
        let snapshot = controller.snapshot
        return VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 6) {
                if snapshot.chain > 0 { ChainDots(chain: snapshot.chain) }
                Text("\(snapshot.momentum)")
                    .font(.tfCaption)
                    .foregroundStyle(TF.Palette.ink2)
                    .contentTransition(.numericText())
            }
            MomentumBar(value: snapshot.momentum)
                .frame(width: 64)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Momentum \(snapshot.momentum), chain \(snapshot.chain)")
    }

    private var planCount: String {
        let total = controller.openTasks.count + controller.doneToday.count
        guard total > 0 else { return "" }
        let focused = TFFormat.short(controller.snapshot.focusToday(now: Date()))
        return "\(controller.doneToday.count) of \(total) · \(focused)"
    }

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title).tfEyebrowStyle()
            Spacer()
            Text(trailing)
                .font(.tfCaption)
                .foregroundStyle(TF.Palette.ink3)
        }
        .padding(.horizontal, TF.Space.page)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity)
        .background(TF.Palette.paper)
        .listRowInsets(EdgeInsets())
    }

    @ViewBuilder
    private var footer: some View {
        if controller.hasStartedToday || !controller.doneToday.isEmpty {
            HStack {
                Spacer()
                Button(controller.dayEnded ? "Day is shut down · reopen" : "Shut down the day") {
                    if controller.dayEnded { controller.reopenDay() } else { showReview = true }
                }
                .buttonStyle(QuietButtonStyle(foreground: TF.Palette.ink2))
                Spacer()
            }
        } else {
            Color.clear.frame(height: 1)
        }
    }

    #if os(iOS)
    @ViewBuilder
    private var attackBar: some View {
        if !controller.mode.isActive, let next = controller.nextTask, !newTaskFocused {
            Button {
                TFHaptics.success()
                controller.start(next)
                controller.isFocusScreenPresented = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: controller.isPaused ? "play.fill" : "bolt.fill")
                    Text(controller.isPaused ? "Resume" : "Attack").fontWeight(.semibold)
                    Text("· \(next.title)")
                        .fontWeight(.regular)
                        .lineLimit(1)
                        .opacity(0.7)
                }
            }
            .buttonStyle(PrimaryButtonStyle(tint: TF.Palette.signal, foreground: TF.Palette.onSignal))
            .padding(.horizontal, TF.Space.page)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    #endif

    @ViewBuilder
    private var settingsSheet: some View {
        #if os(iOS)
        NavigationStack {
            FlowSettingsView()
                .navigationTitle("Rhythm")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showSettings = false }
                    }
                }
        }
        .environment(controller)
        #else
        FlowSettingsView()
            .environment(controller)
            .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    /// Long plans (open plus visible done) switch to tighter lines.
    private var isDense: Bool {
        controller.openTasks.count + (showDone ? controller.doneToday.count : 0) >= TaskRowMetrics.denseFrom
    }

    private func rowInsets(top: CGFloat, bottom: CGFloat) -> EdgeInsets {
        EdgeInsets(top: top, leading: TF.Space.page, bottom: bottom, trailing: TF.Space.page)
    }
}

// MARK: - Cards

/// Shown first thing in the morning: empty your head, then attack.
struct MorningCard: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start the day").tfEyebrowStyle(TF.Palette.signalText)
                    Text("Empty your head.")
                        .font(.tfTitle)
                        .foregroundStyle(TF.Palette.ink)
                    Text("Dump everything on your mind here.")
                        .font(.subheadline)
                        .foregroundStyle(TF.Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(TF.Palette.onSignal)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(TF.Palette.signal))
            }
            .padding(20)
            .tfCard()
        }
        .buttonStyle(.plain)
    }
}

/// Everything's crossed off.
struct ClearedCard: View {
    @Environment(FocusController.self) private var controller
    var onReview: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cleared").tfEyebrowStyle(TF.Palette.restText)
                Text("\(controller.doneToday.count) done. Add the next thing, or shut it down.")
                    .font(.tfTitle)
                    .foregroundStyle(TF.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Review", action: onReview)
                .buttonStyle(QuietButtonStyle())
        }
        .padding(20)
        .tfCard(tint: TF.Palette.rest)
    }
}

extension View {
    /// Strips List chrome so rows sit directly on the paper.
    func tfListRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
