import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Micro-benchmarks for cache operations: get/set cost, eviction behavior under pressure.
final class BenchmarkCacheTests: XCTestCase {

    private let harness = BenchmarkHarness(warmup: 3, iterations: 20)
    private let defaultWidth: CGFloat = 800.0

    // MARK: - Cache Get/Set Micro-Benchmarks

    /// Measures the raw cost of cache hit, miss, set, and clear operations.
    func testCacheGetSetMicro() async {
        var results: [BenchmarkResult] = []

        let parser = MarkdownParser()
        let doc = parser.parse(BenchmarkFixtures.medium)
        let cache = LayoutCache()
        let solver = LayoutSolver(cache: cache)

        // Populate cache
        _ = await solver.solve(node: doc, constrainedToWidth: defaultWidth)

        // Cache hit
        results.append(
            harness.measure(label: "getLayout(hit)", fixture: "medium") {
                _ = cache.getLayout(for: doc, constrainedToWidth: self.defaultWidth)
            }
        )

        // Cache miss (different width)
        results.append(
            harness.measure(label: "getLayout(miss)", fixture: "medium") {
                _ = cache.getLayout(for: doc, constrainedToWidth: 999)
            }
        )

        // setLayout cost
        let layout = cache.getLayout(for: doc, constrainedToWidth: defaultWidth)!
        results.append(
            harness.measure(label: "setLayout()", fixture: "medium") {
                cache.setLayout(layout, constrainedToWidth: 12345)
            }
        )

        // clear() cost
        results.append(
            harness.measure(label: "clear()", fixture: "medium") {
                cache.clear()
            }
        )

        BenchmarkReportFormatter.printSections([
            ("Cache Operations", results),
        ])
    }

    // MARK: - Cache Eviction Pressure

    /// Benchmarks cold, warm-hit-only, and eviction-thrash cache modes separately.
    func testCacheEvictionPressure() async {
        var results: [BenchmarkResult] = []
        let parser = MarkdownParser()
        let doc = parser.parse(BenchmarkFixtures.medium)
        let widths = stride(from: 300, through: 1000, by: 50).map { CGFloat($0) }

        // Cold per iteration: fresh large cache each run, no prewarming.
        results.append(
            await harness.measureAsync(label: "solve(cold-large)", fixture: "medium") {
                let cache = LayoutCache(countLimit: 100_000)
                let solver = LayoutSolver(cache: cache)
                for width in widths {
                    _ = await solver.solve(node: doc, constrainedToWidth: width)
                }
            }
        )

        // Warm-hit-only: prewarm once, then each measured iteration is cache-hit dominated.
        let warmCache = LayoutCache(countLimit: 100_000)
        let warmSolver = LayoutSolver(cache: warmCache)
        for width in widths {
            _ = await warmSolver.solve(node: doc, constrainedToWidth: width)
        }
        results.append(
            await harness.measureAsync(label: "solve(warm-large)", fixture: "medium") {
                for width in widths {
                    _ = await warmSolver.solve(node: doc, constrainedToWidth: width)
                }
            }
        )

        // Eviction thrash: tiny cache cannot retain all width variants between passes.
        let tinyCache = LayoutCache(countLimit: 10)
        let tinySolver = LayoutSolver(cache: tinyCache)
        results.append(
            await harness.measureAsync(label: "solve(tiny-thrash)", fixture: "medium") {
                for width in widths {
                    _ = await tinySolver.solve(node: doc, constrainedToWidth: width)
                }
                for width in widths {
                    _ = await tinySolver.solve(node: doc, constrainedToWidth: width)
                }
            }
        )

        BenchmarkReportFormatter.printSections([
            ("Cache Eviction Pressure", results),
        ])

        BenchmarkRegressionGuard.assertCacheModes(results: results)
    }
}
