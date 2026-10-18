#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation
import TrueFocusKit

/// Keeps one Live Activity in step with the flow state.
///
/// iOS only lets an app *start* a Live Activity while it's in the foreground, so a session
/// started on the Mac appears here the next time the iPhone app is opened
/// (`appDidBecomeActive()`); after that, updates arrive in the background as sync pulls them in.
@MainActor
final class LiveActivityController: FocusEffect {
    static let shared = LiveActivityController()

    typealias State = FocusActivityAttributes.ContentState

    private var activity: Activity<FocusActivityAttributes>?
    private var lastState: State?

    private init() {
        adoptExisting()
    }

    // MARK: FocusEffect

    func focusDidChange(_ snapshot: LiveSnapshot, previous: LiveSnapshot?, settings: TFSettings) {
        sync(with: snapshot)
    }

    /// Call when the app comes to the foreground: the only moment a new activity can start.
    func appDidBecomeActive() {
        sync(with: SharedStore.shared.snapshot)
    }

    // MARK: Sync

    private func sync(with snapshot: LiveSnapshot) {
        adoptExisting()
        let state = State(snapshot: snapshot)

        // A pause keeps the card on the Lock Screen, with Resume one tap away.
        guard snapshot.mode.isActive || snapshot.isPaused else {
            end(with: state, snapshot: snapshot)
            return
        }

        if let activity {
            guard state != lastState else { return }
            lastState = state
            let content = ActivityContent(state: state, staleDate: staleDate(for: snapshot))
            Task { await activity.update(content) }
        } else {
            start(with: state, snapshot: snapshot)
        }
    }

    private func start(with state: State, snapshot: LiveSnapshot) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            let content = ActivityContent(state: state, staleDate: staleDate(for: snapshot))
            activity = try Activity.request(attributes: FocusActivityAttributes(startedAt: Date()),
                                            content: content,
                                            pushType: nil)
            lastState = state
        } catch {
            // Not in the foreground, or Live Activities are off. The widgets still show the task.
        }
    }

    private func end(with state: State, snapshot: LiveSnapshot) {
        guard let activity else { return }
        // Nothing left (or the day is over): clear the Lock Screen now.
        // Idle with work left: leave the final "next up" card on the Lock Screen for a while.
        let nothingLeft = snapshot.dayEnded || snapshot.plannedToday <= snapshot.doneToday
        let policy: ActivityUIDismissalPolicy = nothingLeft ? .immediate : .default
        let content = ActivityContent(state: state, staleDate: nil)
        self.activity = nil
        lastState = nil
        Task { await activity.end(content, dismissalPolicy: policy) }
    }

    /// Picks up an activity left over from a previous launch and ends any duplicates.
    private func adoptExisting() {
        let live = Activity<FocusActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
        if let activity, live.contains(where: { $0.id == activity.id }) {
            endDuplicates(of: activity, in: live)
            return
        }
        activity = live.first
        if let first = live.first {
            lastState = first.content.state
            endDuplicates(of: first, in: live)
        } else {
            lastState = nil
        }
    }

    private func endDuplicates(of keep: Activity<FocusActivityAttributes>, in live: [Activity<FocusActivityAttributes>]) {
        for duplicate in live where duplicate.id != keep.id {
            Task { await duplicate.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// A rest that runs long goes stale 15 minutes after it was meant to end.
    private func staleDate(for snapshot: LiveSnapshot) -> Date? {
        guard snapshot.mode == .rest, let end = snapshot.plannedRestEnd else { return nil }
        return end.addingTimeInterval(15 * 60)
    }
}
#endif
