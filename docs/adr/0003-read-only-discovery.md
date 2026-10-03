# ADR-0003: Read-only, one-shot discovery

Status: accepted, 2026-10-03

## Context

The servers this app looks at include ones with tools that change data. A viewer that can call tools is
one stray click from doing so. The questions the app answers ("what tools exist, what do they say about
themselves") need only the list methods.

## Decision

- The app never sends `tools/call`, nor any other method that acts on the server's data. It sends only
  what discovery needs: the protocol handshake or discovery request, and list methods.
- Discovery is one-shot. Selecting a server runs it the first time; after that, Refresh does. A run opens
  a connection (for stdio, starts the server process), runs discovery, records the result with its time
  and traffic, and closes the connection again. Nothing stays connected between runs.

## Consequences

- Pointing the app at any server is safe as far as the app's own requests go. Starting a stdio server
  still runs that server's code, including whatever it does at startup; that is the same as any MCP host
  starting it.
- A snapshot can be older than the server. Change notifications (`list_changed`) are not listened for;
  Refresh is the way to see changes.
- Calling tools would be a new decision with its own safeguards, not an extension of this one.
