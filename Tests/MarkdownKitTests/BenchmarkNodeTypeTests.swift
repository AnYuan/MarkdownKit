import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Deep benchmarks for per-node-type cost, width/size scaling, plugin composition, and concurrency.
final class BenchmarkNodeTypeTests: XCTestCase {

    private let harness = BenchmarkHarness(warmup: 3, iterations: 20)
    private let defaultWidth: CGFloat = 800.0
    private let defaultPlugins: [ASTPlugin] = [
        MathExtractionPlugin(),
        DiagramExtractionPlugin(),
        DetailsExtractionPlugin()
    ]

    // MARK: - Per-Node-Type Micro-Benchmarks

    /// Measures layout cost for each block-level node type in isolation.
    func testPerNodeTypeComparison() async {
        var results: [BenchmarkResult] = []
        let parser = MarkdownParser(plugins: defaultPlugins)

        for (name, content) in BenchmarkFixtures.nodeTypeFixtures {
            let doc = parser.parse(content)
            let result = await harness.measureAsync(label: "solve", fixture: name) {
                let solver = LayoutSolver(cache: LayoutCache())
                _ = await solver.solve(node: doc, constrainedToWidth: self.defaultWidth)
            }
            results.append(result)
        }

        BenchmarkReportFormatter.printSections([
            ("Per-Node-Type Layout", results)
        ])
    }

    // MARK: - Per-Syntax Tiered Benchmark (simple → complex → extreme)

    /// Measures render time and memory for each syntax at 3 complexity tiers.
    /// Uses a shared solver per syntax group to avoid TextKit resource exhaustion
    /// when creating hundreds of TextKitCalculator instances in a single test.
    func testPerSyntaxTieredBenchmark() async {
        let parser = MarkdownParser(plugins: defaultPlugins)
        let tieredHarness = BenchmarkHarness(warmup: 2, iterations: 10)
        var sections: [(title: String, results: [BenchmarkResult])] = []

        for syntaxGroup in BenchmarkTieredFixtures.all {
            var results: [BenchmarkResult] = []
            let cache = LayoutCache()
            let solver = LayoutSolver(cache: cache)
            for (tier, content) in syntaxGroup.tiers {
                let doc = parser.parse(content)
                results.append(
                    await tieredHarness.measureAsync(
                        label: "solve",
                        fixture: "\(syntaxGroup.syntax)/\(tier)"
                    ) {
                        cache.clear()
                        _ = await solver.solve(
                            node: doc,
                            constrainedToWidth: self.defaultWidth
                        )
                    }
                )
            }
            sections.append((syntaxGroup.syntax, results))
        }

        BenchmarkReportFormatter.printSections(sections)
    }

    // MARK: - Width Scaling

    /// Measures solve performance across multiple container widths.
    func testWidthScaling() async {
        let widths: [CGFloat] = [320, 600, 800, 1024]
        var results: [BenchmarkResult] = []
        let parser = MarkdownParser(plugins: defaultPlugins)

        // Medium fixture across widths
        let medDoc = parser.parse(BenchmarkFixtures.medium)
        for width in widths {
            let result = await harness.measureAsync(
                label: "solve@\(Int(width))w",
                fixture: "medium"
            ) {
                let solver = LayoutSolver(cache: LayoutCache())
                _ = await solver.solve(node: medDoc, constrainedToWidth: width)
            }
            results.append(result)
        }

        // Table-heavy fixture across widths (tables are width-sensitive)
        let tableDoc = parser.parse(BenchmarkFixtures.tableHeavy)
        for width in widths {
            let result = await harness.measureAsync(
                label: "solve@\(Int(width))w",
                fixture: "table-heavy"
            ) {
                let solver = LayoutSolver(cache: LayoutCache())
                _ = await solver.solve(node: tableDoc, constrainedToWidth: width)
            }
            results.append(result)
        }

        BenchmarkReportFormatter.printSections([
            ("Width Scaling", results)
        ])
    }

    // MARK: - Input Size Scaling

    /// Measures parse + solve scaling across 10/50/200/1000 line documents.
    func testInputSizeScaling() async {
        var parseResults: [BenchmarkResult] = []
        var layoutResults: [BenchmarkResult] = []
        let parser = MarkdownParser(plugins: defaultPlugins)

        for (name, content) in BenchmarkFixtures.scalingFixtures {
            parseResults.append(
                harness.measure(label: "parse", fixture: name) {
                    _ = parser.parse(content)
                }
            )

            let doc = parser.parse(content)
            layoutResults.append(
                await harness.measureAsync(label: "solve", fixture: name) {
                    let solver = LayoutSolver(cache: LayoutCache())
                    _ = await solver.solve(node: doc, constrainedToWidth: self.defaultWidth)
                }
            )
        }

        BenchmarkReportFormatter.printSections([
            ("Input Size Scaling — Parse", parseResults),
            ("Input Size Scaling — Layout", layoutResults)
        ])
    }

    // MARK: - Plugin Composition Overhead

    /// Measures incremental cost of adding each plugin to the parse chain.
    func testPluginCompositionOverhead() {
        var results: [BenchmarkResult] = []

        let configurations: [(String, [ASTPlugin])] = [
            ("0-plugins", []),
            ("1-plugin(math)", [MathExtractionPlugin()]),
            ("2-plugins(math+diag)", [MathExtractionPlugin(), DiagramExtractionPlugin()]),
            ("3-plugins(all)", [
                MathExtractionPlugin(),
                DiagramExtractionPlugin(),
                DetailsExtractionPlugin()
            ])
        ]

        let fixtureScenarios: [(name: String, content: String)] = [
            ("large", BenchmarkFixtures.large),
            ("math-heavy", BenchmarkFixtures.mathHeavy),
            ("diagram-heavy", BenchmarkFixtures.diagramHeavy),
            ("details-heavy", BenchmarkFixtures.detailsHeavy)
        ]

        for scenario in fixtureScenarios {
            for (name, plugins) in configurations {
                let parser = MarkdownParser(plugins: plugins)
                results.append(
                    harness.measure(label: "parse", fixture: "\(scenario.name)/\(name)") {
                        _ = parser.parse(scenario.content)
                    }
                )
            }
        }

        BenchmarkReportFormatter.printSections([
            ("Plugin Composition Overhead", results)
        ])
    }

    // MARK: - Concurrent Solve Stress

    /// Measures concurrent vs sequential solve to reveal parallelism benefit and contention.
    /// Sequential and concurrent modes intentionally run the same parse+solve workload.
    func testConcurrentSolveStress() async {
        var results: [BenchmarkResult] = []
        let mediumWidths: [CGFloat] = [320, 600, 800, 1024]
        let largeWidths: [CGFloat] = [300, 400, 500, 600, 700, 800, 900, 1000]

        results.append(
            await harness.measureAsync(label: "sequential-4x", fixture: "medium") {
                await runSequentialParseAndSolve(
                    content: BenchmarkFixtures.medium,
                    widths: mediumWidths
                )
            }
        )

        results.append(
            await harness.measureAsync(label: "concurrent-4x", fixture: "medium") {
                await runConcurrentParseAndSolve(
                    content: BenchmarkFixtures.medium,
                    widths: mediumWidths
                )
            }
        )

        results.append(
            await harness.measureAsync(label: "sequential-8x", fixture: "large") {
                await runSequentialParseAndSolve(
                    content: BenchmarkFixtures.large,
                    widths: largeWidths
                )
            }
        )

        results.append(
            await harness.measureAsync(label: "concurrent-8x", fixture: "large") {
                await runConcurrentParseAndSolve(
                    content: BenchmarkFixtures.large,
                    widths: largeWidths
                )
            }
        )

        BenchmarkReportFormatter.printSections([
            ("Concurrency Stress", results)
        ])
    }

    // MARK: - Combined Deep Report

    /// Runs all deep benchmarks and outputs a single combined report.
    func testDeepBenchmarkFullReport() async {
        let parser = MarkdownParser(plugins: defaultPlugins)
        let medDoc = parser.parse(BenchmarkFixtures.medium)

        let nodeTypeResults = await benchmarkNodeTypes(parser: parser)
        let widthResults = await benchmarkWidths(doc: medDoc)
        let (sizeParseResults, sizeLayoutResults) = await benchmarkSizeScaling(parser: parser)
        let pluginResults = benchmarkPlugins()
        let concurrencyResults = await benchmarkConcurrency()

        BenchmarkReportFormatter.printSections([
            ("Per-Node-Type Layout", nodeTypeResults),
            ("Width Scaling", widthResults),
            ("Input Size Scaling — Parse", sizeParseResults),
            ("Input Size Scaling — Layout", sizeLayoutResults),
            ("Plugin Composition", pluginResults),
            ("Concurrency Stress", concurrencyResults)
        ])

        BenchmarkRegressionGuard.assertDeepReport(concurrencyResults: concurrencyResults)
    }

    // MARK: - Full Report Helpers

    private func benchmarkNodeTypes(parser: MarkdownParser) async -> [BenchmarkResult] {
        var results: [BenchmarkResult] = []
        for (name, content) in BenchmarkFixtures.nodeTypeFixtures {
            let doc = parser.parse(content)
            results.append(
                await harness.measureAsync(label: "solve", fixture: name) {
                    let solver = LayoutSolver(cache: LayoutCache())
                    _ = await solver.solve(node: doc, constrainedToWidth: self.defaultWidth)
                }
            )
        }
        return results
    }

    private func benchmarkWidths(doc: DocumentNode) async -> [BenchmarkResult] {
        var results: [BenchmarkResult] = []
        for width in [320, 600, 800, 1024] as [CGFloat] {
            results.append(
                await harness.measureAsync(label: "solve@\(Int(width))w", fixture: "medium") {
                    let solver = LayoutSolver(cache: LayoutCache())
                    _ = await solver.solve(node: doc, constrainedToWidth: width)
                }
            )
        }
        return results
    }

    private func benchmarkSizeScaling(
        parser: MarkdownParser
    ) async -> (parse: [BenchmarkResult], layout: [BenchmarkResult]) {
        var parseResults: [BenchmarkResult] = []
        var layoutResults: [BenchmarkResult] = []
        for (name, content) in BenchmarkFixtures.scalingFixtures {
            parseResults.append(
                harness.measure(label: "parse", fixture: name) {
                    _ = parser.parse(content)
                }
            )
            let doc = parser.parse(content)
            layoutResults.append(
                await harness.measureAsync(label: "solve", fixture: name) {
                    let solver = LayoutSolver(cache: LayoutCache())
                    _ = await solver.solve(node: doc, constrainedToWidth: self.defaultWidth)
                }
            )
        }
        return (parseResults, layoutResults)
    }

    private func benchmarkPlugins() -> [BenchmarkResult] {
        var results: [BenchmarkResult] = []
        let pluginConfigs: [(String, [ASTPlugin])] = [
            ("0-plugins", []),
            ("1-plugin", [MathExtractionPlugin()]),
            ("2-plugins", [MathExtractionPlugin(), DiagramExtractionPlugin()]),
            ("3-plugins", defaultPlugins)
        ]

        let fixtureScenarios: [(name: String, content: String)] = [
            ("large", BenchmarkFixtures.large),
            ("math-heavy", BenchmarkFixtures.mathHeavy),
            ("diagram-heavy", BenchmarkFixtures.diagramHeavy),
            ("details-heavy", BenchmarkFixtures.detailsHeavy)
        ]

        for scenario in fixtureScenarios {
            for (name, plugins) in pluginConfigs {
                let pluginParser = MarkdownParser(plugins: plugins)
                results.append(
                    harness.measure(label: "parse", fixture: "\(scenario.name)/\(name)") {
                        _ = pluginParser.parse(scenario.content)
                    }
                )
            }
        }
        return results
    }

    private func benchmarkConcurrency() async -> [BenchmarkResult] {
        var results: [BenchmarkResult] = []
        let mediumWidths: [CGFloat] = [320, 600, 800, 1024]
        let largeWidths: [CGFloat] = [300, 400, 500, 600, 700, 800, 900, 1000]

        results.append(
            await harness.measureAsync(label: "sequential-4x", fixture: "medium") {
                await runSequentialParseAndSolve(
                    content: BenchmarkFixtures.medium,
                    widths: mediumWidths
                )
            }
        )

        results.append(
            await harness.measureAsync(label: "concurrent-4x", fixture: "medium") {
                await runConcurrentParseAndSolve(
                    content: BenchmarkFixtures.medium,
                    widths: mediumWidths
                )
            }
        )

        results.append(
            await harness.measureAsync(label: "sequential-8x", fixture: "large") {
                await runSequentialParseAndSolve(
                    content: BenchmarkFixtures.large,
                    widths: largeWidths
                )
            }
        )

        results.append(
            await harness.measureAsync(label: "concurrent-8x", fixture: "large") {
                await runConcurrentParseAndSolve(
                    content: BenchmarkFixtures.large,
                    widths: largeWidths
                )
            }
        )

        return results
    }

    private func runSequentialParseAndSolve(content: String, widths: [CGFloat]) async {
        for width in widths {
            let parser = MarkdownParser()
            let doc = parser.parse(content)
            let solver = LayoutSolver(cache: LayoutCache())
            _ = await solver.solve(node: doc, constrainedToWidth: width)
        }
    }

    private func runConcurrentParseAndSolve(content: String, widths: [CGFloat]) async {
        await withTaskGroup(of: Void.self) { group in
            for width in widths {
                group.addTask {
                    let parser = MarkdownParser()
                    let doc = parser.parse(content)
                    let solver = LayoutSolver(cache: LayoutCache())
                    _ = await solver.solve(node: doc, constrainedToWidth: width)
                }
            }
        }
    }
}
