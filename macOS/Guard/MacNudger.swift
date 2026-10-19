import AppKit
import Foundation
import TrueFocusKit
import UserNotifications

/// Turns the nudge plan into things you notice on the Mac:
/// level 1 → a quiet HUD, level 2 → HUD + a notification, level 3 → the full-screen wake-up.
@MainActor
final class MacNudger: FocusEffect {
    static let shared = MacNudger()

    private var snapshot = LiveSnapshot.idle
    private var settings = TFSettings.default
    private var timers: [Timer] = []
    private var snoozeTimer: Timer?
    /// When the current idle stretch began (idle has no segment to carry a start time).
    private var idleSince = Date()

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func focusDidChange(_ snapshot: LiveSnapshot, previous: LiveSnapshot?, settings: TFSettings) {
        if snapshot.mode == .idle, previous?.mode != .idle {
            idleSince = Date()
        }
        let stateMoved = previous?.mode != snapshot.mode || previous?.modeStartedAt != snapshot.modeStartedAt
        self.snapshot = snapshot
        self.settings = settings

        if stateMoved {
            snoozeTimer?.invalidate()
            snoozeTimer = nil
            // You did the thing — take the overlay away.
            if snapshot.mode == .focus || snapshot.dayEnded {
                WakeUpOverlay.shared.dismiss()
            }
        }
        reschedule()
    }

    private func reschedule() {
        timers.forEach { $0.invalidate() }
        timers.removeAll()

        let context = NudgeContext(
            mode: snapshot.mode,
            modeStartedAt: snapshot.mode == .idle ? (snapshot.pausedAt ?? idleSince) : snapshot.modeStartedAt,
            plannedRestEnd: snapshot.plannedRestEnd,
            taskTitle: snapshot.taskTitle,
            nextTaskTitle: snapshot.nextTaskTitle,
            openTaskCount: max(0, snapshot.plannedToday - snapshot.doneToday),
            dayEnded: snapshot.dayEnded,
            paused: snapshot.isPaused,
            tone: settings.tone,
            customReminders: settings.customReminders,
            thinkNudgeMinutes: settings.thinkNudgeMinutes,
            now: Date()
        )
        for nudge in NudgePlanner.plan(context) {
            let timer = Timer(fire: nudge.fireAt, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.fire(nudge) }
            }
            RunLoop.main.add(timer, forMode: .common)
            timers.append(timer)
        }
    }

    private func fire(_ nudge: Nudge) {
        guard !snapshot.dayEnded else { return }
        let hudMode: FlowMode = snapshot.mode == .idle ? .focus : snapshot.mode
        switch nudge.level {
        case 1:
            HUDToast.shared.show(title: nudge.title, message: nudge.body, mode: hudMode)
        case 2:
            HUDToast.shared.show(title: nudge.title, message: nudge.body, mode: hudMode, duration: 6)
            postNotification(nudge)
        default:
            showOverlay(title: nudge.title, message: nudge.body)
        }
    }

    private func showOverlay(title: String, message: String) {
        WakeUpOverlay.shared.show(.standard(title: title, message: message, snapshot: snapshot, snooze: { [weak self] in
            self?.snooze()
        }))
    }

    /// "Give me 2 minutes": come back in two minutes if nothing changed.
    private func snooze() {
        snoozeTimer?.invalidate()
        let mode = snapshot.mode
        let started = snapshot.modeStartedAt
        let timer = Timer(fire: Date().addingTimeInterval(120), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.snapshot.mode == mode, self.snapshot.modeStartedAt == started,
                      !self.snapshot.dayEnded, self.snapshot.mode != .focus else { return }
                let line = Copy(settings: self.settings).restOver(level: 3, next: self.snapshot.nextTaskTitle ?? self.snapshot.taskTitle)
                self.showOverlay(title: line.title, message: line.body)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        snoozeTimer = timer
    }

    private func postNotification(_ nudge: Nudge) {
        let content = UNMutableNotificationContent()
        content.title = nudge.title
        content.body = nudge.body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "tf.mac.nudge.\(nudge.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
