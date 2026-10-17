import CryptoKit
import Foundation
import Security
import TrueFocusKit

/// The space key lives in this device's Keychain (never iCloud Keychain). Anyone holding it can
/// read and write the space, so it only leaves the device through a one-time pairing code.
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

    static func read() -> Read {
        var result: CFTypeRef?
        let status = run { dataProtection in
            var request = query(dataProtection: dataProtection)
            request[kSecReturnData as String] = true
            request[kSecMatchLimit as String] = kSecMatchLimitOne
            return SecItemCopyMatching(request as CFDictionary, &result)
        }
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let key = String(data: data, encoding: .utf8), key.count >= 32 else {
                return .unavailable
            }
            return .found(key)
        case errSecItemNotFound:
            return .missing
        default:
            return .unavailable
        }
    }

    @discardableResult
    static func write(_ key: String) -> Bool {
        let status = run { dataProtection in
            let match = query(dataProtection: dataProtection)
            let update = SecItemUpdate(match as CFDictionary, [kSecValueData as String: Data(key.utf8)] as CFDictionary)
            guard update == errSecItemNotFound else { return update }
            var add = match
            add[kSecValueData as String] = Data(key.utf8)
            // Readable in the background once the phone has been unlocked after a restart,
            // so a silent push can sync with the screen locked.
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(add as CFDictionary, nil)
        }
        return status == errSecSuccess
    }
}

/// AES-GCM with a key derived from the space key. The server stores only ciphertext and a hash
/// of the space key, so neither it nor anyone with database access can read a plan.
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

    private static func tag(_ spaceKey: String) -> String {
        SHA256.hash(data: Data(spaceKey.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func load(for spaceKey: String) -> SyncLedger {
        guard let url, let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.space == tag(spaceKey) else { return SyncLedger() }
        return stored.ledger
    }

    static func save(_ ledger: SyncLedger, for spaceKey: String) {
        guard let url, let data = try? JSONEncoder().encode(Stored(space: tag(spaceKey), ledger: ledger)) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
