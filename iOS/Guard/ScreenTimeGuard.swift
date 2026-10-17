import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import Observation
import TrueFocusKit
import UIKit

/// The iPhone side of "cut out the distractions".
///
/// - While you work (focus or think, or a Focus with the TrueFocus filter is on), the apps
///   you picked are shielded.
/// - The rest of the day they run on a scroll budget: use them past it and you're booted
///   out for a cooldown. Reply apps get a short pass to answer messages.
/// - The adult filter blocks adult sites across Safari and in-app browsers.
///
/// Everything stays under your control through iOS Settings ▸ Screen Time.
@MainActor
@Observable
final class ScreenTimeGuard: FocusEffect {
    static let shared = ScreenTimeGuard()

    private(set) var authorization: FamilyControls.AuthorizationStatus = .notDetermined
    private(set) var config: GuardConfig = GuardStore.load()
    private(set) var isRequesting = false
    private(set) var lastError: String?

    @ObservationIgnored private var started = false
    @ObservationIgnored private var adultTimer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var lastSettings: TFSettings = .default

    var isAuthorized: Bool { authorization == .approved }

    private init() {}

    // MARK: Lifecycle

    /// Call once at launch, before registering with `FocusController`.
    func start() {
        guard !started else { return }
        started = true
        lastSettings = SharedStore.shared.settings
        refreshAuthorization()
        config = GuardStore.load()
        applyEverything(settings: lastSettings)
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.becameActive() }
        })
    }

    func requestAuthorization() async {
        guard !isRequesting else { return }
        isRequesting = true
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            lastError = nil
        } catch {
            lastError = "Screen Time access wasn't granted. You can allow it any time in Settings ▸ Screen Time."
        }
        isRequesting = false
        refreshAuthorization()
        applyEverything(settings: SharedStore.shared.settings)
    }

    private func refreshAuthorization() {
        authorization = AuthorizationCenter.shared.authorizationStatus
    }

    private func becameActive() {
        refreshAuthorization()
        // The extensions may have changed the config while we were away.
        config = GuardStore.load()
        applyEverything(settings: SharedStore.shared.settings)
    }

    // MARK: FocusEffect

    func focusDidChange(_ snapshot: LiveSnapshot, previous: LiveSnapshot?, settings: TFSettings) {
        lastSettings = settings
        let shieldNow = isAuthorized && snapshot.shouldShield && settings.shieldDuringFocus
        if shieldNow != config.focusShieldActive {
            config = GuardStore.update { $0.focusShieldActive = shieldNow }
        } else {
            config = GuardStore.load()
        }
        applyEverything(settings: settings)
    }

    // MARK: Selection

    func setScrollSelection(_ selection: FamilyActivitySelection) {
        config = GuardStore.update { $0.scrollSelection = selection }
        applyEverything(settings: SharedStore.shared.settings)
    }

    func setReplySelection(_ selection: FamilyActivitySelection) {
        config = GuardStore.update { config in
            config.replySelection = selection
            // A pass only makes sense for an app that is still a reply app.
            config.passTokens = config.passTokens.intersection(selection.applicationTokens)
        }
        applyEverything(settings: SharedStore.shared.settings)
    }

    func passesRemaining(settings: TFSettings) -> Int {
        config.passesRemaining(settings: settings)
    }

    // MARK: Adult filter

    /// Starts the cool-off. The filter stays on until it passes; cancel any time before.
    func requestAdultFilterOff() {
        let now = Date()
        FocusController.shared.updateSettings { $0.adultFilterOffRequestedAt = now }
        if let end = SharedStore.shared.settings.adultFilterOffEffectiveAt {
            GuardMonitoring.scheduleAdultCoolOff(until: end, from: now)
        }
        applyEverything(settings: SharedStore.shared.settings)
    }

    /// Cancels a pending turn-off, or turns the filter back on after it went off.
    func keepAdultFilterOn() {
        FocusController.shared.updateSettings { settings in
            settings.adultFilterOffRequestedAt = nil
            settings.adultFilterEnabled = true
        }
        GuardMonitoring.cancelAdultCoolOff()
        applyEverything(settings: SharedStore.shared.settings)
    }

    // MARK: Applying

    private func applyEverything(settings: TFSettings) {
        guard isAuthorized else { return }
        GuardShields.reapply(config)
        AdultFilter.apply(settings: settings)
        ensureMonitoring(settings: settings)
        scheduleAdultTimer(settings: settings)
    }

    /// Restarts the daily budget monitor only when the selection or budget changed.
    private func ensureMonitoring(settings: TFSettings) {
        let signature = config.signature(settings: settings)
        guard signature != config.monitoringSignature else { return }
        GuardMonitoring.startDailyBudget(config, settings: settings)
        // A fresh budget that was already counting picks up the new selection too.
        if !config.budgetShieldActive, DeviceActivityCenter().activities.contains(.budgetRestart) {
            GuardMonitoring.restartBudget(config, settings: settings)
        }
        if !config.hasSelection {
            config = GuardStore.update { config in
                config.budgetShieldActive = false
                config.budgetShieldUntil = nil
            }
            GuardShields.reapply(config)
        }
        config = GuardStore.update { $0.monitoringSignature = signature }
    }

    /// While the app is open, flip the filter the moment a cool-off ends.
    /// (The monitor extension does the same when the app is closed.)
    private func scheduleAdultTimer(settings: TFSettings) {
        adultTimer?.invalidate()
        adultTimer = nil
        guard let end = settings.adultFilterOffEffectiveAt, end > Date(), settings.adultFilterEnabled else { return }
        adultTimer = Timer.scheduledTimer(withTimeInterval: end.timeIntervalSinceNow + 1, repeats: false) { _ in
            Task { @MainActor in
                AdultFilter.apply()
                FocusController.shared.publish(force: true)
            }
        }
    }
}
