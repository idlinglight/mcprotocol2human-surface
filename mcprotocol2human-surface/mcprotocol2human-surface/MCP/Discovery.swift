import Foundation

nonisolated enum ProtocolEra: String, Sendable {
    /// 2026-07-28 and later: stateless, `server/discover`, `_meta` on every request.
    case modern
    /// 2025-11-25 and earlier: the `initialize` handshake.
    case legacy
}

/// What one discovery run found out about a server.
nonisolated struct DiscoveryResult: Sendable {
    var era: ProtocolEra
    var protocolVersion: String
    /// The server's `Implementation` object: name, version, title, description, icons, websiteUrl.
    var serverInfo: JSONValue?
    var capabilities: JSONValue?
    var instructions: String?
    /// The raw result of `server/discover` (modern) or `initialize` (legacy).
    var handshake: JSONValue
    var toolsAdvertised: Bool
    var tools: [ToolInfo]
    /// How the client classified the server, and deviations it noticed on the way.
    var observations: [String]
}

nonisolated enum DiscoveryError: Error, LocalizedError, Sendable {
    case unauthorized(status: Int, detail: String)
    case rejected(method: String, RPCError)
    case unsupportedVersion(supported: [String])
    case invalidResult(method: String, problem: String)
    case unsupportedTransport(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized(let status, let detail):
            "The server requires authorisation (HTTP \(status)). \(detail)"
        case .rejected(let method, let error):
            "The server rejected \(method). \(error.localizedDescription)"
        case .unsupportedVersion(let supported):
            "The server speaks only protocol versions this client does not know: \(supported.joined(separator: ", "))."
        case .invalidResult(let method, let problem):
            "The result of \(method) is not usable: \(problem)"
        case .unsupportedTransport(let type):
            "Transport “\(type)” is not supported. Use stdio or Streamable HTTP (type “http”)."
        }
    }
}

/// Runs discovery against one server (ADR-0003, ADR-0005): probe with `server/discover`, fall back to
/// `initialize` for legacy servers, list tools, close.
nonisolated enum Discovery {
    static let modernVersion = "2026-07-28"
    static let legacyVersion = "2025-11-25"
    static let knownLegacyVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    /// Error codes the specification reserves for modern servers rejecting a request.
    static let modernErrorCodes: Set<Int> = [-32020, -32021, -32022]
    static let probeTimeout: Duration = .seconds(20)
    static let requestTimeout: Duration = .seconds(60)
    static let maxPages = 200

    static var clientInfo: JSONValue {
        ["name": "mcprotocol2human-surface", "version": .string(BuildInfo.current.version)]
    }

    /// Runs discovery once. Cancelling the calling task closes the connection, which ends the run.
    @concurrent
    static func run(_ config: ServerConfig, traffic: TrafficLog) async throws -> DiscoveryResult {
        let transport = try makeTransport(for: config, traffic: traffic)
        let connection = MCPConnection(transport: transport, traffic: traffic)
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                try await connection.start()
                let result = try await discover(over: connection, traffic: traffic)
                await connection.close()
                return result
            } catch {
                traffic.record(.note, "Discovery failed: \(error.localizedDescription)")
                await connection.close()
                throw error
            }
        } onCancel: {
            Task { await connection.cancel() }
        }
    }

    static func makeTransport(for config: ServerConfig, traffic: TrafficLog) throws -> any MCPTransport {
        switch config.kind {
        case .stdio:
            var environment: [String: String] = [:]
            for variable in config.environment where !variable.key.isEmpty {
                environment[variable.key] = variable.value
            }
            return StdioTransport(command: config.command, arguments: config.arguments, environment: environment, traffic: traffic)
        case .http:
            return try HTTPTransport(url: config.url, headers: config.headers, traffic: traffic)
        case .unsupported(let type):
            throw DiscoveryError.unsupportedTransport(type)
        }
    }

    /// `params` for a modern request: the `_meta` every request carries, plus `extra` members.
    static func modernParams(_ extra: [JSONMember] = []) -> JSONValue {
        let meta: JSONValue = [
            "io.modelcontextprotocol/protocolVersion": .string(modernVersion),
            "io.modelcontextprotocol/clientCapabilities": [:],
            "io.modelcontextprotocol/clientInfo": clientInfo,
        ]
        return .object([JSONMember(key: "_meta", value: meta)] + extra)
    }

    static func discover(over connection: MCPConnection, traffic: TrafficLog) async throws -> DiscoveryResult {
        var observations: [String] = []

        // Probe. A modern server answers server/discover; anything else means legacy.
        await connection.setProtocolHeaders(version: modernVersion, namesMethod: true)
        var probe: RPCOutcome?
        do {
            probe = try await connection.request("server/discover", params: modernParams(), timeout: probeTimeout)
        } catch {
            if let fatal = probeFailureEndingDiscovery(error) { throw fatal }
            observations.append("server/discover failed: \(error.localizedDescription) Treated as a legacy server.")
        }
        if case .error(let error)? = probe, let status = error.httpStatus, status == 401 || status == 403 {
            throw DiscoveryError.unauthorized(status: status, detail: error.message)
        }

        switch probe {
        case .result(let result)? where isDiscoverResult(result):
            return try await discoverModern(result, over: connection, observations: observations)
        case .result(let result)?:
            observations.append(notDiscoverResultRemark(result))
        case .error(let error)? where error.code.map(modernErrorCodes.contains) == true:
            if error.code == -32022 {
                let supported = error.data?["supported"]?.arrayValue?.compactMap(\.stringValue) ?? []
                throw DiscoveryError.unsupportedVersion(supported: supported)
            }
            throw DiscoveryError.rejected(method: "server/discover", error)
        case .error(let error)?:
            observations.append("server/discover answered with \(error.localizedDescription); treated as a legacy server.")
        case nil:
            break
        }
        return try await discoverLegacy(over: connection, observations: observations)
    }

    /// The probe failures that say nothing about the era: the server cannot be reached, has gone away, or
    /// wants authorisation. Anything else means legacy (ADR-0005).
    static func probeFailureEndingDiscovery(_ error: any Error) -> (any Error)? {
        switch error {
        case TransportError.httpStatus(let failure) where failure.status == 401 || failure.status == 403:
            DiscoveryError.unauthorized(status: failure.status, detail: String(failure.body.prefix(300)))
        case TransportError.connectionFailed, TransportError.executableNotFound, TransportError.launchFailed,
             TransportError.writeFailed, ConnectionError.closed, is CancellationError:
            error
        default:
            nil
        }
    }

    /// Whether a result to the probe is a `DiscoverResult`: it has at least one of the two members that type
    /// requires. A result with neither answers something else, so it says nothing about the era (ADR-0005).
    static func isDiscoverResult(_ result: JSONValue) -> Bool {
        result["supportedVersions"]?.arrayValue != nil || result["capabilities"]?.members != nil
    }

    private static func notDiscoverResultRemark(_ result: JSONValue) -> String {
        var remark = "server/discover answered with a result that is not a DiscoverResult (it has neither supportedVersions nor capabilities); treated as a legacy server."
        // Some servers answer unknown methods as if a tool call had failed, instead of with a JSON-RPC error.
        if result["isError"]?.boolValue == true {
            let text = result["content"]?.arrayValue?.compactMap { $0["text"]?.stringValue }.joined(separator: " ") ?? ""
            remark += " The result is shaped like a failed tool call (isError)"
            remark += text.isEmpty ? "." : ", saying “\(text.prefix(300))”."
            remark += " An unknown method should get a JSON-RPC error, such as -32601."
        }
        return remark
    }

    private static func discoverModern(_ result: JSONValue, over connection: MCPConnection, observations: [String]) async throws -> DiscoveryResult {
        var observations = observations
        observations.append("Answered server/discover: a modern server.")
        if let supported = result["supportedVersions"]?.arrayValue?.compactMap(\.stringValue) {
            observations.append("Supported versions: \(supported.joined(separator: ", ")).")
            if !supported.contains(modernVersion) {
                observations.append("\(modernVersion) is not among them, although the server accepted it.")
            }
        } else {
            observations.append("The result has no supportedVersions list, which is required.")
        }
        checkResultType(result, method: "server/discover", into: &observations)
        let capabilities = result["capabilities"]
        if capabilities?.members == nil {
            observations.append("The result has no capabilities object, which is required.")
        }
        let toolsAdvertised = capabilities?["tools"] != nil
        let tools = toolsAdvertised
            ? try await listTools(over: connection, era: .modern, observations: &observations)
            : []
        return DiscoveryResult(
            era: .modern,
            protocolVersion: modernVersion,
            serverInfo: result["_meta"]?["io.modelcontextprotocol/serverInfo"],
            capabilities: capabilities,
            instructions: result["instructions"]?.stringValue,
            handshake: result,
            toolsAdvertised: toolsAdvertised,
            tools: tools,
            observations: unique(observations))
    }

    private static func discoverLegacy(over connection: MCPConnection, observations: [String]) async throws -> DiscoveryResult {
        var observations = observations
        await connection.setProtocolHeaders(version: nil, namesMethod: false)
        let params: JSONValue = [
            "protocolVersion": .string(legacyVersion),
            "capabilities": [:],
            "clientInfo": clientInfo,
        ]
        let outcome = try await connection.request("initialize", params: params, timeout: requestTimeout)
        let result: JSONValue
        switch outcome {
        case .result(let value): result = value
        case .error(let error): throw DiscoveryError.rejected(method: "initialize", error)
        }
        guard let version = result["protocolVersion"]?.stringValue else {
            throw DiscoveryError.invalidResult(method: "initialize", problem: "no protocolVersion")
        }
        if !knownLegacyVersions.contains(version) {
            observations.append("The server chose protocol version \(version), which this client does not know; continuing anyway.")
        }
        await connection.setProtocolHeaders(version: version, namesMethod: false)
        try await connection.notify("notifications/initialized")

        let capabilities = result["capabilities"]
        let toolsAdvertised = capabilities?["tools"] != nil
        let tools = toolsAdvertised
            ? try await listTools(over: connection, era: .legacy, observations: &observations)
            : []
        return DiscoveryResult(
            era: .legacy,
            protocolVersion: version,
            serverInfo: result["serverInfo"],
            capabilities: capabilities,
            instructions: result["instructions"]?.stringValue,
            handshake: result,
            toolsAdvertised: toolsAdvertised,
            tools: tools,
            observations: unique(observations))
    }

    /// The same remark can come up once per page; it is worth reading once.
    private static func unique(_ observations: [String]) -> [String] {
        var seen: Set<String> = []
        return observations.filter { seen.insert($0).inserted }
    }

    private static func listTools(over connection: MCPConnection, era: ProtocolEra, observations: inout [String]) async throws -> [ToolInfo] {
        var tools: [ToolInfo] = []
        var cursor: String?
        var seenCursors: Set<String> = []
        var pages = 0
        while true {
            pages += 1
            let cursorMember = cursor.map { [JSONMember(key: "cursor", value: .string($0))] } ?? []
            let params: JSONValue? = switch era {
            case .modern: modernParams(cursorMember)
            case .legacy: cursorMember.isEmpty ? nil : .object(cursorMember)
            }
            let outcome = try await connection.request("tools/list", params: params, timeout: requestTimeout)
            let result: JSONValue
            switch outcome {
            case .result(let value): result = value
            case .error(let error): throw DiscoveryError.rejected(method: "tools/list", error)
            }
            if era == .modern { checkResultType(result, method: "tools/list", into: &observations) }
            guard let page = result["tools"]?.arrayValue else {
                throw DiscoveryError.invalidResult(method: "tools/list", problem: "no tools array")
            }
            for raw in page {
                tools.append(ToolInfo(raw: raw, position: tools.count))
            }
            guard let next = result["nextCursor"] else { break }
            guard let nextCursor = next.stringValue else {
                observations.append("nextCursor is \(next.kindName), not a string; stopped paging.")
                break
            }
            guard seenCursors.insert(nextCursor).inserted else {
                observations.append("The server repeated cursor “\(nextCursor)”; stopped paging.")
                break
            }
            guard pages < maxPages else {
                observations.append("Stopped after \(maxPages) pages of tools.")
                break
            }
            cursor = nextCursor
        }
        if pages > 1 { observations.append("Tools came in \(pages) pages.") }
        var counts: [String: Int] = [:]
        for tool in tools { counts[tool.name, default: 0] += 1 }
        let duplicates = counts.filter { $0.value > 1 }.keys.sorted()
        if !duplicates.isEmpty {
            observations.append("Tool names used more than once: \(duplicates.joined(separator: ", ")).")
        }
        return tools
    }

    private static func checkResultType(_ result: JSONValue, method: String, into observations: inout [String]) {
        switch result["resultType"]?.stringValue {
        case nil:
            observations.append("The result of \(method) has no resultType, which modern servers must send; taken as complete.")
        case "complete":
            break
        case let other?:
            observations.append("The result of \(method) has resultType “\(other)”, which list results may not have.")
        }
    }
}
