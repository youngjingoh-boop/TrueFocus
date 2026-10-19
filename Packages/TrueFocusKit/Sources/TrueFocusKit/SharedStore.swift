import Foundation

/// The App Group shared by the app and its extensions on one device.
/// Each target's Info.plist carries `TFAppGroup = $(TF_APP_GROUP)`.
public enum AppGroup {
    public static var identifier: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "TFAppGroup") as? String,
           !value.isEmpty, !value.contains("$(") {
            return value
        }
        return "group.app.truefocus"
    }

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

/// A doom-scroll boot-out recorded by an extension, collected by the app.
public struct BootEvent: Codable, Equatable, Sendable {
    public var at: Date
    /// "web", "mac-native", "mac-browser", "ios-budget", "ios-shield"
    public var source: String
    public var site: String?
    public var reason: String?

    public init(at: Date = Date(), source: String, site: String? = nil, reason: String? = nil) {
        self.at = at
        self.source = source
        self.site = site
        self.reason = reason
    }
}

/// A request made from outside the app (a widget button, a shield, a web page) for the
/// app to act on next time it runs. Intents normally run inside the app process; this
/// queue is the fallback for surfaces that can't.
public struct RemoteCommand: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case complete, stuck, backToIt, startNext, endDay
        /// Switch to the juggled task `taskID`.
        case switchTo
        /// Mark the current task as waiting and move to the next juggled one.
        case wait
        /// Stop the clock on the current task, or pick the paused one back up.
        case pause, resume
    }

    public var kind: Kind
    public var at: Date
    /// The task a `switchTo` is about.
    public var taskID: UUID?

    public init(kind: Kind, at: Date = Date(), taskID: UUID? = nil) {
        self.kind = kind
        self.at = at
        self.taskID = taskID
    }
}

/// Read/write access to everything shared through the App Group.
public final class SharedStore {
    public enum Key {
        public static let snapshot = "tf.snapshot.v1"
        public static let settings = "tf.settings.v1"
        public static let boots = "tf.boots.v1"
        public static let commands = "tf.commands.v1"
    }

    public static let shared = SharedStore()

    public let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? AppGroup.defaults
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self.decoder = decoder
    }

    public var snapshot: LiveSnapshot {
        get { read(LiveSnapshot.self, Key.snapshot) ?? .idle }
        set { write(newValue, Key.snapshot) }
    }

    public var settings: TFSettings {
        get { read(TFSettings.self, Key.settings) ?? .default }
        set {
            var normalized = newValue
            normalized.normalize()
            write(normalized, Key.settings)
        }
    }

    /// The snapshot as a JSON object, for the browser extension bridges.
    public func snapshotJSON() -> Data {
        (try? encoder.encode(snapshot)) ?? Data("{}".utf8)
    }

    public func appendBoot(_ event: BootEvent) {
        var events = read([BootEvent].self, Key.boots) ?? []
        events.append(event)
        if events.count > 200 { events.removeFirst(events.count - 200) }
        write(events, Key.boots)
    }

    /// Returns and clears boot-outs recorded by extensions.
    public func drainBoots() -> [BootEvent] {
        let events = read([BootEvent].self, Key.boots) ?? []
        if !events.isEmpty { defaults.removeObject(forKey: Key.boots) }
        return events
    }

    public func enqueue(_ command: RemoteCommand) {
        var commands = read([RemoteCommand].self, Key.commands) ?? []
        commands.append(command)
        write(commands, Key.commands)
    }

    public func drainCommands() -> [RemoteCommand] {
        let commands = read([RemoteCommand].self, Key.commands) ?? []
        if !commands.isEmpty { defaults.removeObject(forKey: Key.commands) }
        return commands
    }

    public func read<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    public func write<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
