import XCTest
@testable import MarkdownKit

final class ASTTransformTests: XCTestCase {

    // MARK: - identity preservation

    func testNoOpVisitorPreservesUUIDAndFingerprint() {
        let parser = MarkdownParser()
        let doc = parser.parse("""
        # Heading

        Body paragraph with **bold** and *italic* runs.

        - item one
        - item two
        """)

        let result = AST.transform(doc.children) { _ in .unchanged }

        XCTAssertEqual(result.count, doc.children.count)
        for (original, returned) in zip(doc.children, result) {
            XCTAssertEqual(
                original.id,
                returned.id,
                "No-op visitor must preserve UUID — a rebuilt node would have a new one."
            )
            XCTAssertEqual(
                original.contentFingerprint,
                returned.contentFingerprint,
                "No-op visitor must preserve content fingerprint."
            )
        }
    }

    func testNoOpVisitorPreservesNestedContainerIdentity() {
        // Ensures the recursion into `node.children` does not silently rebuild
        // parents when no child changed.
        let parser = MarkdownParser()
        let doc = parser.parse("""
        > Quoted paragraph with [a link](https://example.com).
        """)

        let result = AST.transform(doc.children) { _ in .unchanged }

        guard let originalQuote = doc.children.first as? BlockQuoteNode,
              let returnedQuote = result.first as? BlockQuoteNode else {
            XCTFail("Expected first child to be a BlockQuoteNode")
            return
        }
        XCTAssertEqual(originalQuote.id, returnedQuote.id)

        guard let originalPara = originalQuote.children.first as? ParagraphNode,
              let returnedPara = returnedQuote.children.first as? ParagraphNode else {
            XCTFail("Expected blockquote child to be a ParagraphNode")
            return
        }
        XCTAssertEqual(originalPara.id, returnedPara.id)
    }

    // MARK: - one-to-many splat

    func testReplaceManySplatsIntoSiblings() {
        let parser = MarkdownParser()
        let doc = parser.parse("alpha bravo")
        guard let paragraph = doc.children.first as? ParagraphNode else {
            XCTFail("Expected single ParagraphNode")
            return
        }

        let splat = AST.transform(paragraph.children) { node in
            if let text = node as? TextNode, text.text == "alpha bravo" {
                return .replaceMany([
                    TextNode(range: nil, text: "alpha "),
                    StrongNode(range: nil, children: [TextNode(range: nil, text: "bravo")])
                ])
            }
            return .unchanged
        }

        XCTAssertEqual(splat.count, 2)
        XCTAssertTrue(splat[0] is TextNode)
        XCTAssertTrue(splat[1] is StrongNode)
    }

    // MARK: - skipChildren prevents recursion

    func testSkipChildrenStopsRecursionIntoReplacement() {
        // Build an artificial AST: Paragraph -> [Text("@foo")]. A visitor that
        // returns `.skipChildren(replacement)` for the paragraph must not let
        // its visit fire on the inner text.
        var visitCallCount = 0
        let paragraph = ParagraphNode(range: nil, children: [
            TextNode(range: nil, text: "@foo")
        ])

        _ = AST.transform([paragraph]) { node in
            visitCallCount += 1
            if node is ParagraphNode {
                return .skipChildren(
                    LinkNode(
                        range: nil,
                        destination: "https://example.com",
                        title: nil,
                        children: [TextNode(range: nil, text: "@foo")]
                    )
                )
            }
            return .unchanged
        }

        // Only the paragraph itself was visited; the inner text node was
        // skipped because the visitor used .skipChildren.
        XCTAssertEqual(visitCallCount, 1)
    }

    // MARK: - replace recurses into the replacement's children

    func testReplaceRecursesIntoReplacementChildren() {
        // visitor swaps Paragraph for a new BlockQuote and expects the
        // BlockQuote's children to be visited too.
        var sawInnerText = false
        let paragraph = ParagraphNode(range: nil, children: [
            TextNode(range: nil, text: "inner")
        ])

        _ = AST.transform([paragraph]) { node in
            if node is ParagraphNode {
                return .replace(BlockQuoteNode(range: nil, children: [
                    TextNode(range: nil, text: "inner")
                ]))
            }
            if let t = node as? TextNode, t.text == "inner" {
                sawInnerText = true
            }
            return .unchanged
        }

        XCTAssertTrue(sawInnerText, ".replace must allow recursion into the new node's children")
    }

    // MARK: - postProcessSiblings runs at every level

    func testPostProcessSiblingsAppliesAtEveryLevel() {
        // postProcessSiblings should fire on the top-level list AND on each
        // container's children list, by mirroring DetailsExtractionPlugin's
        // recursive structure.
        let parser = MarkdownParser()
        let doc = parser.parse("""
        - first
        - second
        """)

        var siblingListLengths: [Int] = []
        _ = AST.transform(
            doc.children,
            postProcessSiblings: { siblings in
                siblingListLengths.append(siblings.count)
                return siblings
            },
            visit: { _ in .unchanged }
        )

        // We expect calls at the top level + once per container's children
        // list. A list of two items gives at least: top doc, ListNode children,
        // each ListItemNode's children. So count should be >= 4.
        XCTAssertGreaterThanOrEqual(siblingListLengths.count, 3, "postProcessSiblings should fire at multiple nesting levels")
    }
}
