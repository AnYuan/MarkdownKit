import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Multi-actor stress tests that exercise LayoutSolver concurrency boundaries.
/// Validates the @unchecked Sendable contract documented in ConcurrencyContract.md.
final class ConcurrencyStressTests: XCTestCase {

    private struct LayoutMetrics: Sendable {
        let height: CGFloat
        let childCount: Int
    }

    /// Exercise LayoutSolver from multiple concurrent tasks to detect data races.
    /// Each task creates its own parse → solve pipeline to comply with strict concurrency.
    func testConcurrentLayoutSolverAccess() async throws {
        let markdown = "Hello **world**"

        let results = await withTaskGroup(of: LayoutMetrics.self, returning: [LayoutMetrics].self) { group in
            for width in stride(from: 200.0, through: 800.0, by: 100.0) {
                group.addTask {
                    let doc = MarkdownParser().parse(markdown)
                    let solver = LayoutSolver()
                    let result = await solver.solve(node: doc, constrainedToWidth: CGFloat(width))
                    // Check children (paragraph layouts) rather than document-level size
                    let firstChildHeight = result.children.first?.size.height ?? 0
                    return LayoutMetrics(height: firstChildHeight, childCount: result.children.count)
                }
            }

            var collected: [LayoutMetrics] = []
            for await metric in group {
                collected.append(metric)
            }
            return collected
        }

        XCTAssertEqual(results.count, 7)
        for metric in results {
            XCTAssertGreaterThan(metric.childCount, 0, "Document should have child layouts")
            XCTAssertGreaterThan(metric.height, 0, "Child layout should have non-zero height")
        }
    }

    /// Exercise concurrent solve at varying widths with cache reuse.
    func testConcurrentSolveAtVaryingWidths() async throws {
        let markdown = "Hello **world**"

        let results = await withTaskGroup(of: LayoutMetrics.self, returning: [LayoutMetrics].self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let doc = MarkdownParser().parse(markdown)
                    let solver = LayoutSolver()
                    _ = await solver.solve(node: doc, constrainedToWidth: 400)
                    let result = await solver.solve(
                        node: doc,
                        constrainedToWidth: CGFloat.random(in: 200...800)
                    )
                    let firstChildHeight = result.children.first?.size.height ?? 0
                    return LayoutMetrics(height: firstChildHeight, childCount: result.children.count)
                }
            }

            var collected: [LayoutMetrics] = []
            for await metric in group {
                collected.append(metric)
            }
            return collected
        }

        XCTAssertEqual(results.count, 10)
        for metric in results {
            XCTAssertGreaterThan(metric.height, 0, "Child layout should have non-zero height")
            XCTAssertGreaterThan(metric.childCount, 0, "Document should have child layouts")
        }
    }

    /// Constructs each parser (and its plugin-free pipeline) inside its own task with a
    /// distinct per-instance `ResourceLimits`, proving limits are task-confined and do not
    /// leak across concurrent parses. `MarkdownParser` is intentionally **not** `Sendable`
    /// (its `plugins` array may hold non-`Sendable` host types), so each task below
    /// constructs and uses its own parser value entirely locally — no configured parser or
    /// plugin instance is shared or copied across tasks.
    func testConcurrentPerInstanceResourceLimitsDoNotLeak() async throws {
        struct OutcomeSummary: Sendable, Equatable {
            let configuredMaxBytes: Int
            let isRejected: Bool
        }

        // Half the tasks use a tiny byte ceiling (so a fixed oversized payload is rejected),
        // the other half use a generous ceiling (so the same payload is accepted). If limits
        // leaked between task-confined parser instances, some outcomes would flip.
        let payload = String(repeating: "a", count: 500)

        let results = await withTaskGroup(of: OutcomeSummary.self, returning: [OutcomeSummary].self) { group in
            for index in 0..<20 {
                group.addTask {
                    let useTinyLimit = index % 2 == 0
                    let maxBytes = useTinyLimit ? 10 : 1_048_576
                    let limits = MarkdownParser.ResourceLimits(maximumInputBytes: maxBytes)
                    let parser = MarkdownParser(plugins: [], limits: limits)
                    let outcome = parser.parseOutcome(payload)
                    return OutcomeSummary(configuredMaxBytes: maxBytes, isRejected: outcome.isRejected)
                }
            }

            var collected: [OutcomeSummary] = []
            for await summary in group {
                collected.append(summary)
            }
            return collected
        }

        XCTAssertEqual(results.count, 20)
        for summary in results {
            if summary.configuredMaxBytes == 10 {
                XCTAssertTrue(summary.isRejected, "Tiny-limit parser should reject the oversized payload")
            } else {
                XCTAssertFalse(summary.isRejected, "Generous-limit parser should accept the same payload")
            }
        }
    }

    /// Exercise concurrent parse + solve on the same markdown at the same width.
    /// All results should have identical dimensions (deterministic output).
    func testConcurrentSolveProducesDeterministicResults() async throws {
        let markdown = "Hello **world**"

        let results = await withTaskGroup(of: LayoutMetrics.self, returning: [LayoutMetrics].self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let doc = MarkdownParser().parse(markdown)
                    let solver = LayoutSolver()
                    let result = await solver.solve(node: doc, constrainedToWidth: 400)
                    let firstChildHeight = result.children.first?.size.height ?? 0
                    return LayoutMetrics(height: firstChildHeight, childCount: result.children.count)
                }
            }

            var collected: [LayoutMetrics] = []
            for await metric in group {
                collected.append(metric)
            }
            return collected
        }

        XCTAssertEqual(results.count, 10)
        let heights = Set(results.map { Int($0.height.rounded()) })
        XCTAssertEqual(heights.count, 1,
            "Concurrent solvers should produce deterministic heights")
    }
}
