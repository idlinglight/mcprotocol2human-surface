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

    @Test func fencedCodeStaysAsItIsFencesIncluded() {
        let text = "Example:\n```json\n{\"a\": 1,\n  \"b\": 2}\n```\nDone."
        #expect(DescriptionFormat.blocks(text) == [
            .paragraph("Example:"),
            .code("```json\n{\"a\": 1,\n  \"b\": 2}\n```"),
            .paragraph("Done."),
        ])
        #expect(DescriptionFormat.blocks("```\nnever closed") == [.code("```\nnever closed")])
    }

    @Test func keptLinesStayUnits() {
        let text = "First sentence.\nSecond one,\nwith a clause.\n\n- item\n  continued"
        #expect(DescriptionFormat.blocks(text, lines: .kept) == [
            .paragraph("First sentence.\nSecond one,\nwith a clause."),
            .listItem(marker: "-", text: "item\ncontinued", level: 0),
        ])
    }

    @Test func keptLinesJoinWhereACodeSpanWouldBeSplit() {
        let nbsp = "\u{00A0}"
        #expect(DescriptionFormat.blocks("Pass `a\nb` here.\nNext line.", lines: .kept)
            == [.paragraph("Pass `a\(nbsp)b` here.\nNext line.")])
        // A lone backtick that nothing closes does not swallow the following lines.
        #expect(DescriptionFormat.blocks("Type a ` to quote.\nNext line.", lines: .kept)
            == [.paragraph("Type a ` to quote.\nNext line.")])
        // Runs pair by length: a single backtick inside a double-backtick span does not close it.
        #expect(DescriptionFormat.blocks("Use ``x `\ny`` now.", lines: .kept)
            == [.paragraph("Use ``x\(nbsp)`\(nbsp)y`` now.")])
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
