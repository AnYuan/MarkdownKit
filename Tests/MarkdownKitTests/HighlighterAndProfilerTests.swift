import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class HighlighterAndProfilerTests: XCTestCase {

    // MARK: - SplashHighlighter

    func testHighlightSwiftCodeProducesMultipleRuns() {
        let highlighter = SplashHighlighter()
        let result = highlighter.highlight("let x = 42\nprint(x)", language: "swift")

        var runCount = 0
        result.enumerateAttributes(
            in: NSRange(location: 0, length: result.length)
        ) { _, _, _ in
            runCount += 1
        }
        XCTAssertGreaterThan(runCount, 1,
            "Swift code should produce multiple highlighted attribute runs")
    }

    func testHighlightEmptyStringProducesEmptyResult() {
        let highlighter = SplashHighlighter()
        let result = highlighter.highlight("", language: nil)
        XCTAssertEqual(result.length, 0)
    }

    func testHighlightWithCustomTheme() {
        let customCode = TypographyToken(font: Font.monospacedSystemFont(ofSize: 20, weight: .bold))
        let theme = Theme(
            typography: Theme.Typography(
                header1: TypographyToken(font: Font.systemFont(ofSize: 32)),
                header2: TypographyToken(font: Font.systemFont(ofSize: 24)),
                header3: TypographyToken(font: Font.systemFont(ofSize: 20)),
                paragraph: TypographyToken(font: Font.systemFont(ofSize: 16)),
                codeBlock: customCode
            ),
            colors: Theme.Colors(
                textColor: ColorToken(foreground: .white),
                codeColor: ColorToken(foreground: .green, background: .black),
                tableColor: ColorToken(foreground: .gray, background: .darkGray)
            )
        )

        let highlighter = SplashHighlighter(theme: theme)
        let result = highlighter.highlight("var name = \"test\"", language: "swift")
        XCTAssertGreaterThan(result.length, 0)
    }

    func testHighlightPreservesCodeContent() {
        let highlighter = SplashHighlighter()
        let code = "func hello() { }"
        let result = highlighter.highlight(code, language: "swift")
        XCTAssertTrue(result.string.contains("func"))
        XCTAssertTrue(result.string.contains("hello"))
    }

    // MARK: - PerformanceProfiler

    func testMeasureSyncReturnsNonNegativeTime() {
        let elapsed = PerformanceProfiler.measure(.astParsing, log: false) {
            _ = 1 + 1
        }
        XCTAssertGreaterThanOrEqual(elapsed, 0)
    }

    func testMeasureAsyncReturnsNonNegativeTime() async throws {
        let elapsed = await PerformanceProfiler.measureAsync(.layoutCalculation, log: false) {
            await Task.yield()
        }
        XCTAssertGreaterThanOrEqual(elapsed, 0)
    }

    func testMeasureMetricRawValues() {
        XCTAssertEqual(PerformanceProfiler.Metric.astParsing.rawValue, "AST Parsing")
        XCTAssertEqual(PerformanceProfiler.Metric.layoutCalculation.rawValue, "Layout Calculation")
        XCTAssertEqual(PerformanceProfiler.Metric.viewMounting.rawValue, "View Mounting")
        XCTAssertEqual(PerformanceProfiler.Metric.totalRendering.rawValue, "Total Rendering Time")
    }
}
