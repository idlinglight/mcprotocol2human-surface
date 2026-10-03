import SwiftUI

/// Servers on the left, the selected server's tools in the middle, the selected tool (or the server's
/// overview, or its traffic) on the right.
struct MainWindow: View {
    @Bindable var model: AppModel
    #if DEBUG
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        NavigationSplitView {
            ServerSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 360)
        } content: {
            Group {
                if let name = model.selectedServer, model.selectedConfig != nil {
                    ServerColumn(model: model, name: name)
                } else {
                    ContentUnavailableView("No Server Selected", systemImage: "server.rack",
                                           description: Text("Choose a server on the left."))
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 340, max: 520)
        } detail: {
            DetailColumn(model: model)
        }
        .frame(minWidth: 960, minHeight: 560)
        .navigationTitle(model.selectedServer ?? "mcprotocol2human-surface")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    model.refreshSelected()
                }
                .help("Connect again and list the tools (⌘R)")
                .disabled(model.selectedServer == nil || model.selectedServer.map(model.isRunning) == true)
            }
        }
        .onChange(of: model.store.servers.map(\.name)) {
            model.pruneToStore()
        }
        #if DEBUG
        .onAppear {
            SettingsOpener.action = { openSettings() }
            if SettingsOpener.pending {
                SettingsOpener.pending = false
                openSettings()
            }
        }
        #endif
    }

    private var subtitle: String {
        guard let name = model.selectedServer else { return "" }
        if model.isRunning(name) { return "Connecting…" }
        guard let run = model.run(for: name) else { return "" }
        if let result = run.result {
            return "\(result.tools.count) tools · \(result.era.rawValue) \(result.protocolVersion)"
        }
        return "Discovery failed"
    }
}

// MARK: - Sidebar

struct ServerSidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.selectedServer) {
            ForEach(model.store.servers) { server in
                ServerRow(server: server, run: model.run(for: server.name), isRunning: model.isRunning(server.name))
                    .tag(server.name)
                    .contextMenu {
                        Button("Refresh") { model.refresh(server.name) }
                    }
            }
        }
        .overlay {
            if model.store.servers.isEmpty {
                ContentUnavailableView {
                    Label("No Servers", systemImage: "server.rack")
                } description: {
                    if let loadError = model.store.loadError {
                        Text("The servers file could not be read: \(loadError)")
                    } else {
                        Text("Add the MCP servers you want to look at in Settings.")
                    }
                } actions: {
                    SettingsLink { Text("Open Settings…") }
                }
            }
        }
    }
}

struct ServerRow: View {
    var server: ServerConfig
    var run: DiscoveryRun?
    var isRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(server.name)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(server.kindLabel)
                if isRunning {
                    ProgressView().controlSize(.mini)
                } else if let result = run?.result {
                    Text("· \(result.tools.count) tools")
                } else if run?.failure != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("failed")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .help(server.summary)
    }
}

// MARK: - Middle column

struct ServerColumn: View {
    @Bindable var model: AppModel
    var name: String
    @State private var search = ""

    var body: some View {
        let run = model.run(for: name)
        List(selection: $model.selectedPage) {
            Section {
                Label("Overview", systemImage: "info.circle")
                    .tag(ServerPage.overview)
                Label("Traffic", systemImage: "arrow.left.arrow.right")
                    .badge(run?.traffic.count ?? 0)
                    .tag(ServerPage.traffic)
            }
            if let failure = run?.failure {
                Section {
                    Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                        .selectionDisabled()
                }
            }
            if let result = run?.result {
                Section(toolsHeader(result)) {
                    if !result.toolsAdvertised {
                        Text("The server does not advertise the tools capability.")
                            .foregroundStyle(.secondary)
                            .selectionDisabled()
                    }
                    ForEach(filtered(result.tools)) { tool in
                        ToolRow(tool: tool)
                            .tag(ServerPage.tool(tool.position))
                    }
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Filter tools")
        .overlay {
            if run == nil, model.isRunning(name) {
                ProgressView("Connecting…")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let run, let current = model.selectedConfig, !Self.sameSettings(run.config, current) {
                Label("Settings changed since this run. Refresh to apply them.", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
        }
    }

    private func toolsHeader(_ result: DiscoveryResult) -> String {
        let shown = filtered(result.tools).count
        return shown == result.tools.count ? "Tools (\(shown))" : "Tools (\(shown) of \(result.tools.count))"
    }

    private func filtered(_ tools: [ToolInfo]) -> [ToolInfo] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return tools }
        return tools.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.displayName.localizedCaseInsensitiveContains(query)
                || ($0.description?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    /// Equal apart from the identity SwiftUI uses.
    static func sameSettings(_ a: ServerConfig, _ b: ServerConfig) -> Bool {
        a.entry == b.entry
    }
}

struct ToolRow: View {
    var tool: ToolInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(tool.displayName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if tool.displayName != tool.name, !tool.name.isEmpty {
                    Text(tool.name)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                HintIcons(hints: tool.hints)
            }
            if let summary = tool.summary {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .help(tool.description ?? "No description")
    }
}

/// Small icons for the hints a server set explicitly: read-only, or destructive.
struct HintIcons: View {
    var hints: [HintInfo]

    var body: some View {
        let explicit = Dictionary(uniqueKeysWithValues: hints.filter(\.isExplicit).map { ($0.key, $0.value) })
        HStack(spacing: 3) {
            if explicit["readOnlyHint"] == true {
                Image(systemName: "eye").help("Read-only")
            } else if explicit["destructiveHint"] == true {
                Image(systemName: "exclamationmark.triangle").help("Destructive")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Detail column

struct DetailColumn: View {
    @Bindable var model: AppModel

    var body: some View {
        if let name = model.selectedServer, let config = model.selectedConfig {
            let run = model.run(for: name)
            switch model.selectedPage {
            case .tool(let position):
                if let tool = run?.result?.tools.first(where: { $0.position == position }) {
                    ToolDetail(tool: tool)
                        .id(position)
                } else {
                    ContentUnavailableView("Tool Not Found", systemImage: "questionmark",
                                           description: Text("The latest run did not list this tool."))
                }
            case .traffic:
                if let run {
                    TrafficView(entries: run.traffic, started: run.started)
                } else {
                    ContentUnavailableView("No Traffic Yet", systemImage: "arrow.left.arrow.right")
                }
            case .overview, nil:
                ServerOverview(config: config, run: run, isRunning: model.isRunning(name)) {
                    model.selectedPage = .traffic
                }
            }
        } else {
            ContentUnavailableView("Nothing Selected", systemImage: "sidebar.left")
        }
    }
}
