import os

/// Loggers for the unified log; filter with `log stream --predicate 'subsystem == "at.idling.mcprotocol2human-surface"'`.
nonisolated enum Log {
    static let subsystem = "at.idling.mcprotocol2human-surface"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let discovery = Logger(subsystem: subsystem, category: "discovery")
    static let config = Logger(subsystem: subsystem, category: "config")
}
