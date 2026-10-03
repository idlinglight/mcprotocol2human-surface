# ADR-0002: Own MCP client instead of the Swift SDK

Status: accepted, 2026-10-03

## Context

The official Swift SDK (`modelcontextprotocol/swift-sdk`) exists. In October 2026 it is at 0.12.1, still
before 1.0, with API changes between minor versions this year. It depends on `swift-system`, `swift-log` and
`mattt/eventsource`.

What this app needs from MCP is small: open a connection, find out which protocol revision the server speaks,
list tools (following pagination), and close. It never calls a tool ([ADR-0003](0003-read-only-discovery.md)).

The app exists partly to *validate* servers. A typed client decodes replies into its own model types, so
fields it does not know vanish, and a malformed reply turns into a decoding error with the payload gone.
For a viewer, the raw reply is the thing worth seeing.

## Decision

Write the client in this repository: JSON-RPC 2.0 framing, the transports from
[ADR-0004](0004-transports.md), and the few methods discovery needs.

- Replies are kept as raw JSON values. Typed views (tool name, description, parameters) are derived from
  them, and the raw JSON stays available in the UI next to the derived view.
- Every message sent and received is recorded, so the traffic of a discovery run can be inspected.
- Transports sit behind one protocol, so a different implementation, the SDK's included, could replace
  ours without touching the UI.

## Consequences

- Following the specification is our job. A new protocol revision means reading its changelog and
  adjusting the client; [ADR-0005](0005-protocol-revisions.md) records which revisions are supported.
- No dependency, in line with [ADR-0001](0001-native-macos-app.md).
- Reasons to revisit: calling tools, OAuth-protected servers, or long-lived subscriptions. Each would grow
  the client past "small".
