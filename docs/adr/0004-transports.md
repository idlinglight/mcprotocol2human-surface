# ADR-0004: Transports: stdio and Streamable HTTP

Status: accepted, 2026-10-03

## Context

MCP defines two current transports: stdio, where the host starts the server as a child process and
exchanges newline-delimited JSON over its standard input and output, and Streamable HTTP, where each
message is an HTTP POST whose response is either one JSON body or a stream of server-sent events. The
older HTTP+SSE transport is deprecated.

Building only one transport first would let assumptions about it leak into the rest of the client, such as
"there is a process" or "replies arrive in order on one stream".

## Decision

Support both from the first version, behind one transport protocol: send a message, receive a stream of
incoming messages, close. The deprecated HTTP+SSE transport is not supported.

- **stdio**: the command is started with arguments as an array, never through a shell. Standard error is
  collected and shown as the server's log. Closing ends standard input, then terminates the process if it
  does not exit by itself.
- **Streamable HTTP**: plain `URLSession`. Responses of type `application/json` and `text/event-stream` are
  both handled; the event-stream parser is ours. Configured headers are sent with every request.

## Consequences

- Each transport is tested against at least one real server, not only against fakes.
- HTTP servers reachable only over plain `http://` on a named host are blocked by App Transport Security.
  Localhost and IP addresses are exempt, which covers local development servers.
