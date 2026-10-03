import Foundation
import Testing
@testable import mcprotocol2human_surface

struct ServerConfigTests {
    let sample = #"""
    {
      "mcpServers": {
        "local": { "command": "uv", "args": ["run", "server"], "env": { "TOKEN": "x" }, "timeout": 30 },
        "remote": { "type": "streamable-http", "url": "http://127.0.0.1:9000/mcp", "headers": { "A": "b" } },
        "old": { "type": "sse", "url": "http://127.0.0.1:9001/sse" }
      },
      "other": [1, 2]
    }
    """#

    @Test func readsEntriesInFileOrder() throws {
        let file = try ServerFile(data: Data(sample.utf8))
        #expect(file.servers.map(\.name) == ["local", "remote", "old"])
        let local = file.servers[0]
        #expect(local.kind == .stdio)
        #expect(local.typeName == nil)
        #expect(local.arguments == ["run", "server"])
        #expect(local.environment.map(\.key) == ["TOKEN"])
        #expect(local.extra.map(\.key) == ["timeout"])
        #expect(file.servers[1].kind == .http)
        #expect(file.servers[1].headers.first?.value == "b")
        #expect(file.servers[2].kind == .unsupported("sse"))
    }

    @Test func roundTripKeepsUnknownFieldsAndTypeSpelling() throws {
        let file = try ServerFile(data: Data(sample.utf8))
        let again = try ServerFile(data: file.data)
        #expect(again.servers.map(\.entry) == file.servers.map(\.entry))
        #expect(again.extra.map(\.key) == ["other"])
        let text = String(decoding: file.data, as: UTF8.self)
        #expect(text.contains("\"streamable-http\""))
        #expect(text.contains("\"timeout\": 30"))
        #expect(!text.contains("\"type\": \"stdio\""), "an absent type stays absent while it is implied")
    }

    @Test func switchingTransportWritesCanonicalType() {
        var server = ServerConfig(name: "x", entry: ["command": "tool"])
        server.kind = .http
        server.url = "http://localhost:1/mcp"
        #expect(server.entry["type"] == .string("http"))
        #expect(server.entry["command"] == nil)
    }

    @Test func rejectsNonObjectFile() {
        #expect(throws: (any Error).self) { try ServerFile(data: Data("[]".utf8)) }
        #expect(throws: (any Error).self) { try ServerFile(data: Data(#"{"mcpServers": []}"#.utf8)) }
    }
}

@MainActor
struct ServerStoreTests {
    @Test func doesNotOverwriteAFileItCouldNotRead() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "m2h-\(UUID().uuidString).json")
        try Data("{ not json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ServerStore(fileURL: url)
        #expect(store.loadError != nil)
        store.save()
        #expect(try String(contentsOf: url, encoding: .utf8) == "{ not json")
    }

    @Test func refusesDuplicateNames() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "m2h-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ServerStore(fileURL: url)
        let first = store.add()
        let second = store.add()
        guard var renamed = store.server(id: second) else { Issue.record("no server"); return }
        renamed.name = store.server(id: first)?.name ?? ""
        store.update(renamed)
        store.save()
        #expect(store.saveError != nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
