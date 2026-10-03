import Foundation
import Observation
import os

/// The outcome of one discovery run, with everything recorded on the way.
nonisolated struct DiscoveryRun: Sendable {
    var config: ServerConfig
    var started: Date
    var finished: Date
    var outcome: Result<DiscoveryResult, DiscoveryFailure>
    var traffic: [TrafficEntry]

    var result: DiscoveryResult? { try? outcome.get() }

    var failure: DiscoveryFailure? {
        if case .failure(let failure) = outcome { return failure }
        return nil
    }

    var duration: Duration { .seconds(finished.timeIntervalSince(started)) }
}

nonisolated struct DiscoveryFailure: Error, Sendable {
    var message: String
}

/// What the main window shows for a server, besides its tools.
enum ServerPage: Hashable {
    case overview
    case traffic
    case tool(Int)
}

/// App state: the servers, which one is selected, and the latest discovery run per server.
@Observable
final class AppModel {
    let store: ServerStore
    var selectedServer: String? {
        didSet {
            guard selectedServer != oldValue else { return }
            // The overview is what a newly selected server shows, so the list says so too.
            selectedPage = selectedServer == nil ? nil : .overview
            if let selectedServer { refreshIfNeeded(selectedServer) }
        }
    }
    var selectedPage: ServerPage?
    /// Applies to whichever server is selected, so it stays put while switching between them.
    var toolFilter = ToolFilter()
    /// Bumped by ⌘F; the tool list moves focus to its filter field when it changes.
    var filterFocusRequests = 0
    /// The latest finished run per server name.
    private(set) var runs: [String: DiscoveryRun] = [:]
    private(set) var running: Set<String> = []

    /// The run in progress per server name. Its token tells a current run from one that was replaced or
    /// whose server went away; only the current one may store its result.
    @ObservationIgnored private var inFlight: [String: (token: UUID, task: Task<Void, Never>)] = [:]

    init(store: ServerStore) {
        self.store = store
    }

    var selectedConfig: ServerConfig? {
        selectedServer.flatMap(store.server(named:))
    }

    func run(for name: String) -> DiscoveryRun? { runs[name] }

    /// Whether the selected server has tools to filter; the filter field is shown only then.
    var canFilterTools: Bool {
        guard let selectedServer, let tools = runs[selectedServer]?.result?.tools else { return false }
        return !tools.isEmpty
    }

    func isRunning(_ name: String) -> Bool { running.contains(name) }

    func refreshIfNeeded(_ name: String) {
        guard runs[name] == nil, !running.contains(name) else { return }
        refresh(name)
    }

    /// Runs discovery for one server with its current settings. A run already going for it is cancelled and
    /// leaves no result.
    func refresh(_ name: String) {
        guard let config = store.server(named: name) else { return }
        inFlight[name]?.task.cancel()
        running.insert(name)
        let token = UUID()
        let traffic = TrafficLog()
        let started = Date.now
        Log.discovery.info("Discovery for \(name, privacy: .public) started")
        let task = Task {
            let outcome: Result<DiscoveryResult, DiscoveryFailure>
            do {
                outcome = .success(try await Discovery.run(config, traffic: traffic))
            } catch {
                outcome = .failure(DiscoveryFailure(message: error.localizedDescription))
            }
            guard inFlight[name]?.token == token else {
                Log.discovery.info("Discovery for \(name, privacy: .public) superseded")
                return
            }
            runs[name] = DiscoveryRun(config: config, started: started, finished: .now, outcome: outcome, traffic: traffic.entries)
            running.remove(name)
            inFlight[name] = nil
            Log.discovery.info("Discovery for \(name, privacy: .public) finished")
        }
        inFlight[name] = (token, task)
    }

    func refreshSelected() {
        if let selectedServer { refresh(selectedServer) }
    }

    func refreshAll() {
        for server in store.servers { refresh(server.name) }
    }

    /// Drops runs of servers that are no longer in the list, cancels their runs in progress, and clears the
    /// selection if its server is gone.
    func pruneToStore() {
        let names = Set(store.servers.map(\.name))
        for (name, run) in inFlight where !names.contains(name) {
            run.task.cancel()
            inFlight[name] = nil
            running.remove(name)
        }
        runs = runs.filter { names.contains($0.key) }
        if let selectedServer, !names.contains(selectedServer) { self.selectedServer = nil }
    }

    /// The model's state as text, for snapshots taken from a shell.
    var debugSummary: String {
        var lines = ["servers file: \(store.fileURL.path)", "servers: \(store.servers.map(\.name))",
                     "selected: \(selectedServer ?? "none"), page: \(selectedPage.map { "\($0)" } ?? "none")"]
        for (name, run) in runs.sorted(by: { $0.key < $1.key }) {
            switch run.outcome {
            case .success(let result):
                lines.append("\(name): \(result.era.rawValue) \(result.protocolVersion), \(result.tools.count) tools, \(run.traffic.count) traffic entries")
                lines += result.observations.map { "  - \($0)" }
            case .failure(let failure):
                lines.append("\(name): failed: \(failure.message)")
            }
        }
        if !running.isEmpty { lines.append("running: \(running.sorted())") }
        return lines.joined(separator: "\n")
    }
}
