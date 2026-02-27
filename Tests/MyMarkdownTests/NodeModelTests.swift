import XCTest
@testable import MyMarkdown

final class NodeModelTests: XCTestCase {

    // MARK: - Leaf Node Invariants

    func testTextNodeIsLeaf() {
        let node = TextNode(range: nil, text: "hello")
        XCTAssertTrue(node.children.isEmpty)
        XCTAssertEqual(node.text, "hello")
    }

    func testInlineCodeNodeIsLeaf() {
        let node = InlineCodeNode(range: nil, code: "x = 1")
        XCTAssertTrue(node.children.isEmpty)
        XCTAssertEqual(node.code, "x = 1")
    }

    func testCodeBlockNodeIsLeaf() {
        let node = CodeBlockNode(range: nil, language: "swift", code: "print(1)")
        XCTAssertTrue(node.children.isEmpty)
        XCTAssertEqual(node.language, "swift")
        XCTAssertEqual(node.code, "print(1)")
    }

    func testCodeBlockNodeNilLanguage() {
        let node = CodeBlockNode(range: nil, language: nil, code: "echo hi")
        XCTAssertNil(node.language)
    }

    func testImageNodeIsLeaf() {
        let node = ImageNode(range: nil, source: "img.png", altText: "alt", title: "title")
        XCTAssertTrue(node.children.isEmpty)
        XCTAssertEqual(node.source, "img.png")
        XCTAssertEqual(node.altText, "alt")
        XCTAssertEqual(node.title, "title")
    }

    func testImageNodeNilProperties() {
        let node = ImageNode(range: nil, source: nil, altText: nil, title: nil)
        XCTAssertNil(node.source)
        XCTAssertNil(node.altText)
        XCTAssertNil(node.title)
    }

    func testMathNodeIsLeaf() {
        let blockMath = MathNode(range: nil, style: .block, equation: "\\frac{1}{2}")
        XCTAssertTrue(blockMath.children.isEmpty)
        XCTAssertEqual(blockMath.style, .block)
        XCTAssertEqual(blockMath.equation, "\\frac{1}{2}")
        XCTAssertFalse(blockMath.isInline)

        let inlineMath = MathNode(range: nil, style: .inline, equation: "x^2")
        XCTAssertEqual(inlineMath.style, .inline)
        XCTAssertTrue(inlineMath.isInline)
    }

    // MARK: - Container Node Properties

    func testDocumentNodeHoldsChildren() {
        let child = TextNode(range: nil, text: "hi")
        let doc = DocumentNode(range: nil, children: [child])
        XCTAssertEqual(doc.children.count, 1)
    }

    func testHeaderNodeProperties() {
        let text = TextNode(range: nil, text: "Title")
        let header = HeaderNode(range: nil, level: 2, children: [text])
        XCTAssertEqual(header.level, 2)
        XCTAssertEqual(header.children.count, 1)
    }

    func testParagraphNodeHoldsChildren() {
        let text = TextNode(range: nil, text: "body")
        let para = ParagraphNode(range: nil, children: [text])
        XCTAssertEqual(para.children.count, 1)
    }

    func testLinkNodeProperties() {
        let text = TextNode(range: nil, text: "click")
        let link = LinkNode(range: nil, destination: "https://x.com", title: "X", children: [text])
        XCTAssertEqual(link.destination, "https://x.com")
        XCTAssertEqual(link.title, "X")
        XCTAssertEqual(link.children.count, 1)
    }

    func testListNodeIsOrdered() {
        let ordered = ListNode(range: nil, isOrdered: true, children: [])
        XCTAssertTrue(ordered.isOrdered)

        let unordered = ListNode(range: nil, isOrdered: false, children: [])
        XCTAssertFalse(unordered.isOrdered)
    }

    func testListItemNodeCheckboxStates() {
        let checked = ListItemNode(range: nil, checkbox: .checked, children: [])
        XCTAssertEqual(checked.checkbox, .checked)

        let unchecked = ListItemNode(range: nil, checkbox: .unchecked, children: [])
        XCTAssertEqual(unchecked.checkbox, .unchecked)

        let none = ListItemNode(range: nil, children: [])
        XCTAssertEqual(none.checkbox, CheckboxState.none)
    }

    func testTableNodeColumnAlignments() {
        let table = TableNode(range: nil, columnAlignments: [.left, .center, .right, nil], children: [])
        XCTAssertEqual(table.columnAlignments.count, 4)
        XCTAssertEqual(table.columnAlignments[0], .left)
        XCTAssertEqual(table.columnAlignments[1], .center)
        XCTAssertEqual(table.columnAlignments[2], .right)
        XCTAssertNil(table.columnAlignments[3])
    }

    func testDetailsNodeProperties() {
        let summary = SummaryNode(range: nil, children: [TextNode(range: nil, text: "Overview")])
        let details = DetailsNode(
            range: nil,
            isOpen: true,
            summary: summary,
            children: [ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Body")])]
        )

        XCTAssertTrue(details.isOpen)
        XCTAssertEqual((details.summary?.children.first as? TextNode)?.text, "Overview")
        XCTAssertEqual(details.children.count, 1)
    }

    func testSummaryNodeHoldsChildren() {
        let summary = SummaryNode(range: nil, children: [TextNode(range: nil, text: "Summary text")])
        XCTAssertEqual(summary.children.count, 1)
    }

    func testDiagramNodeProperties() {
        let node = DiagramNode(range: nil, language: .mermaid, source: "graph TD\nA-->B\n")
        XCTAssertEqual(node.language, .mermaid)
        XCTAssertEqual(node.source, "graph TD\nA-->B\n")
        XCTAssertTrue(node.children.isEmpty)
    }

    // MARK: - UUID Uniqueness

    func testEachNodeHasUniqueID() {
        let nodeA = TextNode(range: nil, text: "a")
        let nodeB = TextNode(range: nil, text: "a") // same content
        XCTAssertNotEqual(nodeA.id, nodeB.id)
    }
}
