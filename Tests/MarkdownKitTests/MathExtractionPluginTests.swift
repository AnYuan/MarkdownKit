import XCTest
@testable import MarkdownKit

final class MathExtractionPluginTests: XCTestCase {

    func testFencedMathCodeBlockConvertsToBlockMathNode() throws {
        let markdown = """
        ```math
        \\frac{n(n+1)}{2}
        ```
        """

        let doc = TestHelper.parse(markdown, plugins: [MathExtractionPlugin()])
        guard let math = doc.children.first as? MathNode else {
            XCTFail("Expected fenced math block to be converted to MathNode")
            return
        }

        XCTAssertEqual(math.style, .block)
        XCTAssertEqual(math.equation, "\\frac{n(n+1)}{2}")
    }

    func testNonMathFencedCodeBlockRemainsCodeBlockNode() throws {
        let markdown = """
        ```swift
        let x = 1
        ```
        """

        let doc = TestHelper.parse(markdown, plugins: [MathExtractionPlugin()])
        XCTAssertTrue(doc.children.first is CodeBlockNode)
    }

    func testInlineMathParsesMultipleExpressionsInSingleParagraph() throws {
        let markdown = "Before $x$ middle $y^2$ after"
        let doc = TestHelper.parse(markdown, plugins: [MathExtractionPlugin()])

        guard let paragraph = doc.children.first as? ParagraphNode else {
            XCTFail("Expected ParagraphNode")
            return
        }

        XCTAssertEqual(paragraph.children.count, 5)
        XCTAssertEqual((paragraph.children[0] as? TextNode)?.text, "Before ")
        XCTAssertEqual((paragraph.children[1] as? MathNode)?.equation, "x")
        XCTAssertEqual((paragraph.children[2] as? TextNode)?.text, " middle ")
        XCTAssertEqual((paragraph.children[3] as? MathNode)?.equation, "y^2")
        XCTAssertEqual((paragraph.children[4] as? TextNode)?.text, " after")
    }

    func testEscapedDollarDoesNotCreateUnexpectedInlineMath() throws {
        let markdown = #"Escaped \$notMath\$ and real $x$"#
        let doc = TestHelper.parse(markdown, plugins: [MathExtractionPlugin()])

        guard let paragraph = doc.children.first as? ParagraphNode else {
            XCTFail("Expected ParagraphNode")
            return
        }

        let mathNodes = paragraph.children.compactMap { $0 as? MathNode }
        XCTAssertEqual(mathNodes.count, 1)
        XCTAssertEqual(mathNodes.first?.equation, "x")
    }

    func testUnterminatedInlineMathFallsBackToText() throws {
        let markdown = "Price: $x + y"
        let doc = TestHelper.parse(markdown, plugins: [MathExtractionPlugin()])

        guard let paragraph = doc.children.first as? ParagraphNode else {
            XCTFail("Expected ParagraphNode")
            return
        }

        XCTAssertTrue(paragraph.children.allSatisfy { $0 is TextNode })
        let fullText = paragraph.children.compactMap { ($0 as? TextNode)?.text }.joined()
        XCTAssertEqual(fullText, "Price: $x + y")
    }

    // MARK: - Unicode-correctness regression tests
    //
    // `extractInlineMath` previously materialized the input as
    // `[Character]` (grapheme array). Switching to `String.UnicodeScalarView`
    // is allocation-cheaper but slicing now happens at scalar boundaries.
    // These cases make sure emoji + ZWJ sequences in surrounding text don't
    // get mis-sliced — `$` and `\` are ASCII single-scalars so any cut
    // boundary stays inside ASCII and preserves graphemes on either side.

    func testEmojiSurroundingInlineMathSurvivesSlicing() throws {
        // Single-scalar emoji + ZWJ family emoji on both sides of the math.
        let markdown = "Hello 👋 $x$ 👨‍👩‍👧‍👦 done"
        let doc = TestHelper.parse(markdown, plugins: [MathExtractionPlugin()])

        guard let paragraph = doc.children.first as? ParagraphNode else {
            XCTFail("Expected ParagraphNode")
            return
        }
        XCTAssertEqual(paragraph.children.count, 3)

        let leading = paragraph.children[0] as? TextNode
        let math = paragraph.children[1] as? MathNode
        let trailing = paragraph.children[2] as? TextNode

        XCTAssertEqual(leading?.text, "Hello 👋 ")
        XCTAssertEqual(math?.equation, "x")
        XCTAssertEqual(trailing?.text, " 👨‍👩‍👧‍👦 done")
    }

    func testBidiBoundaryAroundInlineMath() throws {
        // RTL Arabic before, LTR after — boundary semantics must hold.
        let markdown = "مرحبا $E=mc^2$ world"
        let doc = TestHelper.parse(markdown, plugins: [MathExtractionPlugin()])

        guard let paragraph = doc.children.first as? ParagraphNode else {
            XCTFail("Expected ParagraphNode")
            return
        }

        let math = paragraph.children.compactMap { $0 as? MathNode }.first
        XCTAssertEqual(math?.equation, "E=mc^2")

        let recovered = paragraph.children.compactMap { ($0 as? TextNode)?.text }.joined()
        XCTAssertEqual(recovered, "مرحبا  world")
    }

    func testBlockMathAcrossParagraphsConvertsToSingleMathNode() throws {
        let markdown = """
        $$

        \\frac{a}{b}

        $$
        """
        let doc = TestHelper.parse(markdown, plugins: [MathExtractionPlugin()])

        guard let math = doc.children.first as? MathNode else {
            XCTFail("Expected block math delimiters to merge into MathNode")
            return
        }

        XCTAssertEqual(math.style, .block)
        XCTAssertEqual(math.equation, "\\frac{a}{b}")
    }
}
