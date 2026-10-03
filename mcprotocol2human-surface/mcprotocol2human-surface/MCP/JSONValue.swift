import Foundation

/// A JSON value as the server sent it.
///
/// Unlike `JSONSerialization` or `Codable`, this keeps object members in their original order (parameter
/// order in a tool's schema is part of what a viewer should show), keeps duplicate keys, and keeps numbers
/// as their original text. Lookups by key return the last member with that key, as most parsers do.
nonisolated enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    /// The number's text exactly as received, such as `1`, `1.0` or `1e3`.
    case number(String)
    case string(String)
    case array([JSONValue])
    case object([JSONMember])

    subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members.last(where: { $0.key == key })?.value
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var members: [JSONMember]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        if case .number(let text) = self { return Double(text) }
        return nil
    }

    /// The number as an integer, if it is one (`3` or `3.0`, not `3.5`).
    var intValue: Int? {
        guard case .number(let text) = self else { return nil }
        if let value = Int(text) { return value }
        if let double = Double(text), double.rounded() == double, abs(double) < 1e15 { return Int(double) }
        return nil
    }

    var isNull: Bool { self == .null }

    /// A short name for the kind of value, for messages.
    var kindName: String {
        switch self {
        case .null: "null"
        case .bool: "boolean"
        case .number: "number"
        case .string: "string"
        case .array: "array"
        case .object: "object"
        }
    }

    /// The same object with `key` set: replaced in place if present, appended otherwise.
    func setting(_ key: String, to value: JSONValue) -> JSONValue {
        guard case .object(var members) = self else { return self }
        if let index = members.lastIndex(where: { $0.key == key }) {
            members[index].value = value
        } else {
            members.append(JSONMember(key: key, value: value))
        }
        return .object(members)
    }
}

nonisolated struct JSONMember: Sendable, Hashable {
    var key: String
    var value: JSONValue
}

// MARK: - Literals, for building requests in code

nonisolated extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral
{
    init(stringLiteral value: String) { self = .string(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(integerLiteral value: Int) { self = .number(String(value)) }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(elements.map { JSONMember(key: $0.0, value: $0.1) })
    }
    init(nilLiteral: ()) { self = .null }
}

// MARK: - Writing

nonisolated extension JSONValue {
    /// Compact JSON on one line, as stdio framing requires.
    var compactText: String {
        var output = ""
        write(to: &output, indent: nil, level: 0)
        return output
    }

    /// Indented JSON for reading.
    var prettyText: String {
        var output = ""
        write(to: &output, indent: "  ", level: 0)
        return output
    }

    var compactData: Data { Data(compactText.utf8) }

    private func write(to output: inout String, indent: String?, level: Int) {
        switch self {
        case .null: output += "null"
        case .bool(let value): output += value ? "true" : "false"
        case .number(let text): output += text
        case .string(let value): Self.writeString(value, to: &output)
        case .array(let elements):
            guard !elements.isEmpty else { output += "[]"; return }
            output += "["
            for (index, element) in elements.enumerated() {
                if index > 0 { output += "," }
                Self.newline(&output, indent: indent, level: level + 1)
                element.write(to: &output, indent: indent, level: level + 1)
            }
            Self.newline(&output, indent: indent, level: level)
            output += "]"
        case .object(let members):
            guard !members.isEmpty else { output += "{}"; return }
            output += "{"
            for (index, member) in members.enumerated() {
                if index > 0 { output += "," }
                Self.newline(&output, indent: indent, level: level + 1)
                Self.writeString(member.key, to: &output)
                output += indent == nil ? ":" : ": "
                member.value.write(to: &output, indent: indent, level: level + 1)
            }
            Self.newline(&output, indent: indent, level: level)
            output += "}"
        }
    }

    private static func newline(_ output: inout String, indent: String?, level: Int) {
        guard let indent else { return }
        output += "\n" + String(repeating: indent, count: level)
    }

    private static func writeString(_ value: String, to output: inout String) {
        output += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case "\u{08}": output += "\\b"
            case "\u{0C}": output += "\\f"
            case let scalar where scalar.value < 0x20:
                output += String(format: "\\u%04x", scalar.value)
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
    }
}

// MARK: - Parsing

nonisolated struct JSONParseError: Error, LocalizedError, Equatable, Sendable {
    var message: String
    /// Byte offset into the input.
    var offset: Int

    var errorDescription: String? { "Invalid JSON at byte \(offset): \(message)" }
}

nonisolated extension JSONValue {
    static func parse(_ text: String) throws(JSONParseError) -> JSONValue {
        try parse(Data(text.utf8))
    }

    /// Parses one JSON value; only whitespace may follow it.
    static func parse(_ data: Data) throws(JSONParseError) -> JSONValue {
        var parser = JSONParser(bytes: [UInt8](data))
        return try parser.parseDocument()
    }
}

/// Recursive descent over UTF-8 bytes, following RFC 8259.
private nonisolated struct JSONParser {
    let bytes: [UInt8]
    var position = 0
    /// Nesting limit, so hostile input cannot exhaust the stack. Parsing runs on threads with 512 KiB
    /// stacks (dispatch and the concurrency pool); MCP messages nest a few dozen levels at most.
    let maxDepth = 100

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func parseDocument() throws(JSONParseError) -> JSONValue {
        // A UTF-8 byte order mark is not JSON, but some writers add one.
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { position = 3 }
        skipWhitespace()
        let value = try parseValue(depth: 0)
        skipWhitespace()
        guard position == bytes.count else { throw error("unexpected content after the value") }
        return value
    }

    private func error(_ message: String) -> JSONParseError {
        JSONParseError(message: message, offset: position)
    }

    private mutating func skipWhitespace() {
        while position < bytes.count {
            switch bytes[position] {
            case 0x20, 0x09, 0x0A, 0x0D: position += 1
            default: return
            }
        }
    }

    private mutating func parseValue(depth: Int) throws(JSONParseError) -> JSONValue {
        guard depth < maxDepth else { throw error("nested deeper than \(maxDepth) levels") }
        guard position < bytes.count else { throw error("unexpected end of input") }
        switch bytes[position] {
        case UInt8(ascii: "{"): return try parseObject(depth: depth)
        case UInt8(ascii: "["): return try parseArray(depth: depth)
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"): try expectLiteral("true"); return .bool(true)
        case UInt8(ascii: "f"): try expectLiteral("false"); return .bool(false)
        case UInt8(ascii: "n"): try expectLiteral("null"); return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .number(try parseNumber())
        default: throw error("unexpected character")
        }
    }

    private mutating func expectLiteral(_ literal: String) throws(JSONParseError) {
        for byte in literal.utf8 {
            guard position < bytes.count, bytes[position] == byte else { throw error("invalid literal") }
            position += 1
        }
    }

    private mutating func parseObject(depth: Int) throws(JSONParseError) -> JSONValue {
        position += 1
        var members: [JSONMember] = []
        skipWhitespace()
        if position < bytes.count, bytes[position] == UInt8(ascii: "}") {
            position += 1
            return .object(members)
        }
        while true {
            skipWhitespace()
            guard position < bytes.count, bytes[position] == UInt8(ascii: "\"") else {
                throw error("expected a string as object key")
            }
            let key = try parseString()
            skipWhitespace()
            guard position < bytes.count, bytes[position] == UInt8(ascii: ":") else { throw error("expected ':'") }
            position += 1
            skipWhitespace()
            let value = try parseValue(depth: depth + 1)
            members.append(JSONMember(key: key, value: value))
            skipWhitespace()
            guard position < bytes.count else { throw error("unterminated object") }
            if bytes[position] == UInt8(ascii: ",") {
                position += 1
            } else if bytes[position] == UInt8(ascii: "}") {
                position += 1
                return .object(members)
            } else {
                throw error("expected ',' or '}'")
            }
        }
    }

    private mutating func parseArray(depth: Int) throws(JSONParseError) -> JSONValue {
        position += 1
        var elements: [JSONValue] = []
        skipWhitespace()
        if position < bytes.count, bytes[position] == UInt8(ascii: "]") {
            position += 1
            return .array(elements)
        }
        while true {
            skipWhitespace()
            elements.append(try parseValue(depth: depth + 1))
            skipWhitespace()
            guard position < bytes.count else { throw error("unterminated array") }
            if bytes[position] == UInt8(ascii: ",") {
                position += 1
            } else if bytes[position] == UInt8(ascii: "]") {
                position += 1
                return .array(elements)
            } else {
                throw error("expected ',' or ']'")
            }
        }
    }

    private mutating func parseString() throws(JSONParseError) -> String {
        position += 1
        var scalars = String.UnicodeScalarView()
        var runStart = position
        func flushRun(_ end: Int) throws(JSONParseError) {
            guard end > runStart else { return }
            guard let text = String(validating: bytes[runStart..<end], as: UTF8.self) else {
                throw JSONParseError(message: "invalid UTF-8 in string", offset: runStart)
            }
            scalars.append(contentsOf: text.unicodeScalars)
        }
        while position < bytes.count {
            let byte = bytes[position]
            if byte == UInt8(ascii: "\"") {
                try flushRun(position)
                position += 1
                return String(scalars)
            }
            if byte == UInt8(ascii: "\\") {
                try flushRun(position)
                position += 1
                scalars.append(try parseEscape())
                runStart = position
                continue
            }
            guard byte >= 0x20 else { throw error("unescaped control character in string") }
            position += 1
        }
        throw error("unterminated string")
    }

    private mutating func parseEscape() throws(JSONParseError) -> Unicode.Scalar {
        guard position < bytes.count else { throw error("unterminated escape") }
        let byte = bytes[position]
        position += 1
        switch byte {
        case UInt8(ascii: "\""): return "\""
        case UInt8(ascii: "\\"): return "\\"
        case UInt8(ascii: "/"): return "/"
        case UInt8(ascii: "b"): return "\u{08}"
        case UInt8(ascii: "f"): return "\u{0C}"
        case UInt8(ascii: "n"): return "\n"
        case UInt8(ascii: "r"): return "\r"
        case UInt8(ascii: "t"): return "\t"
        case UInt8(ascii: "u"):
            let first = try parseHex4()
            if (0xD800...0xDBFF).contains(first) {
                // A high surrogate must be followed by an escaped low surrogate.
                if position + 1 < bytes.count, bytes[position] == UInt8(ascii: "\\"), bytes[position + 1] == UInt8(ascii: "u") {
                    position += 2
                    let second = try parseHex4()
                    if (0xDC00...0xDFFF).contains(second) {
                        let combined = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
                        return Unicode.Scalar(combined) ?? "\u{FFFD}"
                    }
                }
                return "\u{FFFD}"
            }
            return Unicode.Scalar(first) ?? "\u{FFFD}"
        default:
            throw error("invalid escape")
        }
    }

    private mutating func parseHex4() throws(JSONParseError) -> UInt32 {
        guard position + 4 <= bytes.count else { throw error("truncated \\u escape") }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[position]
            let digit: UInt32
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(byte - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(byte - UInt8(ascii: "A") + 10)
            default: throw error("invalid hex digit in \\u escape")
            }
            value = value * 16 + digit
            position += 1
        }
        return value
    }

    private mutating func parseNumber() throws(JSONParseError) -> String {
        let start = position
        func isDigit(_ byte: UInt8) -> Bool { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) }
        if bytes[position] == UInt8(ascii: "-") { position += 1 }
        guard position < bytes.count, isDigit(bytes[position]) else { throw error("expected a digit") }
        if bytes[position] == UInt8(ascii: "0") {
            position += 1
        } else {
            while position < bytes.count, isDigit(bytes[position]) { position += 1 }
        }
        if position < bytes.count, bytes[position] == UInt8(ascii: ".") {
            position += 1
            guard position < bytes.count, isDigit(bytes[position]) else { throw error("expected a digit after '.'") }
            while position < bytes.count, isDigit(bytes[position]) { position += 1 }
        }
        if position < bytes.count, bytes[position] == UInt8(ascii: "e") || bytes[position] == UInt8(ascii: "E") {
            position += 1
            if position < bytes.count, bytes[position] == UInt8(ascii: "+") || bytes[position] == UInt8(ascii: "-") {
                position += 1
            }
            guard position < bytes.count, isDigit(bytes[position]) else { throw error("expected a digit in exponent") }
            while position < bytes.count, isDigit(bytes[position]) { position += 1 }
        }
        return String(decoding: bytes[start..<position], as: UTF8.self)
    }
}
