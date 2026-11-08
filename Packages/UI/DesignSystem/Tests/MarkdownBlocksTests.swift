@testable import DesignSystem
import Testing

struct MarkdownBlocksTests {
    @Test func `a table loses its pipes, its divider, and its column names`() {
        let blocks = MarkdownBlock.parse("""
        ## Software

        | Package | License |
        |---|---|
        | GRDB | MIT |
        | FluidAudio | Apache-2.0 |
        """)
        #expect(blocks == [
            .heading("Software"),
            .table(rows: [["GRDB", "MIT"], ["FluidAudio", "Apache-2.0"]]),
        ])
    }

    @Test func `a paragraph after a table starts a new block`() {
        let blocks = MarkdownBlock.parse("""
        | A | B |
        |---|:--|
        | 1 | 2 |
        Some text
        - An item
        """)
        #expect(blocks == [.table(rows: [["1", "2"]]), .paragraph("Some text"), .bullet("An item")])
    }

    @Test func `a link inside a cell survives`() {
        let blocks = MarkdownBlock.parse("""
        | Name |
        |---|
        | [GRDB](https://example.com/a|b) |
        """)
        #expect(blocks.count == 1)
    }
}
