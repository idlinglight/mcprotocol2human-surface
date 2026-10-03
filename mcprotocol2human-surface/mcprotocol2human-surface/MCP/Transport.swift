import Foundation

/// One JSON-RPC message on its way to the server.
nonisolated struct OutgoingMessage: Sendable {
    var payload: JSONValue
    /// The JSON-RPC method, for the `Mcp-Method` header of modern HTTP requests; nil for responses.
    var method: String?
    /// False for notifications and responses, which the server answers with nothing.
    var expectsReply: Bool
}

nonisolated enum TransportEvent: Sendable {
    /// A message that arrived outside of a `send` call (stdio).
    case message(JSONValue)
    /// No more messages will arrive; the reason, if one is known.
    case closed(String?)
}

/// Carries JSON-RPC messages to and from one server (ADR-0004).
nonisolated protocol MCPTransport: Sendable {
    /// Messages that arrive on their own, and the end of the connection.
    var events: AsyncStream<TransportEvent> { get }
    /// True when replies come back as the result of `send` (HTTP), false when they arrive as events (stdio).
    var repliesArriveWithSend: Bool { get }
    func start() async throws
    /// Sends one message. Transports that carry replies on the same exchange return the messages received
    /// for it, in order; the others return an empty array.
    func send(_ message: OutgoingMessage) async throws -> [JSONValue]
    /// Headers for later HTTP requests: the protocol version, and whether to name the method.
    func setProtocolHeaders(version: String?, namesMethod: Bool) async
    func close() async
}

nonisolated struct HTTPStatusFailure: Sendable, Hashable {
    var status: Int
    var body: String
    /// The body parsed as JSON, when it is JSON.
    var json: JSONValue?
}

nonisolated enum TransportError: Error, LocalizedError, Sendable {
    case executableNotFound(String)
    case launchFailed(String, reason: String)
    case writeFailed(String)
    case invalidURL(String)
    case httpStatus(HTTPStatusFailure)
    case unexpectedContentType(String)
    case connectionFailed(String)
    case unreadableReply(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            "Could not find “\(name)” in the search path. Give a full path, or install it in one of: \(ExecutableLocator.searchDirectories.joined(separator: ", "))."
        case .launchFailed(let name, let reason):
            "Could not start “\(name)”: \(reason)"
        case .writeFailed(let reason):
            "Could not write to the server: \(reason)"
        case .invalidURL(let text):
            "“\(text)” is not a usable http or https URL."
        case .httpStatus(let failure):
            "The server answered with HTTP \(failure.status)\(failure.body.isEmpty ? "" : ": \(failure.body.prefix(300))")"
        case .unexpectedContentType(let type):
            "The server answered with content type “\(type)”, neither JSON nor an event stream."
        case .connectionFailed(let reason):
            "Could not reach the server: \(reason)"
        case .unreadableReply(let reason):
            "The server's reply could not be read: \(reason)"
        }
    }
}
