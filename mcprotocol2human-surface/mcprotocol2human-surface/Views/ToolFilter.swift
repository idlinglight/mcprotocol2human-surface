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

/// The filter field, and under it two pop-up menus whose titles are the current settings in words:
/// where to look, and whether to show the tools that match or those that do not.
struct FilterBar: View {
    @Binding var filter: ToolFilter
    var focused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(.secondary)
                TextField(filter.namesOnly ? "Filter names" : "Filter names and descriptions", text: $filter.text)
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

            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                GridRow {
                    Text("In")
                        .gridColumnAlignment(.trailing)
                    Picker("In", selection: $filter.namesOnly) {
                        Text("Names + descriptions").tag(false)
                        Text("Names only").tag(true)
                    }
                    .help("Where the filter text is looked for. Titles count as names.")
                }
                GridRow {
                    Text("Show")
                    Picker("Show", selection: $filter.inverted) {
                        Text("Matching").tag(false)
                        Text("Not matching").tag(true)
                    }
                    .help("Show the tools that contain the filter text, or those that do not")
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
