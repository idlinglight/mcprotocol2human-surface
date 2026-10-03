# mcprotocol2human-surface

A macOS app for looking at the surface of [Model Context Protocol](https://modelcontextprotocol.io) servers:
which tools a server exposes, and what each tool says about itself. Meant for people who build MCP servers
and want to see their tools the way a client does, without asking an agent or installing an inspector.

Personal tool, built locally, not distributed.

## Status

Scaffolding. The first version will:

- keep a list of servers (stdio and Streamable HTTP), edited in Settings;
- connect to a server on demand, detect which protocol revision it speaks, and list its tools;
- show each tool's name, title, description, parameters and annotations, with the raw JSON alongside.

It only reads. It never calls a tool.

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

## Design decisions

Recorded as ADRs in [docs/adr](docs/adr):

- [0001](docs/adr/0001-native-macos-app.md) Native macOS app without third-party dependencies
- [0002](docs/adr/0002-own-mcp-client.md) Own MCP client instead of the Swift SDK
- [0003](docs/adr/0003-read-only-discovery.md) Read-only, one-shot discovery
- [0004](docs/adr/0004-transports.md) Transports: stdio and Streamable HTTP
- [0005](docs/adr/0005-protocol-revisions.md) Protocol revisions: modern and legacy, probed per run
- [0006](docs/adr/0006-sandbox-and-search-path.md) App Sandbox off; executables from a fixed search path
- [0007](docs/adr/0007-server-configuration.md) Server list as an `mcpServers` JSON file, edited in Settings
