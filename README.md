# mcprotocol2human-surface

A macOS app for looking at the surface of [Model Context Protocol](https://modelcontextprotocol.io) servers:
which tools a server exposes, and what each tool says about itself. Meant for people who build MCP servers
and want to see their tools the way a client does, without asking an agent or installing an inspector.

Personal tool, built locally, not distributed.

## What it does

- Keeps a list of servers, stdio or Streamable HTTP, edited in Settings (⌘,).
- Selecting a server connects to it, finds out which protocol revision it speaks, lists its tools and
  disconnects again. Refresh (⌘R) does it again; Refresh All (⇧⌘R) does it for every server.
- A filter above the tool list (⌘F, Escape clears it). The two buttons beside it show the setting in
  effect and switch it on click: a page searches names and descriptions, a crossed-out page names only
  (titles count as names); an equals sign shows the matching tools, a not-equals sign the others.
- For each tool: name and title, the four behaviour hints (set by the server, or the specification's
  default), the full description, parameters with type, required flag, default, allowed values and
  constraints (nested objects can be opened), the output schema, and the raw JSON.
- Notes what a tool leaves out: a missing description, parameters without description, a missing or odd
  input schema.
- For each server: what it said about itself (name, version, instructions, capabilities), the protocol
  version and era it was talked to in, how the client decided that, and the full traffic of the last run:
  every message sent and received, the server's stderr, and HTTP status lines.

It only reads. It never calls a tool.

## Servers file

`~/Library/Application Support/at.idling.mcprotocol2human-surface/servers.json`, in the `mcpServers` shape
other MCP hosts use, so entries can be pasted in from their configuration:

```json
{
  "mcpServers": {
    "example-stdio": { "type": "stdio", "command": "uv", "args": ["run", "example-server"] },
    "example-http": { "type": "http", "url": "http://127.0.0.1:8000/mcp", "headers": {} }
  }
}
```

Settings edits this file and shows where it is. Commands given by name are looked up in Homebrew,
`/usr/local/bin`, `~/.local/bin` and the system directories; anything elsewhere needs a full path. Set
`M2H_SERVERS_FILE` to use a different file.

## Requirements

- macOS 26, Xcode 27.
- No third-party dependencies.

## Build, run, test

Open `mcprotocol2human-surface/mcprotocol2human-surface.xcodeproj` in Xcode and run the
`mcprotocol2human-surface` scheme.

From a shell:

```sh
xcodebuild -project mcprotocol2human-surface/mcprotocol2human-surface.xcodeproj -scheme mcprotocol2human-surface -configuration Debug build
xcodebuild -project mcprotocol2human-surface/mcprotocol2human-surface.xcodeproj -scheme mcprotocol2human-surface -configuration Debug test -destination 'platform=macOS'
```

`Scripts/build.sh` makes a Release build stamped with the commit it came from; `Scripts/build.sh --install`
also replaces `~/Applications/mcprotocol2human-surface.app` with it and launches it.

Debug builds can be driven from a shell (select a server, show a page, write a snapshot of the window and
quit) through `M2H_*` environment variables; see `Support/DebugAids.swift`.

## Design decisions

Recorded as ADRs in [docs/adr](docs/adr):

- [0001](docs/adr/0001-native-macos-app.md) Native macOS app without third-party dependencies
- [0002](docs/adr/0002-own-mcp-client.md) Own MCP client instead of the Swift SDK
- [0003](docs/adr/0003-read-only-discovery.md) Read-only, one-shot discovery
- [0004](docs/adr/0004-transports.md) Transports: stdio and Streamable HTTP
- [0005](docs/adr/0005-protocol-revisions.md) Protocol revisions: modern and legacy, probed per run
- [0006](docs/adr/0006-sandbox-and-search-path.md) App Sandbox off; executables from a fixed search path
- [0007](docs/adr/0007-server-configuration.md) Server list as an `mcpServers` JSON file, edited in Settings

## Ideas for later

- Save a server's tool list and compare it with a later run, to see what changed between versions.
- More checks on tool definitions, in the spirit of the notes that exist now.
- An estimate of how much context the tool descriptions take up.
- Prompts and resources, listed like tools.
