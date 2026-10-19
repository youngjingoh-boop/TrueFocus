import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where the sync backend lives. Read from Info.plist (`TFSupabaseURL`, `TFSupabaseKey`).
public struct TFCloudConfig: Equatable, Sendable {
    public var url: URL
    public var anonKey: String

    public init(url: URL, anonKey: String) {
        self.url = url
        self.anonKey = anonKey
    }

    public static func fromBundle(_ bundle: Bundle = .main) -> TFCloudConfig? {
        guard let host = bundle.object(forInfoDictionaryKey: "TFSupabaseHost") as? String,
              let key = bundle.object(forInfoDictionaryKey: "TFSupabaseKey") as? String,
              !host.isEmpty, !key.isEmpty, !host.contains("$("), !key.contains("$("),
              let url = URL(string: "https://\(host)") else { return nil }
        return TFCloudConfig(url: url, anonKey: key)
    }
}

/// A short code that links another device to this sync space.
public struct PairingCode: Equatable, Sendable {
    public var code: String
    public var expiresAt: Date

    public init(code: String, expiresAt: Date) {
        self.code = code
        self.expiresAt = expiresAt
    }
}

/// The sync backend: Supabase PostgREST + two edge functions, over plain HTTPS.
/// Every request carries the space's access token in `x-tf-space` (derived one way from the
/// space key on device, so the server never sees the key); row-level security does the rest.
public final class TFCloud: @unchecked Sendable {
    public let config: TFCloudConfig
    private let session: URLSession

    public init(config: TFCloudConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: Records

    /// Records changed since `since` (server time), oldest first, following pages.
    public func pull(access: String, since: Date?, pageSize: Int = 500) async throws -> [RemoteRecord] {
        var all: [RemoteRecord] = []
        var from = since
        while true {
            var items = [
                URLQueryItem(name: "select", value: "id,kind,data,deleted,modified_at,updated_at"),
                URLQueryItem(name: "order", value: "updated_at.asc"),
                URLQueryItem(name: "limit", value: String(pageSize)),
            ]
            if let from { items.append(URLQueryItem(name: "updated_at", value: "gte." + SyncDates.format(from))) }
            let request = try makeRequest(path: "/rest/v1/tf_records", query: items, method: "GET", access: access)
            let data = try await send(request)
            let page = try SyncDates.decoder().decode([RemoteRecord].self, from: data)
            all.append(contentsOf: page)
            guard page.count == pageSize, let last = page.last?.updatedAt, last != from else { break }
            from = last
        }
        return all
    }

    /// Upserts records (last writer wins is enforced by the server).
    public func push(access: String, records: [RemoteRecord]) async throws {
        guard !records.isEmpty else { return }
        for start in stride(from: 0, to: records.count, by: 200) {
            let chunk = Array(records[start..<min(start + 200, records.count)])
            var request = try makeRequest(path: "/rest/v1/tf_records",
                                          query: [URLQueryItem(name: "on_conflict", value: "space,id")],
                                          method: "POST", access: access)
            request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
            request.httpBody = try SyncDates.encoder().encode(chunk)
            _ = try await send(request)
        }
    }

    // MARK: Devices and wake-ups

    public func registerDevice(access: String, token: String, platform: String, environment: String) async throws {
        var request = try makeRequest(path: "/rest/v1/tf_devices",
                                      query: [URLQueryItem(name: "on_conflict", value: "space,token")],
                                      method: "POST", access: access)
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        let row: [String: String] = ["token": token, "platform": platform, "environment": environment,
                                     "updated_at": SyncDates.format(Date())]
        request.httpBody = try JSONSerialization.data(withJSONObject: [row])
        _ = try await send(request)
    }

    /// Asks the server to silently wake this space's other iPhones.
    public func notify(access: String, exceptToken: String?) async throws {
        var request = try makeRequest(path: "/functions/v1/tf-notify", query: [], method: "POST", access: access)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["except_token": exceptToken ?? ""])
        _ = try await send(request)
    }

    // MARK: Moving and deleting a space

    /// One-time move from the legacy space id (the hash of the space key itself) to the one
    /// for `access`. Sends the legacy key once; afterwards only the access token travels.
    @discardableResult
    public func rekey(legacyKey: String, access: String) async throws -> Int {
        var request = try makeRequest(path: "/functions/v1/tf-space", query: [], method: "POST", access: legacyKey)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["action": "rekey", "access": access])
        let data = try await send(request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["moved"] as? Int ?? 0
    }

    /// Removes every record and push token the server holds for this space.
    public func deleteSpace(access: String) async throws {
        var request = try makeRequest(path: "/functions/v1/tf-space", query: [], method: "POST", access: access)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["action": "delete"])
        _ = try await send(request)
    }

    // MARK: Linking (public keys and a sealed box; the key never passes through the server)

    /// Host: opens a code, committing to its public key (`commitment` = sha256 hex of it) without
    /// revealing it yet.
    public func pairHost(commitment: String) async throws -> PairingCode {
        let object = try await pair(["action": "host", "commit": commitment])
        guard let code = object["code"] as? String,
              let expires = (object["expires_at"] as? String).flatMap(SyncDates.parse) else {
            throw SyncError.invalidResponse
        }
        return PairingCode(code: code, expiresAt: expires)
    }

    /// Joiner: claims `code` (`claim` is 64 random hex digits that identify it from here on);
    /// returns the host's commitment.
    public func pairJoin(code: String, claim: String) async throws -> String {
        let object = try await pair(["action": "join", "code": code, "claim": claim])
        guard let commitment = object["commit"] as? String else { throw SyncError.invalidResponse }
        return commitment
    }

    /// Joiner: sends its public key. Call only once `pairJoin` has returned the commitment.
    public func pairOffer(code: String, claim: String, publicKey: String) async throws {
        _ = try await pair(["action": "offer", "code": code, "claim": claim, "pk": publicKey])
    }

    /// Host: the joiner's public key once someone has entered the code, else nil.
    public func pairWait(code: String, commitment: String) async throws -> String? {
        let object = try await pair(["action": "wait", "code": code, "commit": commitment])
        return object["guest_pk"] as? String
    }

    /// Host: reveals the public key it committed to, now that the joiner's is fixed.
    public func pairReveal(code: String, commitment: String, publicKey: String) async throws {
        _ = try await pair(["action": "reveal", "code": code, "commit": commitment, "pk": publicKey])
    }

    /// Host: hands over the sealed space key.
    public func pairSeal(code: String, commitment: String, box: String) async throws {
        _ = try await pair(["action": "seal", "code": code, "commit": commitment, "box": box])
    }

    /// Joiner: the host's public key once revealed, and the sealed space key once sent.
    public func pairFetch(code: String, guestKey: String) async throws -> (hostKey: String?, box: String?) {
        let object = try await pair(["action": "fetch", "code": code, "pk": guestKey])
        return (object["host_pk"] as? String, object["box"] as? String)
    }

    private func pair(_ body: [String: String]) async throws -> [String: Any] {
        var request = try makeRequest(path: "/functions/v1/tf-pair", query: [], method: "POST", access: nil)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SyncError.invalidResponse
        }
        return object
    }

    // MARK: Plumbing

    func makeRequest(path: String, query: [URLQueryItem], method: String, access: String?) throws -> URLRequest {
        guard var components = URLComponents(url: config.url.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw SyncError.notConfigured
        }
        if !query.isEmpty { components.queryItems = query }
        // "+" in timestamps must not be read as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw SyncError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let access { request.setValue(access, forHTTPHeaderField: "x-tf-space") }
        return request
    }

    func send(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let response {
                    continuation.resume(returning: (data ?? Data(), response))
                } else {
                    continuation.resume(throwing: SyncError.invalidResponse)
                }
            }
            task.resume()
        }
        guard let http = response as? HTTPURLResponse else { throw SyncError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw SyncError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}

/// Generates a new random space key: 32 bytes, base64url.
public enum SpaceKey {
    public static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
