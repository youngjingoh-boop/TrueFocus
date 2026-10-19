import XCTest
@testable import TrueFocusKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Two (or three) simulated devices running the same cycle as the app's `SyncService` against
/// the real backend: pull, resolve, apply, then upload. Each test uses its own random
/// `tftest-` space and deletes it afterwards.
/// Runs only when TF_LIVE_SUPABASE_HOST and TF_LIVE_SUPABASE_KEY are set.
final class SyncJourneyLiveTests: XCTestCase {
    /// A device: its records, its ledger and the space it's in. `cycle` mirrors SyncService.cycle.
    final class Device {
        let cloud: TFCloud
        var access: String
        var items: [UUID: LocalItem] = [:]
        var ledger = SyncLedger()
        /// This device's clock, relative to the real one.
        var skew: TimeInterval = 0
        let cipher = PlainCipher()

        init(cloud: TFCloud, access: String) {
            self.cloud = cloud
            self.access = access
        }

        func cycle() async throws {
            let remote = try await cloud.pull(access: access, since: SyncPlanner.pullStart(for: ledger))
            let incoming = remote.compactMap { record -> IncomingChange? in
                if record.deleted {
                    return IncomingChange(id: record.id, kind: record.kind, payload: nil, modifiedAt: record.modifiedAt)
                }
                guard let payload = try? cipher.open(record.blob) else { return nil }
                return IncomingChange(id: record.id, kind: record.kind, payload: payload, modifiedAt: record.modifiedAt)
            }
            for decision in SyncPlanner.resolve(SyncPlanner.incoming(incoming, ledger: ledger), local: items, ledger: ledger) {
                switch decision {
                case .apply(let change):
                    items[change.id] = change.payload.map { LocalItem(id: change.id, kind: change.kind, payload: $0) }
                    SyncPlanner.recordApplied(change, localPayload: items[change.id]?.payload, in: &ledger)
                case .merge(let change, let merged):
                    items[change.id] = LocalItem(id: change.id, kind: .plan, payload: merged)
                    SyncPlanner.recordSeen(change, in: &ledger)
                case .keepLocal(let change):
                    SyncPlanner.recordSeen(change, in: &ledger)
                }
            }
            if let newest = remote.compactMap(\.updatedAt).max() {
                ledger.cursor = max(ledger.cursor ?? newest, newest)
            }
            let outgoing = SyncPlanner.outgoing(local: Array(items.values), ledger: ledger,
                                                now: Date().addingTimeInterval(skew))
            guard !outgoing.isEmpty else { return }
            let records = try outgoing.map { change in
                RemoteRecord(id: change.id, kind: change.kind, blob: try change.payload.map(cipher.seal) ?? "",
                             deleted: change.deleted, modifiedAt: change.modifiedAt)
            }
            try await cloud.push(access: access, records: records)
            SyncPlanner.recordUploaded(outgoing, in: &ledger)
        }

        func setTask(_ id: UUID, _ title: String, done: Bool = false) throws {
            let payload = TaskPayload(title: title, isDone: done, doneAt: nil, createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                                      order: 1, focusSeconds: 0, breadcrumb: "", inPlay: false, inPlayAt: nil)
            items[id] = LocalItem(id: id, kind: .task, payload: try PayloadCoding.encode(payload))
        }

        func title(_ id: UUID) -> String? {
            items[id].flatMap { try? PayloadCoding.decode(TaskPayload.self, from: $0.payload).title }
        }

        func plan(_ id: UUID) -> PlanPayload? {
            items[id].flatMap { try? PayloadCoding.decode(PlanPayload.self, from: $0.payload) }
        }

        func setPlan(_ id: UUID, day: Date, outcome: String = "", dump: String = "", boots: Int = 0) throws {
            let payload = PlanPayload(day: day, outcome: outcome, brainDump: dump, bootCount: boots, endedAt: nil, reflection: "")
            items[id] = LocalItem(id: id, kind: .plan, payload: try PayloadCoding.encode(payload))
        }
    }

    private var spaces: [String] = []
    private var liveCloud: TFCloud?

    func cloud() throws -> TFCloud {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["TF_LIVE_SUPABASE_HOST"], let key = env["TF_LIVE_SUPABASE_KEY"] else {
            throw XCTSkip("set TF_LIVE_SUPABASE_HOST / TF_LIVE_SUPABASE_KEY to run")
        }
        let cloud = TFCloud(config: TFCloudConfig(url: URL(string: "https://\(host)")!, anonKey: key))
        liveCloud = cloud
        return cloud
    }

    func space() -> String {
        let space = "tftest-" + SpaceKey.generate()
        spaces.append(space)
        return space
    }

    override func tearDown() async throws {
        if let liveCloud {
            for space in spaces { try? await liveCloud.deleteSpace(access: space) }
        }
        spaces = []
    }

    func testTwoDevicesMergeBothWaysAndAgreeOnConflicts() async throws {
        let cloud = try cloud()
        let access = space()
        let mac = Device(cloud: cloud, access: access)
        let phone = Device(cloud: cloud, access: access)
        let onMac = UUID(), onPhone = UUID(), shared = UUID()
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let planID = RecordID.plan(day: day)

        // Each device had its own plan before linking.
        try mac.setTask(onMac, "Mac task")
        try mac.setTask(shared, "Shared")
        try mac.setPlan(planID, day: day, outcome: "Ship the beta")
        try phone.setTask(onPhone, "Phone task")
        try phone.setPlan(planID, day: day, dump: "call mum", boots: 1)

        try await mac.cycle()
        try await phone.cycle()
        try await mac.cycle()
        XCTAssertEqual(Set(mac.items.keys), [onMac, onPhone, shared, planID])
        XCTAssertEqual(Set(phone.items.keys), [onMac, onPhone, shared, planID])
        XCTAssertEqual(mac.plan(planID)?.outcome, "Ship the beta")
        XCTAssertEqual(mac.plan(planID)?.brainDump, "call mum")
        XCTAssertEqual(phone.plan(planID), mac.plan(planID))

        // Both edit the same task before either syncs: the one that syncs last keeps its edit,
        // and both devices end up with it.
        try mac.setTask(shared, "Edited on the Mac")
        try phone.setTask(shared, "Edited on the phone")
        try await mac.cycle()
        try await phone.cycle()
        try await mac.cycle()
        XCTAssertEqual(phone.title(shared), "Edited on the phone")
        XCTAssertEqual(mac.title(shared), "Edited on the phone")

        // A clock running ten minutes fast doesn't let a stale device win afterwards.
        mac.skew = 600
        try mac.setTask(shared, "Mac, fast clock")
        try await mac.cycle()
        try await phone.cycle()
        try phone.setTask(shared, "Phone, later")
        try await phone.cycle()
        try await mac.cycle()
        XCTAssertEqual(mac.title(shared), "Phone, later")
        XCTAssertEqual(phone.title(shared), "Phone, later")

        // Deleting on one device deletes on the other.
        phone.items[onMac] = nil
        try await phone.cycle()
        try await mac.cycle()
        XCTAssertNil(mac.items[onMac])

        // A reinstall (same key, no ledger, nothing local) gets everything back, tombstones excluded.
        let reinstalled = Device(cloud: cloud, access: access)
        try await reinstalled.cycle()
        XCTAssertEqual(Set(reinstalled.items.keys), Set(mac.items.keys))
        XCTAssertEqual(reinstalled.title(shared), "Phone, later")
        XCTAssertEqual(reinstalled.plan(planID), mac.plan(planID))

        // Nothing left to upload anywhere: the devices agree with the server.
        for device in [mac, phone, reinstalled] {
            XCTAssertTrue(SyncPlanner.outgoing(local: Array(device.items.values), ledger: device.ledger, now: Date()).isEmpty)
        }
    }

    func testLegacySpaceMovesOnceAndDevicesUpgradeInAnyOrder() async throws {
        let cloud = try cloud()
        let legacy = space()
        let access = space()
        let first = Device(cloud: cloud, access: legacy)
        let second = Device(cloud: cloud, access: legacy)
        let a = UUID(), b = UUID()
        try first.setTask(a, "A")
        try await first.cycle()
        try await second.cycle()
        XCTAssertEqual(second.title(a), "A")

        // The first device upgrades: it moves the space, then syncs under the access token.
        let moved = try await cloud.rekey(legacyKey: legacy, access: access)
        XCTAssertEqual(moved, 1)
        first.access = access
        try await first.cycle()
        XCTAssertEqual(first.title(a), "A")
        XCTAssertTrue(SyncPlanner.outgoing(local: Array(first.items.values), ledger: first.ledger, now: Date()).isEmpty,
                      "moved records come back as echoes, not as changes")

        // The second device is still on the old build and keeps writing to the legacy space.
        try second.setTask(b, "B")
        try await second.cycle()
        // Then it upgrades too: its move merges into the space the first one already uses.
        _ = try await cloud.rekey(legacyKey: legacy, access: access)
        second.access = access
        try await second.cycle()
        try await first.cycle()
        XCTAssertEqual(first.title(b), "B")
        XCTAssertEqual(Set(first.items.keys), Set(second.items.keys))
        let leftBehind = try await cloud.pull(access: legacy, since: nil)
        XCTAssertTrue(leftBehind.isEmpty)
        // Moving an empty legacy space again (a retry) changes nothing.
        let again = try await cloud.rekey(legacyKey: legacy, access: access)
        XCTAssertEqual(again, 0)
        try await first.cycle()
        XCTAssertEqual(first.title(a), "A")
    }

    func testDeletingTheServerCopyLeavesDevicesTheirData() async throws {
        let cloud = try cloud()
        let access = space()
        let mac = Device(cloud: cloud, access: access)
        let phone = Device(cloud: cloud, access: access)
        let a = UUID(), b = UUID()
        try mac.setTask(a, "A")
        try await mac.cycle()
        try await phone.cycle()

        try await cloud.deleteSpace(access: access)
        let afterDelete = try await cloud.pull(access: access, since: nil)
        XCTAssertTrue(afterDelete.isEmpty)
        // The other device keeps its copy and uploads only what changes from now on.
        try await phone.cycle()
        XCTAssertEqual(phone.title(a), "A")
        try phone.setTask(b, "B")
        try await phone.cycle()
        let server = try await cloud.pull(access: access, since: nil)
        XCTAssertEqual(server.map(\.id), [b])
    }
}
