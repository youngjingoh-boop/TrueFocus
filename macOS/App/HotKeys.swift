import AppKit
import Carbon.HIToolbox
import Foundation

/// System-wide shortcuts, so the flow verbs work from any app:
///
///     ⌥⌘D  Done with the current task
///     ⌥⌘S  Stuck → think time
///     ⌥⌘B  Back to it / start the next task
///     ⌥⌘T  Show TrueFocus
///
/// Uses Carbon's RegisterEventHotKey, which needs no special permission.
@MainActor
final class HotKeys {
    static let shared = HotKeys()

    enum Action: UInt32 {
        case done = 1
        case stuck = 2
        case back = 3
        case show = 4
    }

    /// 'TFKY'
    nonisolated fileprivate static let signature: OSType = 0x5446_4B59

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?

    func register() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), tfHotKeyHandler, 1, &eventType, nil, &handlerRef)
        guard status == noErr else {
            print("TrueFocus: couldn't install hot key handler (\(status))")
            return
        }
        let modifiers = UInt32(cmdKey | optionKey)
        add(.done, keyCode: UInt32(kVK_ANSI_D), modifiers: modifiers)
        add(.stuck, keyCode: UInt32(kVK_ANSI_S), modifiers: modifiers)
        add(.back, keyCode: UInt32(kVK_ANSI_B), modifiers: modifiers)
        add(.show, keyCode: UInt32(kVK_ANSI_T), modifiers: modifiers)
    }

    func unregister() {
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    private func add(_ action: Action, keyCode: UInt32, modifiers: UInt32) {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: HotKeys.signature, id: action.rawValue)
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRefs.append(ref)
        } else {
            print("TrueFocus: hot key \(action) unavailable (\(status)) — another app may own it")
        }
    }

    fileprivate func perform(_ rawID: UInt32) {
        guard let action = Action(rawValue: rawID) else { return }
        let controller = FocusController.shared
        switch action {
        case .done:
            controller.complete()
        case .stuck:
            if controller.mode == .focus {
                controller.stuck()
            } else {
                controller.backToIt()
            }
        case .back:
            if controller.mode == .focus { return }
            controller.backToIt()
        case .show:
            WindowOpener.shared.openMain()
        }
    }
}

/// C callback for Carbon. Must not capture context, so it hops to the shared instance.
private func tfHotKeyHandler(_ nextHandler: EventHandlerCallRef?, _ event: EventRef?,
                             _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    guard status == noErr, hotKeyID.signature == HotKeys.signature else {
        return OSStatus(eventNotHandledErr)
    }
    let id = hotKeyID.id
    DispatchQueue.main.async {
        MainActor.assumeIsolated { HotKeys.shared.perform(id) }
    }
    return noErr
}
