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
                .help("Connect again and list the tools (⌘R); restarts a run in progress")
                .disabled(model.selectedServer == nil)
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
    @FocusState private var filterFocused: Bool
    /// A viewing preference, so it is remembered; the filter is not.
    @AppStorage("showsToolDescriptions", store: Preferences.store) private var showsDescriptions = true

    var body: some View {
        let run = model.run(for: name)
        let filter = model.toolFilter
        let shown = run?.result.map { filter.apply($0.tools) } ?? []
        VStack(spacing: 0) {
            // The pages that are not tools stay at the top, above the filter that does not apply to them.
            // A list of their own, sharing the selection, so they look and select like the tool rows.
            List(selection: $model.selectedPage) {
                Label("Overview", systemImage: "info.circle")
                    .tag(ServerPage.overview)
                Label("Traffic", systemImage: "arrow.left.arrow.right")
                    .badge(run?.traffic.count ?? 0)
                    .tag(ServerPage.traffic)
            }
            .scrollDisabled(true)
            .frame(height: Self.pagesHeight)

            if model.canFilterTools {
                Divider()
                FilterBar(filter: $model.toolFilter, focused: $filterFocused)
            }
            Divider()

            List(selection: $model.selectedPage) {
                if let failure = run?.failure {
                    Section {
                        Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                            .selectionDisabled()
                    }
                }
                if let result = run?.result {
                    Section {
                        if !result.toolsAdvertised {
                            Text("The server does not advertise the tools capability.")
                                .foregroundStyle(.secondary)
                                .selectionDisabled()
                        } else if shown.isEmpty, filter.isActive {
                            Text(filter.inverted ? "Every tool matches." : "No tool matches.")
                                .foregroundStyle(.secondary)
                                .selectionDisabled()
                        }
                        // The mode is part of each row's identity: the list keeps row heights for rows it
                        // already has, so switching modes must replace the rows rather than update them.
                        ForEach(shown, id: \.position) { tool in
                            ToolRow(tool: tool, showsDescription: showsDescriptions)
                                .tag(ServerPage.tool(tool.position))
                                .id(RowIdentity(position: tool.position, showsDescription: showsDescriptions))
                        }
                    } header: {
                        // Right after the count, not at the trailing edge, where it would line up with the
                        // filter buttons and look like one of them.
                        HStack(spacing: 6) {
                            Text(filter.header(shown: shown.count, total: result.tools.count))
                            StateButton(
                                symbol: showsDescriptions ? "eye" : "eye.slash",
                                state: showsDescriptions ? "Showing the first line of each description" : "Showing names only",
                                action: showsDescriptions ? "show names only" : "show the first line of each description"
                            ) {
                                showsDescriptions.toggle()
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .overlay {
                if run == nil, model.isRunning(name) {
                    ProgressView("Connecting…")
                }
            }
        }
        .onChange(of: model.filterFocusRequests) {
            filterFocused = true
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

    /// Two rows of the list style, plus its insets.
    static let pagesHeight: CGFloat = 72

    /// Equal apart from the identity SwiftUI uses.
    static func sameSettings(_ a: ServerConfig, _ b: ServerConfig) -> Bool {
        a.entry == b.entry
    }
}

/// A tool row's identity in the list: its tool, and whether it shows the description line.
private struct RowIdentity: Hashable {
    var position: Int
    var showsDescription: Bool
}

struct ToolRow: View {
    var tool: ToolInfo
    /// The first line of the description under the name; the full description is in the tooltip either way.
    var showsDescription = true

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
            if showsDescription, let summary = tool.summary {
                Text(verbatim: summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .help(tool.description.map(DescriptionFormat.plainText) ?? "No description")
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
