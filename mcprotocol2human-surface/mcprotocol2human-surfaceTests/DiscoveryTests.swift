import Foundation
import Testing
@testable import mcprotocol2human_surface

/// An HTTP-like transport whose replies come from a closure, recording what was sent and with which headers.
final class FakeTransport: MCPTransport, @unchecked Sendable {
    enum Reply: @unchecked Sendable {
        /// Delivered one by one until the connection says the reply is in.
        case messages([JSONValue])
        case status(Int, JSONValue?)
        case failure(any Error)
        /// Full control: deliver messages and look at what the client sent in between.
        case script(@Sendable (FakeTransport, @Sendable (JSONValue) async -> Bool) async throws -> Void)
    }

    let events: AsyncStream<TransportEvent>
    var repliesArriveWithSend: Bool { true }
    private let continuation: AsyncStream<TransportEvent>.Continuation
    private let reply: @Sendable (JSONValue) -> Reply
    private let lock = NSLock()
    private var log: [(payload: JSONValue, version: String?, namesMethod: Bool)] = []
    private var version: String?
    private var namesMethod = false

    init(reply: @escaping @Sendable (JSONValue) -> Reply) {
        self.reply = reply
        (events, continuation) = AsyncStream.makeStream()
    }

    var sent: [(payload: JSONValue, version: String?, namesMethod: Bool)] { lock.withLock { log } }
    var sentMethods: [String] { sent.compactMap { $0.payload["method"]?.stringValue } }

    func start() async throws {}

    func send(_ message: OutgoingMessage, receive: @escaping @Sendable (JSONValue) async -> Bool) async throws {
        lock.withLock { log.append((message.payload, version, namesMethod)) }
        guard message.expectsReply else { return }
        switch reply(message.payload) {
        case .messages(let messages):
            for message in messages where await receive(message) {
                return
            }
        case .status(let status, let body):
            throw TransportError.httpStatus(HTTPStatusFailure(status: status, body: body?.compactText ?? "", json: body))
        case .failure(let error):
            throw error
        case .script(let script):
            try await script(self, receive)
        }
    }

    func setProtocolHeaders(version: String?, namesMethod: Bool) async {
        lock.withLock {
            self.version = version
            self.namesMethod = namesMethod
        }
    }

    func close() async {
        continuation.finish()
    }
}

func result(for request: JSONValue, _ result: JSONValue) -> JSONValue {
    ["jsonrpc": "2.0", "id": request["id"] ?? .null, "result": result]
}

func error(for request: JSONValue, code: Int, message: String = "nope", data: JSONValue? = nil) -> JSONValue {
    var error: JSONValue = ["code": .number(String(code)), "message": .string(message)]
    if let data { error = error.setting("data", to: data) }
    return ["jsonrpc": "2.0", "id": request["id"] ?? .null, "error": error]
}

func discover(_ transport: FakeTransport) async throws -> DiscoveryResult {
    let connection = MCPConnection(transport: transport, traffic: TrafficLog())
    try await connection.start()
    defer { Task { await connection.close() } }
    return try await Discovery.discover(over: connection, traffic: TrafficLog())
}

let legacyInitializeResult: JSONValue = [
    "protocolVersion": "2025-06-18",
    "capabilities": ["tools": ["listChanged": true]],
    "serverInfo": ["name": "fake", "version": "1.0"],
    "instructions": "Be nice.",
]

struct DiscoveryTests {
    @Test func modernServerIsListedWithMetaAndPagination() async throws {
        let transport = FakeTransport { request in
            switch request["method"]?.stringValue {
            case "server/discover":
                return .messages([result(for: request, [
                    "resultType": "complete", "supportedVersions": ["2026-07-28"],
                    "capabilities": ["tools": [:]], "ttlMs": 0, "cacheScope": "private",
                    "_meta": ["io.modelcontextprotocol/serverInfo": ["name": "modern", "version": "2"]],
                ])])
            case "tools/list":
                if request["params"]?["cursor"] == nil {
                    return .messages([result(for: request, ["resultType": "complete", "tools": [["name": "a"]], "nextCursor": ""])])
                }
                return .messages([result(for: request, ["resultType": "complete", "tools": [["name": "b"]]])])
            default:
                return .status(404, nil)
            }
        }
        let found = try await discover(transport)
        #expect(found.era == .modern)
        #expect(found.protocolVersion == "2026-07-28")
        #expect(found.serverInfo?["name"] == "modern")
        #expect(found.tools.map(\.name) == ["a", "b"], "an empty-string cursor is not the end")
        #expect(transport.sentMethods == ["server/discover", "tools/list", "tools/list"])
        for sent in transport.sent {
            #expect(sent.payload["params"]?["_meta"]?["io.modelcontextprotocol/protocolVersion"] == "2026-07-28")
            #expect(sent.version == "2026-07-28")
            #expect(sent.namesMethod)
        }
    }

    @Test(arguments: [-32601, -32602, -32600])
    func otherErrorsFallBackToInitialize(code: Int) async throws {
        let transport = FakeTransport { request in
            switch request["method"]?.stringValue {
            case "server/discover": .messages([error(for: request, code: code)])
            case "initialize": .messages([result(for: request, legacyInitializeResult)])
            case "tools/list": .messages([result(for: request, ["tools": [["name": "t"]]])])
            default: .status(500, nil)
            }
        }
        let found = try await discover(transport)
        #expect(found.era == .legacy)
        #expect(found.protocolVersion == "2025-06-18")
        #expect(found.instructions == "Be nice.")
        #expect(found.tools.map(\.name) == ["t"])
        #expect(transport.sentMethods == ["server/discover", "initialize", "notifications/initialized", "tools/list"])
        let initialize = transport.sent[1]
        #expect(initialize.version == nil, "initialize carries no protocol version header")
        #expect(!initialize.namesMethod)
        #expect(transport.sent[3].version == "2025-06-18")
        #expect(transport.sent[3].payload["params"] == nil)
    }

    @Test func httpStatusWithoutModernErrorFallsBack() async throws {
        let transport = FakeTransport { request in
            switch request["method"]?.stringValue {
            case "server/discover": .status(400, ["jsonrpc": "2.0", "id": "server-error", "error": ["code": -32600, "message": "Missing session ID"]])
            case "initialize": .messages([result(for: request, legacyInitializeResult)])
            default: .messages([result(for: request, ["tools": []])])
            }
        }
        #expect(try await discover(transport).era == .legacy)
    }

    @Test func http404WithoutBodyFallsBack() async throws {
        let transport = FakeTransport { request in
            switch request["method"]?.stringValue {
            case "server/discover": .status(404, nil)
            case "initialize": .messages([result(for: request, legacyInitializeResult)])
            default: .messages([result(for: request, ["tools": []])])
            }
        }
        #expect(try await discover(transport).era == .legacy)
    }

    @Test func unsupportedVersionIsReportedNotFallenBackFrom() async throws {
        let transport = FakeTransport { request in
            .messages([error(for: request, code: -32022, data: ["supported": ["2027-01-01"], "requested": "2026-07-28"])])
        }
        await #expect {
            try await discover(transport)
        } throws: { error in
            guard case DiscoveryError.unsupportedVersion(let supported) = error else { return false }
            return supported == ["2027-01-01"]
        }
        #expect(transport.sentMethods == ["server/discover"])
    }

    @Test func unauthorisedIsReported() async throws {
        let transport = FakeTransport { _ in .status(401, nil) }
        await #expect {
            try await discover(transport)
        } throws: { error in
            if case DiscoveryError.unauthorized(401, _) = error { return true }
            return false
        }
    }

    @Test func toolsAreNotListedWithoutTheCapability() async throws {
        let transport = FakeTransport { request in
            switch request["method"]?.stringValue {
            case "server/discover": .messages([error(for: request, code: -32601)])
            default: .messages([result(for: request, ["protocolVersion": "2025-11-25", "capabilities": [:]])])
            }
        }
        let found = try await discover(transport)
        #expect(!found.toolsAdvertised)
        #expect(!transport.sentMethods.contains("tools/list"))
    }

    @Test func repeatedCursorStopsPaging() async throws {
        let transport = FakeTransport { request in
            switch request["method"]?.stringValue {
            case "server/discover": .messages([error(for: request, code: -32601)])
            case "initialize": .messages([result(for: request, legacyInitializeResult)])
            default: .messages([result(for: request, ["tools": [["name": "x"]], "nextCursor": "same"])])
            }
        }
        let found = try await discover(transport)
        #expect(found.tools.count == 2)
        #expect(found.observations.contains { $0.contains("repeated cursor") })
    }

    @Test func pingIsAnsweredWhileTheServerWaitsForIt() async throws {
        let transport = FakeTransport { request in
            switch request["method"]?.stringValue {
            case "server/discover": .messages([error(for: request, code: -32601)])
            case "initialize": .script { transport, receive in
                _ = await receive(["jsonrpc": "2.0", "id": "s1", "method": "ping"])
                // Like a server that holds its reply until the ping is answered.
                guard transport.sent.contains(where: { $0.payload["id"] == "s1" }) else {
                    throw TransportError.unreadableReply("ping not answered before the reply was due")
                }
                _ = await receive(result(for: request, legacyInitializeResult))
            }
            default: .messages([result(for: request, ["tools": []])])
            }
        }
        _ = try await discover(transport)
        let pong = transport.sent.first { $0.payload["id"] == "s1" }
        #expect(pong?.payload["result"] == [:])
    }

    @Test func replyIdWrittenAsDecimalStillMatches() async throws {
        let transport = FakeTransport { request in
            var reply: JSONValue = switch request["method"]?.stringValue {
            case "server/discover": error(for: request, code: -32601)
            case "initialize": result(for: request, legacyInitializeResult)
            default: result(for: request, ["tools": [["name": "t"]]])
            }
            reply = reply.setting("id", to: .number("\(request["id"]?.intValue ?? 0).0"))
            // Followed by something else, as on a stream the server keeps open.
            return .messages([reply, ["jsonrpc": "2.0", "method": "notifications/message"]])
        }
        #expect(try await discover(transport).tools.map(\.name) == ["t"])
    }

    @Test(arguments: [
        FakeTransport.Reply.failure(TransportError.unexpectedContentType("text/plain")),
        .failure(TransportError.unreadableReply("garbage")),
        .status(500, nil),
        .messages([]),
    ])
    func oddProbeAnswersFallBackToLegacy(_ probeReply: FakeTransport.Reply) async throws {
        let transport = FakeTransport { request in
            switch request["method"]?.stringValue {
            case "server/discover": probeReply
            case "initialize": .messages([result(for: request, legacyInitializeResult)])
            default: .messages([result(for: request, ["tools": []])])
            }
        }
        let found = try await discover(transport)
        #expect(found.era == .legacy)
        #expect(found.observations.first?.hasPrefix("server/discover failed:") == true)
    }

    @Test func unreachableServerEndsDiscovery() async throws {
        let transport = FakeTransport { _ in .failure(TransportError.connectionFailed("refused")) }
        await #expect(throws: TransportError.self) { try await discover(transport) }
        #expect(transport.sentMethods == ["server/discover"])
    }

    @Test func repeatedRemarksAndDuplicateNamesAreReportedOnce() async throws {
        let transport = FakeTransport { request in
            switch request["method"]?.stringValue {
            case "server/discover":
                return .messages([result(for: request, ["supportedVersions": ["2026-07-28"], "capabilities": ["tools": [:]]])])
            default:
                let page = request["params"]?["cursor"]?.stringValue ?? "0"
                let next: JSONValue = page == "0" ? "1" : (page == "1" ? "2" : .null)
                var reply = result(for: request, ["tools": [["name": "same"]]])
                if next != .null { reply = reply.setting("result", to: reply["result"]!.setting("nextCursor", to: next)) }
                return .messages([reply])
            }
        }
        let found = try await discover(transport)
        #expect(found.tools.count == 3)
        #expect(found.observations.filter { $0.hasPrefix("The result of tools/list has no resultType") }.count == 1)
        #expect(found.observations.contains("Tool names used more than once: same."))
    }
}

/// Runs real child processes: a small zsh script speaking legacy MCP, and one that exits at once.
struct StdioDiscoveryTests {
    static let fakeServer = #"""
    #!/bin/zsh
    print -u2 "fake server starting"
    while IFS= read -r line; do
      id=${${line#*\"id\":}%%,*}
      case $line in
        *'"method":"server/discover"'*)
          print -r -- '{"jsonrpc":"2.0","id":'$id',"error":{"code":-32601,"message":"Method not found"}}' ;;
        *'"method":"initialize"'*)
          print -r -- '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"fake-stdio","version":"0.1"}}}' ;;
        *'"method":"tools/list"'*)
          print -r -- '{"jsonrpc":"2.0","id":'$id',"result":{"tools":[{"name":"zeta","inputSchema":{"type":"object"}},{"name":"alpha","inputSchema":{"type":"object"}}]}}' ;;
      esac
    done
    """#

    func writeScript(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "m2h-fake-\(UUID().uuidString).zsh")
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test func discoversOverStdio() async throws {
        let script = try writeScript(Self.fakeServer)
        defer { try? FileManager.default.removeItem(at: script) }
        var config = ServerConfig(name: "fake")
        config.command = script.path
        let traffic = TrafficLog()
        let found = try await Discovery.run(config, traffic: traffic)
        #expect(found.era == .legacy)
        #expect(found.serverInfo?["name"] == "fake-stdio")
        #expect(found.tools.map(\.name) == ["zeta", "alpha"])
        #expect(traffic.entries.contains { $0.kind == .stderr && $0.text == "fake server starting" })
    }

    @Test func serverThatExitsAtOnceFailsWithoutHanging() async throws {
        var config = ServerConfig(name: "false")
        config.command = "/usr/bin/false"
        let started = ContinuousClock.now
        await #expect {
            try await Discovery.run(config, traffic: TrafficLog())
        } throws: { error in
            guard case ConnectionError.closed(let reason) = error else { return false }
            return reason?.contains("exited with status 1") == true
        }
        #expect(ContinuousClock.now - started < .seconds(10))
    }

    @Test func missingCommandIsReported() async throws {
        var config = ServerConfig(name: "missing")
        config.command = "definitely-not-installed-mcp-\(UUID().uuidString)"
        await #expect(throws: TransportError.self) {
            try await Discovery.run(config, traffic: TrafficLog())
        }
    }
}
