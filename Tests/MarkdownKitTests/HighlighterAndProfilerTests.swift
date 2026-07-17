import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class HighlighterAndProfilerTests: XCTestCase {
    private struct RangeSnapshot: Equatable {
        let location: Int
        let length: Int
    }


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

    func testHighlightPythonCodeUsesGenericKeywordHighlighting() {
        let highlighter = SplashHighlighter()
        let code = "def hello():\n    print('world')"
        let result = highlighter.highlight(code, language: "python")

        var runCount = 0
        result.enumerateAttributes(
            in: NSRange(location: 0, length: result.length)
        ) { _, _, _ in
            runCount += 1
        }

        XCTAssertGreaterThan(runCount, 1,
            "Python code should have keyword-highlighted attribute runs")
    }

    func testGenericLanguageAliasesReuseCompiledRegexBundle() {
        GenericKeywordHighlighter.resetCacheForTesting()

        let highlighter = SplashHighlighter()
        let code = "def greet():\n    return 42"
        let canonical = highlighter.highlight(code, language: "python")
        let alias = highlighter.highlight(code, language: "py")
        let stats = GenericKeywordHighlighter.cacheStatsForTesting()

        XCTAssertEqual(canonical.string, code)
        XCTAssertEqual(alias.string, code)
        XCTAssertEqual(foregroundRunRanges(in: canonical), foregroundRunRanges(in: alias))
        XCTAssertEqual(stats.misses, 1)
        XCTAssertEqual(stats.hits, 1)
    }

    func testGenericRegexCacheIsThemeIndependent() {
        GenericKeywordHighlighter.resetCacheForTesting()

        let code = "def greet():\n    return 42\n    print('hi')\n# note"
        let firstTheme = makeGenericTheme(
            textColor: .darkGray,
            keywordColor: .systemPink,
            stringColor: .systemOrange,
            numberColor: .systemPurple,
            commentColor: .systemTeal
        )
        let secondTheme = makeGenericTheme(
            textColor: .brown,
            keywordColor: .systemBlue,
            stringColor: .systemGreen,
            numberColor: .systemRed,
            commentColor: .magenta
        )

        let first = SplashHighlighter(theme: firstTheme).highlight(code, language: "python")
        let second = SplashHighlighter(theme: secondTheme).highlight(code, language: "python")
        let stats = GenericKeywordHighlighter.cacheStatsForTesting()

        XCTAssertEqual(first.string, code)
        XCTAssertEqual(second.string, code)
        XCTAssertEqual(foregroundRunRanges(in: first), foregroundRunRanges(in: second))

        assertForegroundColor(firstTheme.syntaxColors.keyword, in: first, for: "def")
        assertForegroundColor(firstTheme.syntaxColors.keyword, in: first, for: "return")
        assertForegroundColor(firstTheme.syntaxColors.number, in: first, for: "42")
        assertForegroundColor(firstTheme.syntaxColors.string, in: first, for: "'hi'")
        assertForegroundColor(firstTheme.syntaxColors.comment, in: first, for: "# note")
        assertForegroundColor(firstTheme.colors.textColor.foreground, in: first, for: "greet")

        assertForegroundColor(secondTheme.syntaxColors.keyword, in: second, for: "def")
        assertForegroundColor(secondTheme.syntaxColors.keyword, in: second, for: "return")
        assertForegroundColor(secondTheme.syntaxColors.number, in: second, for: "42")
        assertForegroundColor(secondTheme.syntaxColors.string, in: second, for: "'hi'")
        assertForegroundColor(secondTheme.syntaxColors.comment, in: second, for: "# note")
        assertForegroundColor(secondTheme.colors.textColor.foreground, in: second, for: "greet")

        XCTAssertEqual(stats.misses, 1)
        XCTAssertEqual(stats.hits, 1)
    }

    func testGenericRegexCacheBuildsOnceUnderConcurrentFirstUse() async {
        GenericKeywordHighlighter.resetCacheForTesting()

        let code = "def greet():\n    return 42\n# note"
        let requestCount = 32

        let outputs = await withTaskGroup(of: String.self, returning: [String].self) { group in
            for _ in 0..<requestCount {
                group.addTask {
                    await Task.yield()
                    let highlighter = SplashHighlighter()
                    return highlighter.highlight(code, language: "python").string
                }
            }

            var collected: [String] = []
            collected.reserveCapacity(requestCount)
            for await output in group {
                collected.append(output)
            }
            return collected
        }

        let stats = GenericKeywordHighlighter.cacheStatsForTesting()

        XCTAssertEqual(outputs.count, requestCount)
        XCTAssertEqual(Set(outputs), Set([code]))
        XCTAssertEqual(stats.builds, 1)
        XCTAssertEqual(stats.misses, 1)
        XCTAssertEqual(stats.hits, requestCount - 1)
    }

    func testHighlightUnlabeledCodeDoesNotUseSplash() {
        let highlighter = SplashHighlighter()
        let code = "x = 42\nprint(x)"
        let result = highlighter.highlight(code, language: nil)

        var runCount = 0
        result.enumerateAttributes(
            in: NSRange(location: 0, length: result.length)
        ) { _, _, _ in
            runCount += 1
        }

        XCTAssertEqual(runCount, 1,
            "Unlabeled code should fall back to plain styling")
    }

    func testSupportedLanguagesProperty() {
        XCTAssertTrue(SplashHighlighter.supportedLanguages.contains("swift"))
        XCTAssertTrue(SplashHighlighter.supportedLanguages.contains("python"))
        XCTAssertTrue(SplashHighlighter.supportedLanguages.contains("javascript"))
        XCTAssertFalse(SplashHighlighter.supportedLanguages.contains("brainfuck"))
    }

    func testHighlightUnknownLanguageFallsBackToPlain() {
        let highlighter = SplashHighlighter()
        let result = highlighter.highlight("some code", language: "brainfuck")

        var runCount = 0
        result.enumerateAttributes(
            in: NSRange(location: 0, length: result.length)
        ) { _, _, _ in
            runCount += 1
        }

        XCTAssertEqual(runCount, 1,
            "Truly unknown language should use plain styling")
    }

    func testHighlightTreatsSwiftLanguageCaseInsensitively() {
        let highlighter = SplashHighlighter()
        let result = highlighter.highlight("let x = 42\nprint(x)", language: "SWIFT")

        var runCount = 0
        result.enumerateAttributes(
            in: NSRange(location: 0, length: result.length)
        ) { _, _, _ in
            runCount += 1
        }

        XCTAssertGreaterThan(runCount, 1,
            "Swift aliases should still use syntax highlighting")
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

    private func foregroundRunRanges(in attrString: NSAttributedString) -> [RangeSnapshot] {
        var ranges: [RangeSnapshot] = []
        attrString.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: attrString.length)
        ) { _, range, _ in
            ranges.append(RangeSnapshot(location: range.location, length: range.length))
        }
        return ranges
    }

    private func assertForegroundColor(
        _ expected: Color,
        in attrString: NSAttributedString,
        for substring: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let nsString = attrString.string as NSString
        let range = nsString.range(of: substring)
        guard range.location != NSNotFound else {
            XCTFail("Missing substring \(substring)", file: file, line: line)
            return
        }

        guard let actual = attrString.attribute(
            .foregroundColor,
            at: range.location,
            effectiveRange: nil
        ) as? Color else {
            XCTFail("Missing foreground color for \(substring)", file: file, line: line)
            return
        }

        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    private func makeGenericTheme(
        textColor: Color,
        keywordColor: Color,
        stringColor: Color,
        numberColor: Color,
        commentColor: Color
    ) -> Theme {
        let base = Theme.default
        return Theme(
            typography: base.typography,
            colors: Theme.Colors(
                textColor: ColorToken(foreground: textColor),
                codeColor: base.colors.codeColor,
                inlineCodeColor: base.colors.inlineCodeColor,
                tableColor: base.colors.tableColor,
                linkColor: base.colors.linkColor,
                blockQuoteColor: base.colors.blockQuoteColor,
                thematicBreakColor: base.colors.thematicBreakColor
            ),
            codeBlock: base.codeBlock,
            blockQuote: base.blockQuote,
            list: base.list,
            details: base.details,
            table: base.table,
            syntaxColors: Theme.SyntaxColors(
                keyword: keywordColor,
                string: stringColor,
                type: base.syntaxColors.type,
                call: base.syntaxColors.call,
                number: numberColor,
                comment: commentColor,
                property: base.syntaxColors.property,
                dotAccess: base.syntaxColors.dotAccess,
                preprocessing: base.syntaxColors.preprocessing
            ),
            highlight: base.highlight,
            thematicBreak: base.thematicBreak
        )
    }
}
