import XCTest
@testable import MyMarkdown

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
}
