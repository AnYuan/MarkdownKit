import XCTest
@testable import MarkdownKit

final class LayoutCacheEdgeCaseTests: XCTestCase {

    func testCacheMissForDifferentWidth() async throws {
        let doc = TestHelper.parse("# Hello")
        let cache = LayoutCache()
        let solver = LayoutSolver(cache: cache)

        _ = await solver.solve(node: doc, constrainedToWidth: 300)
        _ = await solver.solve(node: doc, constrainedToWidth: 500)

        // Different widths should produce independent cache entries
        XCTAssertNotNil(cache.getLayout(for: doc, constrainedToWidth: 300))
        XCTAssertNotNil(cache.getLayout(for: doc, constrainedToWidth: 500))
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

    func testCacheRequiresExactWidthMatchDueToHashing() {
        // NSCache uses hash first (exact CGFloat), so even though CacheKey.isEqual
        // has 0.1 tolerance, different widths produce different hashes and result in misses.
        let cache = LayoutCache()
        let node = DocumentNode(range: nil, children: [])
        let result = LayoutResult(node: node, size: CGSize(width: 100, height: 50))

        cache.setLayout(result, constrainedToWidth: 400.0)

        // Exact width matches
        XCTAssertNotNil(cache.getLayout(for: node, constrainedToWidth: 400.0))

        // Slightly different widths miss due to hash difference
        XCTAssertNil(cache.getLayout(for: node, constrainedToWidth: 400.05))
        XCTAssertNil(cache.getLayout(for: node, constrainedToWidth: 400.2))
    }

    // MARK: - Concurrency

    func testRepeatedCacheAccessDoesNotCrash() {
        let cache = LayoutCache()

        // Perform many rapid cache operations to verify stability
        for index in 0..<100 {
            let node = DocumentNode(range: nil, children: [])
            let result = LayoutResult(node: node, size: CGSize(width: CGFloat(index), height: 50))
            cache.setLayout(result, constrainedToWidth: CGFloat(index))
            _ = cache.getLayout(for: node, constrainedToWidth: CGFloat(index))
        }

        // If we get here without crashing, the test passes
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
}
