import AppKit
import Foundation
import TrueFocusKit
import UserNotifications

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = FocusController.shared
        controller.register(DistractionGuard.shared)
        controller.register(ScrollWatch.shared)
        controller.register(MacNudger.shared)
        controller.register(FocusModeBridge.shared)
        controller.register(AudioDirector.shared)

        ExtensionBridgeServer.shared.start()
        HotKeys.shared.register()

        UNUserNotificationCenter.current().delegate = self
        MacNudger.shared.requestAuthorization()

        controller.appBecameActive()
        SyncService.shared.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        FocusController.shared.appBecameActive()
        Task { await SyncService.shared.syncNow() }
    }

    /// Clicking the Dock icon with no window open brings the main window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowOpener.shared.openMain() }
        return true
    }

    /// Closing the window keeps TrueFocus alive in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeys.shared.unregister()
        ExtensionBridgeServer.shared.stop()
    }

    // MARK: Notifications

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            WindowOpener.shared.openMain()
        }
    }
}
