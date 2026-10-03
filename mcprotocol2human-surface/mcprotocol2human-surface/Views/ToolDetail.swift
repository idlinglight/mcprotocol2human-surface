import SwiftUI

/// Everything a tool says about itself: name, hints, description, parameters, output, raw JSON.
struct ToolDetail: View {
    var tool: ToolInfo
    @State private var showsRaw = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.displayName)
                        .font(.title2.bold())
                        .textSelection(.enabled)
                    if tool.displayName != tool.name {
                        Text(tool.name)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    HintBadges(hints: tool.hints)
                        .padding(.top, 4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Description")
                            .font(.headline)
                        if let description = tool.description, !description.isEmpty {
                            CopyButton(text: description, help: "Copy the description exactly as the server sent it")
                            Spacer()
                            DescriptionDisplayPicker()
                        }
                    }
                    if let description = tool.description, !description.isEmpty {
                        DescriptionText(text: description)
                    } else {
                        Text("No description.").foregroundStyle(.secondary)
                    }
                }

                DetailSection(parametersTitle) {
                    if tool.parameters.isEmpty {
                        Text(tool.inputSchema == nil ? "No input schema." : "No parameters.")
                            .foregroundStyle(.secondary)
                    } else {
                        ParameterList(parameters: tool.parameters)
                    }
                }

                if let output = tool.outputSchema {
                    DetailSection("Output") {
                        let reader = SchemaReader(root: output)
                        let fields = reader.parameters(of: output)
                        if fields.isEmpty {
                            Text(reader.typeLabel(of: output))
                                .font(.body.monospaced())
                        } else {
                            ParameterList(parameters: fields)
                        }
                    }
                }

                if !tool.notes.isEmpty {
                    DetailSection("Notes") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(tool.notes.enumerated()), id: \.offset) { _, note in
                                Label(note, systemImage: "info.circle")
                                    .textSelection(.enabled)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                DisclosureGroup("Raw JSON", isExpanded: $showsRaw) {
                    JSONText(value: tool.raw)
                        .padding(.top, 6)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var parametersTitle: String {
        let count = tool.parameters.count
        guard count > 0 else { return "Parameters" }
        let required = tool.requiredParameterCount
        return required > 0 ? "Parameters (\(count), \(required) required)" : "Parameters (\(count))"
    }
}

struct DetailSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
        }
    }
}

/// All four hints. Those the server set are shown plainly; defaults are dimmed and say so.
struct HintBadges: View {
    var hints: [HintInfo]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(hints) { hint in
                Text("\(hint.label): \(hint.value ? "yes" : "no")")
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(hint.isExplicit ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08)))
                    .foregroundStyle(hint.isExplicit ? .primary : .secondary)
                    .help(hint.isExplicit
                          ? "\(hint.key) is \(String(hint.value)), as set by the server."
                          : "\(hint.key) is not set; the specification's default is \(String(hint.value)).")
            }
        }
    }
}

/// Parameters one per row; object-valued ones can be opened to show their properties.
struct ParameterList: View {
    var parameters: [ParameterInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // By position: a schema may name a property twice, and both should show.
            ForEach(Array(parameters.enumerated()), id: \.offset) { index, parameter in
                if index > 0 { Divider() }
                ParameterRow(parameter: parameter)
                    .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
    }
}

struct ParameterRow: View {
    var parameter: ParameterInfo
    @State private var showsChildren = false
    @State private var showsSchema = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(parameter.name)
                    .font(.body.monospaced().bold())
                    .textSelection(.enabled)
                if parameter.isRequired {
                    Text("required")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 12)
                Text(parameter.typeLabel)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            if let description = parameter.description, !description.isEmpty {
                DescriptionText(text: description)
            }
            facts
            if !parameter.children.isEmpty {
                DisclosureGroup("\(parameter.children.count) properties", isExpanded: $showsChildren) {
                    ParameterList(parameters: parameter.children)
                        .padding(.top, 4)
                }
                .font(.callout)
            }
            DisclosureGroup("Schema", isExpanded: $showsSchema) {
                JSONText(value: parameter.schema)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var facts: some View {
        let lines = factLines
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                }
            }
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
    }

    private var factLines: [String] {
        var lines: [String] = []
        if let value = parameter.defaultValue { lines.append("default: \(value.compactText)") }
        if !parameter.allowedValues.isEmpty {
            lines.append("one of: " + parameter.allowedValues.map(\.compactText).joined(separator: ", "))
        }
        lines += parameter.constraints
        return lines
    }
}

/// Pretty-printed JSON, selectable, with a copy button.
struct JSONText: View {
    var value: JSONValue

    var body: some View {
        let text = value.prettyText
        VStack(alignment: .trailing, spacing: 2) {
            CopyButton(text: text, help: "Copy this JSON")
            MonospaceBlock(text: text)
        }
    }
}
