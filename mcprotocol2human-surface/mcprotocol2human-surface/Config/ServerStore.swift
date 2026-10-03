import Foundation
import Observation
import os

/// The list of servers, read from and written to the servers file (ADR-0007).
///
/// Edits are written back shortly after they happen. If the file could not be read, nothing is written,
/// so a file with a typo is never replaced by an empty list.
@Observable
final class ServerStore {
    private(set) var servers: [ServerConfig] = []
    /// Why the file could not be read; while set, saving is off.
    private(set) var loadError: String?
    private(set) var saveError: String?
    let fileURL: URL

    @ObservationIgnored private var fileExtra: [JSONMember] = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var savePending = false

    /// `M2H_SERVERS_FILE` if set, else `~/Library/Application Support/<bundle id>/servers.json`.
    static var defaultFileURL: URL {
        if let path = ProcessInfo.processInfo.environment["M2H_SERVERS_FILE"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        let support = URL.applicationSupportDirectory
        return support.appending(path: Log.subsystem, directoryHint: .isDirectory).appending(path: "servers.json")
    }

    init(fileURL: URL = ServerStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    func load() {
        saveTask?.cancel()
        savePending = false
        saveError = nil
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            servers = []
            fileExtra = []
            loadError = nil
            return
        }
        do {
            let file = try ServerFile(data: Data(contentsOf: fileURL))
            servers = file.servers
            fileExtra = file.extra
            loadError = nil
            Log.config.info("Loaded \(file.servers.count) servers from \(self.fileURL.path, privacy: .public)")
        } catch {
            servers = []
            fileExtra = []
            loadError = error.localizedDescription
            Log.config.error("Could not read \(self.fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func server(id: ServerConfig.ID) -> ServerConfig? {
        servers.first { $0.id == id }
    }

    func server(named name: String) -> ServerConfig? {
        servers.first { $0.name == name }
    }

    func update(_ server: ServerConfig) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }), servers[index] != server else { return }
        servers[index] = server
        scheduleSave()
    }

    @discardableResult
    func add(after id: ServerConfig.ID? = nil) -> ServerConfig.ID {
        let server = ServerConfig(name: uniqueName("new-server"))
        insert(server, after: id)
        return server.id
    }

    @discardableResult
    func duplicate(_ id: ServerConfig.ID) -> ServerConfig.ID? {
        guard var copy = server(id: id) else { return nil }
        copy.id = UUID()
        copy.name = uniqueName(copy.name + "-copy")
        insert(copy, after: id)
        return copy.id
    }

    /// Adds pasted entries after `id`, as `PastedServers.plan` says: under a free name, or at the position of
    /// the server they replace. A replacement has its own id, so an editor showing the old server starts
    /// afresh rather than keeping state read from it. Returns the entries' ids in order.
    @discardableResult
    func add(_ entries: [PastedServers.Entry], after id: ServerConfig.ID?) -> [ServerConfig.ID] {
        let outcomes = PastedServers.plan(entries, existing: servers)
        var position = id.flatMap { id in servers.firstIndex { $0.id == id } }.map { $0 + 1 } ?? servers.endIndex
        var ids: [ServerConfig.ID] = []
        for (entry, outcome) in zip(entries, outcomes) {
            var config = entry.config
            config.name = outcome.name
            // Ids are unique in the list, whatever the caller passes, such as the same entries twice.
            if servers.contains(where: { $0.id == config.id }) { config.id = UUID() }
            if let target = outcome.replaces, let index = servers.firstIndex(where: { $0.id == target }) {
                servers[index] = config
            } else {
                servers.insert(config, at: position)
                position += 1
            }
            ids.append(config.id)
        }
        if !ids.isEmpty { scheduleSave() }
        return ids
    }

    func remove(_ id: ServerConfig.ID) {
        servers.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Why the list cannot be saved as it is, if it cannot.
    var validationProblem: String? {
        if servers.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return "Every server needs a name."
        }
        var seen: Set<String> = []
        for server in servers where !seen.insert(server.name).inserted {
            return "The name “\(server.name)” is used twice."
        }
        return nil
    }

    func problem(for server: ServerConfig) -> String? {
        if server.name.trimmingCharacters(in: .whitespaces).isEmpty { return "Needs a name." }
        if servers.filter({ $0.name == server.name }).count > 1 { return "Another server has this name." }
        return nil
    }

    // MARK: -

    private func insert(_ server: ServerConfig, after id: ServerConfig.ID?) {
        if let id, let index = servers.firstIndex(where: { $0.id == id }) {
            servers.insert(server, at: index + 1)
        } else {
            servers.append(server)
        }
        scheduleSave()
    }

    private func uniqueName(_ base: String) -> String {
        Self.uniqueName(base, avoiding: Set(servers.map(\.name)))
    }

    /// `base`, or the first of `base-2`, `base-3`, … that is not among `names`.
    nonisolated static func uniqueName(_ base: String, avoiding names: Set<String>) -> String {
        guard names.contains(base) else { return base }
        var number = 2
        while names.contains("\(base)-\(number)") { number += 1 }
        return "\(base)-\(number)"
    }

    private func scheduleSave() {
        savePending = true
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    /// Writes an edit that is still waiting for its delayed save, such as when the app quits.
    func flush() {
        guard savePending else { return }
        saveTask?.cancel()
        save()
    }

    /// Writes the file now, unless reading it failed or the list has a problem.
    func save() {
        savePending = false
        guard loadError == nil else { return }
        if let problem = validationProblem {
            saveError = "Not saved: \(problem)"
            return
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ServerFile(servers: servers, extra: fileExtra).data.write(to: fileURL, options: .atomic)
            saveError = nil
        } catch {
            saveError = "Not saved: \(error.localizedDescription)"
            Log.config.error("Could not write \(self.fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
