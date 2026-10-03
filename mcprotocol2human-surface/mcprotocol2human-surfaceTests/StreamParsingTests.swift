import Foundation
import Testing
@testable import mcprotocol2human_surface

struct LineSplitterTests {
    @Test func splitsOnLFCRAndCRLF() {
        var splitter = LineSplitter()
        let lines = splitter.append(Array("a\nb\r\nc\rd".utf8))
        #expect(lines.map { String(decoding: $0, as: UTF8.self) } == ["a", "b", "c"])
        #expect(splitter.finish().map { String(decoding: $0, as: UTF8.self) } == "d")
    }

    @Test func handlesCRLFSplitAcrossChunks() {
        var splitter = LineSplitter()
        #expect(splitter.append(Array("a\r".utf8)).count == 1)
        #expect(splitter.append(Array("\nb\n".utf8)).map { String(decoding: $0, as: UTF8.self) } == ["b"])
    }
}

struct SSEParserTests {
    @Test func parsesEventsWithCommentsAndMultilineData() {
        var parser = SSEParser()
        let stream = ": comment\r\nevent: message\r\nid: 7\r\ndata: {\"a\":\r\ndata:1}\r\n\r\ndata: second\n\n"
        let events = parser.append(Array(stream.utf8))
        #expect(events == [
            SSEEvent(type: "message", data: "{\"a\":\n1}", id: "7"),
            SSEEvent(type: nil, data: "second", id: "7"),
        ])
    }

    @Test func emptyDataDoesNotDispatch() {
        var parser = SSEParser()
        #expect(parser.append(Array("id: 1\ndata:\n\n".utf8)) == [SSEEvent(type: nil, data: "", id: "1")])
        #expect(parser.append(Array("retry: 10\n\n".utf8)).isEmpty)
    }

    @Test func finishReturnsAnUnterminatedEvent() {
        var parser = SSEParser()
        #expect(parser.append(Array("data: last".utf8)).isEmpty)
        #expect(parser.finish() == SSEEvent(type: nil, data: "last", id: nil))
    }
}
