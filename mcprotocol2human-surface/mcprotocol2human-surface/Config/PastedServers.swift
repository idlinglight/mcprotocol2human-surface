import Foundation

nonisolated enum PasteError: Error, LocalizedError, Equatable, Sendable {
    case empty
    case notJSON(String)
    case notObject(String)
    case noEntries

    var errorDescription: String? {
        switch self {
        case .empty: "Nothing to add yet."
        case .notJSON(let reason): "Not JSON: \(reason)"
        case .notObject(let problem): "Not server entries: \(problem)"
        case .noEntries: "No server entries found."
        }
    }
}

/// Server entries pasted into Settings as JSON (ADR-0007), in the shapes configuration snippets come in:
/// a whole file (`mcpServers`, or VS Code's `servers`), the map of names to entries inside it, a single
/// entry without a name, or a `"name": {…}` fragment copied out of a larger file.
nonisolated struct PastedServers: Sendable {
    /// One entry found in the text, with what the user chose for it in the sheet.
    struct Entry: Identifiable, Sendable, Hashable {
        var config: ServerConfig
        /// The name the entry came with, or the one derived for it; tells a re-parsed entry from a new one.
        var originalName: String
        /// False when the text gave no name and it was derived from the command or URL.
        var nameWasGiven: Bool
        /// Whether to replace the existing server of the same name, rather than add this one renamed.
        var replace = false

        var id: ServerConfig.ID { config.id }
    }

    /// What adding an entry would do: its final name, and the server it takes the place of, if any.
    struct Outcome: Equatable, Sendable {
        var name: String
        var replaces: ServerConfig.ID?
        /// Whether the entry may replace the existing server of its name, which the sheet then offers.
        var canReplace = false
    }

    /// What the text was taken for; the raw value says it in words.
    enum Shape: String, Sendable {
        case file = "a servers file"
        case vsCodeFile = "a VS Code servers file"
        case entriesByName = "entries by name"
        case singleEntry = "a single entry"
    }

    var entries: [Entry] = []
    /// What was left out of the text, and why.
    var notes: [String] = []
    var shape = Shape.entriesByName

    init(text: String) throws(PasteError) {
        let root = try Self.parseLeniently(text)
        guard let members = root.members else {
            throw .notObject("the text holds \(root.kindName == "array" ? "an" : "a") \(root.kindName), not an object.")
        }
        var named: [JSONMember] = []
        var otherKeys: [String] = []
        if let servers = root["mcpServers"] {
            guard let inner = servers.members else { throw .notObject("mcpServers is \(servers.kindName), not an object.") }
            named = inner
            otherKeys = members.map(\.key).filter { $0 != "mcpServers" }
            shape = .file
        } else if let servers = root["servers"], let inner = servers.members, inner.allSatisfy({ $0.value.members != nil }) {
            named = inner
            otherKeys = members.map(\.key).filter { $0 != "servers" }
            shape = .vsCodeFile
        } else if Self.isEntry(root) {
            add(ServerConfig(name: "", entry: root), name: nil)
            shape = .singleEntry
        } else {
            named = members
        }
        if !otherKeys.isEmpty {
            notes.append("Not server entries, so not taken over: \(otherKeys.map { "“\($0)”" }.joined(separator: ", ")).")
        }
        for member in named {
            if member.value.members == nil {
                notes.append("“\(member.key)” is \(member.value.kindName), not a server entry.")
            } else if !Self.isEntry(member.value) {
                notes.append("“\(member.key)” has neither a command nor a url.")
            } else {
                let name = member.key.trimmingCharacters(in: .whitespaces)
                add(ServerConfig(name: name, entry: member.value), name: name.isEmpty ? nil : name)
            }
        }
        if entries.isEmpty && notes.isEmpty { throw .noEntries }
    }

    private mutating func add(_ config: ServerConfig, name: String?) {
        var config = config
        config.name = name ?? Self.derivedName(for: config)
        entries.append(Entry(config: config, originalName: config.name, nameWasGiven: name != nil))
    }

    /// Parses the text as JSON, or, failing that, as a fragment of an object: `"name": {…}`, with or without a
    /// trailing comma, as copied out of a larger file.
    private static func parseLeniently(_ text: String) throws(PasteError) -> JSONValue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        do {
            return try JSONValue.parse(trimmed)
        } catch {
            var fragment = Substring(trimmed)
            if fragment.last == "," { fragment = fragment.dropLast() }
            if trimmed.first == "\"", let object = try? JSONValue.parse("{\(fragment)}") {
                return object
            }
            throw .notJSON(error.localizedDescription)
        }
    }

    /// An entry has a command or a URL; an object with neither is something else, such as a map of entries.
    private static func isEntry(_ value: JSONValue) -> Bool {
        value["command"] != nil || value["url"] != nil
    }

    // MARK: Names

    /// A name for an entry that came without one: from the URL's host, or from the command, or the package
    /// a launcher such as `npx` or `uvx` runs. Only a suggestion; the sheet lets the user change it.
    static func derivedName(for config: ServerConfig) -> String {
        let name = config.kind == .http || config.command.isEmpty
            ? name(fromURL: config.url)
            : name(fromCommand: config.command, arguments: config.arguments)
        return name.flatMap { $0.isEmpty ? nil : $0 } ?? "new-server"
    }

    private static func name(fromURL text: String) -> String? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)),
              let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty
        else { return nil }
        if ["localhost", "127.0.0.1", "::1", "0.0.0.0"].contains(host) {
            return url.port.map { "localhost-\($0)" } ?? "localhost"
        }
        var parts = host.split(separator: ".")
        while parts.count > 2, ["www", "mcp", "api"].contains(parts[0]) { parts.removeFirst() }
        return parts.joined(separator: ".")
    }

    /// Commands that run something else, named in their arguments.
    private static let launchers: Set<String> = [
        "npx", "npm", "pnpm", "pnpx", "yarn", "bun", "bunx", "deno", "node", "uv", "uvx", "pipx",
        "python", "python3", "docker", "podman", "xcrun", "env", "sh", "bash", "zsh", "java", "dotnet",
    ]
    private static let launcherSubcommands: Set<String> = ["run", "x", "exec", "dlx", "tool", "start"]

    private static func name(fromCommand command: String, arguments: [String]) -> String? {
        let commandName = (command.trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent
        if !commandName.isEmpty, !launchers.contains(commandName) { return commandName }
        let isVariableName = { (text: Substring) in
            text.contains(where: \.isLetter) && text.allSatisfy { $0.isUppercase || $0.isNumber || $0 == "_" }
        }
        for argument in arguments {
            if argument.hasPrefix("-") || launcherSubcommands.contains(argument) { continue }
            // Paths, and environment variables such as `-e TOKEN` or `TOKEN=x`.
            if argument.hasPrefix("/") || argument.hasPrefix("~") || argument.hasPrefix(".") { continue }
            if isVariableName(argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[0]) { continue }
            let name = packageName(argument)
            if !name.isEmpty { return name }
        }
        return commandName.isEmpty ? nil : commandName
    }

    /// `@scope/name@1.2` → `name`, `ghcr.io/org/image:tag` → `image`, `name==1.2` → `name`.
    private static func packageName(_ argument: String) -> String {
        var name = Substring(argument)
        if name.hasPrefix("@"), let slash = name.firstIndex(of: "/") { name = name[name.index(after: slash)...] }
        for separator: Character in ["@", "="] {
            if let index = name.firstIndex(of: separator) { name = name[..<index] }
        }
        if let slash = name.lastIndex(of: "/") { name = name[name.index(after: slash)...] }
        if let colon = name.firstIndex(of: ":") { name = name[..<colon] }
        return String(name)
    }

    /// What adding `entries` to `existing` would do, in order. A name that is taken, by a server that stays
    /// or by an entry before it, gets the next free suffix (`name-2`), unless the entry is to replace the
    /// existing server of that name. Only the first entry with a name may replace, so that one choice
    /// decides it. An empty name gets a derived one.
    static func plan(_ entries: [Entry], existing: [ServerConfig]) -> [Outcome] {
        var taken = Set(existing.map(\.name))
        var seen: Set<String> = []
        return entries.map { entry in
            let trimmed = entry.config.name.trimmingCharacters(in: .whitespaces)
            let base = trimmed.isEmpty ? derivedName(for: entry.config) : trimmed
            let target = seen.insert(base).inserted ? existing.first { $0.name == base } : nil
            if entry.replace, let target {
                return Outcome(name: base, replaces: target.id, canReplace: true)
            }
            let name = ServerStore.uniqueName(base, avoiding: taken)
            taken.insert(name)
            return Outcome(name: name, replaces: nil, canReplace: target != nil)
        }
    }
}
