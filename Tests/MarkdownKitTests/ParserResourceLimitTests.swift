import XCTest
import Markdown
@testable import MarkdownKit

/// Exhaustive fast-gate contract tests for Q07's per-parser `ResourceLimits` /
/// `ParseOutcome` API surface: normalization, byte/depth boundary semantics,
/// plugin invocation rules, and the public entry points that thread limits
/// through (`MarkdownKitEngine.makeParser`, `MarkdownView`).
final class ParserResourceLimitTests: XCTestCase {

    // MARK: - Test doubles

    /// Records plugin invocation order. A plain reference type is sufficient here:
    /// every test in this file drives its parser synchronously from a single task,
    /// so no cross-task sharing (and therefore no `Sendable` requirement) is needed.
    private final class PluginCallRecorder {
        private(set) var order: [String] = []
        func record(_ name: String) {
            order.append(name)
        }
    }

    private final class RecordingPlugin: ASTPlugin {
        private let name: String
        private let recorder: PluginCallRecorder

        init(name: String, recorder: PluginCallRecorder) {
            self.name = name
            self.recorder = recorder
        }

        func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
            recorder.record(name)
            return nodes
        }
    }

    // MARK: - Default values and normalization

    func testDefaultResourceLimitsValues() {
        let defaults = MarkdownParser.ResourceLimits.default
        XCTAssertEqual(defaults.maximumInputBytes, 1_048_576)
        XCTAssertEqual(defaults.maximumNestingDepth, 50)
        XCTAssertEqual(MarkdownParser.ResourceLimits(), defaults)
    }

    func testResourceLimitsNormalizesNegativeAndZeroValues() {
        XCTAssertEqual(MarkdownParser.ResourceLimits(maximumInputBytes: -100).maximumInputBytes, 0)
        XCTAssertEqual(MarkdownParser.ResourceLimits(maximumInputBytes: 0).maximumInputBytes, 0)
        XCTAssertEqual(MarkdownParser.ResourceLimits(maximumNestingDepth: 0).maximumNestingDepth, 1)
        XCTAssertEqual(MarkdownParser.ResourceLimits(maximumNestingDepth: -50).maximumNestingDepth, 1)
    }

    // MARK: - Compile-time Sendable checks (ResourceLimits, Diagnostic, ParseOutcome only)

    func testResourceLimitsDiagnosticAndParseOutcomeAreSendable() {
        func requireSendable<T: Sendable>(_: T) {}

        let limits = MarkdownParser.ResourceLimits(maximumInputBytes: 100, maximumNestingDepth: 5)
        let diagnostic = MarkdownParser.Diagnostic.inputTooLarge(actualBytes: 200, maximumBytes: 100)
        let outcome = MarkdownParser.ParseOutcome.rejected(diagnostic: diagnostic)

        requireSendable(limits)
        requireSendable(diagnostic)
        requireSendable(outcome)
    }

    // MARK: - Empty input

    func testEmptyInputParsesToEmptyDocumentWithNoDiagnostics() {
        let parser = MarkdownParser()
        let outcome = parser.parseOutcome("")

        guard case .parsed(let document, let diagnostics) = outcome else {
            return XCTFail("Empty input should parse, not be rejected.")
        }

        XCTAssertTrue(diagnostics.isEmpty)
        XCTAssertNotNil(outcome.document)
        XCTAssertTrue(document.children.isEmpty)
        XCTAssertFalse(outcome.isRejected)
    }

    // MARK: - Zero-byte limit

    func testZeroByteLimitAcceptsEmptyInputAndRejectsNonemptyInput() {
        let parser = MarkdownParser(limits: .init(maximumInputBytes: 0))

        let emptyOutcome = parser.parseOutcome("")
        XCTAssertFalse(emptyOutcome.isRejected)
        XCTAssertEqual(emptyOutcome.document?.children.isEmpty, true)

        let nonEmptyOutcome = parser.parseOutcome("a")
        XCTAssertTrue(nonEmptyOutcome.isRejected)
        XCTAssertNil(nonEmptyOutcome.document)
        XCTAssertEqual(nonEmptyOutcome.diagnostics, [.inputTooLarge(actualBytes: 1, maximumBytes: 0)])
    }

    // MARK: - ASCII byte boundary

    func testASCIIExactBoundaryAcceptedAndMaxPlusOneRejected() {
        let parser = MarkdownParser(limits: .init(maximumInputBytes: 10))
        let exact = String(repeating: "a", count: 10)
        let over = String(repeating: "a", count: 11)

        let exactOutcome = parser.parseOutcome(exact)
        XCTAssertFalse(exactOutcome.isRejected)
        XCTAssertNotNil(exactOutcome.document)
        XCTAssertTrue(exactOutcome.diagnostics.isEmpty)

        let overOutcome = parser.parseOutcome(over)
        XCTAssertTrue(overOutcome.isRejected)
        XCTAssertNil(overOutcome.document)
        XCTAssertEqual(overOutcome.diagnostics, [.inputTooLarge(actualBytes: 11, maximumBytes: 10)])

        guard case .rejected(let diagnostic) = overOutcome else {
            return XCTFail("Expected a .rejected outcome for input exceeding the byte boundary.")
        }
        guard case .inputTooLarge(let actualBytes, let maximumBytes) = diagnostic else {
            return XCTFail("Expected an .inputTooLarge diagnostic.")
        }
        XCTAssertEqual(actualBytes, 11)
        XCTAssertEqual(maximumBytes, 10)
    }

    // MARK: - Multibyte UTF-8 boundary

    func testMultibyteUTF8ExactAndMaxPlusOneBoundary() {
        // U+00E9 (é), a precomposed 2-byte-UTF-8 scalar, built explicitly so the
        // byte count can't be thrown off by grapheme-cluster normalization quirks.
        let multibyteChar = String(Unicode.Scalar(0x00E9)!)
        let exactString = String(repeating: multibyteChar, count: 5)
        XCTAssertEqual(exactString.utf8.count, 10)

        let parser = MarkdownParser(limits: .init(maximumInputBytes: 10))

        let exactOutcome = parser.parseOutcome(exactString)
        XCTAssertFalse(exactOutcome.isRejected)
        XCTAssertNotNil(exactOutcome.document)

        // One extra ASCII byte lands exactly at maximumBytes + 1.
        let overString = exactString + "!"
        XCTAssertEqual(overString.utf8.count, 11)

        let overOutcome = parser.parseOutcome(overString)
        XCTAssertEqual(overOutcome.diagnostics, [.inputTooLarge(actualBytes: 11, maximumBytes: 10)])
        XCTAssertNil(overOutcome.document)
    }

    // MARK: - Plugin invocation rules

    func testRejectionProducesNilDocumentAndDoesNotInvokePlugins() {
        let recorder = PluginCallRecorder()
        let plugin = RecordingPlugin(name: "only", recorder: recorder)
        let parser = MarkdownParser(plugins: [plugin], limits: .init(maximumInputBytes: 3))

        let outcome = parser.parseOutcome("far too long for the configured limit")

        XCTAssertTrue(outcome.isRejected)
        XCTAssertNil(outcome.document)
        XCTAssertTrue(recorder.order.isEmpty, "Plugins must not run when input is rejected before parsing.")
    }

    func testNormalParsedInputPreservesPluginOrder() {
        let recorder = PluginCallRecorder()
        let plugins: [ASTPlugin] = [
            RecordingPlugin(name: "first", recorder: recorder),
            RecordingPlugin(name: "second", recorder: recorder),
            RecordingPlugin(name: "third", recorder: recorder)
        ]
        let parser = MarkdownParser(plugins: plugins)

        let outcome = parser.parseOutcome("Hello **world**")

        XCTAssertFalse(outcome.isRejected)
        XCTAssertEqual(recorder.order, ["first", "second", "third"])
    }

    // MARK: - Depth truncation + plugins

    func testDepthTruncatedInputProducesValidPrefixAndStillInvokesPlugins() {
        let recorder = PluginCallRecorder()
        let plugin = RecordingPlugin(name: "only", recorder: recorder)
        let parser = MarkdownParser(plugins: [plugin], limits: .init(maximumNestingDepth: 3))

        var payload = ""
        for _ in 0..<10 { payload += "> " }
        payload += "Hello"

        let outcome = parser.parseOutcome(payload)

        guard case .parsed(let document, let diagnostics) = outcome else {
            return XCTFail("Depth-truncated input should still parse, not be rejected.")
        }

        XCTAssertEqual(diagnostics, [.maximumNestingDepthExceeded(maximumDepth: 3)])
        XCTAssertEqual(recorder.order, ["only"], "The plugin pipeline should still run, exactly once, on the truncated (but structurally valid) mapped tree.")

        var retainedDepth = 0
        var currentNode: MarkdownNode? = document.children.first
        var lastBlockQuote: BlockQuoteNode?
        while let node = currentNode as? BlockQuoteNode {
            retainedDepth += 1
            lastBlockQuote = node
            currentNode = node.children.first
        }

        XCTAssertEqual(retainedDepth, 3, "Retained BlockQuoteNode prefix should stop exactly at the configured depth budget.")
        XCTAssertEqual(lastBlockQuote?.children.isEmpty, true, "The boundary BlockQuoteNode should have its descendants omitted.")
    }

    // MARK: - No false truncation for a childless boundary markup

    func testNoChildMarkupAtTraversalBoundaryDoesNotReportFalseTruncation() {
        let parser = MarkdownParser(limits: .init(maximumNestingDepth: 2))

        // ">"+empty heading: BlockQuote (depth 1) containing an empty Heading (depth-2
        // boundary). `swift-markdown` maps a bare "# " to a Heading with zero children,
        // so hitting the depth boundary there omits nothing and must not be reported.
        let outcome = parser.parseOutcome("> # \n")

        guard case .parsed(let document, let diagnostics) = outcome else {
            return XCTFail("Boundary input should still parse.")
        }

        XCTAssertTrue(diagnostics.isEmpty, "A childless markup exactly at the depth boundary must not report false truncation.")

        let blockQuote = document.children.first as? BlockQuoteNode
        XCTAssertNotNil(blockQuote)
        let header = blockQuote?.children.first as? HeaderNode
        XCTAssertNotNil(header)
        XCTAssertEqual(header?.children.isEmpty, true)
    }

    // MARK: - Visitor reuse resets truncation state per top-level traversal

    func testVisitorReusedAcrossTraversalsReportsOnlyMostRecentTruncation() {
        var visitor = MarkdownKitVisitor(maxDepth: 3)

        var deepPayload = ""
        for _ in 0..<10 { deepPayload += "> " }
        deepPayload += "Hello"

        _ = visitor.defaultVisit(Document(parsing: deepPayload))
        XCTAssertTrue(visitor.didTruncateAtMaximumDepth, "Deeply nested traversal should report truncation.")

        _ = visitor.defaultVisit(Document(parsing: "Hello **world**"))
        XCTAssertFalse(
            visitor.didTruncateAtMaximumDepth,
            "Reusing the same visitor for a subsequent, non-truncating top-level traversal must not retain stale truncation state."
        )
    }

    // MARK: - Legacy `parse(_:)` compatibility fallback

    func testLegacyParseReturnsHistoricalEmptyFallbackForRejection() {
        let parser = MarkdownParser(limits: .init(maximumInputBytes: 3))

        let document = parser.parse("far too long for the configured limit")

        XCTAssertNil(document.range)
        XCTAssertTrue(document.children.isEmpty)
    }

    func testLegacyParseReturnsPartialDocumentForDepthTruncation() {
        let parser = MarkdownParser(limits: .init(maximumNestingDepth: 3))

        var payload = ""
        for _ in 0..<10 { payload += "> " }
        payload += "Hello"

        let document = parser.parse(payload)

        XCTAssertFalse(document.children.isEmpty, "Depth-truncated legacy parse should still return a partial document, not the empty-input fallback.")
        XCTAssertTrue(document.children.first is BlockQuoteNode)
    }

    // MARK: - Engine forwards configured limits

    func testEngineMakeParserForwardsConfiguredLimits() {
        let limits = MarkdownParser.ResourceLimits(maximumInputBytes: 123, maximumNestingDepth: 7)
        let parser = MarkdownKitEngine.makeParser(resourceLimits: limits)
        XCTAssertEqual(parser.limits, limits)
    }

    // MARK: - MarkdownView accepts configured limits

    #if canImport(SwiftUI)
    @available(iOS 14.0, macOS 11.0, *)
    @MainActor
    func testMarkdownViewInitializerAcceptsConfiguredResourceLimits() {
        let limits = MarkdownParser.ResourceLimits(maximumInputBytes: 2_048, maximumNestingDepth: 5)
        // This is compile-time coverage of the public configuration point. The
        // private async pipeline is reviewed through its RenderInput/RenderJob wiring.
        _ = MarkdownView(text: "# Hello", resourceLimits: limits)
    }
    #endif
}
