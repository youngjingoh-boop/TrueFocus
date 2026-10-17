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
}

/// The sync backend: Supabase PostgREST + two edge functions, over plain HTTPS.
/// Every request carries the space key in `x-tf-space`; row-level security does the rest.
public final class TFCloud: @unchecked Sendable {
    public let config: TFCloudConfig
    private let session: URLSession

    public init(config: TFCloudConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: Records

    /// Records changed since `since` (server time), oldest first, following pages.
    public func pull(spaceKey: String, since: Date?, pageSize: Int = 500) async throws -> [RemoteRecord] {
        var all: [RemoteRecord] = []
        var from = since
        while true {
            var items = [
                URLQueryItem(name: "select", value: "id,kind,data,deleted,modified_at,updated_at"),
                URLQueryItem(name: "order", value: "updated_at.asc"),
                URLQueryItem(name: "limit", value: String(pageSize)),
            ]
            if let from { items.append(URLQueryItem(name: "updated_at", value: "gte." + SyncDates.format(from))) }
            let request = try makeRequest(path: "/rest/v1/tf_records", query: items, method: "GET", spaceKey: spaceKey)
            let data = try await send(request)
            let page = try SyncDates.decoder().decode([RemoteRecord].self, from: data)
            all.append(contentsOf: page)
            guard page.count == pageSize, let last = page.last?.updatedAt, last != from else { break }
            from = last
        }
        return all
    }

    /// Upserts records (last writer wins is enforced by the server).
    public func push(spaceKey: String, records: [RemoteRecord]) async throws {
        guard !records.isEmpty else { return }
        for start in stride(from: 0, to: records.count, by: 200) {
            let chunk = Array(records[start..<min(start + 200, records.count)])
            var request = try makeRequest(path: "/rest/v1/tf_records",
                                          query: [URLQueryItem(name: "on_conflict", value: "space,id")],
                                          method: "POST", spaceKey: spaceKey)
            request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
            request.httpBody = try SyncDates.encoder().encode(chunk)
            _ = try await send(request)
        }
    }

    // MARK: Devices and wake-ups

    public func registerDevice(spaceKey: String, token: String, platform: String, environment: String) async throws {
        var request = try makeRequest(path: "/rest/v1/tf_devices",
                                      query: [URLQueryItem(name: "on_conflict", value: "space,token")],
                                      method: "POST", spaceKey: spaceKey)
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        let row: [String: String] = ["token": token, "platform": platform, "environment": environment,
                                     "updated_at": SyncDates.format(Date())]
        request.httpBody = try JSONSerialization.data(withJSONObject: [row])
        _ = try await send(request)
    }

    /// Asks the server to silently wake this space's other iPhones.
    public func notify(spaceKey: String, exceptToken: String?) async throws {
        var request = try makeRequest(path: "/functions/v1/tf-notify", query: [], method: "POST", spaceKey: spaceKey)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["except_token": exceptToken ?? ""])
        _ = try await send(request)
    }

    // MARK: Pairing

    public func createPairingCode(spaceKey: String) async throws -> PairingCode {
        var request = try makeRequest(path: "/functions/v1/tf-pair", query: [], method: "POST", spaceKey: nil)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["action": "create", "key": spaceKey])
        let data = try await send(request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = object["code"] as? String,
              let expires = (object["expires_at"] as? String).flatMap(SyncDates.parse) else {
            throw SyncError.invalidResponse
        }
        return PairingCode(code: code, expiresAt: expires)
    }

    /// Returns the space key the code stands for.
    public func redeemPairingCode(_ code: String) async throws -> String {
        var request = try makeRequest(path: "/functions/v1/tf-pair", query: [], method: "POST", spaceKey: nil)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["action": "redeem", "code": code])
        let data = try await send(request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = object["key"] as? String, key.count >= 32 else {
            throw SyncError.invalidResponse
        }
        return key
    }

    // MARK: Plumbing

    func makeRequest(path: String, query: [URLQueryItem], method: String, spaceKey: String?) throws -> URLRequest {
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
        if let spaceKey { request.setValue(spaceKey, forHTTPHeaderField: "x-tf-space") }
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
