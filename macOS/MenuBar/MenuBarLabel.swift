import Observation
import SwiftUI
import TrueFocusKit

/// A slow clock for the menu bar: minutes are enough up there, and a ticking
/// seconds counter in the corner of your eye is its own distraction.
@MainActor
@Observable
final class MenuBarClock {
    static let shared = MenuBarClock()

    private(set) var now = Date()
    @ObservationIgnored private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
    }
}

/// The status item: mode symbol, the task you're on, and minutes in.
struct MenuBarLabel: View {
    @Environment(FocusController.self) private var controller
    private let clock = MenuBarClock.shared

    var body: some View {
        let snapshot = controller.snapshot
        HStack(spacing: 5) {
            Image(systemName: symbol(for: snapshot))
            Text(text(for: snapshot, now: clock.now))
        }
        .accessibilityLabel("TrueFocus: \(text(for: snapshot, now: clock.now))")
    }

    private func symbol(for snapshot: LiveSnapshot) -> String {
        if snapshot.dayEnded { return "moon.fill" }
        return snapshot.mode == .idle ? "scope" : snapshot.mode.symbol
    }

    private func text(for snapshot: LiveSnapshot, now: Date) -> String {
        let showTimer = controller.settings.menuBarShowsTimer
        switch snapshot.mode {
        case .focus:
            let title = TFFormat.truncate(snapshot.taskTitle ?? "Focus", to: 26) + juggled(snapshot)
            guard showTimer else { return title }
            return "\(title) · \(minutes(snapshot.taskElapsed(now: now)))"
        case .think:
            let title = TFFormat.truncate(snapshot.taskTitle ?? "Think", to: 22)
            guard showTimer else { return "Think · \(title)" }
            return "Think · \(title) · \(minutes(snapshot.elapsedInMode(now: now)))"
        case .rest:
            if let next = snapshot.nextTaskTitle {
                return "Rest · next: \(TFFormat.truncate(next, to: 20))"
            }
            return "Rest"
        case .idle:
            if snapshot.dayEnded { return "Done for today" }
            if let next = snapshot.nextTaskTitle { return "Next: \(TFFormat.truncate(next, to: 24))" }
            return "Plan today"
        }
    }

    /// " +2" while two other tasks are being juggled.
    private func juggled(_ snapshot: LiveSnapshot) -> String {
        let others = snapshot.juggledOthers.count
        return others > 0 ? " +\(others)" : ""
    }

    private func minutes(_ seconds: TimeInterval) -> String {
        let total = Int(seconds / 60)
        if total >= 60 { return "\(total / 60)h \(total % 60)m" }
        return "\(total)m"
    }
}
