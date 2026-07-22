//
//  PreparedContentReuseTests.swift
//  MarkdownKit
//

import XCTest
import Markdown
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Integration tests for width-independent prepared-content reuse across all three
/// LayoutSolver paths (async, cancellable, sync).
final class PreparedContentReuseTests: XCTestCase {

    // MARK: - Node factories

    private func para(_ text: String, range: SourceRange? = nil) -> ParagraphNode {
        ParagraphNode(range: range, children: [TextNode(range: range, text: text)])
    }

    private func header(_ text: String, level: Int = 1) -> HeaderNode {
        HeaderNode(range: nil, level: level, children: [TextNode(range: nil, text: text)])
    }

    private func codeBlock(language: String = "swift", code: String = "let x = 1") -> CodeBlockNode {
        CodeBlockNode(range: nil, language: language, code: code)
    }

    private func theme(paragraphFontSize: CGFloat) -> Theme {
        let base = Theme.default
        return Theme(
            typography: Theme.Typography(
                header1: base.typography.header1,
                header2: base.typography.header2,
                header3: base.typography.header3,
                paragraph: TypographyToken(font: Font.systemFont(ofSize: paragraphFontSize)),
                codeBlock: base.typography.codeBlock
            ),
            colors: base.colors,
            codeBlock: base.codeBlock,
            blockQuote: base.blockQuote,
            list: base.list,
            details: base.details,
            table: base.table,
            syntaxColors: base.syntaxColors,
            highlight: base.highlight,
            thematicBreak: base.thematicBreak
        )
    }

    private func sourceRange(line: Int, source: String = "file:///doc.md") -> SourceRange {
        let url = URL(string: source)
        return SourceLocation(line: line, column: 1, source: url)
            ..< SourceLocation(line: line, column: 20, source: url)
    }

    /// Task-list with checkbox so the ListNode carries an interaction fingerprint.
    private func taskList(itemRange: SourceRange?, listRange: SourceRange?) -> ListNode {
        let item = ListItemNode(
            range: itemRange,
            checkbox: .unchecked,
            children: [para("task", range: itemRange)]
        )
        return ListNode(range: listRange, isOrdered: false, children: [item])
    }

    // MARK: - 1. Paragraph miss → hit: attributed equality and distinct sizes

    func testParagraphMissHitAttributedEqualityAndDifferentSize() throws {
        let preparedCache = PreparedContentCache()
        let solver = LayoutSolver(preparedCache: preparedCache)
        // Long enough text to wrap at the narrow width
        let node = para("The quick brown fox jumps over the lazy dog near the river bank again")

        let result1 = solver.solveSync(node: node, constrainedToWidth: 150)
        XCTAssertEqual(preparedCache.entryCountForTesting, 1, "Miss should create one entry")

        preparedCache.resetDiagnosticsForTesting()
        let result2 = solver.solveSync(node: node, constrainedToWidth: 600)

        XCTAssertEqual(preparedCache.hitCountForTesting, 1, "Second-width solve must hit prepared cache")
        XCTAssertEqual(preparedCache.missCountForTesting, 0)

        let str1 = try XCTUnwrap(result1.attributedString)
        let str2 = try XCTUnwrap(result2.attributedString)
        XCTAssertTrue(str1.isEqual(to: str2), "Attributed strings from miss and hit must be identical")

        // The narrow width forces more wrapping, yielding a taller and narrower result.
        XCTAssertGreaterThan(result1.size.height, result2.size.height,
                             "Narrow-width result should be taller due to wrapping")
        XCTAssertLessThan(result1.size.width, result2.size.width,
                          "Narrow-width result should be narrower")
    }

    // MARK: - 2. Arithmetic plan: hit bypasses global PreparedText NSCache entirely

    func testArithmeticHitSkipsGlobalPreparedTextLookup() {
        let preparedCache = PreparedContentCache()
        let solver = LayoutSolver(preparedCache: preparedCache)
        let node = para("Simple ASCII paragraph for arithmetic measurement")

        // First solve: miss → build → prepares arithmetic plan, stores in PreparedContentCache
        _ = solver.solveSync(node: node, constrainedToWidth: 300)
        XCTAssertEqual(preparedCache.entryCountForTesting, 1)

        // Reset the global ArithmeticTextCalculator NSCache and counters
        ArithmeticTextCalculator.resetPreparedTextCacheForTesting()

        // Second solve at a different width: PreparedContentCache hit → skips prepare() entirely
        _ = solver.solveSync(node: node, constrainedToWidth: 500)

        XCTAssertEqual(
            ArithmeticTextCalculator.preparedTextCacheHitsForTesting(), 0,
            "Prepared-cache hit must skip ArithmeticTextCalculator's global NSCache lookup"
        )
        XCTAssertEqual(
            ArithmeticTextCalculator.preparedTextCacheMissesForTesting(), 0,
            "Prepared-cache hit must not touch ArithmeticTextCalculator's global NSCache at all"
        )
    }

    // MARK: - 3. Code block: hit at a second width with a valid size

    func testCodeBlockHitAtDifferentWidth() throws {
        let preparedCache = PreparedContentCache()
        let solver = LayoutSolver(preparedCache: preparedCache)
        let node = codeBlock(language: "swift", code: "let x = 42\nlet y = x + 1")

        let result1 = solver.solveSync(node: node, constrainedToWidth: 200)
        XCTAssertEqual(preparedCache.entryCountForTesting, 1)

        preparedCache.resetDiagnosticsForTesting()
        let result2 = solver.solveSync(node: node, constrainedToWidth: 600)

        XCTAssertEqual(preparedCache.hitCountForTesting, 1)
        XCTAssertGreaterThan(result1.size.height, 0)
        XCTAssertGreaterThan(result2.size.height, 0)
        // Wider constraint gives more horizontal room; inset sizing must still work
        XCTAssertGreaterThanOrEqual(result2.size.width, result1.size.width)
    }

    func testCodeBlockAsyncAndCancellableWidthHits() async throws {
        let node = codeBlock(language: "swift", code: "let value = 42\nprint(value)")

        let asyncCache = PreparedContentCache()
        let asyncSolver = LayoutSolver(cache: LayoutCache(), preparedCache: asyncCache)
        _ = await asyncSolver.solve(node: node, constrainedToWidth: 220)
        asyncCache.resetDiagnosticsForTesting()
        let asyncResult = await asyncSolver.solve(node: node, constrainedToWidth: 620)

        XCTAssertEqual(asyncCache.hitCountForTesting, 1)
        XCTAssertGreaterThan(asyncResult.size.height, 0)

        let cancellableCache = PreparedContentCache()
        let cancellableSolver = LayoutSolver(
            cache: LayoutCache(),
            preparedCache: cancellableCache
        )
        _ = await cancellableSolver.solveCancellable(node: node, constrainedToWidth: 220)
        cancellableCache.resetDiagnosticsForTesting()
        let optionalCancellableResult = await cancellableSolver.solveCancellable(
            node: node,
            constrainedToWidth: 620
        )
        let cancellableResult = try XCTUnwrap(optionalCancellableResult)

        XCTAssertEqual(cancellableCache.hitCountForTesting, 1)
        XCTAssertGreaterThan(cancellableResult.size.height, 0)
    }

    // MARK: - 4. Complex-script / TextKit fallback is cached correctly

    func testComplexScriptTextKitPlanCachedAndHits() throws {
        let preparedCache = PreparedContentCache()
        let solver = LayoutSolver(preparedCache: preparedCache)
        // Arabic script triggers TextKit fallback (ArithmeticTextCalculator.requiresTextKitFallback)
        let node = para("مرحبا بالعالم")

        _ = solver.solveSync(node: node, constrainedToWidth: 300)
        XCTAssertEqual(preparedCache.entryCountForTesting, 1)

        preparedCache.resetDiagnosticsForTesting()
        ArithmeticTextCalculator.resetPreparedTextCacheForTesting()

        let result2 = solver.solveSync(node: node, constrainedToWidth: 500)

        XCTAssertEqual(preparedCache.hitCountForTesting, 1, "TextKit plan must hit prepared cache on second width")
        // TextKit plan never calls ArithmeticTextCalculator at all
        XCTAssertEqual(ArithmeticTextCalculator.preparedTextCacheHitsForTesting(), 0)
        XCTAssertEqual(ArithmeticTextCalculator.preparedTextCacheMissesForTesting(), 0)
        XCTAssertGreaterThan(result2.size.height, 0)
    }

    // MARK: - 5. Sync and async namespaces are isolated; async second-width hits

    func testSyncAsyncNamespaceIsolationAndAsyncWidthHit() async throws {
        let preparedCache = PreparedContentCache()
        let solver = LayoutSolver(cache: LayoutCache(), preparedCache: preparedCache)
        let node = para("Namespace isolation test paragraph content here")

        // Sync solve: stores under syncCacheVariantHash
        _ = solver.solveSync(node: node, constrainedToWidth: 300)
        XCTAssertEqual(preparedCache.entryCountForTesting, 1)

        preparedCache.resetDiagnosticsForTesting()

        // Async solve at same width: uses cacheVariantHash (different namespace) → miss
        _ = await solver.solve(node: node, constrainedToWidth: 300)
        XCTAssertEqual(preparedCache.hitCountForTesting, 0,
                       "Async namespace must not hit sync-namespace entry")
        XCTAssertEqual(preparedCache.entryCountForTesting, 2,
                       "Should have one sync entry and one async entry")

        preparedCache.resetDiagnosticsForTesting()

        // Async solve at a different width: same async namespace → hit
        _ = await solver.solve(node: node, constrainedToWidth: 500)
        XCTAssertEqual(preparedCache.hitCountForTesting, 1,
                       "Second async solve at different width must hit async namespace")
    }

    func testCancellableWidthRelayoutUsesCommittedPreparedPayload() async throws {
        let preparedCache = PreparedContentCache()
        let solver = LayoutSolver(cache: LayoutCache(), preparedCache: preparedCache)
        let node = para("A long cancellable paragraph that wraps at the narrow width and reuses prepared arithmetic content")

        let narrowResult = await solver.solveCancellable(node: node, constrainedToWidth: 150)
        let narrow = try XCTUnwrap(narrowResult)
        preparedCache.resetDiagnosticsForTesting()
        ArithmeticTextCalculator.resetPreparedTextCacheForTesting()

        let wideResult = await solver.solveCancellable(node: node, constrainedToWidth: 600)
        let wide = try XCTUnwrap(wideResult)

        XCTAssertEqual(preparedCache.hitCountForTesting, 1)
        XCTAssertEqual(preparedCache.missCountForTesting, 0)
        XCTAssertEqual(ArithmeticTextCalculator.preparedTextCacheHitsForTesting(), 0)
        XCTAssertEqual(ArithmeticTextCalculator.preparedTextCacheMissesForTesting(), 0)
        XCTAssertGreaterThan(narrow.size.height, wide.size.height)
    }

    // MARK: - 6. Theme and appearance variant isolation with shared cache

    func testThemeAndAppearanceVariantIsolation() throws {
        let preparedCache = PreparedContentCache()
        let lightSolver = LayoutSolver(
            theme: .default, appearance: .light, preparedCache: preparedCache
        )
        let darkSolver = LayoutSolver(
            theme: .default, appearance: .dark, preparedCache: preparedCache
        )
        let node = para("Appearance variant isolation")

        _ = lightSolver.solveSync(node: node, constrainedToWidth: 300)
        XCTAssertEqual(preparedCache.entryCountForTesting, 1)

        preparedCache.resetDiagnosticsForTesting()

        _ = darkSolver.solveSync(node: node, constrainedToWidth: 300)
        XCTAssertEqual(preparedCache.hitCountForTesting, 0,
                       "Dark-appearance entry must not hit light-appearance entry")
        XCTAssertEqual(preparedCache.entryCountForTesting, 2)

        // Same appearance again → hits
        preparedCache.resetDiagnosticsForTesting()
        _ = lightSolver.solveSync(node: node, constrainedToWidth: 500)
        XCTAssertEqual(preparedCache.hitCountForTesting, 1,
                       "Same-appearance second-width solve must hit prepared cache")
    }

    func testThemeVariantIsolation() {
        let preparedCache = PreparedContentCache()
        let smallSolver = LayoutSolver(
            theme: theme(paragraphFontSize: 12),
            preparedCache: preparedCache
        )
        let largeSolver = LayoutSolver(
            theme: theme(paragraphFontSize: 28),
            preparedCache: preparedCache
        )
        let node = para("Theme variant isolation")

        _ = smallSolver.solveSync(node: node, constrainedToWidth: 300)
        preparedCache.resetDiagnosticsForTesting()
        _ = largeSolver.solveSync(node: node, constrainedToWidth: 300)

        XCTAssertEqual(preparedCache.hitCountForTesting, 0)
        XCTAssertEqual(preparedCache.entryCountForTesting, 2)
    }

    // MARK: - 7. Range-sensitive interaction isolation (task lists at different source ranges)

    func testRangeSensitiveInteractionIsolation() throws {
        let preparedCache = PreparedContentCache()
        let solver = LayoutSolver(preparedCache: preparedCache)

        let range1 = sourceRange(line: 1)
        let range2 = sourceRange(line: 20)
        let list1 = taskList(itemRange: range1, listRange: range1)
        let list2 = taskList(itemRange: range2, listRange: range2)

        // Same content fingerprint, different interaction fingerprints
        XCTAssertEqual(list1.contentFingerprint, list2.contentFingerprint)
        XCTAssertNotEqual(list1._interactionFingerprint, list2._interactionFingerprint)

        _ = solver.solveSync(node: list1, constrainedToWidth: 300)
        XCTAssertEqual(preparedCache.entryCountForTesting, 1)

        preparedCache.resetDiagnosticsForTesting()
        _ = solver.solveSync(node: list2, constrainedToWidth: 300)

        XCTAssertEqual(preparedCache.hitCountForTesting, 0,
                       "Different source ranges must not share a prepared-cache entry")
        XCTAssertEqual(preparedCache.entryCountForTesting, 2)
    }

    // MARK: - 8. Persistent solver reuses prepared cache across solve calls

    func testPersistentSolverReusesPreparedCache() {
        let preparedCache = PreparedContentCache()
        let solver = LayoutSolver(preparedCache: preparedCache)
        let node = para("Persistent solver reuse check")

        _ = solver.solveSync(node: node, constrainedToWidth: 300)
        XCTAssertGreaterThan(preparedCache.entryCountForTesting, 0)

        preparedCache.resetDiagnosticsForTesting()
        _ = solver.solveSync(node: node, constrainedToWidth: 400)

        XCTAssertGreaterThan(preparedCache.hitCountForTesting, 0,
                             "Persistent solver must reuse prepared content at a fresh width")
        XCTAssertEqual(preparedCache.missCountForTesting, 0)
    }

    // MARK: - 9. Resource exclusions: ineligible types are never prepared-cached

    func testInlineImageExcludesParagraphFromPreparedCache() {
        let preparedCache = PreparedContentCache()
        let solver = LayoutSolver(preparedCache: preparedCache)
        let img = ImageNode(range: nil, source: "https://example.com/img.png", altText: "alt", title: nil)
        let node = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Text "), img])

        _ = solver.solveSync(node: node, constrainedToWidth: 300)
        XCTAssertEqual(preparedCache.entryCountForTesting, 0,
                       "Paragraph with inline image descendant must not be prepared-cached")
    }

    func testInlineMathExcludesParagraphFromPreparedCache() {
        let preparedCache = PreparedContentCache()
        let solver = LayoutSolver(preparedCache: preparedCache)
        let math = MathNode(range: nil, style: .inline, equation: "x^2")
        let node = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Inline "), math])

        _ = solver.solveSync(node: node, constrainedToWidth: 300)
        XCTAssertEqual(preparedCache.entryCountForTesting, 0,
                       "Paragraph with inline math descendant must not be prepared-cached")
    }

    func testDetailsSummaryResourcesExcludePreparedCacheAtAnyDepth() {
        let image = ImageNode(
            range: nil,
            source: "https://example.com/summary.png",
            altText: "summary",
            title: nil
        )
        let summary = SummaryNode(range: nil, children: [image])
        let details = DetailsNode(
            range: nil,
            isOpen: false,
            summary: summary,
            children: []
        )

        let directCache = PreparedContentCache()
        _ = LayoutSolver(preparedCache: directCache).solveSync(
            node: details,
            constrainedToWidth: 300
        )
        XCTAssertEqual(
            directCache.entryCountForTesting,
            0,
            "A details summary resource must exclude the details root from prepared caching"
        )

        let nestedCache = PreparedContentCache()
        _ = LayoutSolver(preparedCache: nestedCache).solveSync(
            node: BlockQuoteNode(range: nil, children: [details]),
            constrainedToWidth: 300
        )
        XCTAssertEqual(
            nestedCache.entryCountForTesting,
            0,
            "Nested details summaries must participate in resource exclusion"
        )
    }

    func testDiagramNodeNotPreparedCached() {
        let preparedCache = PreparedContentCache()
        let solver = LayoutSolver(preparedCache: preparedCache)
        let node = DiagramNode(range: nil, language: .mermaid, source: "graph TD; A-->B")

        _ = solver.solveSync(node: node, constrainedToWidth: 300)
        XCTAssertEqual(preparedCache.entryCountForTesting, 0,
                       "DiagramNode must never be prepared-cached")
    }

    func testDocumentRootNotPreparedCached() {
        let preparedCache = PreparedContentCache()
        let solver = LayoutSolver(preparedCache: preparedCache)
        // DocumentNode with no children; the document root itself must not be cached
        let doc = DocumentNode(range: nil, children: [])

        _ = solver.solveSync(node: doc, constrainedToWidth: 300)
        XCTAssertEqual(preparedCache.entryCountForTesting, 0,
                       "DocumentNode root must never be prepared-cached")
    }

    func testTableNodeNotPreparedCached() {
        let preparedCache = PreparedContentCache()
        let solver = LayoutSolver(preparedCache: preparedCache)
        let tableHead = TableHeadNode(range: nil, children: [])
        let node = TableNode(range: nil, columnAlignments: [], children: [tableHead])

        _ = solver.solveSync(node: node, constrainedToWidth: 300)
        XCTAssertEqual(preparedCache.entryCountForTesting, 0,
                       "TableNode must never be prepared-cached")
    }

    func testThematicBreakCustomDrawNotPreparedCached() {
        let preparedCache = PreparedContentCache()
        let solver = LayoutSolver(preparedCache: preparedCache)

        _ = solver.solveSync(
            node: ThematicBreakNode(range: nil),
            constrainedToWidth: 300
        )

        XCTAssertEqual(preparedCache.entryCountForTesting, 0)
    }

    // MARK: - 10. Transactional cancellation: prepared batch is never committed on cancel

    func testCancellableTransactionDropsPreparedBatchOnCancel() async throws {
        let preparedCache = PreparedContentCache()
        let blockingMath = TestHelper.BlockingMathAdapter(output: "fallback")
        let solver = LayoutSolver(
            cache: LayoutCache(),
            mathAdapter: blockingMath,
            preparedCache: preparedCache
        )

        // Document: eligible paragraph (first) followed by a block-level math node (second).
        // The paragraph will be staged in the prepared batch. The math node blocks.
        let doc = DocumentNode(range: nil, children: [
            para("Eligible paragraph staged before math blocks"),
            MathNode(range: nil, style: .block, equation: "E = mc^2")
        ])

        // Return a Bool from the Task to avoid Sendable constraints on LayoutResult
        let solveTask = Task<Bool, Never> {
            let result = await solver.solveCancellable(node: doc, constrainedToWidth: 320)
            return result == nil
        }

        // Wait until the math adapter starts rendering (paragraph already staged at this point)
        let started = await blockingMath.waitUntilFirstRenderStarts()
        XCTAssertTrue(started, "Math adapter must start rendering to make timing deterministic")

        // Cancel the solve task, then release the blocked math render
        solveTask.cancel()
        await blockingMath.releaseFirstRender()

        let wasNil = await solveTask.value
        XCTAssertTrue(wasNil, "Cancelled solveCancellable must return nil")
        XCTAssertEqual(preparedCache.entryCountForTesting, 0,
                       "Prepared batch must not be committed after cancellation")
    }

    // MARK: - 11. Staged duplicate nodes: same prepared-cache key committed as one entry

    func testStagedDuplicateNodesResultInSingleCacheEntry() async throws {
        let preparedCache = PreparedContentCache()
        let layoutCache = LayoutCache()
        let solver = LayoutSolver(cache: layoutCache, preparedCache: preparedCache)

        // Two paragraphs with identical content → same contentFingerprint, same prepared-cache key.
        let sharedText = TextNode(range: nil, text: "Identical paragraph text")
        let para1 = ParagraphNode(range: nil, children: [sharedText])
        let para2 = ParagraphNode(range: nil, children: [sharedText])
        XCTAssertEqual(para1.contentFingerprint, para2.contentFingerprint)
        XCTAssertNil(para1._interactionFingerprint)

        let doc = DocumentNode(range: nil, children: [para1, para2])
        let result = await solver.solveCancellable(node: doc, constrainedToWidth: 320)

        XCTAssertNotNil(result, "Solve must succeed")
        XCTAssertEqual(result?.children.count, 2)
        // Both paragraphs share one prepared-cache key; only one entry must be committed.
        XCTAssertEqual(preparedCache.entryCountForTesting, 1,
                       "Duplicate prepared-cache keys must not produce more than one cache entry")
        XCTAssertEqual(preparedCache.missCountForTesting, 1)
        XCTAssertEqual(preparedCache.hitCountForTesting, 0)
        TestHelper.assertDebugCounter(
            layoutCache.hitCountForTesting,
            greaterThanOrEqual: 1,
            "Second duplicate should reuse the staged full layout before prepared lookup"
        )
    }
}
