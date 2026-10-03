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
    /// The entries of the last text that could be read, so edits survive text that briefly cannot be.
    @State private var remembered: [PastedServers.Entry] = []
    @State private var isAdding = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let outcomes = Dictionary(zip(entries.map(\.id), PastedServers.plan(entries, existing: store.servers))) { first, _ in first }
        VStack(spacing: 0) {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.body.monospaced())
                        // A fixed height, scrolling inside: a long paste must not push what was found out of view.
                        .frame(height: 110)
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
                    Label("Values of environment variables and headers are stored in plain text in the servers file.",
                          systemImage: "key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(entries.count > 1 ? "Add \(entries.count) Servers" : "Add Server") {
                    // Once only, even if Return comes again while the sheet goes away.
                    guard !isAdding else { return }
                    isAdding = true
                    onAdd(store.add(entries, after: after))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(entries.isEmpty || isAdding)
            }
            .padding(12)
        }
        // As tall as the Settings window allows, which is the limit for a sheet.
        .frame(width: 600)
        .frame(minHeight: 420, idealHeight: 640)
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
        details(config)
        if case .unsupported(let type) = config.kind {
            note("Transport “\(type)” is not supported. The entry is kept in the file, but cannot be looked at.")
        }
    }

    /// The entry with every value as stored (the pasted text shows them anyway). Left-aligned, so a wrapped
    /// line reads as one: each argument starts with its number, each variable or header with its name on a
    /// line of its own, and values wrap indented below. Names never wrap, since wrapping hyphenates them.
    private func details(_ config: ServerConfig) -> some View {
        let showsURL = config.kind == .http || (config.command.isEmpty && !config.url.isEmpty)
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
            detail("Transport") { Text(config.kindLabel) }
            if showsURL {
                detail("URL") { value(config.url) }
            } else {
                detail("Command") { value(config.command) }
                if !config.arguments.isEmpty {
                    detail("Arguments") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(config.arguments.enumerated()), id: \.offset) { index, argument in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("\(index + 1)")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                    value(argument)
                                }
                            }
                        }
                    }
                }
            }
            if !config.environment.isEmpty {
                detail("Environment") { pairs(config.environment) }
            }
            if !config.headers.isEmpty {
                detail("Headers") { pairs(config.headers) }
            }
            if !config.extra.isEmpty {
                detail("Also kept") { Text(config.extra.map(\.key).joined(separator: ", ")) }
            }
        }
        .textSelection(.enabled)
    }

    private func detail(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .fixedSize()
            content()
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func value(_ text: String) -> some View {
        if text.isEmpty {
            Text("(empty)")
                .italic()
                .foregroundStyle(.secondary)
        } else {
            Text(text)
                .font(.body.monospaced())
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pairs(_ pairs: [KeyValue]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(pairs) { pair in
                VStack(alignment: .leading, spacing: 1) {
                    Text(pair.key)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(pair.key)
                    value(pair.value)
                        .padding(.leading, 16)
                }
            }
        }
    }

    /// What happens to a name that is taken: by an existing server, which the entry may replace instead, or
    /// by an entry above it.
    @ViewBuilder private func clash(_ entry: PastedServers.Entry, outcome: PastedServers.Outcome) -> some View {
        let name = entry.config.name.trimmingCharacters(in: .whitespaces)
        if outcome.canReplace {
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
                // A choice to replace was about the old name's server, not whichever one the new name has.
                if name.trimmingCharacters(in: .whitespaces) != entries[index].config.name.trimmingCharacters(in: .whitespaces) {
                    entries[index].replace = false
                }
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
    /// keep what the user changed about them, also across text that could not be read in between.
    private func parse() {
        if !entries.isEmpty { remembered = entries }
        do throws(PasteError) {
            var pasted = try PastedServers(text: text)
            for index in pasted.entries.indices where remembered.indices.contains(index) {
                let previous = remembered[index]
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
