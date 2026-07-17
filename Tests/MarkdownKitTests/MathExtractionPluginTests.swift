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

    func testTopLevelStandaloneBlockMathBecomesDirectMathNode() throws {
        // Pin the pre-Q09 root shape: a same-paragraph `$$x$$` at the document
        // root becomes a direct MathNode sibling, not a MathNode wrapped in
        // a ParagraphNode.
        let markdown = "$$x$$"
        let doc = TestHelper.parse(markdown, plugins: [MathExtractionPlugin()])

        XCTAssertEqual(doc.children.count, 1)
        guard let math = doc.children.first as? MathNode else {
            XCTFail("Expected a top-level standalone $$x$$ to become a direct MathNode sibling")
            return
        }
        XCTAssertEqual(math.style, .block)
        XCTAssertEqual(math.equation, "x")
    }

    // MARK: - Nested sibling-merge regressions (Q09)
    //
    // `mergeBlockMath` previously only ran once on document-root siblings via
    // a direct call in `visit`. Opener/interior/closer paragraphs nested
    // inside a BlockQuoteNode, ListItemNode, DetailsNode, etc. never reached
    // it. It now also runs as `AST.transform`'s `postProcessSiblings` hook,
    // which recurses into every container's sibling list — but with
    // `mergeStandalone: false`, so a nested same-paragraph `$$x$$` is left
    // wrapped in its ParagraphNode (matching pre-Q09 behavior, where it fell
    // through to `extractInlineMath`'s block-math-in-paragraph branch)
    // instead of collapsing to a bare MathNode sibling like the root does.

    func testBlockMathMergesInsideNestedBlockquote() throws {
        let markdown = """
        > $$
        >
        > \\frac{a}{b}
        >
        > $$
        """
        let doc = TestHelper.parse(markdown, plugins: [MathExtractionPlugin()])

        guard let quote = doc.children.first as? BlockQuoteNode else {
            XCTFail("Expected BlockQuoteNode")
            return
        }
        XCTAssertEqual(quote.children.count, 1)
        guard let math = quote.children.first as? MathNode else {
            XCTFail("Expected the three nested paragraphs to merge into one MathNode")
            return
        }
        XCTAssertEqual(math.style, .block)
        XCTAssertEqual(math.equation, "\\frac{a}{b}")
    }

    func testStandaloneBlockMathNestedInListItemStaysWrappedInParagraph() throws {
        // Regression: the recursive nested pass must NOT collapse a
        // same-paragraph "$$x$$" into a direct MathNode sibling the way the
        // root pass does. It must stay `ListItem -> Paragraph -> MathNode`
        // (via `extractInlineMath`'s third pass), preserving paragraph
        // spacing/layout for nested content.
        let markdown = "- $$x$$"
        let doc = TestHelper.parse(markdown, plugins: [MathExtractionPlugin()])

        guard let list = doc.children.first as? ListNode,
              let item = list.children.first as? ListItemNode else {
            XCTFail("Expected ListNode > ListItemNode")
            return
        }
        XCTAssertEqual(item.children.count, 1)
        guard let paragraph = item.children.first as? ParagraphNode else {
            XCTFail("Expected the list item's content to remain wrapped in a ParagraphNode")
            return
        }
        guard let math = paragraph.children.first as? MathNode else {
            XCTFail("Expected the paragraph to contain a block MathNode")
            return
        }
        XCTAssertEqual(math.style, .block)
        XCTAssertEqual(math.equation, "x")
    }

    func testBlockMathMergesInsideDetailsBodyAndRebuildsOnlyThatContainer() throws {
        let unrelatedSibling = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "unrelated")])
        let details = DetailsNode(
            range: nil,
            isOpen: true,
            summary: nil,
            children: [
                ParagraphNode(range: nil, children: [TextNode(range: nil, text: "$$")]),
                ParagraphNode(range: nil, children: [TextNode(range: nil, text: "\\frac{a}{b}")]),
                ParagraphNode(range: nil, children: [TextNode(range: nil, text: "$$")])
            ]
        )
        let unrelatedSiblingID = unrelatedSibling.id
        let detailsID = details.id

        let result = MathExtractionPlugin().visit([unrelatedSibling, details])

        XCTAssertEqual(result.count, 2)
        // The sibling outside the DetailsNode has no math and no formatting
        // change, so its identity must survive untouched.
        XCTAssertEqual(result[0].id, unrelatedSiblingID)

        guard let rebuiltDetails = result[1] as? DetailsNode else {
            XCTFail("Expected DetailsNode to remain a DetailsNode")
            return
        }
        // Its children changed (3 paragraphs -> 1 MathNode), so only this
        // container was rebuilt — proven by its UUID differing from the
        // original while the unrelated sibling's UUID above did not change.
        XCTAssertNotEqual(rebuiltDetails.id, detailsID)
        XCTAssertEqual(rebuiltDetails.children.count, 1)
        guard let math = rebuiltDetails.children.first as? MathNode else {
            XCTFail("Expected the DetailsNode body's three paragraphs to merge into one MathNode")
            return
        }
        XCTAssertEqual(math.style, .block)
        XCTAssertEqual(math.equation, "\\frac{a}{b}")
    }

    func testMixedContentSpanWithCodeBlockDoesNotMergeAndPreservesMiddleNode() throws {
        let opener = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "$$")])
        let code = CodeBlockNode(range: nil, language: "swift", code: "let x = 1")
        let closer = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "$$")])

        let result = MathExtractionPlugin().visit([opener, code, closer])

        XCTAssertEqual(result.count, 3, "A non-plain-text sibling must abort the merge, not collapse the span")
        XCTAssertTrue(result[0] is ParagraphNode)
        guard let resultCode = result[1] as? CodeBlockNode else {
            XCTFail("Expected the CodeBlockNode to survive untouched between unmatched $$ delimiters")
            return
        }
        XCTAssertEqual(resultCode.code, "let x = 1")
        XCTAssertEqual(resultCode.language, "swift")
        XCTAssertTrue(result[2] is ParagraphNode)
    }

    func testMixedContentSpanWithFormattedParagraphDoesNotMerge() throws {
        // A paragraph whose child isn't a plain TextNode must make
        // `extractPlainText` return nil (strict extraction), classifying the
        // paragraph as `.other` rather than silently discarding the StrongNode.
        let opener = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "$$")])
        let formattedMiddle = ParagraphNode(range: nil, children: [
            StrongNode(range: nil, children: [TextNode(range: nil, text: "bold")])
        ])
        let closer = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "$$")])

        let result = MathExtractionPlugin().visit([opener, formattedMiddle, closer])

        XCTAssertEqual(result.count, 3)
        guard let middle = result[1] as? ParagraphNode,
              let strong = middle.children.first as? StrongNode,
              let boldText = strong.children.first as? TextNode else {
            XCTFail("Expected the formatted middle paragraph to survive untouched")
            return
        }
        XCTAssertEqual(boldText.text, "bold")
    }

    func testNoOpPreservesUUIDsAtEveryNestedLevel() throws {
        let text = TextNode(range: nil, text: "plain text, no math here")
        let paragraph = ParagraphNode(range: nil, children: [text])
        let listItem = ListItemNode(range: nil, children: [paragraph])
        let list = ListNode(range: nil, isOrdered: false, children: [listItem])
        let quote = BlockQuoteNode(range: nil, children: [list])

        let result = MathExtractionPlugin().visit([quote])

        XCTAssertEqual(result.count, 1)
        guard let resultQuote = result[0] as? BlockQuoteNode else {
            XCTFail("Expected BlockQuoteNode to survive untouched")
            return
        }
        XCTAssertEqual(resultQuote.id, quote.id)

        guard let resultList = resultQuote.children.first as? ListNode else {
            XCTFail("Expected nested ListNode")
            return
        }
        XCTAssertEqual(resultList.id, list.id)

        guard let resultListItem = resultList.children.first as? ListItemNode else {
            XCTFail("Expected nested ListItemNode")
            return
        }
        XCTAssertEqual(resultListItem.id, listItem.id)

        guard let resultParagraph = resultListItem.children.first as? ParagraphNode else {
            XCTFail("Expected nested ParagraphNode")
            return
        }
        XCTAssertEqual(resultParagraph.id, paragraph.id)

        guard let resultText = resultParagraph.children.first as? TextNode else {
            XCTFail("Expected nested TextNode")
            return
        }
        XCTAssertEqual(resultText.id, text.id)
        XCTAssertEqual(resultText.text, text.text)
    }

    // MARK: - Malformed input regression

    func testUnclosedBareDoubleDollarOpenerPreservesAllContentWithoutFalseMathNode() throws {
        // A bare "$$" opener with no matching closer anywhere in the sibling
        // list must not produce a false MathNode; all original content stays.
        let markdown = """
        $$

        Some prose that never closes the block.
        """
        let doc = TestHelper.parse(markdown, plugins: [MathExtractionPlugin()])

        XCTAssertEqual(doc.children.count, 2)
        XCTAssertTrue(doc.children.allSatisfy { !($0 is MathNode) })

        let fullText = doc.children
            .compactMap { $0 as? ParagraphNode }
            .flatMap { $0.children }
            .compactMap { ($0 as? TextNode)?.text }
            .joined()
        XCTAssertEqual(fullText, "$$Some prose that never closes the block.")
    }
}
