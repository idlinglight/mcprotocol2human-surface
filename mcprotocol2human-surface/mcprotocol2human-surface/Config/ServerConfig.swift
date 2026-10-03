import Foundation

/// A name and value pair, for environment variables and HTTP headers. The id is for SwiftUI lists only.
nonisolated struct KeyValue: Identifiable, Hashable, Sendable {
    var id = UUID()
    var key: String
    var value: String
}

nonisolated enum TransportKind: Hashable, Sendable {
    case stdio
    case http
    /// A `type` this app does not speak, such as the deprecated `sse`.
    case unsupported(String)
}

/// One entry of the `mcpServers` object (ADR-0007).
///
/// Fields for both transports are kept, so switching the transport in Settings and back loses nothing
/// until the file is written. Members the app does not use are kept in `extra` and written back.
nonisolated struct ServerConfig: Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var kind: TransportKind = .stdio
    /// The `type` as written in the file, kept so a round trip does not change its spelling; nil if absent.
    var typeName: String?
    var command = ""
    var arguments: [String] = []
    var environment: [KeyValue] = []
    var url = ""
    var headers: [KeyValue] = []
    var extra: [JSONMember] = []

    init(name: String, kind: TransportKind = .stdio) {
        self.name = name
        self.kind = kind
    }

    init(name: String, entry: JSONValue) {
        self.name = name
        let known: Set<String> = ["type", "command", "args", "env", "url", "headers"]
        extra = entry.members?.filter { !known.contains($0.key) } ?? []
        command = entry["command"]?.stringValue ?? ""
        arguments = entry["args"]?.arrayValue?.map { $0.stringValue ?? $0.compactText } ?? []
        environment = Self.pairs(entry["env"])
        url = entry["url"]?.stringValue ?? ""
        headers = Self.pairs(entry["headers"])
        typeName = entry["type"]?.stringValue
        switch typeName?.lowercased() {
        case "stdio": kind = .stdio
        case "http", "streamable-http", "streamablehttp", "streamable_http": kind = .http
        case let other?: kind = .unsupported(other)
        case nil: kind = entry["url"] != nil && entry["command"] == nil ? .http : .stdio
        }
    }

    /// The entry as written to the file.
    var entry: JSONValue {
        var members: [JSONMember] = []
        let canonicalType: String? = switch kind {
        case .stdio: "stdio"
        case .http: "http"
        case .unsupported(let type): type
        }
        // Keep the original spelling, or its absence, while it still says the same thing.
        if let typeName, ServerConfig(name: "", entry: ["type": .string(typeName)]).kind == kind {
            members.append(JSONMember(key: "type", value: .string(typeName)))
        } else if typeName != nil || kind != inferredKind {
            members.append(JSONMember(key: "type", value: .string(canonicalType ?? "stdio")))
        }
        switch kind {
        case .stdio:
            members.append(JSONMember(key: "command", value: .string(command)))
            members.append(JSONMember(key: "args", value: .array(arguments.map(JSONValue.string))))
            if !environment.isEmpty { members.append(JSONMember(key: "env", value: Self.object(environment))) }
        case .http:
            members.append(JSONMember(key: "url", value: .string(url)))
            if !headers.isEmpty { members.append(JSONMember(key: "headers", value: Self.object(headers))) }
        case .unsupported:
            if !command.isEmpty { members.append(JSONMember(key: "command", value: .string(command))) }
            if !arguments.isEmpty { members.append(JSONMember(key: "args", value: .array(arguments.map(JSONValue.string)))) }
            if !url.isEmpty { members.append(JSONMember(key: "url", value: .string(url))) }
            if !environment.isEmpty { members.append(JSONMember(key: "env", value: Self.object(environment))) }
            if !headers.isEmpty { members.append(JSONMember(key: "headers", value: Self.object(headers))) }
        }
        return .object(members + extra)
    }

    /// What a missing `type` would be read as.
    private var inferredKind: TransportKind {
        !url.isEmpty && command.isEmpty ? .http : .stdio
    }

    /// One line for lists: the command line or the URL.
    var summary: String {
        switch kind {
        case .stdio: ([command] + arguments).joined(separator: " ")
        case .http: url
        case .unsupported(let type): "unsupported transport “\(type)”"
        }
    }

    var kindLabel: String {
        switch kind {
        case .stdio: "stdio"
        case .http: "HTTP"
        case .unsupported(let type): type
        }
    }

    private static func pairs(_ value: JSONValue?) -> [KeyValue] {
        value?.members?.map { KeyValue(key: $0.key, value: $0.value.stringValue ?? $0.value.compactText) } ?? []
    }

    private static func object(_ pairs: [KeyValue]) -> JSONValue {
        .object(pairs.map { JSONMember(key: $0.key, value: .string($0.value)) })
    }
}

/// The servers file: `{"mcpServers": {name: entry, …}}`, other top-level members kept as they are.
nonisolated struct ServerFile: Sendable {
    var servers: [ServerConfig] = []
    var extra: [JSONMember] = []

    init(servers: [ServerConfig] = [], extra: [JSONMember] = []) {
        self.servers = servers
        self.extra = extra
    }

    init(data: Data) throws {
        let root = try JSONValue.parse(data)
        guard let members = root.members else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "The file holds \(root.kindName), not an object."])
        }
        extra = members.filter { $0.key != "mcpServers" }
        guard let servers = root["mcpServers"] else { return }
        guard let entries = servers.members else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "mcpServers is \(servers.kindName), not an object."])
        }
        self.servers = entries.map { ServerConfig(name: $0.key, entry: $0.value) }
    }

    var data: Data {
        let servers = JSONValue.object(servers.map { JSONMember(key: $0.name, value: $0.entry) })
        let root = JSONValue.object([JSONMember(key: "mcpServers", value: servers)] + extra)
        return Data((root.prettyText + "\n").utf8)
    }
}
