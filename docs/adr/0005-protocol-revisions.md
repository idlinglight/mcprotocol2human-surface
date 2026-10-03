# ADR-0005: Protocol revisions: modern and legacy, probed per run

Status: accepted, 2026-10-03

## Context

MCP revision 2026-07-28 made the protocol stateless. The `initialize` handshake and HTTP sessions are gone.
Every request carries the protocol version, client capabilities and client identity in `params._meta`,
and servers describe themselves through a new `server/discover` request. The specification calls this
revision and later ones *modern*, and 2025-11-25 and earlier *legacy*.

Servers in use today are mostly legacy. The Python SDK's 1.x line, for example, speaks up to 2025-11-25
only. The specification describes how a client that speaks both eras (*dual-era*) should find out which
one a server speaks.

## Decision

The client is dual-era: modern 2026-07-28, and legacy 2025-11-25 down to 2024-11-05.

Every discovery run starts with a probe, as the specification recommends:

- Send `server/discover` with `2026-07-28` in `_meta`.
- A `DiscoverResult` means the server is modern. A recognised modern error means the same; those are
  `-32020` header mismatch, `-32021` missing capability and `-32022` unsupported version. The client
  reports them instead of falling back. For `-32022` the specification suggests retrying with a version
  from the error's `supported` list; with 2026-07-28 as the client's only modern version there is none to
  retry with, so the list is shown in the error.
- Any other answer means legacy, and so does no answer within the probe timeout (20 seconds, which includes
  the server's start-up over stdio). That covers other JSON-RPC errors, other HTTP error statuses,
  responses the client cannot read, and responses that end without a reply. The client then runs
  `initialize` (offering 2025-11-25) and `notifications/initialized` on the same connection.
- The fallback is never keyed to one specific error code. Legacy servers answer the probe with whatever
  their implementation does, commonly `-32601` or `-32602`.
- Only failures that say nothing about the era end discovery: `401` and `403`, reported as authorisation
  problems; a server that cannot be reached or started; and a stdio server that exits during the probe.

After the probe, the client lists tools if the server advertises the `tools` capability, following
`nextCursor` until it is absent. A missing `resultType` counts as `"complete"`.

As a legacy client it declares no capabilities, answers `ping`, and answers every other server request
with `-32601`. As a modern client it sends the `_meta` fields on every request and, over HTTP, the
`MCP-Protocol-Version` and `Mcp-Method` headers.

## Consequences

- The detected era and the protocol version are part of each snapshot and shown in the UI. For a tool
  meant to validate servers, what the server negotiated is itself worth seeing.
- The era is not cached between runs. Each run is a fresh process or connection anyway
  ([ADR-0003](0003-read-only-discovery.md)), and the probe shows up in the recorded traffic.
- A legacy server that ignores unknown requests instead of answering them costs one probe timeout per
  refresh.
- The deprecated HTTP+SSE transport, which the specification lists as a last fallback, is not attempted
  ([ADR-0004](0004-transports.md)).
- A new protocol revision means revisiting this ADR.
