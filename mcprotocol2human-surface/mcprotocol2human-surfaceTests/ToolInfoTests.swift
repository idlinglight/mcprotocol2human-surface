import Foundation
import Testing
@testable import mcprotocol2human_surface

struct ToolInfoTests {
    @Test func readsParametersInSchemaOrder() throws {
        let raw = try JSONValue.parse(#"""
        {"name": "ship", "description": "Ship it.\nSecond line.",
         "inputSchema": {"type": "object",
           "$defs": {"Address": {"type": "object", "properties": {"street": {"type": "string", "description": "Street"}}}},
           "properties": {
             "zeta": {"type": "string", "description": "Last letter", "enum": ["a", "b"]},
             "address": {"$ref": "#/$defs/Address"},
             "note": {"anyOf": [{"type": "string"}, {"type": "null"}], "default": null},
             "tags": {"type": "array", "items": {"type": "string"}, "minItems": 1}
           },
           "required": ["address"]},
         "annotations": {"readOnlyHint": true}}
        """#)
        let tool = ToolInfo(raw: raw, position: 0)
        #expect(tool.summary == "Ship it.")
        #expect(tool.parameters.map(\.name) == ["zeta", "address", "note", "tags"])
        #expect(tool.parameters.map(\.typeLabel) == ["string", "Address (object)", "string | null", "array of string"])
        #expect(tool.parameters.map(\.isRequired) == [false, true, false, false])
        #expect(tool.parameters[0].allowedValues == ["a", "b"])
        #expect(tool.parameters[1].children.map(\.name) == ["street"])
        #expect(tool.parameters[2].defaultValue == .null)
        #expect(tool.parameters[3].constraints == ["minItems: 1"])
        #expect(tool.notes == ["Parameters without description: address, note, tags."])
        let readOnly = tool.hints.first { $0.key == "readOnlyHint" }
        #expect(readOnly?.value == true && readOnly?.isExplicit == true)
        let destructive = tool.hints.first { $0.key == "destructiveHint" }
        #expect(destructive?.value == true && destructive?.isExplicit == false)
    }

    @Test func displayNamePrefersTitleThenAnnotationTitle() {
        #expect(ToolInfo(raw: ["name": "a", "title": "T", "annotations": ["title": "U"]], position: 0).displayName == "T")
        #expect(ToolInfo(raw: ["name": "a", "annotations": ["title": "U"]], position: 0).displayName == "U")
        #expect(ToolInfo(raw: ["name": "a"], position: 0).displayName == "a")
    }

    @Test func notesMissingPieces() {
        let tool = ToolInfo(raw: ["name": "bare"], position: 0)
        #expect(tool.notes.contains("No description."))
        #expect(tool.notes.contains("No inputSchema, which is required."))
    }

    @Test func survivesReferenceCycles() {
        let schema: JSONValue = ["type": "object", "$defs": ["Node": ["$ref": "#/$defs/Node"]],
                                 "properties": ["n": ["$ref": "#/$defs/Node"]]]
        let tool = ToolInfo(raw: ["name": "loop", "inputSchema": schema], position: 0)
        #expect(tool.parameters.map(\.name) == ["n"])
    }
}
