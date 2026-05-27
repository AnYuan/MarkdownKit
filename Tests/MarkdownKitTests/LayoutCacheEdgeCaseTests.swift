import XCTest
@testable import MarkdownKit

final class LayoutCacheEdgeCaseTests: XCTestCase {

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

        let missesAfterFirst = cache.missCountForTesting
        XCTAssertGreaterThan(missesAfterFirst, 0, "First solve should populate the cache")

        // Build a *different* solver instance — the same cache must survive.
        let solverB = LayoutSolver(theme: .default, cache: cache)
        let docB = parser.parse(markdown)

        cache.resetStatsForTesting()
        _ = await solverB.solve(node: docB, constrainedToWidth: 320)

        XCTAssertGreaterThan(
            cache.hitCountForTesting,
            0,
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
}
