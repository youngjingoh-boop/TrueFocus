import Foundation

/// What a synced record is. Matches the `kind` check constraint in `tf_records`.
public enum RecordKind: String, Codable, Sendable, CaseIterable {
    case task, segment, plan, note
}

// MARK: - Payloads
//
// Plain mirrors of the SwiftData models. Encoded with sorted keys and seconds-since-1970
// dates so the same content always produces the same bytes (that's how changes are found).

public struct TaskPayload: Codable, Equatable, Sendable {
    public var title: String
    public var isDone: Bool
    public var doneAt: Date?
    public var createdAt: Date
    public var order: Double
    public var focusSeconds: Double
    public var breadcrumb: String
    public var inPlay: Bool
    public var inPlayAt: Date?

    public init(title: String, isDone: Bool, doneAt: Date?, createdAt: Date, order: Double,
                focusSeconds: Double, breadcrumb: String, inPlay: Bool, inPlayAt: Date?) {
        self.title = title
        self.isDone = isDone
        self.doneAt = doneAt
        self.createdAt = createdAt
        self.order = order
        self.focusSeconds = focusSeconds
        self.breadcrumb = breadcrumb
        self.inPlay = inPlay
        self.inPlayAt = inPlayAt
    }
}

public struct SegmentPayload: Codable, Equatable, Sendable {
    public var mode: String
    public var taskID: UUID?
    public var taskTitle: String
    public var startedAt: Date
    public var endedAt: Date?
    public var outcome: String?
    public var plannedSeconds: Double?
    public var device: String

    public init(mode: String, taskID: UUID?, taskTitle: String, startedAt: Date, endedAt: Date?,
                outcome: String?, plannedSeconds: Double?, device: String) {
        self.mode = mode
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.outcome = outcome
        self.plannedSeconds = plannedSeconds
        self.device = device
    }
}

public struct PlanPayload: Codable, Equatable, Sendable {
    public var day: Date
    public var outcome: String
    public var brainDump: String
    public var bootCount: Int
    public var endedAt: Date?
    public var reflection: String

    public init(day: Date, outcome: String, brainDump: String, bootCount: Int, endedAt: Date?, reflection: String) {
        self.day = day
        self.outcome = outcome
        self.brainDump = brainDump
        self.bootCount = bootCount
        self.endedAt = endedAt
        self.reflection = reflection
    }
}

public struct NotePayload: Codable, Equatable, Sendable {
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isPinned: Bool

    public init(body: String, createdAt: Date, updatedAt: Date, isPinned: Bool) {
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
    }
}

public enum PayloadCoding {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(T.self, from: data)
    }
}

public enum RecordID {
    /// Day plans get an ID derived from their day, so every device's plan for the same
    /// day is the same record and merges instead of duplicating.
    public static func plan(day: Date) -> UUID {
        var seconds = Int64(day.timeIntervalSince1970.rounded()).bigEndian
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = 0x54; bytes[1] = 0x46; bytes[2] = 0x50; bytes[3] = 0x4C // "TFPL"
        withUnsafeBytes(of: &seconds) { raw in
            for (index, byte) in raw.enumerated() { bytes[4 + index] = byte }
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x80 // keep the version nibble well-formed
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

// MARK: - Wire format

/// One row of `tf_records`. `blob` is the encrypted payload; the server never sees content.
public struct RemoteRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: RecordKind
    public var blob: String
    public var deleted: Bool
    public var modifiedAt: Date
    public var updatedAt: Date?

    public init(id: UUID, kind: RecordKind, blob: String, deleted: Bool, modifiedAt: Date, updatedAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.blob = blob
        self.deleted = deleted
        self.modifiedAt = modifiedAt
        self.updatedAt = updatedAt
    }

    private struct Envelope: Codable {
        var v: Int
        var c: String
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, data, deleted
        case modifiedAt = "modified_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(RecordKind.self, forKey: .kind)
        blob = (try? c.decode(Envelope.self, forKey: .data))?.c ?? ""
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    /// The server stamps `updated_at` itself, so it is never sent.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(Envelope(v: 1, c: blob), forKey: .data)
        try c.encode(deleted, forKey: .deleted)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }
}

/// Turns payload bytes into the opaque string stored on the server and back.
/// The apps use AES-GCM with a key derived from the space key (CryptoKit).
public protocol PayloadCipher: Sendable {
    func seal(_ plaintext: Data) throws -> String
    func open(_ sealed: String) throws -> Data
}

/// No encryption, for tests.
public struct PlainCipher: PayloadCipher {
    public init() {}
    public func seal(_ plaintext: Data) throws -> String { plaintext.base64EncodedString() }
    public func open(_ sealed: String) throws -> Data {
        guard let data = Data(base64Encoded: sealed) else { throw SyncError.corruptPayload }
        return data
    }
}

public enum SyncError: Error, Equatable, Sendable {
    case notConfigured
    case corruptPayload
    case http(Int, String)
    case invalidResponse
}

/// PostgREST timestamps: "2026-10-17T07:41:20.907161+00:00" in, "…T07:41:20.907Z" out.
public enum SyncDates {
    public static func parse(_ text: String) -> Date? {
        let pattern = #"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(\.\d+)?(Z|[+-]\d{2}:?\d{2})?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let baseRange = Range(match.range(at: 1), in: text) else { return nil }
        var zone = "Z"
        if let zoneRange = Range(match.range(at: 3), in: text) { zone = String(text[zoneRange]) }
        if zone != "Z", !zone.contains(":") { zone.insert(":", at: zone.index(zone.startIndex, offsetBy: 3)) }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let base = formatter.date(from: String(text[baseRange]) + zone) else { return nil }
        var fraction = 0.0
        if let fractionRange = Range(match.range(at: 2), in: text) {
            fraction = Double("0" + text[fractionRange]) ?? 0
        }
        return base.addingTimeInterval(fraction)
    }

    public static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parse(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date \(text)")
            }
            return date
        }
        return decoder
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(format(date))
        }
        return encoder
    }
}
