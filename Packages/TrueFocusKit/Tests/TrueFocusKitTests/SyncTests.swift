import XCTest
@testable import TrueFocusKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class SyncPlannerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func item(_ id: UUID, _ title: String) throws -> LocalItem {
        let payload = TaskPayload(title: title, isDone: false, doneAt: nil, createdAt: t0, order: 1,
                                  focusSeconds: 0, breadcrumb: "", inPlay: false, inPlayAt: nil)
        return LocalItem(id: id, kind: .task, payload: try PayloadCoding.encode(payload))
    }

    func testNewAndChangedItemsAreUploadedOnce() throws {
        let a = UUID(), b = UUID()
        var ledger = SyncLedger()
        let first = SyncPlanner.outgoing(local: [try item(a, "A"), try item(b, "B")], ledger: ledger, now: t0)
        XCTAssertEqual(Set(first.map(\.id)), [a, b])
        SyncPlanner.recordUploaded(first, in: &ledger)

        XCTAssertTrue(SyncPlanner.outgoing(local: [try item(a, "A"), try item(b, "B")], ledger: ledger, now: t0).isEmpty)

        let edited = SyncPlanner.outgoing(local: [try item(a, "A2"), try item(b, "B")], ledger: ledger,
                                          now: t0.addingTimeInterval(10))
        XCTAssertEqual(edited.map(\.id), [a])
        XCTAssertEqual(edited.first!.modifiedAt.timeIntervalSince1970, t0.addingTimeInterval(10).timeIntervalSince1970,
                       accuracy: 0.001)
    }

    func testMissingItemsBecomeTombstonesOnlyForScannedKinds() throws {
        let a = UUID(), note = UUID()
        var ledger = SyncLedger()
        ledger.entries[a] = .init(kind: .task, fingerprint: "x", modifiedAt: t0, deleted: false)
        ledger.entries[note] = .init(kind: .note, fingerprint: "y", modifiedAt: t0, deleted: false)
        let changes = SyncPlanner.outgoing(local: [], ledger: ledger, scanned: [.task], now: t0.addingTimeInterval(5))
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.id, a)
        XCTAssertTrue(changes.first?.deleted ?? false)
    }

    func testClockGoingBackwardsStillWins() throws {
        let a = UUID()
        var ledger = SyncLedger()
        ledger.entries[a] = .init(kind: .task, fingerprint: "old", modifiedAt: t0, deleted: false)
        let change = SyncPlanner.outgoing(local: [try item(a, "new")], ledger: ledger, now: t0.addingTimeInterval(-60))
        XCTAssertGreaterThan(change.first!.modifiedAt, t0)
    }

    func testIncomingSkipsEchoesAndOlderEdits() {
        let a = UUID(), b = UUID(), c = UUID()
        var ledger = SyncLedger()
        ledger.entries[a] = .init(kind: .task, fingerprint: "f", modifiedAt: t0, deleted: false)
        ledger.entries[b] = .init(kind: .task, fingerprint: "f", modifiedAt: t0, deleted: false)
        let remote = [
            IncomingChange(id: a, kind: .task, payload: Data("x".utf8), modifiedAt: t0),                      // echo
            IncomingChange(id: b, kind: .task, payload: Data("y".utf8), modifiedAt: t0.addingTimeInterval(1)), // newer
            IncomingChange(id: c, kind: .task, payload: nil, modifiedAt: t0),                                 // unknown delete
            IncomingChange(id: b, kind: .task, payload: Data("z".utf8), modifiedAt: t0.addingTimeInterval(2)), // newest wins
        ]
        let apply = SyncPlanner.incoming(remote, ledger: ledger)
        XCTAssertEqual(apply.map(\.id), [c, b])
        XCTAssertEqual(apply.last?.payload, Data("z".utf8))
    }

    func testAppliedRecordUsesLocalFingerprint() {
        var ledger = SyncLedger()
        let id = UUID()
        let change = IncomingChange(id: id, kind: .note, payload: Data("remote".utf8), modifiedAt: t0)
        SyncPlanner.recordApplied(change, localPayload: Data("local".utf8), in: &ledger)
        XCTAssertEqual(ledger.entries[id]?.fingerprint, SyncLedger.fingerprint(Data("local".utf8)))
        XCTAssertEqual(ledger.entries[id]?.modifiedAt, t0)
    }

    func plan(_ outcome: String, dump: String = "", boots: Int = 0) throws -> Data {
        try PayloadCoding.encode(PlanPayload(day: t0, outcome: outcome, brainDump: dump, bootCount: boots,
                                             endedAt: nil, reflection: ""))
    }

    func testResolveTakesServerUnlessEditedHere() throws {
        let clean = UUID(), edited = UUID(), deletedHere = UUID(), fresh = UUID()
        let a = try item(clean, "A"), b = try item(edited, "B2")
        var ledger = SyncLedger()
        ledger.entries[clean] = .init(kind: .task, fingerprint: a.fingerprint, modifiedAt: t0, deleted: false)
        ledger.entries[edited] = .init(kind: .task, fingerprint: "before", modifiedAt: t0, deleted: false)
        ledger.entries[deletedHere] = .init(kind: .task, fingerprint: "x", modifiedAt: t0, deleted: false)
        let later = t0.addingTimeInterval(30)
        let remote = [clean, edited, deletedHere, fresh].map {
            IncomingChange(id: $0, kind: .task, payload: Data("r".utf8), modifiedAt: later)
        }
        let result = SyncPlanner.resolve(remote, local: [clean: a, edited: b], ledger: ledger)
        XCTAssertEqual(result, [.apply(remote[0]), .keepLocal(remote[1]), .keepLocal(remote[2]), .apply(remote[3])])

        // A kept edit is uploaded next, stamped after the server's.
        SyncPlanner.recordSeen(remote[1], in: &ledger)
        let out = SyncPlanner.outgoing(local: [a, b], ledger: ledger, now: t0)
        XCTAssertEqual(out.first { $0.id == edited }?.payload, b.payload)
        XCTAssertGreaterThan(out.first { $0.id == edited }!.modifiedAt, later)
    }

    func testDayPlansMergeFieldByField() throws {
        let base = try plan("Ship it", boots: 1)
        let local = try plan("Ship it", dump: "call mum", boots: 2)   // brain dump + one boot here
        let remote = try plan("Ship the beta", boots: 3)               // outcome + two boots there
        let merged = try PayloadCoding.decode(PlanPayload.self,
                                              from: PlanPayload.merge(base: base, local: local, remote: remote)!)
        XCTAssertEqual(merged.outcome, "Ship the beta")
        XCTAssertEqual(merged.brainDump, "call mum")
        XCTAssertEqual(merged.bootCount, 4)

        let id = RecordID.plan(day: t0)
        var ledger = SyncLedger()
        let change = IncomingChange(id: id, kind: .plan, payload: base, modifiedAt: t0)
        SyncPlanner.recordApplied(change, localPayload: nil, in: &ledger)
        XCTAssertEqual(ledger.entries[id]?.base, base)
        let incoming = IncomingChange(id: id, kind: .plan, payload: remote, modifiedAt: t0.addingTimeInterval(9))
        let result = SyncPlanner.resolve([incoming], local: [id: LocalItem(id: id, kind: .plan, payload: local)],
                                         ledger: ledger)
        guard case .merge(_, let data) = result.first else { return XCTFail("expected a merge") }
        XCTAssertEqual(try PayloadCoding.decode(PlanPayload.self, from: data), merged)
    }

    func testNewlyLinkedDeviceKeepsItsOwnPlanText() throws {
        let merged = try PayloadCoding.decode(PlanPayload.self, from: PlanPayload.merge(
            base: nil, local: try plan("", dump: "ideas", boots: 1), remote: try plan("Ship it", boots: 2))!)
        XCTAssertEqual(merged.outcome, "Ship it")
        XCTAssertEqual(merged.brainDump, "ideas")
        XCTAssertEqual(merged.bootCount, 2)
    }

    func testStampsAreWholeMilliseconds() throws {
        let out = SyncPlanner.outgoing(local: [try item(UUID(), "A")], ledger: SyncLedger(),
                                       now: Date(timeIntervalSince1970: 1_800_000_000.123_4))
        XCTAssertEqual(out[0].modifiedAt.timeIntervalSince1970, 1_800_000_000.124, accuracy: 0.000_001)
    }

    func testTaskPayloadsFromOlderBuildsStillDecode() throws {
        let old = #"{"breadcrumb":"","createdAt":1800000000,"focusSeconds":0,"inPlay":true,"isDone":false,"order":1,"title":"A"}"#
        let task = try PayloadCoding.decode(TaskPayload.self, from: Data(old.utf8))
        XCTAssertNil(task.waitingSince)
        // Not waiting encodes exactly as before, so existing records don't look changed.
        XCTAssertEqual(try PayloadCoding.encode(task), Data(old.utf8))
    }

    func testPlanIDsAreStablePerDay() {
        let day = Date(timeIntervalSince1970: 1_792_224_000)
        XCTAssertEqual(RecordID.plan(day: day), RecordID.plan(day: day))
        XCTAssertNotEqual(RecordID.plan(day: day), RecordID.plan(day: day.addingTimeInterval(86_400)))
    }

    func testPayloadEncodingIsDeterministic() throws {
        let note = NotePayload(body: "T\n- [ ] a", createdAt: t0, updatedAt: t0.addingTimeInterval(0.123), isPinned: true)
        let once = try PayloadCoding.encode(note)
        let twice = try PayloadCoding.encode(try PayloadCoding.decode(NotePayload.self, from: once))
        XCTAssertEqual(once, twice)
    }
}

final class SyncWireTests: XCTestCase {
    func testPostgrestDates() {
        let date = SyncDates.parse("2026-10-17T07:41:20.907161+00:00")!
        XCTAssertEqual(date.timeIntervalSince1970, 1_792_222_880.907161, accuracy: 0.000_01)
        XCTAssertEqual(SyncDates.parse("2026-10-17T07:41:20Z")!.timeIntervalSince1970, 1_792_222_880, accuracy: 0.001)
        XCTAssertEqual(SyncDates.parse("2026-10-17T09:41:20+0200")!.timeIntervalSince1970, 1_792_222_880, accuracy: 0.001)
        XCTAssertNil(SyncDates.parse("yesterday"))
        XCTAssertEqual(SyncDates.format(Date(timeIntervalSince1970: 1_792_222_880.25)), "2026-10-17T07:41:20.250Z")
    }

    func testRemoteRecordRoundTrip() throws {
        let json = #"[{"id":"11111111-1111-1111-1111-111111111111","kind":"task","data":{"c":"abc","v":1},"deleted":false,"modified_at":"2026-10-17T08:00:00+00:00","updated_at":"2026-10-17T17:15:51.805208+00:00"}]"#
        let records = try SyncDates.decoder().decode([RemoteRecord].self, from: Data(json.utf8))
        XCTAssertEqual(records.first?.blob, "abc")
        XCTAssertEqual(records.first?.kind, .task)
        XCTAssertNotNil(records.first?.updatedAt)

        let out = try SyncDates.encoder().encode(records)
        let object = try JSONSerialization.jsonObject(with: out) as! [[String: Any]]
        XCTAssertNil(object[0]["updated_at"], "the server stamps updated_at")
        XCTAssertEqual((object[0]["data"] as? [String: Any])?["c"] as? String, "abc")
    }

    func testSpaceKeysAreLongAndURLSafe() {
        let key = SpaceKey.generate()
        XCTAssertEqual(key.count, 43)
        XCTAssertNil(key.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
        XCTAssertNotEqual(key, SpaceKey.generate())
    }

    func testConfigIgnoresUnexpandedBuildSettings() {
        XCTAssertNil(TFCloudConfig.fromBundle(Bundle(for: SyncWireTests.self)))
    }
}

/// Talks to the real backend. Runs only when TF_LIVE_SUPABASE_HOST and TF_LIVE_SUPABASE_KEY are set.
final class SyncLiveTests: XCTestCase {
    func cloud() throws -> TFCloud {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["TF_LIVE_SUPABASE_HOST"], let key = env["TF_LIVE_SUPABASE_KEY"] else {
            throw XCTSkip("set TF_LIVE_SUPABASE_HOST / TF_LIVE_SUPABASE_KEY to run")
        }
        return TFCloud(config: TFCloudConfig(url: URL(string: "https://\(host)")!, anonKey: key))
    }

    func testPushPullPairAgainstSupabase() async throws {
        let cloud = try cloud()
        let space = "tftest-" + SpaceKey.generate()
        let cipher = PlainCipher()
        let id = UUID()
        let start = Date().addingTimeInterval(-60)
        let payload = try PayloadCoding.encode(NotePayload(body: "live test", createdAt: Date(), updatedAt: Date(), isPinned: false))
        try await cloud.push(access: space, records: [
            RemoteRecord(id: id, kind: .note, blob: try cipher.seal(payload), deleted: false, modifiedAt: Date()),
        ])
        let pulled = try await cloud.pull(access: space, since: start)
        XCTAssertEqual(pulled.map(\.id), [id])
        XCTAssertEqual(try cipher.open(pulled[0].blob), payload)

        let strangers = try await cloud.pull(access: "tftest-" + SpaceKey.generate(), since: start)
        XCTAssertTrue(strangers.isEmpty, "another space must not see this record")

        // An older edit must not overwrite.
        try await cloud.push(access: space, records: [
            RemoteRecord(id: id, kind: .note, blob: "stale", deleted: false, modifiedAt: Date().addingTimeInterval(-3600)),
        ])
        let afterStale = try await cloud.pull(access: space, since: start)
        XCTAssertEqual(afterStale.first?.blob, try cipher.seal(payload))

        // Tombstone, then pairing.
        try await cloud.push(access: space, records: [
            RemoteRecord(id: id, kind: .note, blob: "", deleted: true, modifiedAt: Date().addingTimeInterval(1)),
        ])
        let afterDelete = try await cloud.pull(access: space, since: start)
        XCTAssertEqual(afterDelete.first?.deleted, true)

        // Linking: the host commits to its key, the joiner sends its own, then the host reveals.
        let hostKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        let guestKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        let commitment = sha256Hex(hostKey)
        let code = try await cloud.pairHost(commitment: commitment)
        XCTAssertEqual(code.code.count, 6)
        let waitingAlone = try await cloud.pairWait(code: code.code, commitment: commitment)
        XCTAssertNil(waitingAlone)
        let claim = sha256Hex(SpaceKey.generate())
        let committed = try await cloud.pairJoin(code: code.code, claim: claim)
        XCTAssertEqual(committed, commitment)
        let waitingForOffer = try await cloud.pairWait(code: code.code, commitment: commitment)
        XCTAssertNil(waitingForOffer, "the joiner's key comes only after it holds the commitment")
        try await cloud.pairOffer(code: code.code, claim: claim, publicKey: guestKey)
        let beforeReveal = try await cloud.pairFetch(code: code.code, guestKey: guestKey)
        XCTAssertNil(beforeReveal.hostKey, "the host key stays hidden until the joiner's is in")
        let waited = try await cloud.pairWait(code: code.code, commitment: commitment)
        XCTAssertEqual(waited, guestKey)
        do {
            let other = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
            try await cloud.pairReveal(code: code.code, commitment: commitment, publicKey: other)
            XCTFail("a key that doesn't match the commitment is refused")
        } catch SyncError.http(let status, _) {
            XCTAssertEqual(status, 400)
        }
        try await cloud.pairReveal(code: code.code, commitment: commitment, publicKey: hostKey)
        let revealed = try await cloud.pairFetch(code: code.code, guestKey: guestKey)
        XCTAssertEqual(revealed.hostKey, hostKey)
        XCTAssertNil(revealed.box, "nothing to fetch until the host seals")
        let box = String(repeating: "A", count: 64)
        try await cloud.pairSeal(code: code.code, commitment: commitment, box: box)
        let fetched = try await cloud.pairFetch(code: code.code, guestKey: guestKey)
        XCTAssertEqual(fetched.box, box)
        do {
            _ = try await cloud.pairJoin(code: code.code, claim: sha256Hex(SpaceKey.generate()))
            XCTFail("a code links one device")
        } catch SyncError.http(let status, _) {
            XCTAssertEqual(status, 404)
        }

        // Moving from the legacy space keeps the records; deleting removes them.
        let access = "tftest-" + SpaceKey.generate()
        let moved = try await cloud.rekey(legacyKey: space, access: access)
        XCTAssertEqual(moved, 1)
        let afterMove = try await cloud.pull(access: access, since: start)
        XCTAssertEqual(afterMove.map(\.id), [id])
        let legacyAfterMove = try await cloud.pull(access: space, since: start)
        XCTAssertTrue(legacyAfterMove.isEmpty)

        try await cloud.registerDevice(access: access, token: "test-token", platform: "ios", environment: "development")
        try await cloud.notify(access: access, exceptToken: "test-token")
        try await cloud.deleteSpace(access: access)
        let afterDelete2 = try await cloud.pull(access: access, since: start)
        XCTAssertTrue(afterDelete2.isEmpty)
    }
}

final class SHA256HelperTests: XCTestCase {
    func testKnownVectors() {
        XCTAssertEqual(sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(sha256Hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
}

/// sha256 hex without CryptoKit (unavailable on Linux), for the live linking test.
private func sha256Hex(_ text: String) -> String {
    var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
    let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]
    var bytes = Array(text.utf8)
    let bitLength = UInt64(bytes.count) * 8
    bytes.append(0x80)
    while bytes.count % 64 != 56 { bytes.append(0) }
    for i in (0..<8).reversed() { bytes.append(UInt8((bitLength >> (UInt64(i) * 8)) & 0xff)) }
    func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
    for chunk in stride(from: 0, to: bytes.count, by: 64) {
        var w = [UInt32](repeating: 0, count: 64)
        for i in 0..<16 {
            let j = chunk + i * 4
            w[i] = UInt32(bytes[j]) << 24 | UInt32(bytes[j + 1]) << 16 | UInt32(bytes[j + 2]) << 8 | UInt32(bytes[j + 3])
        }
        for i in 16..<64 {
            let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
            let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
            w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
        }
        var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
        for i in 0..<64 {
            let t1 = hh &+ (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) &+ ((e & f) ^ (~e & g)) &+ k[i] &+ w[i]
            let t2 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) &+ ((a & b) ^ (a & c) ^ (b & c))
            (hh, g, f, e, d, c, b, a) = (g, f, e, d &+ t1, c, b, a, t1 &+ t2)
        }
        h = zip(h, [a, b, c, d, e, f, g, hh]).map { $0 &+ $1 }
    }
    return h.map { String(format: "%08x", $0) }.joined()
}
