import SwiftUI
import TrueFocusKit
import UIKit

@main
struct TrueFocusApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(FocusController.shared)
                .modelContainer(FocusController.shared.container)
                .onOpenURL { url in
                    DeepLink.handle(url)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                FocusController.shared.appBecameActive()
                LiveActivityController.shared.appDidBecomeActive()
                Task { await SyncService.shared.syncNow() }
            case .background:
                // Get the last edits up before iOS suspends the app.
                let application = UIApplication.shared
                var task = UIBackgroundTaskIdentifier.invalid
                task = application.beginBackgroundTask { application.endBackgroundTask(task) }
                Task {
                    await SyncService.shared.syncNow()
                    application.endBackgroundTask(task)
                }
            default:
                break
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let controller = FocusController.shared

        ScreenTimeGuard.shared.start()
        controller.register(ScreenTimeGuard.shared)

        NudgeScheduler.shared.start()
        controller.register(NudgeScheduler.shared)

        controller.register(LiveActivityController.shared)

        SyncService.shared.start()
        // Silent pushes from the sync server wake the app when the Mac changes the plan,
        // so the Lock Screen, Live Activity and shields follow along in the background.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        SyncService.shared.setDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await SyncService.shared.syncNow()
        return .newData
    }
}

enum DeepLink {
    /// truefocus://focus · truefocus://today · truefocus://done · truefocus://next
    @MainActor
    static func handle(_ url: URL) {
        guard url.scheme == "truefocus" else { return }
        let controller = FocusController.shared
        switch url.host() ?? url.path() {
        case "focus":
            controller.isFocusScreenPresented = controller.mode.isActive
        case "done":
            controller.complete()
        case "next":
            controller.startNext()
            controller.isFocusScreenPresented = true
        default:
            controller.isFocusScreenPresented = false
        }
    }
}
