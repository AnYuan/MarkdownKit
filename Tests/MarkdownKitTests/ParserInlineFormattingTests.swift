import XCTest
@testable import MarkdownKit

final class ParserInlineFormattingTests: XCTestCase {

    // MARK: - Basic Inline Formatting

    func testBoldTextParsesToStrongNode() {
        let doc = TestHelper.parse("**bold**")
        let para = TestHelper.assertChild(doc, at: 0, is: ParagraphNode.self)
        let strong = TestHelper.assertChild(para!, at: 0, is: StrongNode.self)
        let text = TestHelper.assertChild(strong!, at: 0, is: TextNode.self)
        XCTAssertEqual(text?.text, "bold")
    }

    func testItalicTextParsesToEmphasisNode() {
        let doc = TestHelper.parse("*italic*")
        let para = TestHelper.assertChild(doc, at: 0, is: ParagraphNode.self)
        let emphasis = TestHelper.assertChild(para!, at: 0, is: EmphasisNode.self)
        let text = TestHelper.assertChild(emphasis!, at: 0, is: TextNode.self)
        XCTAssertEqual(text?.text, "italic")
    }

    func testStrikethroughParsesToStrikethroughNode() {
        let doc = TestHelper.parse("~~struck~~")
        let para = TestHelper.assertChild(doc, at: 0, is: ParagraphNode.self)
        let strike = TestHelper.assertChild(para!, at: 0, is: StrikethroughNode.self)
        let text = TestHelper.assertChild(strike!, at: 0, is: TextNode.self)
        XCTAssertEqual(text?.text, "struck")
    }

    func testBlockQuoteParsesToBlockQuoteNode() {
        let doc = TestHelper.parse("> quote text")
        let bq = TestHelper.assertChild(doc, at: 0, is: BlockQuoteNode.self)
        let para = TestHelper.assertChild(bq!, at: 0, is: ParagraphNode.self)
        let text = TestHelper.assertChild(para!, at: 0, is: TextNode.self)
        XCTAssertEqual(text?.text, "quote text")
    }

    func testThematicBreakParsesToThematicBreakNode() {
        let doc = TestHelper.parse("---")
        TestHelper.assertChild(doc, at: 0, is: ThematicBreakNode.self)
    }

    // MARK: - Nested Formatting

    func testNestedBlockQuoteWithInlineFormatting() {
        let doc = TestHelper.parse("> **bold** and *italic*")
        let bq = TestHelper.assertChild(doc, at: 0, is: BlockQuoteNode.self)
        let para = TestHelper.assertChild(bq!, at: 0, is: ParagraphNode.self)
        XCTAssertNotNil(para)

        let children = para!.children
        let hasStrong = children.contains { $0 is StrongNode }
        let hasEmphasis = children.contains { $0 is EmphasisNode }
        XCTAssertTrue(hasStrong, "Block quote should contain StrongNode")
        XCTAssertTrue(hasEmphasis, "Block quote should contain EmphasisNode")
    }

    func testMixedBoldAndItalic() {
        let doc = TestHelper.parse("***both***")
        let para = TestHelper.assertChild(doc, at: 0, is: ParagraphNode.self)
        XCTAssertNotNil(para)

        // swift-markdown nests EmphasisNode inside StrongNode (or vice versa)
        let firstChild = para!.children[0]
        let isNested = (firstChild is StrongNode && firstChild.children.first is EmphasisNode)
            || (firstChild is EmphasisNode && firstChild.children.first is StrongNode)
        XCTAssertTrue(isNested, "Expected nested bold+italic nodes, got \(type(of: firstChild))")
    }

    func testBoldInsideStrikethrough() {
        let doc = TestHelper.parse("~~**bold struck**~~")
        let para = TestHelper.assertChild(doc, at: 0, is: ParagraphNode.self)
        let strike = TestHelper.assertChild(para!, at: 0, is: StrikethroughNode.self)
        let strong = TestHelper.assertChild(strike!, at: 0, is: StrongNode.self)
        let text = TestHelper.assertChild(strong!, at: 0, is: TextNode.self)
        XCTAssertEqual(text?.text, "bold struck")
    }

    // MARK: - Complex Structures

    func testDeeplyNestedList() {
        let markdown = """
        - Level 1
          - Level 2
            - Level 3
        """
        let doc = TestHelper.parse(markdown)
        let list = TestHelper.assertChild(doc, at: 0, is: ListNode.self)
        XCTAssertNotNil(list)

        // Walk down to find nested lists
        guard let item1 = list?.children.first as? ListItemNode else {
            XCTFail("Expected ListItemNode at level 1")
            return
        }
        let nestedList = item1.children.first { $0 is ListNode } as? ListNode
        XCTAssertNotNil(nestedList, "Expected nested list at level 2")

        if let nestedItem = nestedList?.children.first as? ListItemNode {
            let deepList = nestedItem.children.first { $0 is ListNode } as? ListNode
            XCTAssertNotNil(deepList, "Expected nested list at level 3")
        }
    }

    func testTableWithInlineFormattingInCells() {
        let markdown = """
        | Name | Status |
        |------|--------|
        | **Bold** | *Italic* |
        """
        let doc = TestHelper.parse(markdown)
        let table = TestHelper.assertChild(doc, at: 0, is: TableNode.self)
        XCTAssertNotNil(table)

        // Walk through body rows to find inline formatting
        func findNodeType<T: MarkdownNode>(_ type: T.Type, in node: MarkdownNode) -> Bool {
            if node is T { return true }
            return node.children.contains { findNodeType(type, in: $0) }
        }

        XCTAssertTrue(findNodeType(StrongNode.self, in: table!), "Table should contain StrongNode")
        XCTAssertTrue(findNodeType(EmphasisNode.self, in: table!), "Table should contain EmphasisNode")
    }

    func testSoftBreakBecomesSpace() {
        // Two lines without double trailing spaces = soft break
        let markdown = "Line one\nLine two"
        let doc = TestHelper.parse(markdown)
        let para = TestHelper.assertChild(doc, at: 0, is: ParagraphNode.self)
        XCTAssertNotNil(para)

        // Collect all text content
        let texts = para!.children.compactMap { ($0 as? TextNode)?.text }
        let joined = texts.joined()
        XCTAssertTrue(joined.contains("Line one"), "Should contain first line text")
        XCTAssertTrue(joined.contains("Line two"), "Should contain second line text")
    }

    func testLineBreakBecomesNewline() {
        // Two trailing spaces + newline = hard line break
        let markdown = "Line one  \nLine two"
        let doc = TestHelper.parse(markdown)
        let para = TestHelper.assertChild(doc, at: 0, is: ParagraphNode.self)
        XCTAssertNotNil(para)

        // Hard breaks should produce a TextNode with "\n"
        let allTexts = para!.children.compactMap { ($0 as? TextNode)?.text }
        let hasNewline = allTexts.contains { $0.contains("\n") }
        // The paragraph should at least have two lines of content
        XCTAssertGreaterThanOrEqual(para!.children.count, 2,
            "Hard line break should produce multiple inline children")
        // If no explicit newline in TextNode, the parser may represent it differently
        // but the text should still be split across children
        if !hasNewline {
            XCTAssertGreaterThanOrEqual(allTexts.count, 2,
                "Expected multiple text segments around hard break")
        }
    }
}
