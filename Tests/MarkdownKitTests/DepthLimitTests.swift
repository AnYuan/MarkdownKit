import XCTest
import Markdown
@testable import MarkdownKit

final class DepthLimitTests: XCTestCase {

    /// `ResourceLimits.default` documents (and this pins) a maximum native-AST
    /// container-nesting depth of 50 beneath the root document.
    func testDefaultResourceLimitsMaximumNestingDepthIsFifty() {
        XCTAssertEqual(MarkdownParser.ResourceLimits.default.maximumNestingDepth, 50)
    }

    func testDeeplyNestedBlockquotesAreProgrammaticallyTruncated() {
        // Construct a maliciously deep blockquote payload. 200 levels is comfortably
        // past the default 50-level budget while staying fast to parse.
        let maliciousDepth = 200
        var maliciousPayload = ""
        for _ in 0..<maliciousDepth {
            maliciousPayload += "> "
        }
        maliciousPayload += "Hello"

        let parser = MarkdownParser()
        let outcome = parser.parseOutcome(maliciousPayload)

        guard case .parsed(let document, let diagnostics) = outcome else {
            return XCTFail("Depth-truncated input should still parse, not be rejected.")
        }

        // Exactly one typed diagnostic reports the truncation, at the configured maximum.
        XCTAssertEqual(diagnostics, [.maximumNestingDepthExceeded(maximumDepth: 50)])

        // Walk the retained BlockQuoteNode prefix. The root Document is not counted,
        // so exactly 50 nested BlockQuoteNodes are retained, and the 50th (boundary)
        // node has its descendants omitted rather than included.
        var retainedDepth = 0
        var currentNode: MarkdownNode? = document.children.first
        var lastBlockQuote: BlockQuoteNode?
        while let node = currentNode as? BlockQuoteNode {
            retainedDepth += 1
            lastBlockQuote = node
            currentNode = node.children.first
        }

        XCTAssertEqual(retainedDepth, 50, "Expected exactly 50 retained BlockQuoteNode levels at the default depth budget.")
        XCTAssertEqual(lastBlockQuote?.children.isEmpty, true, "The boundary BlockQuoteNode should have its descendants truncated (empty children).")
    }

    func testLegacyParseReturnsPartialDocumentForDepthTruncation() {
        let maliciousDepth = 200
        var maliciousPayload = ""
        for _ in 0..<maliciousDepth {
            maliciousPayload += "> "
        }
        maliciousPayload += "Hello"

        let parser = MarkdownParser()
        let document = parser.parse(maliciousPayload)

        var retainedDepth = 0
        var currentNode: MarkdownNode? = document.children.first
        while let node = currentNode as? BlockQuoteNode, let next = node.children.first {
            retainedDepth += 1
            currentNode = next
        }

        // The legacy lossy API still returns the same retained/truncated prefix,
        // never exceeding the default 50-level native-mapping limit.
        XCTAssertLessThanOrEqual(retainedDepth, 50, "Parser allowed nested depth to exceed the security limit.")
        XCTAssertFalse(document.children.isEmpty, "Legacy parse should still return a partial (non-empty) document for depth truncation, not the empty-input fallback.")
    }
}
