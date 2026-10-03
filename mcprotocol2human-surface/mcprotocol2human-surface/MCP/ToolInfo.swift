import Foundation

/// One tool from `tools/list`, with the parts a reader looks at derived from the raw JSON.
nonisolated struct ToolInfo: Identifiable, Sendable, Hashable {
    /// Position in the server's list. Names are not guaranteed unique, so this is the identity.
    var position: Int
    var raw: JSONValue
    var name: String
    var title: String?
    var description: String?
    var inputSchema: JSONValue?
    var outputSchema: JSONValue?
    var annotations: JSONValue?
    var parameters: [ParameterInfo]
    var hints: [HintInfo]
    /// Deviations from the specification, and gaps worth knowing about when designing tools.
    var notes: [String]

    var id: Int { position }

    init(raw: JSONValue, position: Int) {
        self.raw = raw
        self.position = position
        name = raw["name"]?.stringValue ?? ""
        title = raw["title"]?.stringValue
        description = raw["description"]?.stringValue
        inputSchema = raw["inputSchema"]
        outputSchema = raw["outputSchema"]
        annotations = raw["annotations"]
        parameters = inputSchema.map { SchemaReader(root: $0).parameters(of: $0) } ?? []
        hints = HintInfo.all(from: annotations)

        var notes: [String] = []
        if raw.members == nil { notes.append("The entry is \(raw.kindName), not an object.") }
        if name.isEmpty { notes.append("No name.") }
        if description?.isEmpty ?? true { notes.append("No description.") }
        if let inputSchema {
            if inputSchema["type"]?.stringValue != "object" {
                notes.append("inputSchema has type \(inputSchema["type"]?.compactText ?? "none"), not \"object\".")
            }
        } else {
            notes.append("No inputSchema, which is required.")
        }
        let undocumented = parameters.filter { $0.description?.isEmpty ?? true }.map(\.name)
        if !undocumented.isEmpty {
            notes.append("Parameters without description: \(undocumented.joined(separator: ", ")).")
        }
        self.notes = notes
    }

    /// `title`, then `annotations.title`, then `name`, as the specification orders them for display.
    var displayName: String {
        title ?? annotations?["title"]?.stringValue ?? (name.isEmpty ? "(unnamed)" : name)
    }

    /// The first non-empty line of the description.
    var summary: String? {
        description?
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    var requiredParameterCount: Int { parameters.count(where: \.isRequired) }
}

/// One property of an object schema. Names can repeat (JSON objects may have duplicate keys), so lists of
/// these are identified by position.
nonisolated struct ParameterInfo: Sendable, Hashable {
    var name: String
    var typeLabel: String
    var description: String?
    var isRequired: Bool
    var defaultValue: JSONValue?
    var allowedValues: [JSONValue]
    /// Constraints worth showing, such as `minimum: 1` or `format: date-time`.
    var constraints: [String]
    /// Properties of an object (or of an array's object items), for drilling down.
    var children: [ParameterInfo]
    var schema: JSONValue
}

/// Reads JSON Schema enough to describe parameters. Follows local `$ref`s (`#/$defs/…`, `#/definitions/…`)
/// a few levels deep; anything it does not understand still shows in the raw JSON.
nonisolated struct SchemaReader {
    let root: JSONValue
    let maxDepth = 6

    func parameters(of schema: JSONValue, depth: Int = 0) -> [ParameterInfo] {
        let schema = resolved(schema)
        guard depth < maxDepth, let properties = schema["properties"]?.members else { return [] }
        let required = Set(schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        return properties.map { property in
            let value = resolved(property.value)
            return ParameterInfo(
                name: property.key,
                typeLabel: typeLabel(of: property.value),
                description: value["description"]?.stringValue ?? property.value["description"]?.stringValue,
                isRequired: required.contains(property.key),
                defaultValue: value["default"] ?? property.value["default"],
                allowedValues: allowedValues(of: value),
                constraints: constraints(of: value),
                children: children(of: value, depth: depth + 1),
                schema: property.value)
        }
    }

    private func children(of schema: JSONValue, depth: Int) -> [ParameterInfo] {
        if schema["properties"] != nil { return parameters(of: schema, depth: depth) }
        if let items = schema["items"] { return parameters(of: items, depth: depth) }
        for key in ["anyOf", "oneOf"] {
            // Optional objects come as `anyOf: [{object}, {type: null}]`.
            if let variants = schema[key]?.arrayValue {
                let objects = variants.map { resolved($0) }.filter { $0["properties"] != nil }
                if objects.count == 1 { return parameters(of: objects[0], depth: depth) }
            }
        }
        return []
    }

    /// The schema a local `$ref` points to, or the schema itself.
    func resolved(_ schema: JSONValue, hops: Int = 0) -> JSONValue {
        guard hops < maxDepth, let reference = schema["$ref"]?.stringValue, reference.hasPrefix("#/") else { return schema }
        var target: JSONValue? = root
        for component in reference.dropFirst(2).split(separator: "/") {
            let key = component.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            target = target?[key]
        }
        guard let target else { return schema }
        return resolved(target, hops: hops + 1)
    }

    /// A short type description: `string`, `array of integer`, `string | null`, `Address (object)`.
    func typeLabel(of schema: JSONValue, depth: Int = 0) -> String {
        guard depth < maxDepth else { return "…" }
        if schema == .bool(true) { return "any" }
        if schema == .bool(false) { return "nothing" }
        if let reference = schema["$ref"]?.stringValue {
            let name = reference.split(separator: "/").last.map(String.init) ?? reference
            let target = resolved(schema)
            return target == schema ? name : "\(name) (\(typeLabel(of: target, depth: depth + 1)))"
        }
        if let constant = schema["const"] { return "const \(constant.compactText)" }
        for key in ["anyOf", "oneOf"] {
            if let variants = schema[key]?.arrayValue, !variants.isEmpty {
                var labels: [String] = []
                for label in variants.map({ typeLabel(of: $0, depth: depth + 1) }) where !labels.contains(label) {
                    labels.append(label)
                }
                return labels.joined(separator: " | ")
            }
        }
        if let parts = schema["allOf"]?.arrayValue, parts.count == 1 {
            return typeLabel(of: parts[0], depth: depth + 1)
        }
        var types = schema["type"]?.stringValue.map { [$0] } ?? schema["type"]?.arrayValue?.compactMap(\.stringValue) ?? []
        if types.isEmpty, schema["enum"] != nil { types = ["enum"] }
        if types.isEmpty, schema["properties"] != nil { types = ["object"] }
        if types.isEmpty { return "any" }
        return types.map { type in
            if type == "array", let items = schema["items"] {
                return "array of \(typeLabel(of: items, depth: depth + 1))"
            }
            return type
        }.joined(separator: " | ")
    }

    private func allowedValues(of schema: JSONValue) -> [JSONValue] {
        if let values = schema["enum"]?.arrayValue { return values }
        if let items = schema["items"], let values = resolved(items)["enum"]?.arrayValue { return values }
        return []
    }

    private func constraints(of schema: JSONValue) -> [String] {
        let keys = ["format", "pattern", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum",
                    "minLength", "maxLength", "minItems", "maxItems", "uniqueItems"]
        return keys.compactMap { key in
            guard let value = schema[key] else { return nil }
            return "\(key): \(value.stringValue ?? value.compactText)"
        }
    }
}

/// One of the four behaviour hints in `annotations`, with the default the specification gives it.
nonisolated struct HintInfo: Identifiable, Sendable, Hashable {
    var key: String
    var label: String
    var value: Bool
    /// False when the server left the hint out and the default applies.
    var isExplicit: Bool

    var id: String { key }

    static let defaults: [(key: String, label: String, value: Bool)] = [
        ("readOnlyHint", "read-only", false),
        ("destructiveHint", "destructive", true),
        ("idempotentHint", "idempotent", false),
        ("openWorldHint", "open world", true),
    ]

    static func all(from annotations: JSONValue?) -> [HintInfo] {
        defaults.map { hint in
            let explicit = annotations?[hint.key]?.boolValue
            return HintInfo(key: hint.key, label: hint.label, value: explicit ?? hint.value, isExplicit: explicit != nil)
        }
    }
}
