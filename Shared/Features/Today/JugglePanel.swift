import SwiftUI
import TrueFocusKit

/// The tasks you're juggling: up to a few in the air at once, for when the current one is
/// waiting on someone. Each keeps its slot; tap one to switch to it.
struct JugglePanel: View {
    @Environment(FocusController.self) private var controller
    var onDark = false
    /// A task already shown big above the panel (the focus screen's), left out of the list.
    var excluding: UUID? = nil

    var body: some View {
        let juggling = controller.inPlayTasks.filter { $0.id != excluding }
        if controller.inPlayTasks.count > 1, !juggling.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Juggling").tfEyebrowStyle(secondary)
                    Text("\(controller.inPlayTasks.count) of \(controller.juggleLimit)")
                        .font(.tfCaption)
                        .foregroundStyle(tertiary)
                    Spacer()
                    JuggleAddMenu(onDark: onDark)
                }
                VStack(spacing: 0) {
                    ForEach(juggling, id: \.id) { task in
                        JuggleRow(task: task, onDark: onDark)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: TF.Radius.control, style: .continuous)
                        .fill(onDark ? Color.white.opacity(0.06) : TF.Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: TF.Radius.control, style: .continuous)
                        .strokeBorder(onDark ? Color.white.opacity(0.08) : TF.Palette.hairline, lineWidth: 1)
                )
            }
        } else if controller.mode.isWorking {
            // One task in the air: offer the juggle without taking room.
            HStack(spacing: 8) {
                JuggleAddMenu(onDark: onDark, label: "Juggle another task")
                Spacer()
            }
        }
    }

    private var secondary: Color { onDark ? TF.Palette.nightInk2 : TF.Palette.ink2 }
    private var tertiary: Color { onDark ? TF.Palette.nightInk2 : TF.Palette.ink3 }
}

/// Inside the Now card, under the task you're on: the other tasks in the air, below a
/// "Juggling" rule. The main task isn't listed again.
struct JuggleSection: View {
    @Environment(FocusController.self) private var controller
    /// The task the card is about (current, paused or resting into).
    var main: UUID?

    var body: some View {
        let others = controller.inPlayTasks.filter { $0.id != main }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    rule
                    Text("Juggling").tfEyebrowStyle(TF.Palette.ink3)
                    Text("\(controller.inPlayTasks.count) of \(controller.juggleLimit)")
                        .font(.tfCaption)
                        .foregroundStyle(TF.Palette.ink3)
                        .fixedSize()
                    rule
                    JuggleAddMenu()
                }
                ForEach(others, id: \.id) { task in
                    JuggleRow(task: task, inset: 0)
                }
            }
        } else if controller.mode.isWorking {
            HStack {
                JuggleAddMenu(label: "Juggle another task")
                Spacer()
            }
            .padding(.bottom, -10)
        }
    }

    private var rule: some View {
        Rectangle().fill(TF.Palette.hairline).frame(height: 1)
    }
}

/// One juggled task. The current one carries the mode's colour; waiting ones an hourglass.
struct JuggleRow: View {
    @Environment(FocusController.self) private var controller
    let task: FocusTask
    var onDark = false
    /// Leading space: inside a bordered panel the row needs it; inside the Now card it doesn't.
    var inset: CGFloat = 12

    private var isNow: Bool { controller.nowTask?.id == task.id }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                guard !isNow else { return }
                TFHaptics.tap()
                withAnimation(TF.Motion.snappy) { controller.start(task) }
            } label: {
                HStack(spacing: 10) {
                    glyph.frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(task.title)
                            .font(.system(size: 15, weight: isNow ? .semibold : .regular))
                            .foregroundStyle(onDark ? TF.Palette.nightInk : TF.Palette.ink)
                            .lineLimit(1)
                        if let detail {
                            Text(detail)
                                .font(.system(size: 12))
                                .foregroundStyle(onDark ? TF.Palette.nightInk2 : TF.Palette.ink2)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 6)
                    if isNow {
                        Text("now")
                            .font(.tfCaption)
                            // Small text: the bright tint reads on night, the deeper text tint on paper.
                            .foregroundStyle(onDark ? TF.tint(for: controller.mode) : TF.textTint(for: controller.mode))
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isNow ? "\(task.title), current task" : "Switch to \(task.title)")

            Menu {
                actions
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(onDark ? TF.Palette.nightInk2 : TF.Palette.ink3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More for \(task.title)")
        }
        .padding(.leading, inset)
        .padding(.trailing, inset == 0 ? -12 : 0)
        .contextMenu { actions }
    }

    @ViewBuilder
    private var glyph: some View {
        if isNow {
            ModeDot(mode: controller.mode, size: 8)
        } else if task.waitingSince != nil {
            Image(systemName: "hourglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(onDark ? TF.Palette.nightInk2 : TF.Palette.ink2)
        } else {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(onDark ? TF.Palette.nightInk2 : TF.Palette.ink3)
        }
    }

    private var detail: String? {
        if let since = task.waitingSince, !isNow {
            return "Waiting · \(TFFormat.short(Date().timeIntervalSince(since)))"
        }
        if !task.breadcrumb.isEmpty { return "↳ \(task.breadcrumb)" }
        return nil
    }

    @ViewBuilder
    private var actions: some View {
        if !isNow {
            Button("Switch to This", systemImage: "arrow.left.arrow.right") { controller.start(task) }
        }
        if isNow {
            Button("Waiting on It", systemImage: "hourglass") { controller.waitOnCurrent() }
        } else if task.waitingSince != nil {
            Button("Not Waiting Anymore", systemImage: "hourglass.bottomhalf.filled") { controller.setWaiting(task, false) }
        } else {
            Button("Waiting on It", systemImage: "hourglass") { controller.setWaiting(task, true) }
        }
        Button("Done", systemImage: "checkmark") {
            TFHaptics.success()
            controller.toggleDone(task)
        }
        if !isNow {
            Divider()
            Button("Drop from Juggle", systemImage: "minus.circle") { controller.drop(task) }
        }
    }
}

/// "+": pick tasks from the plan to put in the air.
struct JuggleAddMenu: View {
    @Environment(FocusController.self) private var controller
    var onDark = false
    var label: String? = nil

    var body: some View {
        let candidates = Array(controller.juggleCandidates.prefix(15))
        Menu {
            if controller.canJuggleMore {
                ForEach(candidates, id: \.id) { task in
                    Button(TFFormat.truncate(task.title, to: 48)) {
                        TFHaptics.tap()
                        withAnimation(TF.Motion.snappy) { _ = controller.juggle(task) }
                    }
                }
                if candidates.isEmpty {
                    Text("Add tasks to the plan first")
                }
            } else {
                Text("Juggling \(controller.juggleLimit) — finish or drop one first")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text(label ?? "Add")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(onDark ? TF.Palette.nightInk2 : TF.Palette.ink2)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Juggle up to \(controller.juggleLimit) tasks while one is waiting")
    }
}
