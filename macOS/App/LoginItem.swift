import ServiceManagement
import SwiftUI

/// TrueFocus opens at login, so the menu bar, shields and sync keep running after a restart
/// or after quitting Xcode. Turned on once, on first launch; Settings can turn it off.
enum LoginItem {
    private static let offeredKey = "tf.loginItem.offered.v1"

    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("TrueFocus: login item \(on ? "register" : "unregister") failed: \(error)")
        }
    }

    /// Call at launch.
    static func enableOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: offeredKey) else { return }
        defaults.set(true, forKey: offeredKey)
        set(true)
    }
}

/// "Open at login" for the Mac settings.
struct LoginItemSection: View {
    @State private var isOn = LoginItem.isOn

    var body: some View {
        SettingsSection("Mac", footnote: "Keeps the menu bar, shields and sync running after a restart. Run TrueFocus from Applications rather than Xcode so it stays put.") {
            ToggleRow(title: "Open at login", isOn: Binding(
                get: { isOn },
                set: { value in
                    LoginItem.set(value)
                    isOn = LoginItem.isOn
                }
            ))
        }
        .onAppear { isOn = LoginItem.isOn }
    }
}
