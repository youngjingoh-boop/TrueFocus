import Foundation
import TrueFocusKit
import UserNotifications

/// Turns `NudgePlanner`'s schedule into local notifications on the iPhone:
/// "Rest's over. Move." → "Wake up." → "Wake the fuck up." (in the Savage tone).
///
/// Re-plans on every state change and cancels whatever was pending, so a nudge never
/// fires for a state you've already left.
private enum NudgeIDs {
    static let prefix = "tf.nudge."
    static let category = "tf.nudge"
    static let startNextAction = "tf.nudge.startNext"
    static let onItAction = "tf.nudge.onIt"
}

@MainActor
final class NudgeScheduler: NSObject, FocusEffect, UNUserNotificationCenterDelegate {
    static let shared = NudgeScheduler()

    private var started = false
    /// Bumped on every re-plan so a slow, older pass can't add stale requests.
    private var generation = 0
    private var lastTone: NudgeTone?
    private var lastThinkMinutes: Double?

    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    private override init() {
        super.init()
    }

    /// Call once at launch, before registering with `FocusController`.
    func start() {
        guard !started else { return }
        started = true
        center.delegate = self
        let startNext = UNNotificationAction(identifier: NudgeIDs.startNextAction, title: "Start next", options: [.foreground])
        let onIt = UNNotificationAction(identifier: NudgeIDs.onItAction, title: "I'm on it", options: [])
        let category = UNNotificationCategory(identifier: NudgeIDs.category, actions: [startNext, onIt],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error { print("TrueFocus: notification authorization failed: \(error)") }
        }
    }

    // MARK: FocusEffect

    func focusDidChange(_ snapshot: LiveSnapshot, previous: LiveSnapshot?, settings: TFSettings) {
        let settingsChanged = settings.tone != lastTone || settings.thinkNudgeMinutes != lastThinkMinutes
        guard previous == nil || !snapshot.isSameState(as: previous) || settingsChanged else { return }
        lastTone = settings.tone
        lastThinkMinutes = settings.thinkNudgeMinutes
        replan(snapshot: snapshot, settings: settings)
    }

    private func replan(snapshot: LiveSnapshot, settings: TFSettings) {
        generation += 1
        let pass = generation
        let openTasks = max(0, snapshot.plannedToday - snapshot.doneToday)

        // The device that started the segment owns its nudges; the Mac shows its own overlay.
        // Idle nudges come from every device: the phone is where the scrolling happens.
        let ownsNudges = snapshot.originDevice == "iPhone" || (snapshot.mode == .idle && openTasks > 0)

        var nudges: [Nudge] = []
        if ownsNudges {
            let context = NudgeContext(
                mode: snapshot.mode,
                modeStartedAt: snapshot.modeStartedAt,
                plannedRestEnd: snapshot.plannedRestEnd,
                taskTitle: snapshot.taskTitle,
                nextTaskTitle: snapshot.nextTaskTitle,
                openTaskCount: openTasks,
                dayEnded: snapshot.dayEnded,
                tone: settings.tone,
                thinkNudgeMinutes: settings.thinkNudgeMinutes,
                now: Date()
            )
            nudges = NudgePlanner.plan(context)
        }

        Task { @MainActor in
            let pending = await center.pendingNotificationRequests()
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(NudgeIDs.prefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            guard pass == generation else { return }
            for nudge in nudges {
                let interval = nudge.fireAt.timeIntervalSinceNow
                guard interval > 0 else { continue }
                let request = UNNotificationRequest(identifier: NudgeIDs.prefix + nudge.id,
                                                    content: content(for: nudge),
                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
                do {
                    try await center.add(request)
                } catch {
                    print("TrueFocus: couldn't schedule nudge \(nudge.id): \(error)")
                }
            }
        }
    }

    private func content(for nudge: Nudge) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = nudge.title
        content.body = nudge.body
        content.categoryIdentifier = NudgeIDs.category
        content.threadIdentifier = "tf.nudges"
        content.sound = .default
        switch nudge.level {
        case 1:
            content.interruptionLevel = .active
            content.relevanceScore = 0.4
        case 2:
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 0.8
        default:
            // The loudest a non-critical notification can be: breaks through Focus,
            // tops the summary.
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
        }
        return content
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let isNudge = response.notification.request.identifier.hasPrefix(NudgeIDs.prefix)
        Task { @MainActor in
            let focus = FocusController.shared
            if isNudge {
                switch action {
                case NudgeIDs.startNextAction:
                    focus.startNext()
                    focus.isFocusScreenPresented = focus.mode.isActive
                case NudgeIDs.onItAction:
                    focus.backToIt()
                case UNNotificationDefaultActionIdentifier:
                    focus.isFocusScreenPresented = focus.mode.isActive
                default:
                    break
                }
            }
            completionHandler()
        }
    }
}
