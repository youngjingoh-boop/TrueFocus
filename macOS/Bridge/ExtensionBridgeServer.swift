import Foundation
import Network
import TrueFocusKit

/// A tiny loopback-only HTTP server so Chrome-family browsers (which have no native
/// messaging to a sandboxed app) can read TrueFocus's live state.
///
///     GET  http://127.0.0.1:52525/state  → {"snapshot": {...}, "settings": {...}}
///     POST http://127.0.0.1:52525/boot   ← {"site": "Instagram", "reason": "binge"}
///
/// Only browser-extension origins are answered; ordinary web pages can't read your tasks.
@MainActor
final class ExtensionBridgeServer {
    static let shared = ExtensionBridgeServer()
    static let port: UInt16 = 52525

    private let server = BridgeHTTPServer(port: ExtensionBridgeServer.port)

    func start() {
        server.start()
    }

    func stop() {
        server.stop()
    }
}

/// The networking half. Runs entirely on its own queue; the app is only touched for boots.
final class BridgeHTTPServer: @unchecked Sendable {
    private let port: UInt16
    private let queue = DispatchQueue(label: "app.truefocus.bridge")
    private var listener: NWListener?
    private var restartWorkItem: DispatchWorkItem?

    init(port: UInt16) {
        self.port = port
    }

    func start() {
        queue.async { self.startOnQueue() }
    }

    func stop() {
        queue.async {
            self.restartWorkItem?.cancel()
            self.restartWorkItem = nil
            self.listener?.cancel()
            self.listener = nil
        }
    }

    private func startOnQueue() {
        guard listener == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        do {
            let listener = try NWListener(using: parameters, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                BridgeConnection(connection: connection, queue: self.queue).start()
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .failed(let error):
                    print("TrueFocus bridge: listener failed: \(error)")
                    self.scheduleRestart()
                case .cancelled:
                    break
                default:
                    break
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            print("TrueFocus bridge: could not listen on \(port): \(error)")
            scheduleRestart()
        }
    }

    /// The port can be busy for a moment after a relaunch; try again shortly.
    private func scheduleRestart() {
        listener?.cancel()
        listener = nil
        restartWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.startOnQueue() }
        restartWorkItem = item
        queue.asyncAfter(deadline: .now() + 5, execute: item)
    }
}

/// One request, one response, then close.
private final class BridgeConnection: @unchecked Sendable {
    private static let maxRequestBytes = 64 * 1024

    private let connection: NWConnection
    private let queue: DispatchQueue
    private var buffer = Data()

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    func start() {
        connection.start(queue: queue)
        receive()
        // Never hold a socket open for a slow or silent client.
        queue.asyncAfter(deadline: .now() + 5) { [connection] in
            connection.cancel()
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, isComplete, error in
            if let data, !data.isEmpty { self.buffer.append(data) }
            if let request = BridgeHTTPRequest.parse(self.buffer) {
                self.respond(to: request)
                return
            }
            if error != nil || isComplete || self.buffer.count > Self.maxRequestBytes {
                self.connection.cancel()
                return
            }
            self.receive()
        }
    }

    private func respond(to request: BridgeHTTPRequest) {
        let origin = request.headers["origin"]
        // DNS-rebinding guard: only our own loopback names.
        let host = (request.headers["host"] ?? "").lowercased()
        let hostOK = host.hasPrefix("127.0.0.1") || host.hasPrefix("localhost") || host.isEmpty
        // A web page has an http(s) Origin. Extensions have their own schemes, or none.
        let originOK = origin.map(Self.isExtensionOrigin) ?? true
        guard hostOK, originOK else {
            send(status: 403, body: Data(#"{"error":"forbidden"}"#.utf8), origin: nil)
            return
        }

        switch (request.method, request.path) {
        case ("OPTIONS", _):
            send(status: 204, body: Data(), origin: origin)
        case ("GET", "/state"):
            send(status: 200, body: Self.stateBody(), origin: origin)
        case ("POST", "/boot"):
            let json = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            let site = (json["site"] as? String).map { String($0.prefix(120)) }
            let reason = (json["reason"] as? String).map { String($0.prefix(40)) }
            SharedStore.shared.appendBoot(BootEvent(source: "web", site: site, reason: reason))
            Task { @MainActor in
                FocusController.shared.drainSharedQueues()
            }
            send(status: 200, body: Data(#"{"ok":true}"#.utf8), origin: origin)
        case ("GET", "/health"):
            send(status: 200, body: Data(#"{"ok":true}"#.utf8), origin: origin)
        default:
            send(status: 404, body: Data(#"{"error":"not found"}"#.utf8), origin: origin)
        }
    }

    static func isExtensionOrigin(_ origin: String) -> Bool {
        let lowered = origin.lowercased()
        return lowered.hasPrefix("chrome-extension://")
            || lowered.hasPrefix("safari-web-extension://")
            || lowered.hasPrefix("moz-extension://")
            || lowered.hasPrefix("extension://")
    }

    /// `{"snapshot": <LiveSnapshot JSON>, "settings": <TFSettings JSON>}`, built by
    /// splicing two valid JSON documents.
    private static func stateBody() -> Data {
        let store = SharedStore.shared
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let settings = (try? encoder.encode(store.settings)) ?? Data("{}".utf8)
        var body = Data(#"{"snapshot":"#.utf8)
        body.append(store.snapshotJSON())
        body.append(Data(#","settings":"#.utf8))
        body.append(settings)
        body.append(Data("}".utf8))
        return body
    }

    private func send(status: Int, body: Data, origin: String?) {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        head += "Content-Type: application/json; charset=utf-8\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n"
        if let origin, Self.isExtensionOrigin(origin) {
            head += "Access-Control-Allow-Origin: \(origin)\r\n"
            head += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
            head += "Access-Control-Allow-Headers: Content-Type\r\n"
            head += "Access-Control-Allow-Private-Network: true\r\n"
            head += "Vary: Origin\r\n"
        }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { [connection] _ in
            connection.cancel()
        })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        default: return "Error"
        }
    }
}

/// Just enough HTTP/1.1 to read one request: request line, headers, Content-Length body.
struct BridgeHTTPRequest {
    var method: String
    var path: String
    /// Lower-cased header names.
    var headers: [String: String]
    var body: Data

    /// Returns nil until the buffer holds a complete request.
    static func parse(_ buffer: Data) -> BridgeHTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: separator) else { return nil }
        guard let head = String(data: buffer.subdata(in: buffer.startIndex..<headerEnd.lowerBound), encoding: .utf8) else {
            return BridgeHTTPRequest(method: "BAD", path: "", headers: [:], body: Data())
        }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count >= 2 else {
            return BridgeHTTPRequest(method: "BAD", path: "", headers: [:], body: Data())
        }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        let length = min(Int(headers["content-length"] ?? "0") ?? 0, 64 * 1024)
        let bodyStart = headerEnd.upperBound
        guard buffer.count - (bodyStart - buffer.startIndex) >= length else { return nil }
        let body = buffer.subdata(in: bodyStart..<(bodyStart + length))
        // Drop any query string: "/state?x=1" → "/state".
        let target = String(requestLine[1])
        let path = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? target
        return BridgeHTTPRequest(method: String(requestLine[0]).uppercased(), path: path, headers: headers, body: body)
    }
}
