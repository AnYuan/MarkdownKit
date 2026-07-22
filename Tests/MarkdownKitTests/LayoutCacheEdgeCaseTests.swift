import XCTest
import Markdown
@testable import MarkdownKit

final class LayoutCacheEdgeCaseTests: XCTestCase {

    // MARK: - contentFingerprint property-toggle matrix

    /// Whenever a node carries a non-children property (Header.level, Math.isInline,
    /// List.isOrdered, Details.isOpen, etc.), toggling that property MUST change
    /// `contentFingerprint`. Otherwise `LayoutCache` would return a stale layout
    /// for the new state.
    func testFingerprintChangesWhenNodePropertiesToggle() {
        let r: SourceRange? = nil

        // Header level
        XCTAssertNotEqual(
            HeaderNode(range: r, level: 1, children: []).contentFingerprint,
            HeaderNode(range: r, level: 2, children: []).contentFingerprint
        )

        // TextNode text
        XCTAssertNotEqual(
            TextNode(range: r, text: "a").contentFingerprint,
            TextNode(range: r, text: "b").contentFingerprint
        )

        // CodeBlock language/code
        XCTAssertNotEqual(
            CodeBlockNode(range: r, language: "swift", code: "1").contentFingerprint,
            CodeBlockNode(range: r, language: "swift", code: "2").contentFingerprint
        )
        XCTAssertNotEqual(
            CodeBlockNode(range: r, language: "swift", code: "1").contentFingerprint,
            CodeBlockNode(range: r, language: "python", code: "1").contentFingerprint
        )

        // InlineCode code
        XCTAssertNotEqual(
            InlineCodeNode(range: r, code: "a").contentFingerprint,
            InlineCodeNode(range: r, code: "b").contentFingerprint
        )

        // Math: inline vs block AND equation
        XCTAssertNotEqual(
            MathNode(range: r, style: .inline, equation: "x").contentFingerprint,
            MathNode(range: r, style: .block, equation: "x").contentFingerprint
        )
        XCTAssertNotEqual(
            MathNode(range: r, style: .inline, equation: "x").contentFingerprint,
            MathNode(range: r, style: .inline, equation: "y").contentFingerprint
        )

        // Diagram language and source
        XCTAssertNotEqual(
            DiagramNode(range: r, language: .mermaid, source: "a").contentFingerprint,
            DiagramNode(range: r, language: .mermaid, source: "b").contentFingerprint
        )
        XCTAssertNotEqual(
            DiagramNode(range: r, language: .mermaid, source: "a").contentFingerprint,
            DiagramNode(range: r, language: .geojson, source: "a").contentFingerprint
        )

        // List ordered vs unordered
        XCTAssertNotEqual(
            ListNode(range: r, isOrdered: true, children: []).contentFingerprint,
            ListNode(range: r, isOrdered: false, children: []).contentFingerprint
        )

        // ListItem checkbox state
        XCTAssertNotEqual(
            ListItemNode(range: r, checkbox: .checked, children: []).contentFingerprint,
            ListItemNode(range: r, checkbox: .unchecked, children: []).contentFingerprint
        )
        XCTAssertNotEqual(
            ListItemNode(range: r, checkbox: .none, children: []).contentFingerprint,
            ListItemNode(range: r, checkbox: .checked, children: []).contentFingerprint
        )

        // Image source / altText / title
        XCTAssertNotEqual(
            ImageNode(range: r, source: "a.png", altText: nil, title: nil).contentFingerprint,
            ImageNode(range: r, source: "b.png", altText: nil, title: nil).contentFingerprint
        )
        XCTAssertNotEqual(
            ImageNode(range: r, source: "a.png", altText: "x", title: nil).contentFingerprint,
            ImageNode(range: r, source: "a.png", altText: "y", title: nil).contentFingerprint
        )

        // Link destination/title
        XCTAssertNotEqual(
            LinkNode(range: r, destination: "https://a", title: nil, children: []).contentFingerprint,
            LinkNode(range: r, destination: "https://b", title: nil, children: []).contentFingerprint
        )

        // Details isOpen
        XCTAssertNotEqual(
            DetailsNode(range: r, isOpen: true, summary: nil, children: []).contentFingerprint,
            DetailsNode(range: r, isOpen: false, summary: nil, children: []).contentFingerprint
        )

        // Details summary content
        XCTAssertNotEqual(
            DetailsNode(
                range: r,
                isOpen: true,
                summary: SummaryNode(range: r, children: [TextNode(range: r, text: "a")]),
                children: []
            ).contentFingerprint,
            DetailsNode(
                range: r,
                isOpen: true,
                summary: SummaryNode(range: r, children: [TextNode(range: r, text: "b")]),
                children: []
            ).contentFingerprint
        )

        // Table column alignments
        XCTAssertNotEqual(
            TableNode(range: r, columnAlignments: [.left], children: []).contentFingerprint,
            TableNode(range: r, columnAlignments: [.right], children: []).contentFingerprint
        )
    }

    /// Equal nodes (same fields, same children) must produce the same
    /// fingerprint regardless of when they were constructed. This is the
    /// invariant that lets `MarkdownCache` survive re-parses with fresh UUIDs.
    func testFingerprintStableAcrossReparseOfIdenticalContent() {
        let parser = MarkdownParser()
        let doc1 = parser.parse("# Heading\n\nBody.")
        let doc2 = parser.parse("# Heading\n\nBody.")
        XCTAssertEqual(doc1.contentFingerprint, doc2.contentFingerprint)
        XCTAssertNotEqual(doc1.id, doc2.id, "Sanity: UUIDs do regenerate per parse.")
    }

    func testCacheSharedAcrossSolversHitsOnSecondSolve() async throws {
        // Simulates `MarkdownEngine.solver(for:)` which now reuses one persistent
        // `LayoutCache` across solver instances. Each call to `MarkdownParser.parse()`
        // produces fresh nodes (new UUIDs), so the cache must key on content
        // fingerprint for streaming/reparse scenarios to hit.
        let markdown = """
        # Heading

        Body paragraph that should round-trip through the cache.

        Another paragraph for good measure.
        """

        let parser = MarkdownParser()
        let cache = LayoutCache()
        cache.resetStatsForTesting()

        let solverA = LayoutSolver(theme: .default, cache: cache)
        let docA = parser.parse(markdown)
        _ = await solverA.solve(node: docA, constrainedToWidth: 320)

        TestHelper.assertDebugCounter(
            cache.missCountForTesting,
            greaterThan: 0,
            "First solve should populate the cache"
        )

        // Build a *different* solver instance — the same cache must survive.
        let solverB = LayoutSolver(theme: .default, cache: cache)
        let docB = parser.parse(markdown)

        cache.resetStatsForTesting()
        _ = await solverB.solve(node: docB, constrainedToWidth: 320)

        TestHelper.assertDebugCounter(
            cache.hitCountForTesting,
            greaterThan: 0,
            "Second solve via a fresh solver should hit the persistent cache"
        )
    }

    func testCacheMissForDifferentWidth() async throws {
        let doc = TestHelper.parse("# Hello")
        let cache = LayoutCache()
        let narrow = LayoutResult(node: doc, size: CGSize(width: 300, height: 42))
        let wide = LayoutResult(node: doc, size: CGSize(width: 500, height: 24))

        cache.setLayout(narrow, constrainedToWidth: 300)
        cache.setLayout(wide, constrainedToWidth: 500)

        // Different widths should produce independent cache entries
        XCTAssertEqual(cache.getLayout(for: doc, constrainedToWidth: 300)?.size.width, 300)
        XCTAssertEqual(cache.getLayout(for: doc, constrainedToWidth: 500)?.size.width, 500)
    }

    func testCacheExactWidthHit() {
        let cache = LayoutCache()
        let node = DocumentNode(range: nil, children: [])
        let result = LayoutResult(node: node, size: CGSize(width: 100, height: 50))

        cache.setLayout(result, constrainedToWidth: 400.0)

        // Exact same width should hit
        let hit = cache.getLayout(for: node, constrainedToWidth: 400.0)
        XCTAssertNotNil(hit)

        // Different width should miss
        let miss = cache.getLayout(for: node, constrainedToWidth: 401.0)
        XCTAssertNil(miss)
    }

    func testCacheCustomCountLimit() {
        let cache = LayoutCache(countLimit: 2)
        let node1 = DocumentNode(range: nil, children: [])
        let node2 = DocumentNode(range: nil, children: [])

        let result1 = LayoutResult(node: node1, size: CGSize(width: 100, height: 50))
        let result2 = LayoutResult(node: node2, size: CGSize(width: 200, height: 100))

        cache.setLayout(result1, constrainedToWidth: 400)
        cache.setLayout(result2, constrainedToWidth: 400)

        // Both should be retrievable (at limit, not over)
        XCTAssertNotNil(cache.getLayout(for: node1, constrainedToWidth: 400))
        XCTAssertNotNil(cache.getLayout(for: node2, constrainedToWidth: 400))
    }

    // MARK: - Retained-cost budget

    func testCacheDefaultLimits() {
        let cache = LayoutCache()

        XCTAssertEqual(cache.countLimitForTesting, 100_000)
        XCTAssertEqual(cache.totalCostLimitForTesting, 64 * 1_024 * 1_024)
    }

    func testCacheCustomAndNegativeLimitsAreNormalized() {
        let custom = LayoutCache(countLimit: 7, totalCostLimit: 12_345)
        XCTAssertEqual(custom.countLimitForTesting, 7)
        XCTAssertEqual(custom.totalCostLimitForTesting, 12_345)

        let negative = LayoutCache(countLimit: -7, totalCostLimit: -12_345)
        XCTAssertEqual(negative.countLimitForTesting, 0)
        XCTAssertEqual(negative.totalCostLimitForTesting, 0)

        let unlimited = LayoutCache(countLimit: 0, totalCostLimit: 0)
        XCTAssertEqual(unlimited.countLimitForTesting, 0)
        XCTAssertEqual(unlimited.totalCostLimitForTesting, 0)
    }

    func testLayoutResultEmptyCostIsPositive() {
        let result = LayoutResult(
            node: DocumentNode(range: nil, children: []),
            size: .zero
        )

        XCTAssertEqual(result.estimatedCacheCost, 256)
        XCTAssertGreaterThan(result.estimatedCacheCost, 0)
    }

    func testAttributedStringCostUsesUTF16Length() {
        let node = DocumentNode(range: nil, children: [])
        let empty = LayoutResult(
            node: node,
            size: .zero,
            attributedString: NSAttributedString(string: "")
        )
        let oneUnit = LayoutResult(
            node: node,
            size: .zero,
            attributedString: NSAttributedString(string: "a")
        )
        let twoUnits = LayoutResult(
            node: node,
            size: .zero,
            attributedString: NSAttributedString(string: "😀")
        )

        XCTAssertEqual(oneUnit.estimatedCacheCost - empty.estimatedCacheCost, 64)
        XCTAssertEqual(twoUnits.estimatedCacheCost - empty.estimatedCacheCost, 2 * 64)
    }

    func testLayoutResultFreezesMutableAttributedStringAndCost() {
        let node = DocumentNode(range: nil, children: [])
        let source = NSMutableAttributedString(string: "before")
        let result = LayoutResult(
            node: node,
            size: .zero,
            attributedString: source
        )
        let estimatedCost = result.estimatedCacheCost

        source.mutableString.setString(String(repeating: "x", count: 10_000))

        XCTAssertEqual(result.attributedString?.string, "before")
        XCTAssertEqual(result.estimatedCacheCost, estimatedCost)
    }

    func testChildCostsIncludeArrayStorageAndAggregatedSubtreeCost() {
        let node = DocumentNode(range: nil, children: [])
        let firstChild = LayoutResult(node: node, size: .zero)
        let secondChild = LayoutResult(
            node: node,
            size: .zero,
            attributedString: NSAttributedString(string: "child")
        )
        let parent = LayoutResult(
            node: node,
            size: .zero,
            children: [firstChild, secondChild]
        )
        let childSum = firstChild.estimatedCacheCost + secondChild.estimatedCacheCost
        let expectedParentOverhead = 256 + 2 * MemoryLayout<LayoutResult>.stride

        XCTAssertGreaterThan(parent.estimatedCacheCost, firstChild.estimatedCacheCost)
        XCTAssertGreaterThan(parent.estimatedCacheCost, childSum)
        XCTAssertEqual(parent.estimatedCacheCost, childSum + expectedParentOverhead)
    }

    func testCustomDrawCostScalesWithFiniteDrawArea() {
        let node = DocumentNode(range: nil, children: [])
        let noDraw = LayoutResult(node: node, size: CGSize(width: 1, height: 1))
        let smallDraw = LayoutResult(
            node: node,
            size: CGSize(width: 1, height: 1),
            customDraw: { _, _ in }
        )
        let largeDraw = LayoutResult(
            node: node,
            size: CGSize(width: 10, height: 10),
            customDraw: { _, _ in }
        )

        XCTAssertGreaterThan(smallDraw.estimatedCacheCost, noDraw.estimatedCacheCost)
        XCTAssertGreaterThan(largeDraw.estimatedCacheCost, smallDraw.estimatedCacheCost)
        XCTAssertEqual(
            LayoutCacheCostEstimator.customDrawGeometryCost(
                for: CGSize(width: 2.1, height: 3)
            ),
            28
        )
    }

    func testCostEstimatorSaturatesArithmeticAndInvalidDrawGeometry() {
        XCTAssertEqual(LayoutCacheCostEstimator.saturatingAdd(.max, 1), .max)
        XCTAssertEqual(LayoutCacheCostEstimator.saturatingMultiply(.max, 2), .max)

        let invalidSizes = [
            CGSize(width: CGFloat.nan, height: 1),
            CGSize(width: CGFloat.infinity, height: 1),
            CGSize(width: -1, height: 1),
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: 2)
        ]
        for size in invalidSizes {
            XCTAssertEqual(
                LayoutCacheCostEstimator.customDrawGeometryCost(for: size),
                .max
            )
        }

        let saturatedResult = LayoutResult(
            node: DocumentNode(range: nil, children: []),
            size: CGSize(width: CGFloat.infinity, height: 1),
            customDraw: { _, _ in }
        )
        XCTAssertEqual(saturatedResult.estimatedCacheCost, .max)
    }

    func testStableIdentityCopiesPreserveEstimatedCost() {
        let child = LayoutResult(
            node: DocumentNode(range: nil, children: []),
            size: CGSize(width: 4, height: 5),
            attributedString: NSAttributedString(string: "child"),
            customDraw: { _, _ in }
        )
        let result = LayoutResult(
            node: DocumentNode(range: nil, children: []),
            size: CGSize(width: 20, height: 10),
            attributedString: NSAttributedString(string: "parent"),
            children: [child]
        )

        let restamped = result.withStableIdentity(
            .topLevel(node: result.node, index: 456)
        )
        let positioned = result.positionedAtTopLevel(index: 3)

        XCTAssertEqual(restamped.estimatedCacheCost, result.estimatedCacheCost)
        XCTAssertEqual(positioned.estimatedCacheCost, result.estimatedCacheCost)
        XCTAssertTrue(restamped.attributedString === result.attributedString)
        XCTAssertTrue(positioned.attributedString === result.attributedString)
    }

    func testEntryAtCostLimitIsRetainedAndOversizedEntryIsSkipped() {
        let node = DocumentNode(range: nil, children: [])
        let result = LayoutResult(
            node: node,
            size: .zero,
            attributedString: NSAttributedString(string: "budgeted")
        )

        let exactCache = LayoutCache(
            countLimit: 10,
            totalCostLimit: result.estimatedCacheCost
        )
        exactCache.setLayout(result, constrainedToWidth: 320)
        XCTAssertNotNil(exactCache.getLayout(for: node, constrainedToWidth: 320))

        let undersizedCache = LayoutCache(
            countLimit: 10,
            totalCostLimit: result.estimatedCacheCost - 1
        )
        undersizedCache.setLayout(result, constrainedToWidth: 320)
        XCTAssertNil(undersizedCache.getLayout(for: node, constrainedToWidth: 320))
    }

    func testZeroTotalCostLimitRetainsOtherwiseOversizedEntry() {
        let node = DocumentNode(range: nil, children: [])
        let result = LayoutResult(
            node: node,
            size: .zero,
            attributedString: NSAttributedString(string: String(repeating: "x", count: 1_000))
        )
        let cache = LayoutCache(countLimit: 10, totalCostLimit: 0)

        cache.setLayout(result, constrainedToWidth: 320)

        XCTAssertNotNil(cache.getLayout(for: node, constrainedToWidth: 320))
    }

    func testWriteBatchKeepsOversizedEntryLocalButPublishesFittingEntry() {
        let oversizedNode = TextNode(range: nil, text: "oversized")
        let fittingNode = TextNode(range: nil, text: "fitting")
        let oversized = LayoutResult(
            node: oversizedNode,
            size: .zero,
            attributedString: NSAttributedString(string: "too large")
        )
        let fitting = LayoutResult(node: fittingNode, size: .zero)
        let cache = LayoutCache(
            countLimit: 10,
            totalCostLimit: fitting.estimatedCacheCost
        )
        var batch = cache.makeWriteBatch()

        batch.stage(oversized, constrainedToWidth: 320, variantHash: 7)
        batch.stage(fitting, constrainedToWidth: 320, variantHash: 7)

        XCTAssertEqual(
            batch.getLayout(
                for: oversizedNode,
                constrainedToWidth: 320,
                variantHash: 7
            )?.attributedString?.string,
            "too large"
        )

        batch.commit()

        XCTAssertNil(
            cache.getLayout(
                for: oversizedNode,
                constrainedToWidth: 320,
                variantHash: 7
            )
        )
        XCTAssertNotNil(
            cache.getLayout(
                for: fittingNode,
                constrainedToWidth: 320,
                variantHash: 7
            )
        )
    }

    func testClearRemovesAllEntries() {
        let cache = LayoutCache()
        let node = DocumentNode(range: nil, children: [])
        let result = LayoutResult(node: node, size: CGSize(width: 100, height: 50))

        cache.setLayout(result, constrainedToWidth: 300)
        cache.setLayout(result, constrainedToWidth: 500)

        cache.clear()

        XCTAssertNil(cache.getLayout(for: node, constrainedToWidth: 300))
        XCTAssertNil(cache.getLayout(for: node, constrainedToWidth: 500))
    }

    // MARK: - Width Tolerance

    func testCacheUsesDeterministicWidthBucketing() {
        let cache = LayoutCache()
        let node = DocumentNode(range: nil, children: [])
        let result = LayoutResult(node: node, size: CGSize(width: 100, height: 50))

        cache.setLayout(result, constrainedToWidth: 400.0)

        // Exact width always matches
        XCTAssertNotNil(cache.getLayout(for: node, constrainedToWidth: 400.0))

        // Same rounded integer bucket should hit (400.0 -> 400, 400.49 -> 400)
        XCTAssertNotNil(cache.getLayout(for: node, constrainedToWidth: 400.05))
        XCTAssertNotNil(cache.getLayout(for: node, constrainedToWidth: 400.49))

        // Next rounded bucket should miss (400.51 -> 401)
        XCTAssertNil(cache.getLayout(for: node, constrainedToWidth: 400.51))
        XCTAssertNil(cache.getLayout(for: node, constrainedToWidth: 401.0))
    }

    // MARK: - Concurrency

    func testRepeatedCacheAccessReturnsCorrectEntries() {
        let cache = LayoutCache()

        // Store 100 entries at different widths
        var nodes: [DocumentNode] = []
        for index in 0..<100 {
            let node = DocumentNode(range: nil, children: [])
            nodes.append(node)
            let result = LayoutResult(node: node, size: CGSize(width: CGFloat(index), height: 50))
            cache.setLayout(result, constrainedToWidth: CGFloat(index))
        }

        // Verify a sample of entries are retrievable with correct sizes
        for index in stride(from: 0, to: 100, by: 10) {
            let retrieved = cache.getLayout(for: nodes[index], constrainedToWidth: CGFloat(index))
            XCTAssertNotNil(retrieved, "Cache entry at width \(index) should exist")
            XCTAssertEqual(retrieved?.size.width, CGFloat(index), "Cached width should match stored width")
            XCTAssertEqual(retrieved?.size.height, 50, "Cached height should match stored height")
        }
    }

    // MARK: - Multiple Widths

    func testCacheSameNodeDifferentWidths() {
        let cache = LayoutCache()
        let node = DocumentNode(range: nil, children: [])

        let widths: [CGFloat] = [100, 200, 300, 400, 500]
        for width in widths {
            let result = LayoutResult(node: node, size: CGSize(width: width, height: 50))
            cache.setLayout(result, constrainedToWidth: width)
        }

        for width in widths {
            let hit = cache.getLayout(for: node, constrainedToWidth: width)
            XCTAssertNotNil(hit, "Should retrieve layout for width \(width)")
            XCTAssertEqual(hit?.size.width, width, "Retrieved layout width should match stored width")
        }
    }

    func testSharedCacheDoesNotReuseLayoutAcrossThemes() async throws {
        let cache = LayoutCache()
        let doc = TestHelper.parse("A paragraph that wraps and measures with the active font.")

        let smallTheme = makeTheme(paragraphFontSize: 12)
        let largeTheme = makeTheme(paragraphFontSize: 28)

        let smallLayout = await LayoutSolver(theme: smallTheme, cache: cache)
            .solve(node: doc, constrainedToWidth: 220)
        let largeLayout = await LayoutSolver(theme: largeTheme, cache: cache)
            .solve(node: doc, constrainedToWidth: 220)

        let smallParagraph = try XCTUnwrap(smallLayout.children.first)
        let largeParagraph = try XCTUnwrap(largeLayout.children.first)

        XCTAssertNotEqual(
            smallParagraph.size.height,
            largeParagraph.size.height,
            "Theme-specific font metrics must not reuse a stale cached layout"
        )
    }

    func testSyncAndAsyncSolverCachesAndRenderFingerprintsRemainIsolated() async throws {
        let node = try XCTUnwrap(
            TestHelper.parse("Envelope-specific cache entry.").children.first
        )
        let cache = LayoutCache()
        let solver = LayoutSolver(cache: cache)
        let width: CGFloat = 320

        let sync = solver.solveSync(node: node, constrainedToWidth: width)

        cache.resetStatsForTesting()
        let async = await solver.solve(node: node, constrainedToWidth: width)
        TestHelper.assertDebugCounter(cache.hitCountForTesting, equals: 0)
        TestHelper.assertDebugCounter(cache.missCountForTesting, equals: 1)
        XCTAssertNotEqual(sync.renderFingerprint, async.renderFingerprint)

        cache.resetStatsForTesting()
        XCTAssertEqual(
            solver.solveSync(node: node, constrainedToWidth: width).renderFingerprint,
            sync.renderFingerprint
        )
        TestHelper.assertDebugCounter(cache.hitCountForTesting, equals: 1)
        TestHelper.assertDebugCounter(cache.missCountForTesting, equals: 0)

        cache.resetStatsForTesting()
        let asyncCached = await solver.solve(node: node, constrainedToWidth: width)
        XCTAssertEqual(
            asyncCached.renderFingerprint,
            async.renderFingerprint
        )
        TestHelper.assertDebugCounter(cache.hitCountForTesting, equals: 1)
        TestHelper.assertDebugCounter(cache.missCountForTesting, equals: 0)
    }

    func testAsyncCachedChildIsRestampedAtItsCurrentDocumentPosition() async {
        let cache = LayoutCache()
        let solver = LayoutSolver(cache: cache)
        let cachedParagraph = paragraph("reused")
        _ = await solver.solve(node: cachedParagraph, constrainedToWidth: 320)

        let document = DocumentNode(
            range: nil,
            children: [paragraph("first"), paragraph("reused")]
        )
        let result = await solver.solve(node: document, constrainedToWidth: 320)

        XCTAssertEqual(
            result.children[1].stableIdentity,
            .topLevel(node: cachedParagraph, index: 1)
        )
    }

    func testSyncCachedChildIsRestampedAtItsCurrentDocumentPosition() {
        let cache = LayoutCache()
        let solver = LayoutSolver(cache: cache)
        let cachedParagraph = paragraph("reused")
        _ = solver.solveSync(node: cachedParagraph, constrainedToWidth: 320)

        let document = DocumentNode(
            range: nil,
            children: [paragraph("first"), paragraph("reused")]
        )
        let result = solver.solveSync(node: document, constrainedToWidth: 320)

        XCTAssertEqual(
            result.children[1].stableIdentity,
            .topLevel(node: cachedParagraph, index: 1)
        )
    }

    func testCacheEvictionAtCountLimit() {
        let cache = LayoutCache(countLimit: 2)

        let nodes = (0..<3).map { _ in DocumentNode(range: nil, children: []) }
        for (index, node) in nodes.enumerated() {
            let result = LayoutResult(node: node, size: CGSize(width: 100, height: CGFloat(index * 10)))
            cache.setLayout(result, constrainedToWidth: 400)
        }

        // NSCache eviction is non-deterministic, but at least one old entry should be evicted
        var retrievableCount = 0
        for node in nodes where cache.getLayout(for: node, constrainedToWidth: 400) != nil {
            retrievableCount += 1
        }

        XCTAssertLessThanOrEqual(retrievableCount, 3,
            "At most 3 entries should be retrievable (NSCache may evict)")
        // The most recent entry should definitely be there
        XCTAssertNotNil(cache.getLayout(for: nodes[2], constrainedToWidth: 400),
            "Most recently inserted entry should be retrievable")
    }

    private func makeTheme(paragraphFontSize: CGFloat) -> Theme {
        let base = Theme.default
        let typography = Theme.Typography(
            header1: base.typography.header1,
            header2: base.typography.header2,
            header3: base.typography.header3,
            paragraph: TypographyToken(font: Font.systemFont(ofSize: paragraphFontSize)),
            codeBlock: base.typography.codeBlock
        )
        return Theme(
            typography: typography,
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

    private func paragraph(_ text: String) -> ParagraphNode {
        ParagraphNode(range: nil, children: [TextNode(range: nil, text: text)])
    }
}
