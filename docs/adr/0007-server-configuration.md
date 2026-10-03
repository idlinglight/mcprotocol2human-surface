# ADR-0007: Server list as an `mcpServers` JSON file, edited in Settings

Status: accepted, 2026-10-03; amended 2026-10-03 (pasting entries in Settings)

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
- Settings also takes entries in as pasted JSON ("Add Servers from JSON…" below the server list, or ⌘V
  while the list has focus). It accepts the shapes configuration snippets come in: a whole file
  (`mcpServers`, or VS Code's `servers`), the map of names to entries, a single entry without a name, and a
  `"name": {…}` fragment copied out of a file, with or without its trailing comma. Members that are not
  entries are left out and listed.
- Nothing is added before a sheet shows what was found: each entry's name, transport and command or URL,
  and its environment variables and headers with their values. A note beside the Add button says the
  values are stored in plain text. The values are not hidden: the pasted text shows them anyway, and the
  form has to show them to edit them.
- Names can be edited in the sheet. An entry without a name gets one derived from the URL's host or from
  the command (for launchers such as `npx`, `uvx` or `docker`, the package or image they run).
- A name that is taken is added with a suffix (`name-2`) by default. For a clash with an existing server,
  the sheet offers to replace it instead; the replacement keeps that server's place in the list.
- Fields the app does not know are kept when the file is written back.
- No import from other hosts' configuration files for now; their files can hold secrets in `env` and
  `headers`, and copying entries by hand keeps that a deliberate act. Pasting is such an act.

## Consequences

- Secrets in `env` or `headers` are stored in plain text, as in other hosts' files. Keychain storage would
  be a later decision, once a server needs it.
- The environment variable `M2H_SERVERS_FILE` points the app at a different file, for tests and
  experiments without touching the real list.
- Replacing on paste is how an entry is refreshed from a new snippet, such as an IDE's server that moved
  to another port.
- VS Code's `inputs` (prompted values such as `${input:api-key}`) are not resolved; such references stay
  in the entry as written.
