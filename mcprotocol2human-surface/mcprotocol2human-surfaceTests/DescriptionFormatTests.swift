import Foundation
import Testing
@testable import mcprotocol2human_surface

struct DescriptionFormatTests {
    typealias Block = DescriptionFormat.Block

    @Test func joinsHardWrappedLinesAndKeepsParagraphs() {
        let text = "Fetch the widgets for a\ngiven shelf.\n\nThe shelf must exist;\nunknown shelves raise."
        #expect(DescriptionFormat.blocks(text) == [
            .paragraph("Fetch the widgets for a given shelf."),
            .paragraph("The shelf must exist; unknown shelves raise."),
        ])
    }

    @Test func listItemsKeepTheirLinesAndAbsorbIndentedContinuations() {
        let text = """
        Modes:
          - `fast`: skips the
            cache entirely.
          - `slow`: reads through.
        1. first
        2) second
        """
        #expect(DescriptionFormat.blocks(text) == [
            .paragraph("Modes:"),
            .listItem(marker: "-", text: "`fast`: skips the cache entirely.", level: 1),
            .listItem(marker: "-", text: "`slow`: reads through.", level: 1),
            .listItem(marker: "1.", text: "first", level: 0),
            .listItem(marker: "2)", text: "second", level: 0),
        ])
    }

    @Test func unindentedLineAfterAListStartsAParagraph() {
        #expect(DescriptionFormat.blocks("- one\nReturns nothing.") == [
            .listItem(marker: "-", text: "one", level: 0),
            .paragraph("Returns nothing."),
        ])
    }

    @Test func fencedCodeStaysAsItIs() {
        let text = "Example:\n```json\n{\"a\": 1,\n  \"b\": 2}\n```\nDone."
        #expect(DescriptionFormat.blocks(text) == [
            .paragraph("Example:"),
            .code("{\"a\": 1,\n  \"b\": 2}"),
            .paragraph("Done."),
        ])
        #expect(DescriptionFormat.blocks("```\nnever closed") == [.code("never closed")])
    }

    @Test func dedentsLikeADocstringAndHandlesWindowsLineEnds() {
        let text = "Summary line.\r\n\r\n    Details that were\r\n    indented."
        #expect(DescriptionFormat.blocks(text) == [
            .paragraph("Summary line."),
            .paragraph("Details that were indented."),
        ])
    }

    @Test func twoTrailingSpacesKeepALineBreak() {
        #expect(DescriptionFormat.blocks("first line  \nsecond line") == [.paragraph("first line\nsecond line")])
    }

    @Test func numbersWithoutTheMarkerShapeAreText() {
        #expect(DescriptionFormat.blocks("2024 was the year.") == [.paragraph("2024 was the year.")])
        #expect(DescriptionFormat.blocks("3.14 is pi.") == [.paragraph("3.14 is pi.")])
    }

    @Test func plainTextForTooltips() {
        let text = "Do the thing\nquickly.\n\n- a\n* b\n\nEnd."
        #expect(DescriptionFormat.plainText(text) == "Do the thing quickly.\n\n- a\n* b\n\nEnd.", "markers as typed")
    }

    @Test func codeSpansKeepTheirSpacesTogether() {
        let nbsp = "\u{00A0}"
        #expect(DescriptionFormat.keepingCodeSpansTogether("use `a b c` or `x`") == "use `a\(nbsp)b\(nbsp)c` or `x`")
        #expect(DescriptionFormat.keepingCodeSpansTogether("``a ` b`` then") == "``a\(nbsp)`\(nbsp)b`` then", "runs pair by length")
        #expect(DescriptionFormat.keepingCodeSpansTogether("an `unclosed span") == "an `unclosed span")
        #expect(DescriptionFormat.blocks("call\n`do it`") == [.paragraph("call `do\(nbsp)it`")])
    }

    @Test func inlineMarkdownMarksCodeAndSurvivesOddText() {
        let rendered = DescriptionText.inline("Use `limit` here")
        #expect(rendered.runs.contains { $0.inlinePresentationIntent == .code })
        #expect(String(DescriptionText.inline("a * b and [x").characters) == "a * b and [x")
    }
}
