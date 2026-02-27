import XCTest
@testable import MarkdownKit
import Markdown

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class MarkdownKitBenchmarkTests: XCTestCase {

    private let harness = BenchmarkHarness(warmup: 3, iterations: 20)
    private let defaultWidth: CGFloat = 800.0
    private let defaultPlugins: [ASTPlugin] = [
        MathExtractionPlugin(),
        DiagramExtractionPlugin(),
        DetailsExtractionPlugin(),
    ]

    // MARK: - Phase 1: Parse

    func testPhase1_Parse() {
        var results: [BenchmarkResult] = []

        for (name, content) in BenchmarkFixtures.allFixtures {
            // End-to-end parse with all plugins
            let parser = MarkdownParser(plugins: defaultPlugins)
            results.append(
                harness.measure(label: "parse", fixture: name) {
                    _ = parser.parse(content)
                }
            )

            // swift-markdown C parser alone
            results.append(
                harness.measure(label: "Document(parsing:)", fixture: name) {
                    _ = Document(parsing: content)
                }
            )

            // AST visitor conversion alone
            let document = Document(parsing: content)
            results.append(
                harness.measure(label: "Visitor.defaultVisit", fixture: name) {
                    var visitor = MarkdownKitVisitor()
                    _ = visitor.defaultVisit(document)
                }
            )
        }

        // Individual plugin benchmarks on targeted fixtures
        let pluginFixtures: [(String, String)] = [
            ("math-heavy", BenchmarkFixtures.mathHeavy),
            ("large", BenchmarkFixtures.large),
        ]

        for (name, content) in pluginFixtures {
            let rawParser = MarkdownParser(plugins: [])
            let rawDoc = rawParser.parse(content)
            let rawNodes = rawDoc.children

            let mathPlugin = MathExtractionPlugin()
            results.append(
                harness.measure(label: "MathPlugin.visit", fixture: name) {
                    _ = mathPlugin.visit(rawNodes)
                }
            )

            let diagramPlugin = DiagramExtractionPlugin()
            results.append(
                harness.measure(label: "DiagramPlugin.visit", fixture: name) {
                    _ = diagramPlugin.visit(rawNodes)
                }
            )

            let detailsPlugin = DetailsExtractionPlugin()
            results.append(
                harness.measure(label: "DetailsPlugin.visit", fixture: name) {
                    _ = detailsPlugin.visit(rawNodes)
                }
            )
        }

        BenchmarkReportFormatter.printReport(
            parseResults: results,
            layoutResults: [],
            cacheResults: []
        )
    }

    // MARK: - Phase 2: Layout

    func testPhase2_Layout() async {
        var results: [BenchmarkResult] = []

        // Pre-parse all fixtures
        let parser = MarkdownParser(plugins: defaultPlugins)
        let parsed: [(String, DocumentNode)] = BenchmarkFixtures.allFixtures.map {
            ($0.name, parser.parse($0.content))
        }

        // Full LayoutSolver.solve per fixture
        for (name, doc) in parsed {
            let result = await harness.measureAsync(label: "solve", fixture: name) {
                let solver = LayoutSolver(cache: LayoutCache())
                _ = await solver.solve(node: doc, constrainedToWidth: self.defaultWidth)
            }
            results.append(result)
        }

        // TextKitCalculator.calculateSize in isolation
        let textCalc = TextKitCalculator()
        let sampleStrings: [(String, NSAttributedString)] = [
            ("short", NSAttributedString(
                string: "Hello World",
                attributes: [.font: Font.systemFont(ofSize: 16)]
            )),
            ("paragraph", NSAttributedString(
                string: String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 20),
                attributes: [.font: Font.systemFont(ofSize: 16)]
            )),
            ("long", NSAttributedString(
                string: String(repeating: "A comprehensive paragraph with enough words. ", count: 200),
                attributes: [.font: Font.systemFont(ofSize: 16)]
            )),
        ]

        for (name, attrStr) in sampleStrings {
            results.append(
                harness.measure(label: "TextKit.calcSize", fixture: name) {
                    _ = textCalc.calculateSize(for: attrStr, constrainedToWidth: self.defaultWidth)
                }
            )
        }

        // SplashHighlighter.highlight in isolation
        let highlighter = SplashHighlighter()
        let codeSamples: [(String, String)] = [
            ("10-lines", (1...10).map { "let x\($0) = compute(\($0))" }.joined(separator: "\n")),
            ("50-lines", (1...50).map { "let x\($0) = compute(\($0))" }.joined(separator: "\n")),
            ("100-lines", (1...100).map { "let x\($0) = compute(\($0))" }.joined(separator: "\n")),
        ]

        for (name, code) in codeSamples {
            results.append(
                harness.measure(label: "Splash.highlight", fixture: name) {
                    _ = highlighter.highlight(code, language: "swift")
                }
            )
        }

        BenchmarkReportFormatter.printReport(
            parseResults: [],
            layoutResults: results,
            cacheResults: []
        )
    }

    // MARK: - Cache hit/miss benchmark

    func testCacheHitMissRates() async {
        var results: [BenchmarkResult] = []

        let parser = MarkdownParser(plugins: defaultPlugins)
        let doc = parser.parse(BenchmarkFixtures.medium)
        let cache = LayoutCache()
        let solver = LayoutSolver(cache: cache)

        // Cold: clear cache before each iteration
        results.append(
            await harness.measureAsync(label: "solve(cold)", fixture: "medium") {
                cache.clear()
                _ = await solver.solve(node: doc, constrainedToWidth: self.defaultWidth)
            }
        )

        // Warm: pre-populate cache, then measure cached hits
        _ = await solver.solve(node: doc, constrainedToWidth: defaultWidth)
        results.append(
            await harness.measureAsync(label: "solve(warm)", fixture: "medium") {
                _ = await solver.solve(node: doc, constrainedToWidth: self.defaultWidth)
            }
        )

        BenchmarkReportFormatter.printReport(
            parseResults: [],
            layoutResults: [],
            cacheResults: results
        )
    }

    // MARK: - Full combined report

    func testBenchmarkFullReport() async {
        var parseResults: [BenchmarkResult] = []
        var layoutResults: [BenchmarkResult] = []
        var cacheResults: [BenchmarkResult] = []

        let parser = MarkdownParser(plugins: defaultPlugins)

        // --- Phase 1: Parse ---
        for (name, content) in BenchmarkFixtures.allFixtures {
            parseResults.append(
                harness.measure(label: "parse", fixture: name) {
                    _ = parser.parse(content)
                }
            )
        }

        // --- Phase 2: Layout ---
        let parsed: [(String, DocumentNode)] = BenchmarkFixtures.allFixtures.map {
            ($0.name, parser.parse($0.content))
        }

        for (name, doc) in parsed {
            layoutResults.append(
                await harness.measureAsync(label: "solve", fixture: name) {
                    let solver = LayoutSolver(cache: LayoutCache())
                    _ = await solver.solve(node: doc, constrainedToWidth: self.defaultWidth)
                }
            )
        }

        // --- Cache ---
        let medDoc = parser.parse(BenchmarkFixtures.medium)
        let cache = LayoutCache()
        let solver = LayoutSolver(cache: cache)

        cacheResults.append(
            await harness.measureAsync(label: "solve(cold)", fixture: "medium") {
                cache.clear()
                _ = await solver.solve(node: medDoc, constrainedToWidth: self.defaultWidth)
            }
        )

        _ = await solver.solve(node: medDoc, constrainedToWidth: defaultWidth)
        cacheResults.append(
            await harness.measureAsync(label: "solve(warm)", fixture: "medium") {
                _ = await solver.solve(node: medDoc, constrainedToWidth: self.defaultWidth)
            }
        )

        BenchmarkReportFormatter.printReport(
            parseResults: parseResults,
            layoutResults: layoutResults,
            cacheResults: cacheResults
        )
    }
}
