# Working in this repository

- The Xcode project lives one level down: `mcprotocol2human-surface/mcprotocol2human-surface.xcodeproj`.
  App sources are in `mcprotocol2human-surface/mcprotocol2human-surface/`, tests in
  `mcprotocol2human-surface/mcprotocol2human-surfaceTests/`. Both folders are synchronized groups: a new
  file there is part of the target without touching the project file.
- Build and test commands are in the README. Tests use Swift Testing.
- Decisions are ADRs in `docs/adr/` (`ADR-NNNN: Title`, a status line, then Context, Decision,
  Consequences). A change that contradicts an ADR amends it or adds a new one. Keep the README's ADR list
  in step.
- No third-party dependencies (ADR-0001). The MCP client is our own code (ADR-0002); the specification
  lives in the GitHub repository `modelcontextprotocol/modelcontextprotocol`.
- The repository may become public. Keep personal context, real server output and secrets out of it:
  examples and test fixtures use made-up servers and tools.
