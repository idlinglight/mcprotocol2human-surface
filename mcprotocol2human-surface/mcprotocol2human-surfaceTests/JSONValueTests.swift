import Foundation
import Testing
@testable import mcprotocol2human_surface

struct JSONValueTests {
    @Test func keepsMemberOrderAndDuplicates() throws {
        let value = try JSONValue.parse(#"{"z": 1, "a": 2, "z": 3}"#)
        #expect(value.members?.map(\.key) == ["z", "a", "z"])
        #expect(value["z"] == .number("3"))
    }

    @Test func keepsNumberText() throws {
        let value = try JSONValue.parse("[1, 1.0, -0, 1e3, 2.50]")
        #expect(value.compactText == "[1,1.0,-0,1e3,2.50]")
        #expect(value.arrayValue?[1].intValue == 1)
        #expect(value.arrayValue?[4].intValue == nil)
    }

    @Test func decodesEscapesAndSurrogatePairs() throws {
        let value = try JSONValue.parse(#""a\"b\\c\/d\né😀""#)
        #expect(value == .string("a\"b\\c/d\né😀"))
    }

    @Test func writesWhatItReads() throws {
        let text = #"{"name":"x","list":[true,false,null,{"k":"tab\tquote\""}],"n":-1.5e-3,"empty":{},"none":[]}"#
        let value = try JSONValue.parse(text)
        #expect(value.compactText == text)
        #expect(try JSONValue.parse(value.prettyText) == value)
    }

    @Test func escapesControlCharactersWhenWriting() {
        #expect(JSONValue.string("\u{01}").compactText == #""\u0001""#)
    }

    @Test(arguments: ["", "{", "[1,]", #"{"a" 1}"#, "tru", "01", "1.", "\"unterminated", "[1] x", "\"\u{01}\""])
    func rejectsInvalidInput(_ text: String) {
        #expect(throws: JSONParseError.self) { try JSONValue.parse(text) }
    }

    @Test func limitsNesting() throws {
        func nested(_ depth: Int) -> String { String(repeating: "[", count: depth) + String(repeating: "]", count: depth) }
        #expect(throws: JSONParseError.self) { try JSONValue.parse(nested(600)) }
        _ = try JSONValue.parse(nested(90))
    }

    @Test func settingReplacesOrAppends() {
        let value: JSONValue = ["a": 1, "b": 2]
        #expect(value.setting("a", to: 9).compactText == #"{"a":9,"b":2}"#)
        #expect(value.setting("c", to: 3).compactText == #"{"a":1,"b":2,"c":3}"#)
    }
}
