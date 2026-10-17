import Foundation
import TrueFocusKit

/// A platform side effect of the flow state: shields, Live Activity, nudges, the Mac
/// overlay and distraction guard, Focus-mode shortcuts. Register with
/// `FocusController.register(_:)`; it is called once immediately and then after every
/// state change, whether it happened here or arrived from the other device.
@MainActor
protocol FocusEffect: AnyObject {
    func focusDidChange(_ snapshot: LiveSnapshot, previous: LiveSnapshot?, settings: TFSettings)
}
