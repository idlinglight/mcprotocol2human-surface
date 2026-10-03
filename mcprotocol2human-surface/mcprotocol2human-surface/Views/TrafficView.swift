import SwiftUI

/// The messages of one discovery run, the server's stderr, and the client's notes, in order.
struct TrafficView: View {
    var entries: [TrafficEntry]
    var started: Date
    @State private var filter = Filter.all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case messages = "Messages"
        case log = "Server Log"
        var id: Self { self }
    }

    var body: some View {
        let shown = entries.filter(matches)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(shown) { entry in
                    TrafficRow(entry: entry, offset: entry.time.timeIntervalSince(started))
                    Divider()
                }
            }
            .padding(.horizontal, 12)
        }
        .overlay {
            if shown.isEmpty {
                ContentUnavailableView("Nothing Recorded", systemImage: "tray")
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                Button("Copy All", systemImage: "doc.on.doc") {
                    let text = shown.map { TrafficRow.line(for: $0, offset: $0.time.timeIntervalSince(started)) }
                        .joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .help("Copy the shown entries as text")
            }
        }
    }

    private func matches(_ entry: TrafficEntry) -> Bool {
        switch filter {
        case .all: true
        case .messages: entry.kind == .sent || entry.kind == .received
        case .log: entry.kind == .stderr
        }
    }
}

struct TrafficRow: View {
    var entry: TrafficEntry
    var offset: TimeInterval
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.offsetText(offset))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 16)
                .help(entry.kind.rawValue)
            VStack(alignment: .leading, spacing: 4) {
                Text(expanded ? expandedText : entry.text)
                    .font(.callout.monospaced())
                    .lineLimit(expanded ? nil : 3)
                    .textSelection(.enabled)
                    .foregroundStyle(entry.kind == .note ? .secondary : .primary)
                if isMessage {
                    Button(expanded ? "Collapse" : "Expand") { expanded.toggle() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private var isMessage: Bool { entry.kind == .sent || entry.kind == .received }

    /// Messages pretty-printed when they parse; other text as it is.
    private var expandedText: String {
        guard isMessage, let value = try? JSONValue.parse(entry.text) else { return entry.text }
        return value.prettyText
    }

    private var symbol: String {
        switch entry.kind {
        case .sent: "arrow.up.right"
        case .received: "arrow.down.left"
        case .stderr: "text.alignleft"
        case .note: "info.circle"
        }
    }

    private var color: Color {
        switch entry.kind {
        case .sent: .blue
        case .received: .green
        case .stderr: .orange
        case .note: .secondary
        }
    }

    static func offsetText(_ offset: TimeInterval) -> String {
        String(format: "+%.3f", offset)
    }

    static func line(for entry: TrafficEntry, offset: TimeInterval) -> String {
        let label = switch entry.kind {
        case .sent: "→"
        case .received: "←"
        case .stderr: "stderr"
        case .note: "note"
        }
        return "\(offsetText(offset)) \(label) \(entry.text)"
    }
}
