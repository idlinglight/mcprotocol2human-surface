import Foundation

/// Where the app keeps its preferences.
///
/// Debug and installed builds share one bundle id and so one preferences domain. A debug run can use a
/// scratch store instead (`M2H_DEFAULTS_SUITE=<name>`, emptied at launch, optionally seeded with
/// `M2H_DEFAULTS='{"key": value}'`), so trying settings never changes the installed app's.
enum Preferences {
    static let store: UserDefaults = {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let suite = environment["M2H_DEFAULTS_SUITE"], !suite.isEmpty, let scratch = UserDefaults(suiteName: suite) {
            scratch.removePersistentDomain(forName: suite)
            if let json = environment["M2H_DEFAULTS"],
               let values = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
                for (key, value) in values { scratch.set(value, forKey: key) }
            }
            return scratch
        }
        #endif
        return .standard
    }()
}
