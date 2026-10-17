import Foundation
import Observation
import SwiftData
import TrueFocusKit

/// Keeps this device's plan, notes and timeline in step with the user's other devices through
/// the TrueFocus server (Supabase). No account: devices that share a space key share data,
/// and a new device joins with a one-time code from one that already has it.
///
/// A sync pulls what changed on the server, applies it (a record edited here since the last
/// sync keeps its edit; day plans merge field by field), then uploads what changed here.
@MainActor
@Observable
final class SyncService {
    static let shared = SyncService()

    enum Status: Equatable {
        /// This build has no server configured.
        case off
        case idle
        case syncing
        case failed(String)
    }

    private(set) var status: Status
    private(set) var lastSyncAt: Date?

    var isAvailable: Bool { cloud != nil }

    @ObservationIgnored private let cloud: TFCloud?
    @ObservationIgnored private var spaceKey: String?
    @ObservationIgnored private var ledger = SyncLedger()
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var again = false
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var pendingNotify: Task<Void, Never>?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var applying = false
    @ObservationIgnored private var deviceToken: String?

    private init() {
        cloud = TFCloudConfig.fromBundle().map { TFCloud(config: $0) }
        status = cloud == nil ? .off : .idle
    }

    /// Call once at launch, after `FocusController.shared` exists.
    func start() {
        guard cloud != nil, timer == nil else { return }
        // Delivered on the saving thread, so a save made by `cycle` is still flagged `applying`.
        observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave,
                                                          object: FocusController.shared.context,
                                                          queue: nil) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.localDidChange() }
            } else {
                Task { @MainActor in self?.localDidChange() }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.syncNow() }
        }
        Task { await syncNow() }
    }

    /// Something was saved here. Uploads shortly, so a burst of edits goes up as one.
    func localDidChange() {
        guard cloud != nil, !applying else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// Runs a sync now, or waits for the one in flight and runs once more after it.
    func syncNow() async {
        guard cloud != nil else { return }
        if let running {
            again = true
            await running.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.again = false
                await self.cycle()
            } while self.again
            self.running = nil
        }
        running = task
        await task.value
    }

    // MARK: Linking devices

    /// A six-digit code another device can enter to join this one. Valid once, for ten minutes.
    func makeLinkCode() async throws -> PairingCode {
        guard let cloud, let key = loadKey() else { throw SyncError.notConfigured }
        await syncNow()
        return try await cloud.createPairingCode(spaceKey: key)
    }

    /// Joins the space behind `code`. What's on this device is merged into it.
    func link(code: String) async throws {
        guard let cloud else { throw SyncError.notConfigured }
        let key = try await cloud.redeemPairingCode(code)
        guard key != loadKey() else { return }
        guard SyncKeychain.write(key) else { throw SyncError.notConfigured }
        await running?.value
        spaceKey = key
        ledger = SyncLedger()
        SyncLedgerFile.save(ledger, for: key)
        registerDevice()
        await syncNow()
    }

    // MARK: Silent pushes (iPhone)

    func setDeviceToken(_ token: Data) {
        deviceToken = token.map { String(format: "%02x", $0) }.joined()
        registerDevice()
    }

    private func registerDevice() {
        #if os(iOS)
        guard let cloud, let key = loadKey(), let token = deviceToken else { return }
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif
        Task { try? await cloud.registerDevice(spaceKey: key, token: token, platform: "ios", environment: environment) }
        #endif
    }

    /// Wakes the other iPhones a moment after the last upload of a burst.
    private func notifyOthers(_ key: String) {
        guard let cloud else { return }
        pendingNotify?.cancel()
        let token = deviceToken
        pendingNotify = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            try? await cloud.notify(spaceKey: key, exceptToken: token)
        }
    }

    // MARK: The sync

    /// The space key, created on first launch. Nil while the Keychain is locked.
    private func loadKey() -> String? {
        if let spaceKey { return spaceKey }
        switch SyncKeychain.read() {
        case .found(let key):
            spaceKey = key
        case .missing:
            let key = SpaceKey.generate()
            guard SyncKeychain.write(key) else { return nil }
            spaceKey = key
        case .unavailable:
            return nil
        }
        if let spaceKey { ledger = SyncLedgerFile.load(for: spaceKey) }
        registerDevice()
        return spaceKey
    }

    private func cycle() async {
        guard let cloud, let key = loadKey() else { return }
        let controller = FocusController.shared
        let context = controller.context
        let cipher = SyncCipher(spaceKey: key)
        status = .syncing
        defer { SyncLedgerFile.save(ledger, for: key) }
        do {
            let remote = try await cloud.pull(spaceKey: key, since: SyncPlanner.pullStart(for: ledger))
            guard key == spaceKey else { return }
            let incoming = remote.compactMap { record -> IncomingChange? in
                if record.deleted {
                    return IncomingChange(id: record.id, kind: record.kind, payload: nil, modifiedAt: record.modifiedAt)
                }
                // Unreadable (corrupt, or sealed with another key): leave it.
                guard let payload = try? cipher.open(record.blob) else { return nil }
                return IncomingChange(id: record.id, kind: record.kind, payload: payload, modifiedAt: record.modifiedAt)
            }

            let local = Dictionary(SyncMapping.scan(context).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var changed = false
            for decision in SyncPlanner.resolve(SyncPlanner.incoming(incoming, ledger: ledger), local: local, ledger: ledger) {
                switch decision {
                case .apply(let change):
                    guard SyncMapping.apply(change.kind, id: change.id, payload: change.payload, in: context) else { continue }
                    let applied = SyncMapping.payload(change.kind, id: change.id, in: context)
                    SyncPlanner.recordApplied(change, localPayload: applied, in: &ledger)
                    changed = true
                case .merge(let change, let merged):
                    guard SyncMapping.apply(.plan, id: change.id, payload: merged, in: context) else { continue }
                    SyncPlanner.recordSeen(change, in: &ledger)
                    changed = true
                case .keepLocal(let change):
                    SyncPlanner.recordSeen(change, in: &ledger)
                }
            }
            if changed {
                applying = true
                try context.save()
                applying = false
            }
            if let newest = remote.compactMap(\.updatedAt).max() {
                ledger.cursor = max(ledger.cursor ?? newest, newest)
            }

            let outgoing = SyncPlanner.outgoing(local: SyncMapping.scan(context), ledger: ledger, now: Date())
            if !outgoing.isEmpty {
                let records = try outgoing.map { change in
                    RemoteRecord(id: change.id, kind: change.kind, blob: try change.payload.map(cipher.seal) ?? "",
                                 deleted: change.deleted, modifiedAt: change.modifiedAt)
                }
                try await cloud.push(spaceKey: key, records: records)
                SyncPlanner.recordUploaded(outgoing, in: &ledger)
                notifyOthers(key)
            }

            lastSyncAt = Date()
            status = .idle
            if changed { controller.refresh() }
        } catch {
            applying = false
            status = .failed(Self.describe(error))
        }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case SyncError.http(404, _): return "That code didn't work. Codes last 10 minutes and work once."
        case SyncError.http(429, _): return "Too many tries. Wait a few minutes."
        case SyncError.http(let status, _): return "The server answered \(status)."
        case SyncError.notConfigured: return "Sync isn't available in this build."
        case let error as URLError where error.code == .notConnectedToInternet: return "Offline. Will sync when you're back."
        default: return "Couldn't reach the server."
        }
    }
}
