import XCTest
@testable import MarkdownKit

#if canImport(UIKit) && !os(watchOS)
import UIKit

/// iOS-specific tests verifying UIKit table layout behavior:
/// tab stop offsets, container insets, and column alignment.
final class iOSTableLayoutTests: XCTestCase {

    // MARK: - Container Inset Tests

    func testUIKitTableFirstColumnHasHeadIndent() async throws {
        let markdown = """
        | Name | Score |
        |------|-------|
        | Alice | 95   |
        """
        let layout = await TestHelper.solveLayout(markdown, width: 400)
        guard let attrStr = layout.children[0].attributedString else {
            XCTFail("Table layout missing attributed string")
            return
        }

        let style = attrStr.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertNotNil(style, "Expected paragraph style on table text")
        XCTAssertGreaterThan(style?.firstLineHeadIndent ?? 0, 0,
                             "First column should have a leading head indent")
        XCTAssertGreaterThan(style?.headIndent ?? 0, 0,
                             "First column should have a head indent for wrapped lines")
    }

    func testUIKitTableTabStopsAreOffsetByInset() async throws {
        let markdown = """
        | A | B | C |
        |---|---|---|
        | 1 | 2 | 3 |
        """
        let layout = await TestHelper.solveLayout(markdown, width: 600)
        guard let attrStr = layout.children[0].attributedString else {
            XCTFail("Table layout missing attributed string")
            return
        }

        let style = attrStr.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let tabStops = style?.tabStops ?? []

        XCTAssertEqual(tabStops.count, 3, "Expected 3 tab stops for 3 columns")
        guard let firstStop = tabStops.first else { return }

        // The first tab stop should be offset (> 0), not at position 0
        XCTAssertGreaterThan(firstStop.location, 0,
                             "First tab stop should be offset by the horizontal inset, not at 0")

        // All tab stops should be evenly spaced
        if tabStops.count >= 3 {
            let gap1 = tabStops[1].location - tabStops[0].location
            let gap2 = tabStops[2].location - tabStops[1].location
            XCTAssertEqual(gap1, gap2, accuracy: 1.0,
                           "Tab stops should be evenly spaced")
        }
    }

    func testUIKitTableSeparatorTabStopsMatchContentTabStops() async throws {
        let markdown = """
        | Left | Right |
        |:-----|------:|
        | x    | y     |
        """
        let layout = await TestHelper.solveLayout(markdown, width: 500)
        guard let attrStr = layout.children[0].attributedString else {
            XCTFail("Table layout missing attributed string")
            return
        }

        // Collect paragraph styles from all runs
        var contentTabStops: [NSTextTab]?
        var separatorTabStops: [NSTextTab]?
        let text = attrStr.string

        attrStr.enumerateAttribute(
            .paragraphStyle,
            in: NSRange(location: 0, length: attrStr.length)
        ) { value, range, _ in
            guard let style = value as? NSParagraphStyle else { return }
            let substring = (text as NSString).substring(with: range)
            if substring.contains("─") {
                separatorTabStops = style.tabStops
            } else if contentTabStops == nil && !substring.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                contentTabStops = style.tabStops
            }
        }

        XCTAssertNotNil(contentTabStops, "Should find content row tab stops")
        XCTAssertNotNil(separatorTabStops, "Should find separator row tab stops")

        guard let content = contentTabStops, let separator = separatorTabStops else { return }
        XCTAssertEqual(content.count, separator.count,
                       "Separator and content rows should have the same number of tab stops")

        for (contentStop, sepStop) in zip(content, separator) {
            XCTAssertEqual(contentStop.location, sepStop.location, accuracy: 0.01,
                           "Separator tab stop locations should match content tab stop locations")
        }
    }

    // MARK: - Column Alignment Tests

    func testUIKitTableColumnAlignmentWithInset() async throws {
        let markdown = """
        | Left | Center | Right |
        |:-----|:------:|------:|
        | a    | b      | c     |
        """
        let layout = await TestHelper.solveLayout(markdown, width: 600)
        guard let attrStr = layout.children[0].attributedString else {
            XCTFail("Table layout missing attributed string")
            return
        }

        // First run's paragraph style controls column 0 alignment
        let style = attrStr.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.alignment, .left,
                       "Column 0 paragraph alignment should be .left")

        // Tab stops encode alignment for columns 1+
        let tabStops = style?.tabStops ?? []
        guard tabStops.count >= 3 else {
            XCTFail("Expected at least 3 tab stops, got \(tabStops.count)")
            return
        }
        XCTAssertEqual(tabStops[1].alignment, .center,
                       "Column 1 tab stop should have .center alignment")
        XCTAssertEqual(tabStops[2].alignment, .right,
                       "Column 2 tab stop should have .right alignment")

        // Head indent should still be applied
        XCTAssertGreaterThan(style?.firstLineHeadIndent ?? 0, 0,
                             "Head indent should be applied even with custom alignment")
    }

    // MARK: - Size Constraint Tests

    func testUIKitTableContentFitsWithinConstrainedWidth() async throws {
        let markdown = """
        | Feature | Status | Priority |
        |:--------|:------:|--------:|
        | Parsing | Done   | High    |
        | Layout  | WIP    | Medium  |
        """
        let width: CGFloat = 375 // iPhone SE width
        let layout = await TestHelper.solveLayout(markdown, width: width)
        let tableLayout = layout.children[0]

        XCTAssertLessThanOrEqual(tableLayout.size.width, width,
                                 "Table layout width should not exceed the constrained width")
        XCTAssertGreaterThan(tableLayout.size.height, 0,
                             "Table should have positive height")
    }

    func testUIKitTableNarrowWidthDoesNotCrash() async throws {
        let markdown = """
        | A | B | C | D |
        |---|---|---|---|
        | 1 | 2 | 3 | 4 |
        """
        // Very narrow width — should not crash or produce negative tab stop locations
        let layout = await TestHelper.solveLayout(markdown, width: 100)
        let tableLayout = layout.children[0]

        XCTAssertNotNil(tableLayout.attributedString,
                        "Table should still produce an attributed string at narrow widths")
        XCTAssertGreaterThan(tableLayout.size.height, 0)

        // Verify no negative tab stop locations
        if let style = tableLayout.attributedString?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
            for stop in style.tabStops {
                XCTAssertGreaterThanOrEqual(stop.location, 0,
                                            "Tab stop locations should never be negative")
            }
        }
    }

    func testUIKitTableNarrowWidthUsesReadableFallbackWithoutTabStops() async throws {
        let markdown = """
        | Feature | Status | Priority | Owner |
        |---------|--------|----------|-------|
        | Parsing | Done   | High     | Core  |
        """

        let layout = await TestHelper.solveLayout(markdown, width: 100)
        let tableLayout = layout.children[0]

        guard let attr = tableLayout.attributedString else {
            XCTFail("Table should produce attributed output")
            return
        }

        XCTAssertFalse(attr.string.contains("\t"),
                       "Narrow-width fallback should avoid tab-delimited table rows")

        if let style = attr.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
            XCTAssertTrue(style.tabStops.isEmpty,
                          "Narrow-width fallback should not rely on tab stops")
        }
    }

    func testUIKitTableBodyRowsUseAlternatingBackgroundShading() async throws {
        let markdown = """
        | Name  | Score |
        |-------|-------|
        | Alice | 95    |
        | Bob   | 87    |
        """
        let layout = await TestHelper.solveLayout(markdown, width: 420)
        guard let attr = layout.children[0].attributedString else {
            XCTFail("Table layout missing attributed string")
            return
        }

        let fullText = attr.string as NSString
        var aliceBackground: UIColor?
        var bobBackground: UIColor?

        attr.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: attr.length)) { value, range, _ in
            let snippet = fullText.substring(with: range)
            if snippet.contains("Alice") {
                aliceBackground = value as? UIColor
            }
            if snippet.contains("Bob") {
                bobBackground = value as? UIColor
            }
        }

        XCTAssertNotNil(aliceBackground, "First body row should carry background attribute")
        XCTAssertNotNil(bobBackground, "Second body row should carry background attribute")

        let aliceAlpha = aliceBackground?.cgColor.alpha ?? -1
        let bobAlpha = bobBackground?.cgColor.alpha ?? -1

        XCTAssertEqual(aliceAlpha, 0, accuracy: 0.01,
                       "First body row should remain unshaded")
        XCTAssertGreaterThan(bobAlpha, 0.01,
                             "Second body row should receive subtle shading")
    }
}
#endif
