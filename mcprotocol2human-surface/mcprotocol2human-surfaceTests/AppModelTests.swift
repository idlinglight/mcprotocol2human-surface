import Foundation
import Testing
@testable import mcprotocol2human_surface

/// Runs against a slow fake stdio server: it waits a second before each answer.
@MainActor
struct AppModelTests {
    static let slowServer = #"""
    #!/bin/zsh
    while IFS= read -r line; do
      sleep 1
      id=${${line#*\"id\":}%%,*}
      case $line in
        *'"method":"server/discover"'*)
          print -r -- '{"jsonrpc":"2.0","id":'$id',"error":{"code":-32601,"message":"Method not found"}}' ;;
        *'"method":"initialize"'*)
          print -r -- '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"slow","version":"0.1"}}}' ;;
        *'"method":"tools/list"'*)
          print -r -- '{"jsonrpc":"2.0","id":'$id',"result":{"tools":[{"name":"one","inputSchema":{"type":"object"}}]}}' ;;
      esac
    done
    """#

    let directory = FileManager.default.temporaryDirectory.appending(path: "m2h-model-\(UUID().uuidString)")

    func makeModel() throws -> (AppModel, ServerConfig.ID) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appending(path: "slow.zsh")
        try Data(Self.slowServer.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let store = ServerStore(fileURL: directory.appending(path: "servers.json"))
        let id = store.add()
        var server = try #require(store.server(id: id))
        server.name = "slow"
        server.command = script.path
        store.update(server)
        return (AppModel(store: store), id)
    }

    func waitUntil(_ limit: Duration = .seconds(15), _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + limit
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    @Test func runOfARemovedServerLeavesNoResult() async throws {
        let (model, id) = try makeModel()
        defer { try? FileManager.default.removeItem(at: directory) }
        model.refresh("slow")
        #expect(model.isRunning("slow"))
        model.store.remove(id)
        model.pruneToStore()
        #expect(!model.isRunning("slow"))
        // Long enough for the cancelled run to wind down and, before the fix, write its result.
        try await Task.sleep(for: .seconds(4))
        #expect(model.run(for: "slow") == nil)
    }

    @Test func refreshDuringARunReplacesIt() async throws {
        let (model, _) = try makeModel()
        defer { try? FileManager.default.removeItem(at: directory) }
        model.refresh("slow")
        try await Task.sleep(for: .milliseconds(300))
        model.refresh("slow")
        await waitUntil { model.run(for: "slow") != nil && !model.isRunning("slow") }
        let run = try #require(model.run(for: "slow"))
        #expect(run.result?.tools.map(\.name) == ["one"])
        #expect(!run.traffic.contains { $0.text == "Cancelled." }, "the stored run is the second one")
    }
}

struct CancellationTests {
    @Test func cancellingARunEndsItPromptly() async throws {
        let script = FileManager.default.temporaryDirectory.appending(path: "m2h-silent-\(UUID().uuidString).zsh")
        try Data("#!/bin/zsh\ncat > /dev/null\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: script) }
        var config = ServerConfig(name: "silent")
        config.command = script.path
        let task = Task { try await Discovery.run(config, traffic: TrafficLog()) }
        try await Task.sleep(for: .milliseconds(500))
        let cancelled = ContinuousClock.now
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(ContinuousClock.now - cancelled < .seconds(5), "not the 20 s probe timeout")
    }
}
