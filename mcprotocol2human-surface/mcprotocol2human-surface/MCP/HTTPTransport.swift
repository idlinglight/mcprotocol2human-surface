import Foundation

/// Streamable HTTP: every message is a POST; the reply is one JSON body or a stream of server-sent events.
///
/// Handles both eras (ADR-0005): a legacy session id from `initialize` is sent back on later requests and
/// ended with DELETE on close; modern requests carry `MCP-Protocol-Version` and `Mcp-Method`.
nonisolated final class HTTPTransport: MCPTransport, @unchecked Sendable {
    let endpoint: URL
    let headers: [KeyValue]
    let traffic: TrafficLog
    let events: AsyncStream<TransportEvent>
    var repliesArriveWithSend: Bool { true }
    /// Replies larger than this are cut off and reported as unreadable.
    let replyLimit = 16 * 1_048_576

    private let continuation: AsyncStream<TransportEvent>.Continuation
    private let session: URLSession
    // Guarded by `lock`.
    private let lock = NSLock()
    private var sessionID: String?
    private var protocolVersion: String?
    private var namesMethod = false

    init(url: String, headers: [KeyValue], traffic: TrafficLog) throws {
        guard let endpoint = URL(string: url.trimmingCharacters(in: .whitespaces)),
              let scheme = endpoint.scheme?.lowercased(), scheme == "http" || scheme == "https",
              endpoint.host() != nil
        else { throw TransportError.invalidURL(url) }
        self.endpoint = endpoint
        self.headers = headers
        self.traffic = traffic
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: configuration)
        (events, continuation) = AsyncStream.makeStream()
    }

    func start() async throws {}

    func setProtocolHeaders(version: String?, namesMethod: Bool) async {
        lock.withLock {
            protocolVersion = version
            self.namesMethod = namesMethod
        }
    }

    func send(_ message: OutgoingMessage, receive: @escaping @Sendable (JSONValue) async -> Bool) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        for header in headers where !header.key.isEmpty {
            request.setValue(header.value, forHTTPHeaderField: header.key)
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        let (sessionID, version, namesMethod) = lock.withLock { (self.sessionID, protocolVersion, self.namesMethod) }
        if let version { request.setValue(version, forHTTPHeaderField: "MCP-Protocol-Version") }
        if namesMethod, let method = message.method { request.setValue(method, forHTTPHeaderField: "Mcp-Method") }
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        request.httpBody = message.payload.compactData

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw TransportError.connectionFailed(error.localizedDescription)
        }
        // Whatever is left unread once the reply is in (or on an error) is not wanted.
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else {
            throw TransportError.connectionFailed("not an HTTP response")
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        traffic.record(.note, "HTTP \(http.statusCode)\(contentType.isEmpty ? "" : " " + contentType)")
        if let newSessionID = http.value(forHTTPHeaderField: "Mcp-Session-Id"), newSessionID != sessionID {
            lock.withLock { self.sessionID = newSessionID }
            traffic.record(.note, "Session id \(newSessionID)")
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = try await collect(bytes)
            let text = String(decoding: body, as: UTF8.self)
            if !text.isEmpty { traffic.record(.received, text) }
            throw TransportError.httpStatus(HTTPStatusFailure(
                status: http.statusCode, body: text, json: try? JSONValue.parse(body)))
        }
        if http.statusCode == 202 || !message.expectsReply {
            return
        }
        let mediaType = contentType.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        switch mediaType {
        case "text/event-stream":
            try await readEventStream(bytes, receive: receive)
        case "application/json":
            let body = try await collect(bytes)
            let text = String(decoding: body, as: UTF8.self)
            traffic.record(.received, text)
            let value: JSONValue
            do {
                value = try JSONValue.parse(body)
            } catch {
                throw TransportError.unreadableReply(error.localizedDescription)
            }
            _ = await receive(value)
        default:
            throw TransportError.unexpectedContentType(contentType.isEmpty ? "none" : contentType)
        }
    }

    /// Hands each event's message to `receive` until it says the reply is in, or the stream ends.
    private func readEventStream(_ bytes: URLSession.AsyncBytes, receive: @Sendable (JSONValue) async -> Bool) async throws {
        var parser = SSEParser()
        var count = 0
        func take(_ event: SSEEvent) async -> Bool {
            // Events of another type are not MCP messages; an empty data line primes the stream.
            guard event.type == nil || event.type == "message" else {
                traffic.record(.note, "Ignored event of type “\(event.type ?? "")”")
                return false
            }
            guard !event.data.isEmpty else { return false }
            traffic.record(.received, event.data)
            guard let value = try? JSONValue.parse(event.data) else {
                traffic.record(.note, "That event's data is not JSON.")
                return false
            }
            return await receive(value)
        }
        do {
            for try await byte in bytes {
                count += 1
                guard count <= replyLimit else { throw TransportError.unreadableReply("event stream longer than \(replyLimit) bytes") }
                if let event = parser.append(byte), await take(event) {
                    return
                }
            }
        } catch let error as TransportError {
            throw error
        } catch {
            throw TransportError.connectionFailed(error.localizedDescription)
        }
        if let event = parser.finish() {
            traffic.record(.note, "The event stream ended without a blank line after its last event.")
            _ = await take(event)
        }
    }

    private func collect(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                guard data.count <= replyLimit else { throw TransportError.unreadableReply("body longer than \(replyLimit) bytes") }
            }
        } catch let error as TransportError {
            throw error
        } catch {
            throw TransportError.connectionFailed(error.localizedDescription)
        }
        return data
    }

    func close() async {
        if let sessionID = lock.withLock({ self.sessionID }) {
            var request = URLRequest(url: endpoint, timeoutInterval: 5)
            request.httpMethod = "DELETE"
            for header in headers where !header.key.isEmpty {
                request.setValue(header.value, forHTTPHeaderField: header.key)
            }
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
            if let version = lock.withLock({ protocolVersion }) {
                request.setValue(version, forHTTPHeaderField: "MCP-Protocol-Version")
            }
            do {
                let (_, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                traffic.record(.note, "DELETE session: HTTP \(status)")
            } catch {
                traffic.record(.note, "DELETE session failed: \(error.localizedDescription)")
            }
        }
        session.invalidateAndCancel()
        continuation.yield(.closed(nil))
        continuation.finish()
    }
}
