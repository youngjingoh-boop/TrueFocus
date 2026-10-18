import Foundation
import SafariServices
import TrueFocusKit

/// Native side of the TrueFocus Safari extension (iPhone and Mac).
///
/// The extension's background script calls `browser.runtime.sendNativeMessage` with:
/// - `{type: "state"}` → `{ok, snapshot, settings}` read from the App Group.
/// - `{type: "boot", site, reason}` → records a doom-scroll boot-out for the app to collect,
///   then replies like `state`.
/// - `{type: "command", kind: "switchTo" | "wait", taskID}` → queues a juggling command
///   for the app, then replies like `state`.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    /// Posted (Darwin notification) whenever the extension writes to the App Group,
    /// so a running app can pick the change up without waiting to be foregrounded.
    static let sharedChangedNotification = "app.truefocus.shared-changed"

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]
        let type = message["type"] as? String ?? "state"
        let store = SharedStore.shared

        var reply: [String: Any] = ["ok": true]
        switch type {
        case "boot":
            store.appendBoot(BootEvent(source: "web",
                                       site: Self.string(message["site"]),
                                       reason: Self.string(message["reason"])))
            Self.postSharedChanged()
            reply["recorded"] = true
        case "command":
            let kind = (message["kind"] as? String).flatMap(RemoteCommand.Kind.init(rawValue:))
            let taskID = (message["taskID"] as? String).flatMap(UUID.init(uuidString:))
            if let kind, kind == .wait || (kind == .switchTo && taskID != nil) {
                store.enqueue(RemoteCommand(kind: kind, taskID: taskID))
                Self.postSharedChanged()
                reply["queued"] = true
            } else {
                reply["ok"] = false
                reply["error"] = "bad command"
            }
        case "state":
            break
        default:
            reply["ok"] = false
            reply["error"] = "unknown message type"
        }

        reply["snapshot"] = Self.jsonObject(store.snapshotJSON()) ?? [:]
        reply["settings"] = Self.jsonObject(Self.encode(store.settings)) ?? [:]

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: reply]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    // MARK: Helpers

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(120))
    }

    /// Encodes with the same date strategy as SharedStore (seconds since 1970).
    private static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return (try? encoder.encode(value)) ?? Data("{}".utf8)
    }

    /// JSON data → Foundation objects Safari can hand to JavaScript.
    private static func jsonObject(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data, options: [])
    }

    private static func postSharedChanged() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let name = CFNotificationName(sharedChangedNotification as CFString)
        CFNotificationCenterPostNotification(center, name, nil, nil, true)
    }
}
