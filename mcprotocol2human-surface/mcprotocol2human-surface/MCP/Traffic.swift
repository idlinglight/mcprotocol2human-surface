import Foundation
import Synchronization

/// One line of a discovery run's record: a message sent or received, a line the server wrote to stderr,
/// or a note from the client (an HTTP status, a classification, a timeout).
nonisolated struct TrafficEntry: Sendable, Identifiable, Hashable {
    enum Kind: String, Sendable {
        case sent, received, stderr, note
    }

    var id: Int
    var time: Date
    var kind: Kind
    var text: String
}

/// Collects the traffic of one discovery run. Written from transport callbacks on any thread.
nonisolated final class TrafficLog: Sendable {
    private let state = Mutex<[TrafficEntry]>([])
    /// Entries beyond this are dropped, with one note saying so.
    let limit: Int

    init(limit: Int = 5_000) {
        self.limit = limit
    }

    func record(_ kind: TrafficEntry.Kind, _ text: String) {
        state.withLock { entries in
            guard entries.count <= limit else { return }
            let entry = entries.count == limit
                ? TrafficEntry(id: entries.count, time: .now, kind: .note, text: "Record full; later traffic not kept.")
                : TrafficEntry(id: entries.count, time: .now, kind: kind, text: text)
            entries.append(entry)
        }
    }

    var entries: [TrafficEntry] {
        state.withLock { $0 }
    }
}
