# ADR-0006: App Sandbox off; executables from a fixed search path

Status: accepted, 2026-10-03

## Context

A stdio server is started by the app. Typical commands are `uv run …`, `npx …` or a path to a script.
Under the App Sandbox the child inherits the sandbox: it could not read its own project directory, caches
or configuration, and most servers would fail to start.

Apps launched from the Finder or the Dock get the system `PATH` only (`/usr/bin:/bin:/usr/sbin:/sbin`), so
`uv` or `node` installed through Homebrew would not be found by name.

## Decision

- App Sandbox off. Hardened Runtime stays on.
- A command given by name is resolved against a fixed list of directories: Homebrew (`/opt/homebrew/bin`,
  `/opt/homebrew/sbin`), `/usr/local/bin`, `~/.local/bin`, then the system directories. A command containing
  a slash is used as a path. The child gets that list as its `PATH`, plus the environment variables
  configured for the server.

This follows the approach of a sister project that runs command-line tools the same way.

## Consequences

- Servers run with the user's full permissions, as they do under any other MCP host.
- Tools installed elsewhere (a version manager's directory, say) need a full path in the configuration.
  If that becomes common, the next step is a setting for extra directories, or reading the login shell's
  `PATH` once at launch.
