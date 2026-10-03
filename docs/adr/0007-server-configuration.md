# ADR-0007: Server list as an `mcpServers` JSON file, edited in Settings

Status: accepted, 2026-10-03

## Context

The app needs a list of servers: a name, a transport, and for stdio a command with arguments and
environment, for HTTP a URL with headers. MCP hosts have converged on one JSON shape for this, the
`mcpServers` object used by Claude Code and Claude Desktop. The user wants to see and edit the list in a
form, not by reading JSON.

## Decision

- The list is stored as a JSON file at `~/Library/Application Support/at.idling.mcprotocol2human-surface/servers.json`,
  in the `mcpServers` shape:

  ```json
  {
    "mcpServers": {
      "example-stdio": { "type": "stdio", "command": "uv", "args": ["run", "example-server"], "env": {} },
      "example-http": { "type": "http", "url": "http://127.0.0.1:8000/mcp", "headers": {} }
    }
  }
  ```

- The Settings window edits it through a form. The file stays readable and editable by hand, and entries
  can be pasted in from another host's configuration. Settings can reveal it in the Finder.
- Fields the app does not know are kept when the file is written back.
- No import from other hosts' configuration files for now; their files can hold secrets in `env` and
  `headers`, and copying entries by hand keeps that a deliberate act.

## Consequences

- Secrets in `env` or `headers` are stored in plain text, as in other hosts' files. Keychain storage would
  be a later decision, once a server needs it.
- The environment variable `M2H_SERVERS_FILE` points the app at a different file, for tests and
  experiments without touching the real list.
