import SwiftUI

/// Takes server entries in as pasted JSON (ADR-0007): shows what the text holds and what adding it would do
/// before anything is added.
struct PasteServersSheet: View {
    var store: ServerStore
    /// Where the entries go: after this server, or at the end.
    var after: ServerConfig.ID?
    /// Called with the ids of the servers added or replaced, in order.
    var onAdd: ([ServerConfig.ID]) -> Void
    @State var text: String
    @State private var entries: [PastedServers.Entry] = []
    @State private var notes: [String] = []
    @State private var shape = PastedServers.Shape.entriesByName
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let outcomes = Dictionary(zip(entries.map(\.id), PastedServers.plan(entries, existing: store.servers))) { first, _ in first }
        VStack(spacing: 0) {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.body.monospaced())
                        .frame(minHeight: 90)
                        .scrollContentBackground(.hidden)
                } header: {
                    Text("JSON")
                } footer: {
                    Text("A servers file, its mcpServers (or servers) object, a single entry, or a \"name\": {…} part of a file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                ForEach(entries) { entry in
                    Section {
                        if let outcome = outcomes[entry.id] { entryRows(entry, outcome: outcome) }
                    } header: {
                        if entry.id == entries.first?.id { Text(summary) }
                    }
                }
                if !notes.isEmpty {
                    Section("Left out") {
                        ForEach(notes, id: \.self) { Text($0) }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                // Here rather than in the form, so it is in view when deciding (ADR-0007).
                if entries.contains(where: { !$0.config.environment.isEmpty || !$0.config.headers.isEmpty }) {
                    Label("Values of environment variables and headers are not shown. They are stored in plain text in the servers file.",
                          systemImage: "key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(entries.count > 1 ? "Add \(entries.count) Servers" : "Add Server") {
                    onAdd(store.add(entries, after: after))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(entries.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 600, height: 460)
        .onChange(of: text, initial: true) { parse() }
    }

    private var summary: String {
        var text = shape == .singleEntry
            ? "Found \(shape.rawValue)"
            : "Found \(shape.rawValue): \(entries.count) \(entries.count == 1 ? "server" : "servers")"
        if !notes.isEmpty { text += "; some of it is left out, see below" }
        return text
    }

    @ViewBuilder private func entryRows(_ entry: PastedServers.Entry, outcome: PastedServers.Outcome) -> some View {
        let config = entry.config
        TextField("Name", text: name(of: entry.id))
        if !entry.nameWasGiven {
            note("The text gives no name; this one comes from the \(config.kind == .http || config.command.isEmpty ? "URL" : "command").")
        }
        clash(entry, outcome: outcome)
        LabeledContent(config.kindLabel) {
            Text(config.kind == .http ? config.url : config.summary)
                .font(.body.monospaced())
                .lineLimit(3)
                .textSelection(.enabled)
        }
        if case .unsupported(let type) = config.kind {
            note("Transport “\(type)” is not supported. The entry is kept in the file, but cannot be looked at.")
        }
        if !config.environment.isEmpty {
            LabeledContent("Environment", value: config.environment.map(\.key).joined(separator: ", "))
        }
        if !config.headers.isEmpty {
            LabeledContent("Headers", value: config.headers.map(\.key).joined(separator: ", "))
        }
        if !config.extra.isEmpty {
            LabeledContent("Also kept", value: config.extra.map(\.key).joined(separator: ", "))
        }
    }

    /// What happens to a name that is taken: by an existing server, which the entry may replace instead, or
    /// by an entry above it.
    @ViewBuilder private func clash(_ entry: PastedServers.Entry, outcome: PastedServers.Outcome) -> some View {
        let name = entry.config.name.trimmingCharacters(in: .whitespaces)
        if store.server(named: name) != nil {
            Picker("A server named “\(name)” exists", selection: replace(of: entry.id)) {
                Text("Add as “\(alternativeName(for: entry.id))”").tag(false)
                Text("Replace it").tag(true)
            }
            .pickerStyle(.radioGroup)
        } else if outcome.name != name, !name.isEmpty {
            note("Another entry above has this name; added as “\(outcome.name)”.")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// The name the entry gets when it does not replace the server of its name.
    private func alternativeName(for id: ServerConfig.ID) -> String {
        var adding = entries
        if let index = adding.firstIndex(where: { $0.id == id }) { adding[index].replace = false }
        let outcomes = PastedServers.plan(adding, existing: store.servers)
        return zip(adding, outcomes).first { $0.0.id == id }?.1.name ?? ""
    }

    // By id, not position: the rows come and go as the text changes (see KeyValueEditor.field).
    private func name(of id: ServerConfig.ID) -> Binding<String> {
        Binding(
            get: { entries.first { $0.id == id }?.config.name ?? "" },
            set: { name in
                guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
                entries[index].config.name = name
            })
    }

    private func replace(of id: ServerConfig.ID) -> Binding<Bool> {
        Binding(
            get: { entries.first { $0.id == id }?.replace ?? false },
            set: { replace in
                guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
                entries[index].replace = replace
            })
    }

    /// Reads the text again. Entries that are still there, at the same place under the same original name,
    /// keep what the user changed about them.
    private func parse() {
        do throws(PasteError) {
            var pasted = try PastedServers(text: text)
            for index in pasted.entries.indices where entries.indices.contains(index) {
                let previous = entries[index]
                guard previous.originalName == pasted.entries[index].originalName else { continue }
                pasted.entries[index].config.id = previous.config.id
                pasted.entries[index].config.name = previous.config.name
                pasted.entries[index].replace = previous.replace
            }
            entries = pasted.entries
            notes = pasted.notes
            shape = pasted.shape
            problem = nil
        } catch {
            entries = []
            notes = []
            problem = error == .empty ? nil : error.localizedDescription
        }
    }
}
