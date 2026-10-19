import Foundation

/// Who may talk to the Mac app's loopback bridge (`http://127.0.0.1:52525`), which the
/// Chrome-family extension uses for live state, boot-outs, juggling and the drift guard's tab
/// reports. Kept here so the rules are tested; `ExtensionBridgeServer` applies them.
///
/// - Web pages always send an `Origin` on a POST (`https://…`, or `null` when hidden), so only
///   browser-extension origins get through. A GET from a page without CORS gets an opaque reply.
/// - The `Host` header must be the loopback address itself. This stops DNS rebinding, where a
///   page on `127.0.0.1.attacker.example` re-points its own name at 127.0.0.1 and then reads
///   `/state` same-origin (no `Origin` header on a same-origin GET).
public enum BridgePolicy {
    public static func isExtensionOrigin(_ origin: String) -> Bool {
        let lowered = origin.lowercased()
        return lowered.hasPrefix("chrome-extension://")
            || lowered.hasPrefix("safari-web-extension://")
            || lowered.hasPrefix("moz-extension://")
            || lowered.hasPrefix("extension://")
    }

    /// `127.0.0.1`, `localhost` or `[::1]`, optionally with the bridge's port. An absent Host
    /// (only non-browser clients omit it) is allowed; browsers always send one.
    public static func isLoopbackHost(_ header: String?, port: UInt16) -> Bool {
        let host = (header ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if host.isEmpty { return true }
        let names = ["127.0.0.1", "localhost", "[::1]"]
        return names.contains { host == $0 || host == "\($0):\(port)" }
    }

    public static func allows(host: String?, origin: String?, port: UInt16) -> Bool {
        guard isLoopbackHost(host, port: port) else { return false }
        return origin.map(isExtensionOrigin) ?? true
    }
}
