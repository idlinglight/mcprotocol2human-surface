import Foundation

/// Finds executables for stdio servers (ADR-0006).
///
/// Apps launched from the Finder or Dock get a minimal PATH, so executables given by name are resolved
/// against `searchDirectories` instead, and children get that list as their PATH.
nonisolated enum ExecutableLocator {
    /// Directories searched, in order, when an executable is given by name rather than by path.
    static var searchDirectories: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/opt/homebrew/bin", "/opt/homebrew/sbin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
    }

    /// Resolves a name or path to an executable file, or nil if there is none.
    static func resolve(_ executable: String) -> URL? {
        resolve(executable, searching: searchDirectories)
    }

    /// Like `resolve(_:)`, searching the given directories in order.
    static func resolve(_ executable: String, searching directories: [String]) -> URL? {
        let fileManager = FileManager.default
        guard !executable.isEmpty else { return nil }
        if executable.contains("/") {
            let path = (executable as NSString).expandingTildeInPath
            return fileManager.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        for directory in directories {
            let path = "\(directory)/\(executable)"
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// The environment a server runs in: the app's environment with the fixed PATH, plus the server's own variables.
    static func childEnvironment(adding extra: [String: String]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchDirectories.joined(separator: ":")
        environment["NO_COLOR"] = "1"
        environment.merge(extra) { _, new in new }
        return environment
    }
}
