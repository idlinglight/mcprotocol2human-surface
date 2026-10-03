# ADR-0001: Native macOS app without third-party dependencies

Status: accepted, 2026-10-03

## Context

The app is a developer's window onto MCP servers: which servers are configured, which tools each one
exposes, and what those tools say about themselves. Looking at that today means asking an agent, reading
source files, or installing an inspector through npm for one session. The npm route pulls in a large,
fast-moving dependency tree for what is a read-only viewer.

The app has one user and runs on that user's Macs. It is not distributed.

## Decision

- A SwiftUI app for macOS 26 and later, written in Swift 6. No other platforms.
- No third-party dependencies: Apple frameworks only. Adding one needs its own ADR.
- Built and installed locally with `Scripts/build.sh`, which stamps the commit into the app. No App Store,
  no notarized releases.

## Consequences

- Building needs only Xcode. There is no package resolution step and no lockfile to keep current.
- Everything the app does with MCP is code in this repository, which matters for [ADR-0002](0002-own-mcp-client.md).
- The deployment target can follow the newest macOS freely; nobody else has to run it.
