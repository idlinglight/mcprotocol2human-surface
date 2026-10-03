import Foundation

/// Splits a byte stream into lines. A line ends at LF, CR or CRLF; the terminator is not part of the line.
nonisolated struct LineSplitter: Sendable {
    private var buffer: [UInt8] = []
    private var lastWasCR = false

    /// Feeds bytes and returns the lines they completed.
    mutating func append(_ bytes: some Sequence<UInt8>) -> [[UInt8]] {
        var lines: [[UInt8]] = []
        for byte in bytes {
            if let line = append(byte) { lines.append(line) }
        }
        return lines
    }

    /// Feeds one byte; returns a line if it completed one.
    mutating func append(_ byte: UInt8) -> [UInt8]? {
        defer { lastWasCR = byte == 0x0D }
        switch byte {
        case 0x0A:
            if lastWasCR { return nil }
            return takeLine()
        case 0x0D:
            return takeLine()
        default:
            buffer.append(byte)
            return nil
        }
    }

    /// The unterminated rest, if any.
    mutating func finish() -> [UInt8]? {
        guard !buffer.isEmpty else { return nil }
        return takeLine()
    }

    private mutating func takeLine() -> [UInt8] {
        let line = buffer
        buffer.removeAll(keepingCapacity: true)
        return line
    }
}

/// One server-sent event.
nonisolated struct SSEEvent: Equatable, Sendable {
    var type: String?
    var data: String
    var id: String?
}

/// Parses a `text/event-stream` body as the HTML standard describes it, minus reconnection.
nonisolated struct SSEParser: Sendable {
    private var lines = LineSplitter()
    private var dataLines: [String] = []
    private var type: String?
    private var id: String?

    mutating func append(_ bytes: some Sequence<UInt8>) -> [SSEEvent] {
        var events: [SSEEvent] = []
        for byte in bytes {
            if let line = lines.append(byte), let event = process(line) {
                events.append(event)
            }
        }
        return events
    }

    mutating func append(_ byte: UInt8) -> SSEEvent? {
        guard let line = lines.append(byte) else { return nil }
        return process(line)
    }

    /// At the end of the stream: an event that was not followed by a blank line. The standard discards it;
    /// callers here keep it and note the deviation.
    mutating func finish() -> SSEEvent? {
        if let line = lines.finish(), let event = process(line) { return event }
        return dispatch()
    }

    private mutating func process(_ bytes: [UInt8]) -> SSEEvent? {
        guard !bytes.isEmpty else { return dispatch() }
        let line = String(decoding: bytes, as: UTF8.self)
        if line.hasPrefix(":") { return nil }
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = line[...]
            value = ""
        }
        switch field {
        case "data": dataLines.append(String(value))
        case "event": type = String(value)
        case "id": id = String(value)
        default: break
        }
        return nil
    }

    private mutating func dispatch() -> SSEEvent? {
        defer {
            dataLines = []
            type = nil
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(type: type, data: dataLines.joined(separator: "\n"), id: id)
    }
}
