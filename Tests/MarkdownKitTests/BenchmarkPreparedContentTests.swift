import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Isolated Release benchmarks for cold first solve and prepared-content-friendly width relayout.
final class BenchmarkPreparedContentTests: XCTestCase {

    private let harness = BenchmarkHarness(warmup: 3, iterations: 20)
    private let representativeWidth: CGFloat = 600
    private let resizeSweep: [CGFloat] = [320, 360, 390, 428, 480, 540, 600, 672, 768]

    private struct WidthSweepSolverContext {
        let width: CGFloat
        let solver: LayoutSolver
    }

    func testPersistentWidthRelayout() async {
        let document = MarkdownKitEngine.makeParser().parse(BenchmarkFixtures.large)
        var results: [BenchmarkResult] = []

        results.append(
            await harness.measureAsync(
                label: "solve(cold-first)",
                fixture: "large",
                prepare: {
                    ArithmeticTextCalculator.resetPreparedTextCacheForTesting()
                    return LayoutSolver(cache: LayoutCache())
                }
            ) { solver in
                await self.solveBenchmarkLayout(
                    with: solver,
                    document: document,
                    width: self.representativeWidth
                )
            }
        )

        let persistentCache = LayoutCache()
        let persistentSolver = LayoutSolver(cache: persistentCache)
        await solveBenchmarkLayout(
            with: persistentSolver,
            document: document,
            width: representativeWidth
        )

        results.append(
            await harness.measureAsync(
                label: "solve(width-sweep)",
                fixture: "large",
                prepare: {
                    ArithmeticTextCalculator.resetPreparedTextCacheForTesting()
                    persistentCache.clear()
                    return persistentSolver
                }
            ) { solver in
                await self.solveWidthSweep(with: solver, document: document)
            }
        )

        results.append(
            await harness.measureAsync(
                label: "solve(rebuild-sweep)",
                fixture: "large",
                prepare: {
                    ArithmeticTextCalculator.resetPreparedTextCacheForTesting()
                    return self.resizeSweep.map { width in
                        WidthSweepSolverContext(width: width, solver: LayoutSolver(cache: LayoutCache()))
                    }
                }
            ) { contexts in
                await self.solveWidthSweep(with: contexts, document: document)
            }
        )

        BenchmarkReportFormatter.printSections([
            ("Prepared Content Relayout", results)
        ])
        BenchmarkRegressionGuard.assertPreparedContentRelayout(results: results, widthCount: resizeSweep.count)
    }

    private func solveWidthSweep(with solver: LayoutSolver, document: DocumentNode) async {
        for width in resizeSweep {
            await solveBenchmarkLayout(with: solver, document: document, width: width)
        }
    }

    private func solveWidthSweep(with contexts: [WidthSweepSolverContext], document: DocumentNode) async {
        precondition(
            contexts.count == resizeSweep.count,
            "Prepared-content rebuild sweep must create one solver per resize width."
        )

        for context in contexts {
            await solveBenchmarkLayout(with: context.solver, document: document, width: context.width)
        }
    }

    private func solveBenchmarkLayout(
        with solver: LayoutSolver,
        document: DocumentNode,
        width: CGFloat
    ) async {
        let result = await solver.solveCancellable(node: document, constrainedToWidth: width)
        precondition(
            result != nil,
            "Release benchmark solve unexpectedly returned nil without cancellation."
        )
    }
}
