import SwiftUI

/// What the server said about itself in the handshake, how the client classified it, and its instructions.
struct ServerOverview: View {
    var config: ServerConfig
    var run: DiscoveryRun?
    var isRunning: Bool
    var showTraffic: () -> Void
    @State private var showsHandshake = false
    @State private var showsCapabilities = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if isRunning, run == nil {
                    ProgressView("Connecting…")
                }
                if let failure = run?.failure {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .textSelection(.enabled)
                            Button("Show Traffic", action: showTraffic)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                facts
                if let result = run?.result {
                    DetailSection("Instructions") {
                        if let instructions = result.instructions, !instructions.isEmpty {
                            DescriptionText(text: instructions)
                        } else {
                            Text("None.").foregroundStyle(.secondary)
                        }
                    }
                    DetailSection("How the client got here") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(result.observations.enumerated()), id: \.offset) { _, line in
                                Label(line, systemImage: "info.circle")
                                    .textSelection(.enabled)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Capabilities", isExpanded: $showsCapabilities) {
                        JSONText(value: result.capabilities ?? .null)
                            .padding(.top, 6)
                    }
                    DisclosureGroup(result.era == .modern ? "server/discover result" : "initialize result",
                                    isExpanded: $showsHandshake) {
                        JSONText(value: result.handshake)
                            .padding(.top, 6)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        let info = run?.result?.serverInfo
        return VStack(alignment: .leading, spacing: 4) {
            Text(info?["title"]?.stringValue ?? info?["name"]?.stringValue ?? config.name)
                .font(.title2.bold())
                .textSelection(.enabled)
            if let description = info?["description"]?.stringValue {
                Text(description)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var facts: some View {
        let result = run?.result
        let info = result?.serverInfo
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            if let name = info?["name"]?.stringValue {
                fact("Server", name + (info?["version"]?.stringValue.map { " \($0)" } ?? ""))
            }
            if let website = info?["websiteUrl"]?.stringValue {
                fact("Website", website)
            }
            if let result {
                fact("Protocol", "\(result.protocolVersion) (\(result.era.rawValue))")
                fact("Capabilities", capabilityNames(result.capabilities))
                fact("Tools", result.toolsAdvertised ? "\(result.tools.count)" : "not advertised")
            }
            fact("Transport", "\(config.kindLabel): \(config.summary)")
            if let run {
                fact("Last run", "\(run.finished.formatted(date: .omitted, time: .standard)), took \(run.duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow, maximumUnitCount: 2)))")
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
        }
    }

    /// Top-level capability names, with the flags set inside each: `tools (listChanged)`.
    private func capabilityNames(_ capabilities: JSONValue?) -> String {
        guard let members = capabilities?.members, !members.isEmpty else { return "none" }
        return members.map { member in
            let flags = member.value.members?.filter { $0.value == .bool(true) }.map(\.key) ?? []
            return flags.isEmpty ? member.key : "\(member.key) (\(flags.joined(separator: ", ")))"
        }.joined(separator: ", ")
    }
}
