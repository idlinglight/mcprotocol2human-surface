import SwiftUI

/// Which tools the middle column shows: those whose text contains the filter text, case-insensitively.
nonisolated struct ToolFilter: Equatable, Sendable {
    var text = ""
    /// Match the tool's name and title only, not its description.
    var namesOnly = false
    /// Show the tools that do not match instead.
    var inverted = false

    var query: String { text.trimmingCharacters(in: .whitespaces) }

    /// False while there is no text: then everything shows, inverted or not.
    var isActive: Bool { !query.isEmpty }

    func matches(_ tool: ToolInfo) -> Bool {
        let query = query
        guard !query.isEmpty else { return true }
        var found = tool.name.localizedCaseInsensitiveContains(query)
            || tool.displayName.localizedCaseInsensitiveContains(query)
        if !found, !namesOnly {
            found = tool.description?.localizedCaseInsensitiveContains(query) ?? false
        }
        return found != inverted
    }

    func apply(_ tools: [ToolInfo]) -> [ToolInfo] {
        isActive ? tools.filter(matches) : tools
    }

    /// The tools section's header: `Tools (18)`, `Tools (4 of 18)`, `Tools not matching (14 of 18)`.
    func header(shown: Int, total: Int) -> String {
        guard isActive else { return "Tools (\(total))" }
        return inverted ? "Tools not matching (\(shown) of \(total))" : "Tools (\(shown) of \(total))"
    }
}

/// The filter field with its two toggles, above the tool list.
struct FilterBar: View {
    @Binding var filter: ToolFilter
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(.secondary)
                TextField("Filter tools", text: $filter.text)
                    .textFieldStyle(.plain)
                    .focused(focused)
                    .onExitCommand { filter.text = "" }
                if !filter.text.isEmpty {
                    Button("Clear Filter", systemImage: "xmark.circle.fill") { filter.text = "" }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))

            Toggle(isOn: $filter.namesOnly) {
                Text("Aa").font(.callout.weight(.semibold))
            }
            .help(filter.namesOnly ? "Matching tool names and titles only" : "Match tool names and titles only")
            .accessibilityLabel("Names only")
            Toggle(isOn: $filter.inverted) {
                Image(systemName: "notequal")
            }
            .help(filter.inverted ? "Showing the tools that do not match" : "Show the tools that do not match")
            .accessibilityLabel("Show non-matching")
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
