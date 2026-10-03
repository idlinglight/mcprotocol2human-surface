import SwiftUI

/// The server list as a form (ADR-0007). Edits are saved to the servers file as they happen.
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var selection: ServerConfig.ID?

    private var store: ServerStore { model.store }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                serverList
                    .frame(width: 210)
                Divider()
                editor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 500)
        .onDisappear { store.flush() }
        .onAppear {
            if selection == nil { selection = model.selectedConfig?.id ?? store.servers.first?.id }
        }
    }

    private var serverList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.servers) { server in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(server.name.isEmpty ? "(no name)" : server.name)
                            .lineLimit(1)
                        Text(server.kindLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(server.id)
                    .contextMenu {
                        Button("Duplicate") { selection = store.duplicate(server.id) }
                        Button("Remove", role: .destructive) { remove(server.id) }
                    }
                }
            }
            Divider()
            HStack(spacing: 2) {
                Button("Add Server", systemImage: "plus") {
                    selection = store.add(after: selection)
                }
                Button("Remove Server", systemImage: "minus") {
                    if let selection { remove(selection) }
                }
                .disabled(selection == nil)
                Spacer()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(6)
            .disabled(store.loadError != nil)
        }
    }

    @ViewBuilder private var editor: some View {
        if let loadError = store.loadError {
            ContentUnavailableView {
                Label("Servers File Unreadable", systemImage: "exclamationmark.triangle")
            } description: {
                Text("\(loadError)\n\nFix the file and reload it. Nothing is saved until it can be read.")
            }
        } else if let id = selection, let server = store.server(id: id) {
            ServerEditor(
                server: Binding(get: { store.server(id: id) ?? server }, set: { store.update($0) }),
                problem: store.problem(for: server))
            .id(id)
        } else {
            ContentUnavailableView("No Server Selected", systemImage: "server.rack",
                                   description: Text("Add a server with the + button."))
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.fileURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if let saveError = store.saveError {
                    Text(saveError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Button("Reveal in Finder") {
                if FileManager.default.fileExists(atPath: store.fileURL.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                } else {
                    NSWorkspace.shared.open(store.fileURL.deletingLastPathComponent())
                }
            }
            Button("Reload") {
                store.load()
                model.pruneToStore()
                if let current = selection, store.server(id: current) == nil { selection = store.servers.first?.id }
            }
            .help("Read the file again, dropping edits that are not saved yet")
        }
        .padding(10)
    }

    private func remove(_ id: ServerConfig.ID) {
        let index = store.servers.firstIndex { $0.id == id }
        store.remove(id)
        if let index, !store.servers.isEmpty {
            selection = store.servers[min(index, store.servers.count - 1)].id
        } else {
            selection = nil
        }
    }
}

struct ServerEditor: View {
    @Binding var server: ServerConfig
    var problem: String?
    @State private var argumentsText = ""
    @State private var showsJSON = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $server.name)
                if let problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Picker("Transport", selection: $server.kind) {
                    Text("stdio").tag(TransportKind.stdio)
                    Text("HTTP").tag(TransportKind.http)
                    if case .unsupported(let type) = server.kind {
                        Text(type).tag(server.kind)
                    }
                }
                .pickerStyle(.segmented)
            }

            switch server.kind {
            case .stdio:
                Section {
                    TextField("Command", text: $server.command, prompt: Text("uv, npx, or a full path"))
                        .font(.body.monospaced())
                    commandResolution
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Arguments")
                        TextEditor(text: $argumentsText)
                            .font(.body.monospaced())
                            .frame(minHeight: 70)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
                        Text("One argument per line.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Process")
                }
                Section("Environment") {
                    KeyValueEditor(pairs: $server.environment, keyPrompt: "NAME", valuePrompt: "value")
                }
            case .http:
                Section("Endpoint") {
                    TextField("URL", text: $server.url, prompt: Text("http://127.0.0.1:8000/mcp"))
                        .font(.body.monospaced())
                }
                Section("Headers") {
                    KeyValueEditor(pairs: $server.headers, keyPrompt: "Header", valuePrompt: "value")
                }
            case .unsupported(let type):
                Section {
                    Text("Transport “\(type)” is not supported. Choose stdio or HTTP (Streamable HTTP).")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                DisclosureGroup("As JSON", isExpanded: $showsJSON) {
                    JSONText(value: .object([JSONMember(key: server.name, value: server.entry)]))
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { argumentsText = server.arguments.joined(separator: "\n") }
        .onChange(of: argumentsText) {
            // Only an edit writes back; showing the arguments must not change them.
            guard argumentsText != server.arguments.joined(separator: "\n") else { return }
            let arguments = Self.arguments(from: argumentsText)
            if arguments != server.arguments { server.arguments = arguments }
        }
    }

    /// One argument per line. Empty lines in between are empty arguments; trailing ones are not arguments,
    /// so a newline typed at the end does not add one.
    static func arguments(from text: String) -> [String] {
        // By `isNewline`, not "\n": a pasted "\r\n" is one Character and would not split.
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }

    @ViewBuilder private var commandResolution: some View {
        let command = server.command.trimmingCharacters(in: .whitespaces)
        if !command.isEmpty {
            if let url = ExecutableLocator.resolve(command) {
                Label(url.path, systemImage: "checkmark.circle")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                Label(command.contains("/") ? "No executable file at this path." : "Not found in the search path.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(ExecutableLocator.searchDirectories.joined(separator: "\n"))
            }
        }
    }
}

/// Rows of name and value with add and remove, for environment variables and headers.
struct KeyValueEditor: View {
    @Binding var pairs: [KeyValue]
    var keyPrompt: String
    var valuePrompt: String

    var body: some View {
        ForEach(pairs) { pair in
            HStack {
                TextField(keyPrompt, text: field(\.key, of: pair.id), prompt: Text(keyPrompt))
                    .labelsHidden()
                    .frame(maxWidth: 200)
                TextField(valuePrompt, text: field(\.value, of: pair.id), prompt: Text(valuePrompt))
                    .labelsHidden()
                Button("Remove", systemImage: "minus.circle") {
                    pairs.removeAll { $0.id == pair.id }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            .font(.body.monospaced())
        }
        Button("Add", systemImage: "plus") {
            pairs.append(KeyValue(key: "", value: ""))
        }
        .buttonStyle(.borderless)
    }

    /// A row's field, found by the row's id rather than its position. A text field can still read or write
    /// its binding while its row is being removed; with `ForEach($pairs)` that is a position past the end
    /// and crashes. Here a removed row reads as empty and drops the write.
    func field(_ keyPath: WritableKeyPath<KeyValue, String>, of id: KeyValue.ID) -> Binding<String> {
        Binding(
            get: { pairs.first { $0.id == id }?[keyPath: keyPath] ?? "" },
            set: { text in
                guard let index = pairs.firstIndex(where: { $0.id == id }) else { return }
                pairs[index][keyPath: keyPath] = text
            })
    }
}
