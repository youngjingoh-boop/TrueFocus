import Foundation

/// A record as it exists on this device right now.
public struct LocalItem: Equatable, Sendable {
    public var id: UUID
    public var kind: RecordKind
    /// Canonical payload bytes (`PayloadCoding.encode`).
    public var payload: Data

    public init(id: UUID, kind: RecordKind, payload: Data) {
        self.id = id
        self.kind = kind
        self.payload = payload
    }

    public var fingerprint: String { SyncLedger.fingerprint(payload) }
}

/// What this device last agreed with the server about, per record, plus the pull cursor.
public struct SyncLedger: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var kind: RecordKind
        public var fingerprint: String
        public var modifiedAt: Date
        public var deleted: Bool
        /// Day plans only: the last agreed payload, so concurrent edits merge field by field.
        public var base: Data?

        public init(kind: RecordKind, fingerprint: String, modifiedAt: Date, deleted: Bool, base: Data? = nil) {
            self.kind = kind
            self.fingerprint = fingerprint
            self.modifiedAt = modifiedAt
            self.deleted = deleted
            self.base = base
        }
    }

    public var entries: [UUID: Entry]
    /// Server `updated_at` of the newest record pulled.
    public var cursor: Date?

    public init(entries: [UUID: Entry] = [:], cursor: Date? = nil) {
        self.entries = entries
        self.cursor = cursor
    }

    /// FNV-1a 64. Only needs to notice change, not resist attack.
    public static func fingerprint(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}

/// A change this device should upload.
public struct OutgoingChange: Equatable, Sendable {
    public var id: UUID
    public var kind: RecordKind
    /// nil for a deletion.
    public var payload: Data?
    public var modifiedAt: Date

    public var deleted: Bool { payload == nil }
}

/// A record from the server, opened, and what to do with it.
public struct IncomingChange: Equatable, Sendable {
    public var id: UUID
    public var kind: RecordKind
    /// nil for a deletion.
    public var payload: Data?
    public var modifiedAt: Date

    public var deleted: Bool { payload == nil }
}

/// What to do with a pulled change.
public enum Resolution: Equatable, Sendable {
    /// Nothing changed here since the last sync: take the server's version.
    case apply(IncomingChange)
    /// Both sides changed a day plan: write this merged payload, then upload it.
    case merge(IncomingChange, Data)
    /// This device changed the record too and its edit wins; it is uploaded next.
    case keepLocal(IncomingChange)

    public var change: IncomingChange {
        switch self {
        case .apply(let change), .merge(let change, _), .keepLocal(let change): return change
        }
    }
}

/// The sync decisions, with no I/O. The app supplies what's on the device and what came from
/// the server; this says what to upload and what to apply. Last writer wins by modification time.
public enum SyncPlanner {
    /// - Parameters:
    ///   - local: every record currently on the device, for the kinds in `scanned`.
    ///   - scanned: kinds `local` is complete for; only those can produce deletions.
    public static func outgoing(local: [LocalItem], ledger: SyncLedger,
                                scanned: Set<RecordKind> = Set(RecordKind.allCases), now: Date) -> [OutgoingChange] {
        var changes: [OutgoingChange] = []
        var present = Set<UUID>()
        for item in local {
            present.insert(item.id)
            let entry = ledger.entries[item.id]
            if entry == nil || entry?.deleted == true || entry?.fingerprint != item.fingerprint {
                // Never stamp an edit older than what we already agreed on (clock went back).
                let stamp = millis(max(now, (entry?.modifiedAt ?? .distantPast).addingTimeInterval(0.001)))
                changes.append(OutgoingChange(id: item.id, kind: item.kind, payload: item.payload, modifiedAt: stamp))
            }
        }
        for (id, entry) in ledger.entries where !entry.deleted && scanned.contains(entry.kind) && !present.contains(id) {
            let stamp = millis(max(now, entry.modifiedAt.addingTimeInterval(0.001)))
            changes.append(OutgoingChange(id: id, kind: entry.kind, payload: nil, modifiedAt: stamp))
        }
        return changes.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// The ledger after `changes` were uploaded successfully.
    public static func recordUploaded(_ changes: [OutgoingChange], in ledger: inout SyncLedger) {
        for change in changes {
            ledger.entries[change.id] = SyncLedger.Entry(
                kind: change.kind,
                fingerprint: change.payload.map(SyncLedger.fingerprint) ?? "",
                modifiedAt: change.modifiedAt,
                deleted: change.deleted,
                base: change.kind == .plan ? change.payload : nil
            )
        }
    }

    /// Which pulled records to apply. Anything not newer than what this device has is skipped,
    /// including echoes of its own uploads.
    public static func incoming(_ remote: [IncomingChange], ledger: SyncLedger) -> [IncomingChange] {
        var newest: [UUID: IncomingChange] = [:]
        for change in remote {
            if let existing = newest[change.id], existing.modifiedAt >= change.modifiedAt { continue }
            newest[change.id] = change
        }
        return newest.values
            .filter { change in
                guard let entry = ledger.entries[change.id] else { return true }
                return change.modifiedAt > entry.modifiedAt
            }
            .sorted { $0.modifiedAt < $1.modifiedAt }
    }

    /// The ledger after `change` was applied on the device. `localPayload` is the payload as
    /// the device re-encodes it after applying, so the next scan doesn't see a false change.
    public static func recordApplied(_ change: IncomingChange, localPayload: Data?, in ledger: inout SyncLedger) {
        let payload = change.deleted ? nil : (localPayload ?? change.payload)
        ledger.entries[change.id] = SyncLedger.Entry(
            kind: change.kind,
            fingerprint: payload.map(SyncLedger.fingerprint) ?? "",
            modifiedAt: change.modifiedAt,
            deleted: change.deleted,
            base: change.kind == .plan ? payload : nil
        )
    }

    /// The ledger after seeing `change` without taking it (`merge`, `keepLocal`). The device's
    /// own version now differs from what the ledger holds, so the next `outgoing` uploads it
    /// with a stamp newer than the server's.
    public static func recordSeen(_ change: IncomingChange, in ledger: inout SyncLedger) {
        ledger.entries[change.id] = SyncLedger.Entry(
            kind: change.kind,
            fingerprint: change.payload.map(SyncLedger.fingerprint) ?? "",
            modifiedAt: change.modifiedAt,
            deleted: change.deleted,
            base: change.kind == .plan ? change.payload : nil
        )
    }

    /// Decides each pulled change against what is on the device. A record this device changed
    /// since the last sync keeps its edit (day plans merge field by field instead); everything
    /// else takes the server's version. Pass the result of `incoming`, and every local record.
    public static func resolve(_ incoming: [IncomingChange], local: [UUID: LocalItem],
                               ledger: SyncLedger) -> [Resolution] {
        incoming.map { change in
            let entry = ledger.entries[change.id]
            let item = local[change.id]
            let editedHere: Bool
            if let item {
                editedHere = entry == nil || entry?.deleted == true || entry?.fingerprint != item.fingerprint
            } else {
                editedHere = entry.map { !$0.deleted } ?? false // deleted here since the last sync
            }
            guard editedHere else { return .apply(change) }
            if change.kind == .plan, let item, let remote = change.payload,
               let merged = PlanPayload.merge(base: entry?.base, local: item.payload, remote: remote) {
                return .merge(change, merged)
            }
            return .keepLocal(change)
        }
    }

    /// Where the next pull starts: a little before the newest row seen, because rows committed
    /// in the same instant can land out of order. Re-reading a few rows is harmless.
    /// Whole milliseconds, which is what the server keeps, so echoes compare equal.
    static func millis(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded(.up) / 1000)
    }

    public static func pullStart(for ledger: SyncLedger, overlap: TimeInterval = 5) -> Date? {
        ledger.cursor.map { $0.addingTimeInterval(-overlap) }
    }
}

extension PlanPayload {
    /// Three-way merge of a day plan edited on two devices. A field one side left as it was in
    /// `base` takes the other side's value; boot-outs add up. Without a base (first sync of a
    /// newly linked device) the local text wins where it isn't empty.
    public static func merge(base baseData: Data?, local localData: Data, remote remoteData: Data) -> Data? {
        guard let local = try? PayloadCoding.decode(PlanPayload.self, from: localData),
              let remote = try? PayloadCoding.decode(PlanPayload.self, from: remoteData) else { return nil }
        let base = baseData.flatMap { try? PayloadCoding.decode(PlanPayload.self, from: $0) }

        func pick<T: Equatable>(_ path: KeyPath<PlanPayload, T>, empty: (T) -> Bool) -> T {
            if let base { return local[keyPath: path] == base[keyPath: path] ? remote[keyPath: path] : local[keyPath: path] }
            return empty(local[keyPath: path]) ? remote[keyPath: path] : local[keyPath: path]
        }
        let boots: Int
        if let base {
            boots = max(0, local.bootCount + remote.bootCount - base.bootCount)
        } else {
            boots = max(local.bootCount, remote.bootCount)
        }
        let merged = PlanPayload(
            day: remote.day,
            outcome: pick(\.outcome, empty: { $0.isEmpty }),
            brainDump: pick(\.brainDump, empty: { $0.isEmpty }),
            bootCount: boots,
            endedAt: pick(\.endedAt, empty: { $0 == nil }),
            reflection: pick(\.reflection, empty: { $0.isEmpty })
        )
        return try? PayloadCoding.encode(merged)
    }
}
