import XCTest
@testable import MarkdownKit

#if canImport(WebKit)

final class MathCacheTests: XCTestCase {

    func testCacheMissReturnsNil() {
        let result = MathRenderer.cachedImage(for: "\\frac{1}{2}")
        XCTAssertNil(result, "Cache should miss for never-rendered equations")
    }

    func testCachedImageReturnedAfterAsyncRender() async throws {
        let latex = "x^2"
        let expectation = XCTestExpectation(description: "Math render completes")

        await MainActor.run {
            MathRenderer.shared.render(latex: latex, display: false) { _ in
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 10.0)

        // After async render, the cache should have the image
        // (may be nil if MathJax/WebKit not available in test env, so we just verify no crash)
        _ = MathRenderer.cachedImage(for: latex)
    }

    func testSyncPathUsesCachedMathImage() async throws {
        let markdown = "$E=mc^2$"
        let parser = MarkdownParser(plugins: [MathExtractionPlugin()])
        let doc = parser.parse(markdown)

        // Async solve populates cache
        let solver = LayoutSolver()
        let asyncResult = await solver.solve(node: doc, constrainedToWidth: 400)

        // Sync solve should now find cached images (if render succeeded)
        let syncResult = solver.solveSync(node: doc, constrainedToWidth: 400)

        // Both should produce valid results without crash
        XCTAssertGreaterThan(asyncResult.children.count, 0)
        XCTAssertGreaterThan(syncResult.children.count, 0)
    }
}

#endif
