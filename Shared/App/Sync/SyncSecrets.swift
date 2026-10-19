import CryptoKit
import Foundation
import Security
import TrueFocusKit

/// The space key lives in this device's Keychain (never iCloud Keychain). Anyone holding it can
/// read and write the space. It never goes to the server: requests carry an access token derived
/// from it, and linking hands it to the other device sealed (see `PairingSecret`).
enum SyncKeychain {
    enum Read: Equatable {
        case found(String)
        case missing
        /// Locked or otherwise unreadable right now. Never treat this as "no key".
        case unavailable
    }

    private static let service = "app.truefocus.sync"
    private static let account = "space-key"

    private static func query(dataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        return query
    }

    /// The data-protection keychain needs a signed build; fall back to the login keychain without one.
    private static func run(_ body: (Bool) -> OSStatus) -> OSStatus {
        let status = body(true)
        return status == errSecMissingEntitlement ? body(false) : status
    }

    private static func copy(dataProtection: Bool) -> (OSStatus, String?) {
        var result: CFTypeRef?
        var request = query(dataProtection: dataProtection)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        let key = (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
        return (status, key)
    }

    static func read() -> Read {
        // Look in both keychains before calling the key missing. A Mac build signed one way
        // writes to the login keychain and one signed another way reads the data-protection
        // keychain; missing it there must not fork this device into a new space.
        var (status, key) = copy(dataProtection: true)
        #if os(macOS)
        if status == errSecItemNotFound || status == errSecMissingEntitlement {
            let modern = status
            (status, key) = copy(dataProtection: false)
            // Found in the login keychain while the modern one works: copy it across.
            if status == errSecSuccess, modern == errSecItemNotFound, let key, key.count >= 32 {
                _ = addItem(key, dataProtection: true)
            }
        }
        #else
        if status == errSecMissingEntitlement { (status, key) = copy(dataProtection: false) }
        #endif
        switch status {
        case errSecSuccess:
            guard let key, key.count >= 32 else { return .unavailable }
            return .found(key)
        case errSecItemNotFound:
            return .missing
        default:
            return .unavailable
        }
    }

    private static func addItem(_ key: String, dataProtection: Bool) -> OSStatus {
        var add = query(dataProtection: dataProtection)
        add[kSecValueData as String] = Data(key.utf8)
        // Readable in the background once the phone has been unlocked after a restart,
        // so a silent push can sync with the screen locked.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil)
    }

    /// Forgets the key (both keychains on the Mac).
    static func delete() {
        _ = SecItemDelete(query(dataProtection: true) as CFDictionary)
        #if os(macOS)
        _ = SecItemDelete(query(dataProtection: false) as CFDictionary)
        #endif
    }

    @discardableResult
    static func write(_ key: String) -> Bool {
        let status = run { dataProtection in
            let match = query(dataProtection: dataProtection)
            let update = SecItemUpdate(match as CFDictionary, [kSecValueData as String: Data(key.utf8)] as CFDictionary)
            guard update == errSecItemNotFound else { return update }
            return addItem(key, dataProtection: dataProtection)
        }
        return status == errSecSuccess
    }
}

/// What the server sees instead of the space key: HKDF(key, "access.v1"), base64url. It proves
/// membership of the space but can't be turned back into the key, so the server (or anyone with
/// its database or logs) can't derive the payload key below.
enum SyncAccess {
    static func token(for spaceKey: String) -> String {
        let derived = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(spaceKey.utf8)),
                                             salt: Data("truefocus.sync".utf8),
                                             info: Data("access.v1".utf8),
                                             outputByteCount: 32)
        return derived.withUnsafeBytes { Data($0) }.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// AES-GCM with a key derived from the space key. The server stores only ciphertext and a hash
/// of the access token, so neither it nor anyone with database access can read a plan.
struct SyncCipher: PayloadCipher {
    private let key: SymmetricKey

    init(spaceKey: String) {
        key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(spaceKey.utf8)),
                                     salt: Data("truefocus.sync".utf8),
                                     info: Data("payload.v1".utf8),
                                     outputByteCount: 32)
    }

    func seal(_ plaintext: Data) throws -> String {
        guard let combined = try AES.GCM.seal(plaintext, using: key).combined else { throw SyncError.corruptPayload }
        return combined.base64EncodedString()
    }

    func open(_ sealed: String) throws -> Data {
        guard let data = Data(base64Encoded: sealed) else { throw SyncError.corruptPayload }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
    }
}

/// The ledger, kept next to the store. Tied to the space it describes: linking to another
/// space starts a fresh one.
enum SyncLedgerFile {
    private struct Stored: Codable {
        var space: String
        var ledger: SyncLedger
    }

    private static var url: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = base.appendingPathComponent("TrueFocus", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("sync-ledger.json")
    }

    /// This device has synced before (its ledger names a space), so a missing key means the
    /// link was lost, not that this is a first launch.
    static var hasHistory: Bool {
        guard let url, let data = try? Data(contentsOf: url) else { return false }
        return (try? JSONDecoder().decode(Stored.self, from: data)) != nil
    }

    /// The first 16 hex digits of the space key's hash, the same on every linked device. Shown in
    /// Settings so two devices can be compared. (Not the server's id, which hashes the access token.)
    static func tag(_ spaceKey: String) -> String {
        SHA256.hash(data: Data(spaceKey.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func load(for spaceKey: String) -> SyncLedger {
        guard let url, let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.space == tag(spaceKey) else { return SyncLedger() }
        return stored.ledger
    }

    static func delete() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func save(_ ledger: SyncLedger, for spaceKey: String) {
        guard let url, let data = try? JSONEncoder().encode(Stored(space: tag(spaceKey), ledger: ledger)) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// One side of linking two devices. They swap X25519 public keys through the server, then both
/// derive the same box key (to seal the space key) and a 4-digit match number from the shared
/// secret. A server that swapped the keys would leave the two screens showing different numbers,
/// so the host only sends the key after you confirm they match.
struct PairingSecret {
    private let privateKey = Curve25519.KeyAgreement.PrivateKey()

    /// Base64, as the server expects.
    var publicKey: String { privateKey.publicKey.rawRepresentation.base64EncodedString() }

    struct Session {
        fileprivate let boxKey: SymmetricKey
        /// Four digits, the same on both screens when nobody is in the middle.
        let match: String

        func seal(_ spaceKey: String) throws -> String {
            guard let combined = try AES.GCM.seal(Data(spaceKey.utf8), using: boxKey).combined else {
                throw SyncError.corruptPayload
            }
            return combined.base64EncodedString()
        }

        func open(_ box: String) throws -> String {
            guard let data = Data(base64Encoded: box),
                  let key = String(data: try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: boxKey), encoding: .utf8),
                  key.count >= 32 else { throw SyncError.corruptPayload }
            return key
        }
    }

    /// Both sides pass the keys in host, guest order, so they derive the same session.
    func session(peer: String, hostKey: String, guestKey: String, code: String) throws -> Session {
        guard let raw = Data(base64Encoded: peer),
              let peerKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw) else {
            throw SyncError.invalidResponse
        }
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: peerKey)
        let transcript = Data("\(code)|\(hostKey)|\(guestKey)".utf8)
        let boxKey = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: transcript,
                                                    sharedInfo: Data("truefocus.pair.box.v1".utf8),
                                                    outputByteCount: 32)
        let matchKey = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: transcript,
                                                      sharedInfo: Data("truefocus.pair.match.v1".utf8),
                                                      outputByteCount: 4)
        let number = matchKey.withUnsafeBytes { bytes in bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } }
        return Session(boxKey: boxKey, match: String(format: "%04d", number % 10_000))
    }
}
