import Foundation
import Observation
import SwiftData
import TrueFocusKit

/// Keeps this device's plan, notes and timeline in step with the user's other devices through
/// the TrueFocus server (Supabase). No account: devices that share a space key share data,
/// and a new device joins with a one-time code from one that already has it.
///
/// End to end: payloads are sealed with a key derived from the space key, requests carry a
/// separate access token derived one way from it, and linking passes the key sealed between
/// the two devices. The server never holds the space key.
///
/// Off until you turn it on or link a device; a device that synced before this asked stays on.
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
    /// The key went missing on a device that had synced: it waits to be linked again instead of
    /// quietly starting a separate space that its other devices never see.
    private(set) var needsRelink = false
    /// Short id of this device's space; linked devices show the same one.
    private(set) var spaceTag: String?
    /// You turned sync on here (or linked this device). Nothing leaves the device while false.
    private(set) var isEnabled = false

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
        resolveEnabled()
    }

    private static let enabledKey = "tf.sync.enabled"

    /// Remembered per device. Before sync asked first, it started on its own: a device that has
    /// synced keeps syncing, a new one waits to be turned on.
    private func resolveEnabled() {
        let defaults = UserDefaults.standard
        if let stored = defaults.object(forKey: Self.enabledKey) as? Bool {
            isEnabled = stored
            return
        }
        // Only a ledger counts: iOS keeps Keychain items after the app is deleted, so a key alone
        // may be left over from a previous install, and a reinstall must ask again.
        setEnabled(SyncLedgerFile.hasHistory)
    }

    private func setEnabled(_ on: Bool) {
        isEnabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
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
        guard cloud != nil, isEnabled, !applying else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// Runs a sync now, or waits for the one in flight and runs once more after it.
    func syncNow() async {
        guard cloud != nil, isEnabled else { return }
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

    // MARK: On and off

    /// Starts syncing from this device: a new space, or the one it had before it was turned off.
    func turnOn() async {
        guard cloud != nil else { return }
        if SyncKeychain.read() == .missing, !SyncLedgerFile.hasHistory {
            let key = SpaceKey.generate()
            guard SyncKeychain.write(key) else { return }
            Self.markMigrated(key)
        }
        setEnabled(true)
        status = .idle
        registerDevice()
        await syncNow()
    }

    /// Stops syncing on this device. Keeps the key, so turning it back on picks up where it was.
    func turnOff() async {
        setEnabled(false)
        pending?.cancel()
        await running?.value
        status = .idle
    }

    /// Deletes everything the server holds for this space, then forgets the key here. Other
    /// linked devices keep their own copies (and upload future edits unless they're turned off).
    func deleteServerCopy() async throws {
        guard let cloud else { throw SyncError.notConfigured }
        // Off first, so no sync starts while the delete is in flight: it would upload again and
        // write the ledger back, and the next "Turn on" would then say "Not linked".
        let wasEnabled = isEnabled
        setEnabled(false)
        pending?.cancel()
        await running?.value
        guard let key = loadKey() else {
            setEnabled(wasEnabled)
            throw SyncError.notConfigured
        }
        do {
            try await cloud.deleteSpace(access: SyncAccess.token(for: key))
        } catch {
            setEnabled(wasEnabled)
            throw error
        }
        SyncKeychain.delete()
        SyncLedgerFile.delete()
        spaceKey = nil
        spaceTag = nil
        ledger = SyncLedger()
        lastSyncAt = nil
        needsRelink = false
        status = .idle
    }

    // MARK: Linking devices

    /// This device's side of a link it offered: the code on screen and its half of the exchange.
    struct HostedLink {
        let code: PairingCode
        fileprivate let secret: PairingSecret
    }

    /// Someone entered the code. Send the key once both screens show `match`.
    struct JoinedLink {
        let match: String
        fileprivate let session: PairingSecret.Session
    }

    /// The joining side, waiting for the other device.
    struct PendingJoin {
        let code: String
        fileprivate let commitment: String
        fileprivate let secret: PairingSecret
    }

    enum JoinProgress {
        /// The other device hasn't revealed its key yet.
        case waiting
        /// Compare this with the other screen; the key arrives once it's confirmed there.
        case compare(String)
        /// Linked.
        case joined
    }

    /// Offers a six-digit code another device can enter. Valid for ten minutes, links one device.
    func offerLink() async throws -> HostedLink {
        guard let cloud else { throw SyncError.notConfigured }
        if !isEnabled { await turnOn() }
        guard loadKey() != nil else { throw SyncError.notConfigured }
        await syncNow()
        let secret = PairingSecret()
        return HostedLink(code: try await cloud.pairHost(commitment: secret.commitment), secret: secret)
    }

    /// One look for a device that entered the code. Nil until one has; then reveals this
    /// device's key and returns the match number to compare.
    func joiner(for link: HostedLink) async throws -> JoinedLink? {
        guard let cloud else { throw SyncError.notConfigured }
        let host = link.secret.publicKey
        let code = link.code.code
        guard let guest = try await cloud.pairWait(code: code, commitment: link.secret.commitment) else { return nil }
        let session = try link.secret.session(peer: guest, hostKey: host, guestKey: guest, code: code)
        try await cloud.pairReveal(code: code, commitment: link.secret.commitment, publicKey: host)
        return JoinedLink(match: session.match, session: session)
    }

    /// The numbers match: hand the key over, sealed so only the other device can open it.
    func approve(_ link: HostedLink, _ joined: JoinedLink) async throws {
        guard let cloud, let key = loadKey() else { throw SyncError.notConfigured }
        try await cloud.pairSeal(code: link.code.code, commitment: link.secret.commitment, box: joined.session.seal(key))
    }

    /// Enters a code from another device. Takes the other device's commitment first, and only
    /// then sends this device's key, so neither side's key can be picked after seeing the other.
    func join(code: String) async throws -> PendingJoin {
        guard let cloud else { throw SyncError.notConfigured }
        let secret = PairingSecret()
        let claim = PairingSecret().commitment  // 64 random hex digits; nothing secret
        let commitment = try await cloud.pairJoin(code: code, claim: claim)
        try await cloud.pairOffer(code: code, claim: claim, publicKey: secret.publicKey)
        return PendingJoin(code: code, commitment: commitment, secret: secret)
    }

    /// One look at how joining is going. The host's key must match what it committed to before
    /// this device saw it; anything else is someone in the middle.
    func checkJoin(_ pending: PendingJoin) async throws -> JoinProgress {
        guard let cloud else { throw SyncError.notConfigured }
        let guest = pending.secret.publicKey
        let fetched = try await cloud.pairFetch(code: pending.code, guestKey: guest)
        guard let host = fetched.hostKey else { return .waiting }
        guard PairingSecret.commitment(to: host) == pending.commitment else { throw SyncError.corruptPayload }
        let session = try pending.secret.session(peer: host, hostKey: host, guestKey: guest, code: pending.code)
        guard let box = fetched.box else { return .compare(session.match) }
        try await adopt(session.open(box))
        return .joined
    }

    private func adopt(_ key: String) async throws {
        Self.markMigrated(key)
        setEnabled(true)
        guard key != loadKey() else { await syncNow(); return }
        guard SyncKeychain.write(key) else { throw SyncError.notConfigured }
        await running?.value
        spaceKey = key
        spaceTag = String(SyncLedgerFile.tag(key).prefix(8))
        needsRelink = false
        status = .idle
        ledger = SyncLedger()
        SyncLedgerFile.save(ledger, for: key)
        registerDevice()
        await syncNow()
    }

    /// Lost the link and there's no other device to link with: start a new space from what's
    /// on this device.
    func startFreshSpace() async {
        guard cloud != nil else { return }
        await running?.value
        let key = SpaceKey.generate()
        guard SyncKeychain.write(key) else { return }
        Self.markMigrated(key)
        setEnabled(true)
        spaceKey = key
        spaceTag = String(SyncLedgerFile.tag(key).prefix(8))
        needsRelink = false
        status = .idle
        ledger = SyncLedger()
        SyncLedgerFile.save(ledger, for: key)
        registerDevice()
        await syncNow()
    }

    // MARK: Moving off the legacy space id

    /// Spaces made before access tokens live under the hash of the key itself. Each device moves
    /// its space once (the server merges, so the order devices upgrade in doesn't matter).
    private static func migratedKey(_ key: String) -> String { "tf.sync.access.\(SyncLedgerFile.tag(key))" }
    private static func isMigrated(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: migratedKey(key)) }
    private static func markMigrated(_ key: String) { UserDefaults.standard.set(true, forKey: migratedKey(key)) }

    // MARK: Silent pushes (iPhone)

    func setDeviceToken(_ token: Data) {
        deviceToken = token.map { String(format: "%02x", $0) }.joined()
        registerDevice()
    }

    private func registerDevice() {
        #if os(iOS)
        guard isEnabled, let cloud, let key = loadKey(), let token = deviceToken else { return }
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif
        let access = SyncAccess.token(for: key)
        Task { try? await cloud.registerDevice(access: access, token: token, platform: "ios", environment: environment) }
        #endif
    }

    /// Wakes the other iPhones a moment after the last upload of a burst.
    private func notifyOthers(_ access: String) {
        guard let cloud else { return }
        pendingNotify?.cancel()
        let token = deviceToken
        pendingNotify = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            try? await cloud.notify(access: access, exceptToken: token)
        }
    }

    // MARK: The sync

    /// The space key, made when sync is turned on. Nil while the Keychain is locked or before then.
    private func loadKey() -> String? {
        if let spaceKey { return spaceKey }
        switch SyncKeychain.read() {
        case .found(let key):
            spaceKey = key
        case .missing:
            if SyncLedgerFile.hasHistory, isEnabled {
                needsRelink = true
                status = .failed("Not linked. Enter a code from your other device.")
            }
            return nil
        case .unavailable:
            return nil
        }
        if let spaceKey {
            ledger = SyncLedgerFile.load(for: spaceKey)
            spaceTag = String(SyncLedgerFile.tag(spaceKey).prefix(8))
            needsRelink = false
        }
        registerDevice()
        return spaceKey
    }

    private func cycle() async {
        guard isEnabled, let cloud, let key = loadKey() else { return }
        let controller = FocusController.shared
        let context = controller.context
        let cipher = SyncCipher(spaceKey: key)
        let access = SyncAccess.token(for: key)
        let hadHistory = SyncLedgerFile.hasHistory
        status = .syncing
        defer { SyncLedgerFile.save(ledger, for: key) }
        do {
            if !Self.isMigrated(key) {
                // Only a device that synced before (it has a ledger) can have records under the
                // legacy id. A reinstall keeps its Keychain key but not this flag, and must not
                // send the key to the server again. Moved records come back below as echoes.
                if hadHistory {
                    // The last time this key travels.
                    try await cloud.rekey(legacyKey: key, access: access)
                }
                Self.markMigrated(key)
                registerDevice()
            }
            let remote = try await cloud.pull(access: access, since: SyncPlanner.pullStart(for: ledger))
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
                // Now, before the upload below suspends: until the controller re-reads the store,
                // its lists still hold records just deleted here, and views and timers touching
                // a deleted model crash.
                controller.refresh()
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
                try await cloud.push(access: access, records: records)
                SyncPlanner.recordUploaded(outgoing, in: &ledger)
                notifyOthers(access)
            }

            lastSyncAt = Date()
            status = .idle
        } catch {
            applying = false
            status = .failed(Self.describe(error))
        }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case SyncError.http(404, _): return "That code didn't work. Codes last 10 minutes and link one device."
        case SyncError.corruptPayload: return "Linking failed. Start again with a new code."
        case SyncError.http(429, _): return "Too many tries. Wait a few minutes."
        case SyncError.http(let status, _): return "The server answered \(status)."
        case SyncError.notConfigured: return "Sync isn't available in this build."
        case let error as URLError where error.code == .notConnectedToInternet: return "Offline. Will sync when you're back."
        default: return "Couldn't reach the server."
        }
    }
}
