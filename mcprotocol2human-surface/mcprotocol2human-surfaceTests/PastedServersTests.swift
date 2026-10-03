import Foundation
import Testing
@testable import mcprotocol2human_surface

struct PastedServersTests {
    func names(_ text: String) throws -> [String] {
        try PastedServers(text: text).entries.map(\.config.name)
    }

    @Test func wholeFileKeepsUnknownFieldsAndNotesOtherMembers() throws {
        let pasted = try PastedServers(text: #"""
        {
          "mcpServers": {
            "local": { "command": "uv", "args": ["run", "server"], "env": { "TOKEN": "x" }, "timeout": 30 },
            "remote": { "type": "http", "url": "http://127.0.0.1:9000/mcp" }
          },
          "globalShortcut": "Ctrl+Space"
        }
        """#)
        #expect(pasted.shape == .file)
        #expect(pasted.entries.map(\.config.name) == ["local", "remote"])
        #expect(pasted.entries.allSatisfy { $0.nameWasGiven })
        #expect(pasted.entries[0].config.environment.map(\.key) == ["TOKEN"])
        #expect(pasted.entries[0].config.extra.map(\.key) == ["timeout"])
        #expect(pasted.entries[1].config.kind == .http)
        #expect(pasted.notes == ["Not server entries, so not taken over: “globalShortcut”."])
    }

    @Test func vsCodeServersKey() throws {
        let pasted = try PastedServers(text: #"{"servers": {"weather": {"type": "stdio", "command": "weather-mcp"}}, "inputs": []}"#)
        #expect(pasted.shape == .vsCodeFile)
        #expect(pasted.entries.map(\.config.name) == ["weather"])
        #expect(pasted.notes.count == 1)
    }

    @Test func innerMapAndFragments() throws {
        let entry = #"{"command": "example-mcp"}"#
        #expect(try names(#"{"a": \#(entry), "b": \#(entry)}"#) == ["a", "b"])
        #expect(try names(#""a": \#(entry)"#) == ["a"], "a fragment copied out of a file")
        #expect(try names(#""a": \#(entry),"#) == ["a"], "with the comma that followed it")
        #expect(try names(#""a": \#(entry), "b": \#(entry),"#) == ["a", "b"])
    }

    @Test func singleEntryGetsDerivedName() throws {
        let pasted = try PastedServers(text: #"{"type": "http", "url": "https://mcp.example.com/mcp"}"#)
        #expect(pasted.shape == .singleEntry)
        #expect(pasted.entries.map(\.config.name) == ["example.com"])
        #expect(pasted.entries.first?.nameWasGiven == false)
    }

    @Test func entriesThatAreNotEntriesAreLeftOutWithANote() throws {
        let pasted = try PastedServers(text: #"{"a": {"command": "x"}, "b": "text", "c": {"enabled": true}}"#)
        #expect(pasted.entries.map(\.config.name) == ["a"])
        #expect(pasted.notes == ["“b” is string, not a server entry.", "“c” has neither a command nor a url."])
    }

    @Test func unusableTextIsAnError() {
        #expect(throws: PasteError.empty) { try PastedServers(text: "  \n") }
        #expect(throws: PasteError.noEntries) { try PastedServers(text: "{}") }
        #expect(throws: PasteError.noEntries) { try PastedServers(text: #"{"mcpServers": {}}"#) }
        #expect(throws: PasteError.notObject("the text holds an array, not an object.")) { try PastedServers(text: "[1]") }
        #expect(throws: PasteError.notObject("mcpServers is array, not an object.")) { try PastedServers(text: #"{"mcpServers": []}"#) }
        #expect {
            try PastedServers(text: #"{"a": {"command": "x"}"#)
        } throws: { error in
            if case PasteError.notJSON = error { return true }
            return false
        }
    }

    @Test(arguments: [
        ("npx", ["-y", "@example/server-files@1.2.0", "/Users/someone/Desktop"], "server-files"),
        ("uvx", ["example-mcp-server==0.3"], "example-mcp-server"),
        ("uv", ["run", "--project", "/path/to/project", "example-tools-mcp"], "example-tools-mcp"),
        ("docker", ["run", "-i", "--rm", "-e", "EXAMPLE_TOKEN", "ghcr.io/example/example-mcp:latest"], "example-mcp"),
        ("xcrun", ["mcpbridge"], "mcpbridge"),
        ("/opt/tools/bin/example-server", ["--verbose"], "example-server"),
        ("node", ["/path/to/server.js"], "node"),
    ])
    func derivedNameFromCommand(command: String, arguments: [String], expected: String) {
        var config = ServerConfig(name: "")
        config.command = command
        config.arguments = arguments
        #expect(PastedServers.derivedName(for: config) == expected)
    }

    @Test(arguments: [
        ("https://mcp.example.com/mcp", "example.com"),
        ("https://www.api.example.co/v1/mcp", "example.co"),
        ("http://127.0.0.1:8000/mcp", "localhost-8000"),
        ("http://localhost/mcp", "localhost"),
        ("not a url", "new-server"),
    ])
    func derivedNameFromURL(url: String, expected: String) {
        var config = ServerConfig(name: "", kind: .http)
        config.url = url
        #expect(PastedServers.derivedName(for: config) == expected)
    }

    func entry(_ name: String, replace: Bool = false) -> PastedServers.Entry {
        var config = ServerConfig(name: name)
        config.command = "example-mcp"
        return PastedServers.Entry(config: config, originalName: name, nameWasGiven: true, replace: replace)
    }

    @Test func takenNamesAreRenamedUnlessReplacing() {
        let existing = [ServerConfig(name: "a"), ServerConfig(name: "b"), ServerConfig(name: "b-2")]
        let outcomes = PastedServers.plan(
            [entry("a", replace: true), entry("b"), entry("c"), entry("c"), entry("a", replace: true), entry("d", replace: true)],
            existing: existing)
        #expect(outcomes.map(\.name) == ["a", "b-3", "c", "c-2", "a-2", "d"])
        #expect(outcomes.map(\.replaces) == [existing[0].id, nil, nil, nil, nil, nil])
        #expect(outcomes.map(\.canReplace) == [true, true, false, false, false, false],
                "only the first entry with a taken name may replace; replacing a name nobody has adds")
    }

    @Test func onlyTheFirstEntryWithANameDecidesAboutReplacing() {
        let existing = [ServerConfig(name: "a")]
        let outcomes = PastedServers.plan([entry("a"), entry("a", replace: true)], existing: existing)
        #expect(outcomes.map(\.name) == ["a-2", "a-3"])
        #expect(outcomes.allSatisfy { $0.replaces == nil })
    }

    @Test @MainActor func storeAddsAfterSelectionAndReplacesInPlace() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "m2h-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ServerStore(fileURL: url)
        let first = store.add()
        store.add(after: first)
        guard let second = store.servers.last else { Issue.record("no server"); return }
        var replacement = entry(second.name, replace: true)
        replacement.config.url = "changed"
        let ids = store.add([entry("x"), replacement, entry("y")], after: first)
        #expect(store.servers.map(\.name) == ["new-server", "x", "y", "new-server-2"])
        #expect(store.servers[3].id == ids[1] && ids[1] != second.id, "the replacement has its own id")
        #expect(store.servers.last?.url == "changed")
        store.flush()
        #expect(try ServerFile(data: Data(contentsOf: url)).servers.count == 4)
    }

    @Test @MainActor func addingTheSameEntriesTwiceKeepsIdsUnique() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "m2h-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ServerStore(fileURL: url)
        let entries = [entry("x"), entry("y")]
        store.add(entries, after: nil)
        store.add(entries, after: nil)
        #expect(store.servers.map(\.name) == ["x", "y", "x-2", "y-2"])
        #expect(Set(store.servers.map(\.id)).count == 4)
    }
}
