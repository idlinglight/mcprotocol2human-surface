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
- The repository is public. Keep personal context, real server output and secrets out of it:
  examples and test fixtures use made-up servers and tools.
- Debug builds read `M2H_*` environment variables to drive the app from a shell and write a snapshot
  (PNG plus a text dump of model state and views); see `Support/DebugAids.swift`. Point them at a scratch
  servers file with `M2H_SERVERS_FILE`, never at the real one.
- Debug and installed builds share one bundle id, so they share preferences. Never change the user's
  from a debug run: pass a preference as a launch argument (`-showsToolDescriptions NO`, overrides for
  that launch, never written), or use a scratch store (`M2H_DEFAULTS_SUITE=<name>`, see `Preferences`).
  App code reads preferences through `Preferences.store` so the scratch store takes effect.
- xcodebuild's console output leaves out Swift Testing failure messages. Run tests with
  `-resultBundlePath build/tests.xcresult` and read them with
  `xcrun xcresulttool get test-results tests --path build/tests.xcresult`.
- Every pull request runs `.github/workflows/ci.yml` (job `build-and-test`, a required check on `main`).
  Actions are pinned by full commit SHA with a version comment; the repository only allows actions from
  GitHub's own organizations.
