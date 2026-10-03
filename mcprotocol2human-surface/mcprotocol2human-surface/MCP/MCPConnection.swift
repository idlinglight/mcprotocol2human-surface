import Foundation

/// A JSON-RPC error object, as the server sent it.
nonisolated struct RPCError: Error, LocalizedError, Sendable, Hashable {
    var code: Int?
    var message: String
    var data: JSONValue?
    /// The HTTP status the error came with, for HTTP transports.
    var httpStatus: Int?

    init(code: Int?, message: String, data: JSONValue? = nil, httpStatus: Int? = nil) {
        self.code = code
        self.message = message
        self.data = data
        self.httpStatus = httpStatus
    }

    /// Reads the `error` member of a response, if it has one.
    init?(response: JSONValue, httpStatus: Int? = nil) {
        guard let error = response["error"], error.members != nil else { return nil }
        self.init(
            code: error["code"]?.intValue,
            message: error["message"]?.stringValue ?? "(no message)",
            data: error["data"],
            httpStatus: httpStatus)
    }

    var errorDescription: String? {
        var text = code.map { "Error \($0): \(message)" } ?? "Error: \(message)"
        if let httpStatus { text += " (HTTP \(httpStatus))" }
        return text
    }
}

nonisolated enum RPCOutcome: Sendable {
    case result(JSONValue)
    case error(RPCError)
}

nonisolated enum ConnectionError: Error, LocalizedError, Sendable {
    case timedOut(method: String, after: Duration)
    case closed(String?)
    case noReply(method: String)

    var errorDescription: String? {
        switch self {
        case .timedOut(let method, let after):
            "No answer to \(method) within \(after.formatted(.units(allowed: [.seconds])))."
        case .closed(let reason):
            "The connection closed before the answer arrived. \(reason ?? "")"
        case .noReply(let method):
            "The server's response to \(method) contained no reply to it."
        }
    }
}

/// One JSON-RPC conversation over a transport: numbers requests, matches replies, answers what the server
/// asks of a read-only client, and records everything in the traffic log.
actor MCPConnection {
    let transport: any MCPTransport
    let traffic: TrafficLog

    private var nextID = 1
    private var pending: [Int: CheckedContinuation<RPCOutcome, any Error>] = [:]
    private var timers: [Int: Task<Void, Never>] = [:]
    /// Error responses that matched no open request, kept per request until it settles: some servers
    /// answer with an error whose id is null or made up, and it still answers that request.
    private var strays: [Int: [JSONValue]] = [:]
    private var closedReason: String??
    private var isClosed = false
    private var eventsTask: Task<Void, Never>?

    init(transport: any MCPTransport, traffic: TrafficLog) {
        self.transport = transport
        self.traffic = traffic
    }

    /// Starts the transport, unless the connection was closed (cancelled) before it got here.
    func start() async throws {
        if isClosed { throw ConnectionError.closed(closedReason ?? nil) }
        try await transport.start()
        // Closed while starting: the earlier close found nothing to stop, so stop what just started.
        if isClosed {
            await transport.close()
            throw ConnectionError.closed(closedReason ?? nil)
        }
        let events = transport.events
        eventsTask = Task {
            for await event in events {
                await self.handle(event)
            }
        }
    }

    func setProtocolHeaders(version: String?, namesMethod: Bool) async {
        await transport.setProtocolHeaders(version: version, namesMethod: namesMethod)
    }

    /// Sends a request and waits for its reply. A JSON-RPC error comes back as `.error`; transport failures,
    /// timeouts and a closed connection are thrown.
    func request(_ method: String, params: JSONValue?, timeout: Duration) async throws -> RPCOutcome {
        if let reason = closedReason { throw ConnectionError.closed(reason) }
        let id = nextID
        nextID += 1
        var payload: JSONValue = ["jsonrpc": "2.0", "id": .number(String(id)), "method": .string(method)]
        if let params { payload = payload.setting("params", to: params) }
        let message = OutgoingMessage(payload: payload, method: method, expectsReply: true)
        traffic.record(.sent, payload.compactText)

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            timers[id] = Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self.traffic.record(.note, "Gave up waiting for the answer to \(method).")
                self.settle(id, with: .failure(ConnectionError.timedOut(method: method, after: timeout)))
            }
            Task { await self.exchange(id: id, method: method, message: message) }
        }
    }

    /// Sends a notification; nothing comes back.
    func notify(_ method: String, params: JSONValue? = nil) async throws {
        var payload: JSONValue = ["jsonrpc": "2.0", "method": .string(method)]
        if let params { payload = payload.setting("params", to: params) }
        traffic.record(.sent, payload.compactText)
        try await transport.send(OutgoingMessage(payload: payload, method: method, expectsReply: false)) { _ in true }
    }

    /// Closes the transport and fails whatever is still waiting. Closing twice does nothing.
    func close(reason: String = "Closed by the client.") async {
        guard !isClosed else { return }
        isClosed = true
        closedReason = .some(reason)
        eventsTask?.cancel()
        for id in pending.keys {
            settle(id, with: .failure(ConnectionError.closed(reason)))
        }
        await transport.close()
    }

    /// For task cancellation: ends the run as soon as possible.
    func cancel() async {
        guard !isClosed else { return }
        traffic.record(.note, "Cancelled.")
        await close(reason: "Cancelled.")
    }

    // MARK: -

    private func exchange(id: Int, method: String, message: OutgoingMessage) async {
        do {
            try await transport.send(message) { reply in
                await self.receive(reply, during: id)
            }
            guard transport.repliesArriveWithSend, pending[id] != nil else { return }
            if let stray = strays[id]?.first, let error = RPCError(response: stray) {
                traffic.record(.note, "The error response carries id \(stray["id"]?.compactText ?? "none") instead of \(id); taken as the answer to \(method).")
                settle(id, with: .success(.error(error)))
            } else {
                settle(id, with: .failure(ConnectionError.noReply(method: method)))
            }
        } catch TransportError.httpStatus(let failure) {
            if let json = failure.json, let error = RPCError(response: json, httpStatus: failure.status) {
                settle(id, with: .success(.error(error)))
            } else {
                settle(id, with: .failure(TransportError.httpStatus(failure)))
            }
        } catch {
            settle(id, with: .failure(error))
        }
    }

    /// A message that arrived while request `id` was being sent. Returns true once that request has its answer.
    private func receive(_ message: JSONValue, during id: Int) async -> Bool {
        if !(await handle(message)), RPCError(response: message) != nil {
            strays[id, default: []].append(message)
        }
        return pending[id] == nil
    }

    private func handle(_ event: TransportEvent) async {
        switch event {
        case .message(let message):
            if !(await handle(message)) {
                traffic.record(.note, "That message answers no open request; ignored.")
            }
        case .closed(let reason):
            if closedReason == nil { closedReason = .some(reason) }
            for id in pending.keys {
                settle(id, with: .failure(ConnectionError.closed(reason)))
            }
        }
    }

    /// Handles one incoming message. Returns false if it was a reply to no open request.
    private func handle(_ message: JSONValue) async -> Bool {
        if let batch = message.arrayValue {
            var allHandled = true
            for element in batch where !(await handle(element)) {
                allHandled = false
            }
            return allHandled
        }
        if let method = message["method"]?.stringValue {
            if let id = message["id"] {
                await answer(request: method, id: id)
            }
            return true
        }
        guard let id = message["id"]?.intValue, pending[id] != nil else { return false }
        if let error = RPCError(response: message) {
            settle(id, with: .success(.error(error)))
        } else {
            settle(id, with: .success(.result(message["result"] ?? .null)))
        }
        return true
    }

    /// A read-only client declares no capabilities, so the only request it can serve is `ping`.
    private func answer(request method: String, id: JSONValue) async {
        let reply: JSONValue = method == "ping"
            ? ["jsonrpc": "2.0", "id": id, "result": [:]]
            : ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": .string("Method not found: \(method)")]]
        traffic.record(.sent, reply.compactText)
        do {
            try await transport.send(OutgoingMessage(payload: reply, method: nil, expectsReply: false)) { _ in true }
        } catch {
            traffic.record(.note, "Could not answer \(method): \(error.localizedDescription)")
        }
    }

    private func settle(_ id: Int, with outcome: Result<RPCOutcome, any Error>) {
        timers.removeValue(forKey: id)?.cancel()
        strays[id] = nil
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(with: outcome)
    }
}
