import Foundation
import Testing
@testable import mcprotocol2human_surface

struct ToolFilterTests {
    let tools = [
        ToolInfo(raw: ["name": "list_items", "description": "List every item."], position: 0),
        ToolInfo(raw: ["name": "get_item", "title": "Fetch One", "description": "Return one item."], position: 1),
        ToolInfo(raw: ["name": "status", "description": "Server status."], position: 2),
    ]

    func names(_ filter: ToolFilter) -> [String] { filter.apply(tools).map(\.name) }

    @Test func matchesNameTitleAndDescriptionIgnoringCase() {
        #expect(names(ToolFilter(text: "ITEM")) == ["list_items", "get_item"])
        #expect(names(ToolFilter(text: "fetch")) == ["get_item"])
        #expect(names(ToolFilter(text: "server")) == ["status"])
    }

    @Test func namesOnlyLeavesDescriptionsOut() {
        #expect(names(ToolFilter(text: "every", namesOnly: true)) == [])
        #expect(names(ToolFilter(text: "fetch", namesOnly: true)) == ["get_item"], "the title counts as a name")
    }

    @Test func invertedShowsWhatDoesNotMatch() {
        #expect(names(ToolFilter(text: "item", inverted: true)) == ["status"])
        #expect(names(ToolFilter(text: "item", namesOnly: true, inverted: true)) == ["status"])
    }

    @Test func emptyTextShowsEverythingEvenInverted() {
        #expect(names(ToolFilter(text: "  ", inverted: true)).count == 3)
        #expect(!ToolFilter(text: " ").isActive)
    }

    @Test func headerSaysWhatIsShown() {
        #expect(ToolFilter().header(shown: 3, total: 3) == "Tools (3)")
        #expect(ToolFilter(text: "x").header(shown: 1, total: 3) == "Tools (1 of 3)")
        #expect(ToolFilter(text: "x", inverted: true).header(shown: 2, total: 3) == "Tools not matching (2 of 3)")
    }
}
